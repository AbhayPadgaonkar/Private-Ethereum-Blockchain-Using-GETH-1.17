const fs = require('fs');
const path = require('path');
const http = require('http');
const { ethers } = require('ethers');

const KEYSTORE_DIR = path.join(__dirname, 'node1', 'keystore');
const PASSWORD_FILE = path.join(__dirname, 'node1', 'password-clean');
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:18545';
const BEACON_REST = process.env.BEACON_REST || 'http://127.0.0.1:3500';
const TO_ADDRESS = '0x7B25e791D24A3F5c453A9E5468cF6cEa2243092C';

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

async function main() {
  const files = fs.readdirSync(KEYSTORE_DIR).filter(f => f.startsWith('UTC--'));
  if (files.length === 0) {
    throw new Error('No keystore file found in ' + KEYSTORE_DIR);
  }
  const targetAddress = '014bff6c76d88e815075c0323c3904fe635c2325';
  let keystoreFile = files.find(f => f.toLowerCase().includes(targetAddress));
  if (!keystoreFile) {
    keystoreFile = files[0];
  }
  const keystorePath = path.join(KEYSTORE_DIR, keystoreFile);
  const keystoreJson = fs.readFileSync(keystorePath, 'utf8');
  const password = fs.readFileSync(PASSWORD_FILE, 'utf8').trim();

  const wallet = await ethers.Wallet.fromEncryptedJson(keystoreJson, password);
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
  const signer = wallet.connect(provider);

  console.log('From:', signer.address);
  console.log('Balance before:', ethers.utils.formatEther(await provider.getBalance(signer.address)), 'ETH');

  console.log('\n--- PoS consensus checks before sending ---');
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

  const latestExec = await provider.getBlock('latest');
  console.log('Execution block:', latestExec.number,
    '| difficulty:', latestExec.difficulty.toString(),
    '| totalDifficulty:', latestExec.totalDifficulty ? latestExec.totalDifficulty.toString() : 'n/a',
    '| nonce:', latestExec.nonce,
    '| miner:', latestExec.miner);

  const tx = await signer.sendTransaction({
    to: TO_ADDRESS,
    value: ethers.utils.parseEther('10'),
    gasLimit: 30000
  });

  console.log('\nTransaction hash:', tx.hash);

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

  const minedExec = await provider.getBlock(receipt.blockHash);
  const minedBeacon = await beaconGet('/eth/v1/beacon/headers/head');

  console.log('\n--- PoS consensus details for the mined block ---');
  console.log('Execution block hash:', minedExec.hash);
  console.log('Execution difficulty:', minedExec.difficulty.toString(),
    '| nonce:', minedExec.nonce,
    '| miner:', minedExec.miner);
  console.log('Execution extraData:', minedExec.extraData);

  if (minedBeacon.data && minedBeacon.data.header) {
    const bh = minedBeacon.data.header.message;
    const slot = parseInt(bh.slot, 10);
    const epoch = Math.floor(slot / 32);
    console.log('Beacon slot:', slot, '| epoch:', epoch);
    console.log('Beacon proposer index:', bh.proposer_index);
    console.log('Beacon parent root:', bh.parent_root);
    console.log('Beacon state root:', bh.state_root);
    console.log('Beacon block root:', minedBeacon.data.root);
  } else {
    console.log('Beacon head:', JSON.stringify(minedBeacon));
  }

  console.log('\nBalance after sender:', ethers.utils.formatEther(await provider.getBalance(signer.address)), 'ETH');
  console.log('Balance of recipient:', ethers.utils.formatEther(await provider.getBalance(TO_ADDRESS)), 'ETH');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
