const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

const GENESIS_FILE = path.join(__dirname, 'genesis.json');
const DEFAULT_PASSWORD = 'node';
const DEFAULT_BALANCE_ETH = '100000';

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

async function main() {
  const count = parseInt(process.env.WALLET_COUNT || '5', 10);
  const balanceEth = process.env.WALLET_BALANCE_ETH || DEFAULT_BALANCE_ETH;

  if (!fs.existsSync(GENESIS_FILE)) {
    console.error('genesis.json not found at', GENESIS_FILE);
    process.exit(1);
  }

  const genesis = JSON.parse(fs.readFileSync(GENESIS_FILE, 'utf8'));
  if (!genesis.alloc) genesis.alloc = {};

  const wallets = [];

  for (let i = 1; i <= count; i++) {
    const nodeDir = path.join(__dirname, `node${i}`);
    const keystoreDir = path.join(nodeDir, 'keystore');
    const passwordFile = path.join(nodeDir, 'password-clean');

    ensureDir(keystoreDir);

    const password = `${DEFAULT_PASSWORD}${i}`;
    fs.writeFileSync(passwordFile, password, { encoding: 'ascii' });

    const wallet = ethers.Wallet.createRandom();
    const keystoreJson = await wallet.encrypt(password);
    const keystoreName = `UTC--${new Date().toISOString().replace(/:/g, '-')}--${wallet.address.slice(2)}`;
    const keystorePath = path.join(keystoreDir, keystoreName);

    fs.writeFileSync(keystorePath, keystoreJson);

    genesis.alloc[wallet.address] = {
      balance: ethers.utils.parseEther(balanceEth).toString()
    };

    wallets.push({
      node: i,
      address: wallet.address,
      privateKey: wallet.privateKey,
      password,
      keystore: keystorePath
    });

    console.log(`Created wallet for node ${i}: ${wallet.address}`);
  }

  fs.writeFileSync(GENESIS_FILE, JSON.stringify(genesis, null, 2) + '\n');

  const summaryPath = path.join(__dirname, 'metamask-wallets.json');
  fs.writeFileSync(
    summaryPath,
    JSON.stringify(
      {
        network: {
          name: 'Local PoS Devnet',
          rpcUrls: wallets.map(w => `http://127.0.0.1:${18544 + w.node}`),
          chainId: genesis.config.chainId,
          currencySymbol: 'ETH'
        },
        wallets
      },
      null,
      2
    )
  );

  const csvPath = path.join(__dirname, 'metamask-wallets.csv');
  const csvLines = ['node,address,privateKey,password,keystore'];
  for (const w of wallets) {
    csvLines.push(`${w.node},${w.address},${w.privateKey},${w.password},${path.basename(w.keystore)}`);
  }
  fs.writeFileSync(csvPath, csvLines.join('\n'));

  console.log('\nUpdated genesis.json with funded accounts.');
  console.log('Wallet summary written to:');
  console.log('  -', summaryPath);
  console.log('  -', csvPath);
  console.log('\nIMPORTANT: These files contain private keys. Keep them secret and do not commit them.');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
