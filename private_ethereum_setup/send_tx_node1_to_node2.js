const fs = require('fs');
const path = require('path');
const http = require('http');
const { ethers } = require('ethers');

const SENDER_KEYSTORE_DIR = path.join(__dirname, 'node1', 'keystore');
const SENDER_PASSWORD_FILE = path.join(__dirname, 'node1', 'password-clean');
const RECIPIENT_KEYSTORE_DIR = path.join(__dirname, 'node2', 'keystore');
const RECIPIENT_PASSWORD_FILE = path.join(__dirname, 'node2', 'password-clean');
const RPC_URL_NODE1 = process.env.RPC_URL || 'http://127.0.0.1:18545';
const BEACON_REST = process.env.BEACON_REST || 'http://127.0.0.1:3500';
const SENDER_ADDRESS = '0x014BFF6c76d88e815075c0323C3904Fe635c2325';

function getNodeCount() {
  const env = process.env.NODE_COUNT;
  if (env) return parseInt(env, 10);
  return 3;
}

function getNodeRpcPort(i) {
  return 18544 + i;
}

function beaconGet(endpoint) {
  return new Promise((resolve, reject) => {
    http.get(`${BEACON_REST}${endpoint}`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          resolve(data);
        }
      });
    }).on('error', reject);
  });
}

async function loadWallet(keystoreDir, passwordFile, targetAddress) {
  const files = fs.readdirSync(keystoreDir).filter(f => f.startsWith('UTC--'));
  if (files.length === 0) {
    throw new Error('No keystore file found in ' + keystoreDir);
  }
  let keystoreFile = files[0];
  if (targetAddress) {
    const found = files.find(f => f.toLowerCase().includes(targetAddress.toLowerCase().replace('0x', '')));
    if (found) keystoreFile = found;
  }
  const keystorePath = path.join(keystoreDir, keystoreFile);
  const keystoreJson = fs.readFileSync(keystorePath, 'utf8');
  const password = fs.readFileSync(passwordFile, 'utf8').trim();
  return ethers.Wallet.fromEncryptedJson(keystoreJson, password);
}

async function getBalance(provider, address, label) {
  const bal = await provider.getBalance(address);
  console.log(`${label} balance:`, ethers.utils.formatEther(bal), 'ETH');
  return bal;
}

async function main() {
  console.log('Loading Node 1 sender wallet...');
  const senderWallet = await loadWallet(SENDER_KEYSTORE_DIR, SENDER_PASSWORD_FILE, SENDER_ADDRESS);
  console.log('Sender address (Node 1):', senderWallet.address);

  console.log('\nLoading Node 2 recipient wallet...');
  const recipientWallet = await loadWallet(RECIPIENT_KEYSTORE_DIR, RECIPIENT_PASSWORD_FILE);
  console.log('Recipient address (Node 2):', recipientWallet.address);

  const providerNode1 = new ethers.providers.JsonRpcProvider(RPC_URL_NODE1);
  const signer = senderWallet.connect(providerNode1);

  console.log('\n--- Balances before transaction ---');
  await getBalance(providerNode1, senderWallet.address, 'Node 1 sender');
  await getBalance(providerNode1, recipientWallet.address, 'Node 2 recipient');

  console.log('\n--- PoS consensus check before sending ---');
  try {
    const version = await beaconGet('/eth/v1/node/version');
    const sync = await beaconGet('/eth/v1/node/syncing');
    const fork = await beaconGet('/eth/v1/beacon/states/head/fork');
    console.log('Beacon client:', version.data.version);
    console.log('Beacon syncing:', sync.data.is_syncing, '| optimistic:', sync.data.is_optimistic);
    console.log('Current fork:', fork.data.current_version, '| epoch:', fork.data.epoch);
  } catch (e) {
    console.log('Could not reach beacon node on', BEACON_REST, '-', e.message);
  }

  const latestExec = await providerNode1.getBlock('latest');
  console.log('Execution block:', latestExec.number,
    '| difficulty:', latestExec.difficulty.toString(),
    '| nonce:', latestExec.nonce,
    '| miner:', latestExec.miner);

  console.log('\nSending 10 ETH from Node 1 wallet to Node 2 wallet via Node 1 RPC...');
  const tx = await signer.sendTransaction({
    to: recipientWallet.address,
    value: ethers.utils.parseEther('10'),
    gasLimit: 30000
  });
  console.log('Transaction hash:', tx.hash);

  let receipt = null;
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      receipt = await tx.wait();
      break;
    } catch (err) {
      if (err.message && err.message.includes('transaction indexing is in progress')) {
        await new Promise(r => setTimeout(r, 2000));
        continue;
      }
      throw err;
    }
  }
  if (!receipt) {
    throw new Error('Transaction receipt not available after retries');
  }

  console.log('Mined in execution block:', receipt.blockNumber);
  console.log('Gas used:', receipt.gasUsed.toString());

  const minedExec = await providerNode1.getBlock(receipt.blockHash);
  const minedBeacon = await beaconGet('/eth/v1/beacon/headers/head');

  console.log('\n--- PoS consensus details for the mined block ---');
  console.log('Execution block hash:', minedExec.hash);
  console.log('Execution difficulty:', minedExec.difficulty.toString(),
    '| nonce:', minedExec.nonce,
    '| miner:', minedExec.miner);

  if (minedBeacon.data && minedBeacon.data.header) {
    const bh = minedBeacon.data.header.message;
    const slot = parseInt(bh.slot, 10);
    const epoch = Math.floor(slot / 32);
    console.log('Beacon slot:', slot, '| epoch:', epoch);
    console.log('Beacon proposer index:', bh.proposer_index);
    console.log('Beacon block root:', minedBeacon.data.root);
  }

  console.log('\n--- Balances after transaction ---');
  await getBalance(providerNode1, senderWallet.address, 'Node 1 sender');
  await getBalance(providerNode1, recipientWallet.address, 'Node 2 recipient');

  console.log('\n--- Cross-node verification ---');
  const nodeCount = getNodeCount();
  for (let i = 1; i <= nodeCount; i++) {
    const port = getNodeRpcPort(i);
    try {
      const provider = new ethers.providers.JsonRpcProvider(`http://127.0.0.1:${port}`);
      const senderBal = ethers.utils.formatEther(await provider.getBalance(senderWallet.address));
      const recipientBal = ethers.utils.formatEther(await provider.getBalance(recipientWallet.address));
      console.log(`Node ${i} (port ${port}) -> sender: ${senderBal} ETH, recipient: ${recipientBal} ETH`);
    } catch (e) {
      console.log(`Node ${i} (port ${port}) -> unreachable (${e.message})`);
    }
  }

  console.log(`\nNote: The transaction was submitted through Node 1 RPC, but the balance change is visible on all ${nodeCount} nodes because they share the same blockchain state.`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
