const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

const WALLETS_FILE = path.join(__dirname, 'metamask-wallets.json');
const SENDER_NODE = parseInt(process.env.SENDER_NODE || '1', 10);
const RECIPIENT_NODE = parseInt(process.env.RECIPIENT_NODE || '2', 10);
const RPC_NODE = parseInt(process.env.RPC_NODE || '1', 10);
const AMOUNT_ETH = process.env.AMOUNT_ETH || '10';

async function main() {
  if (!fs.existsSync(WALLETS_FILE)) {
    console.error('metamask-wallets.json not found. Run: node create-funded-wallets.js');
    process.exit(1);
  }

  const data = JSON.parse(fs.readFileSync(WALLETS_FILE, 'utf8'));
  const wallets = data.wallets;

  const sender = wallets.find(w => w.node === SENDER_NODE);
  const recipient = wallets.find(w => w.node === RECIPIENT_NODE);

  if (!sender || !recipient) {
    console.error(`Wallet not found for sender node ${SENDER_NODE} or recipient node ${RECIPIENT_NODE}`);
    process.exit(1);
  }

  const rpcPort = 18544 + RPC_NODE;
  const rpcUrl = `http://127.0.0.1:${rpcPort}`;
  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

  const senderWallet = new ethers.Wallet(sender.privateKey, provider);

  console.log(`RPC node: ${rpcUrl} (Node ${RPC_NODE})`);
  console.log(`Sender (Node ${SENDER_NODE}):`, sender.address);
  console.log(`Recipient (Node ${RECIPIENT_NODE}):`, recipient.address);

  console.log('\n--- Balances before ---');
  const senderBalBefore = await provider.getBalance(sender.address);
  const recipientBalBefore = await provider.getBalance(recipient.address);
  console.log('Sender balance:', ethers.utils.formatEther(senderBalBefore), 'ETH');
  console.log('Recipient balance:', ethers.utils.formatEther(recipientBalBefore), 'ETH');

  console.log(`\nSending ${AMOUNT_ETH} ETH...`);
  const tx = await senderWallet.sendTransaction({
    to: recipient.address,
    value: ethers.utils.parseEther(AMOUNT_ETH),
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

  console.log('Mined in block:', receipt.blockNumber);

  console.log('\n--- Cross-node balance verification ---');
  const nodeCount = wallets.length;
  for (let i = 1; i <= nodeCount; i++) {
    const port = 18544 + i;
    try {
      const p = new ethers.providers.JsonRpcProvider(`http://127.0.0.1:${port}`);
      const sb = ethers.utils.formatEther(await p.getBalance(sender.address));
      const rb = ethers.utils.formatEther(await p.getBalance(recipient.address));
      console.log(`Node ${i} (port ${port}) -> sender: ${sb} ETH, recipient: ${rb} ETH`);
    } catch (e) {
      console.log(`Node ${i} (port ${port}) -> unreachable (${e.message})`);
    }
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
