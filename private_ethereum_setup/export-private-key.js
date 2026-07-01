const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

const DEFAULT_KEYSTORE_DIR = path.join(__dirname, 'node1', 'keystore');
const DEFAULT_PASSWORD_FILE = path.join(__dirname, 'node1', 'password-clean');

async function main() {
  const keystoreDir = process.env.KEYSTORE_DIR || DEFAULT_KEYSTORE_DIR;
  const passwordFile = process.env.PASSWORD_FILE || DEFAULT_PASSWORD_FILE;

  if (!fs.existsSync(keystoreDir)) {
    console.error('Keystore directory not found:', keystoreDir);
    console.error('Create a wallet first with: geth account new --datadir node1');
    process.exit(1);
  }

  const files = fs.readdirSync(keystoreDir).filter(f => f.startsWith('UTC--'));
  if (files.length === 0) {
    console.error('No keystore files found in', keystoreDir);
    process.exit(1);
  }

  const password = fs.readFileSync(passwordFile, 'utf8').trim();

  for (const file of files) {
    const keystorePath = path.join(keystoreDir, file);
    const keystoreJson = fs.readFileSync(keystorePath, 'utf8');
    const wallet = await ethers.Wallet.fromEncryptedJson(keystoreJson, password);

    console.log('Address:', wallet.address);
    console.log('Private key:', wallet.privateKey);
    console.log('');
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
