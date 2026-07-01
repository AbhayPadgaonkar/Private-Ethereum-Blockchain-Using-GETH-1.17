# Private Ethereum Blockchain Setup on Windows using Geth 1.17 + Prysm (PoS)

A Windows-friendly setup for a local private Ethereum network using **Geth 1.17** as the execution client and **Prysm** as the consensus client.

> **Note:** Geth 1.17+ only supports Proof-of-Stake (PoS) networks. The older Clique (Proof of Authority) mining setup does not work with Geth 1.17. This guide uses PoS with Prysm.

This README covers an **N-node devnet** — any number of Geth execution nodes, Prysm beacon nodes, and Prysm validators that peer and sync on the same Windows machine. The examples use 3 nodes by default, but you can scale to 6, 9, or more by changing one parameter.

---

## What the Components Do

### Geth (execution client)
- Stores the Ethereum state: accounts, balances, smart contracts
- Validates and executes transactions
- Builds execution blocks when instructed by the beacon node
- Peers with other Geth nodes to share transactions and blocks

### Beacon node (consensus client)
- Tracks PoS time: slots, epochs, validator duties
- Decides which validator proposes the next block
- Tells Geth which block to build on via the Engine API
- Gossips blocks and attestations with other beacon nodes
- Finalizes blocks so they cannot be reverted

### Validator
- Holds the validator private keys
- Signs block proposals and attestations when selected by the protocol
- Submits signed messages to its beacon node
- Earns rewards for correct participation, can be slashed for misbehavior

In short:
- **Geth** = the ledger and transaction executor
- **Beacon node** = the PoS coordinator
- **Validator** = the signer that participates in consensus

---

## Requirements

- Windows 10 / 11
- PowerShell
- `geth.exe` v1.17.x
- `beacon-chain.exe` from Prysm
- `validator.exe` from Prysm
- `prysmctl.exe` from Prysm
- Node.js + npm (for sending transactions with `send_tx.js`)

---

## Download Binaries

1. **Geth** — download from https://geth.ethereum.org/downloads
2. **Prysm** — download from https://github.com/OffchainLabs/prysm/releases
   - `beacon-chain-v...-windows-amd64.exe`
   - `validator-v...-windows-amd64.exe`
   - `prysmctl-v...-windows-amd64.exe`

Place all files in:
```
C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup
```

Rename them to:
- `geth.exe`
- `beacon-chain.exe`
- `validator.exe`
- `prysmctl.exe`

---

## Open PowerShell in the Project Folder

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup
```

Check Geth works:

```powershell
.\geth.exe version
```

Install Node dependencies if you plan to send transactions:

```powershell
npm install
```

---

## Create a Funded Account

The repo already contains the required files in `private_ethereum_setup`:
- `genesis.json` — PoS-ready Geth genesis
- `chain-config.yaml` — Prysm chain configuration
- `jwt.hex` — JWT secret for Geth-Prysm auth

The genesis funds address `0x014BFF6c76d88e815075c0323C3904Fe635c2325`, and the `node1\keystore` already contains the matching keystore. The transaction scripts are configured to use this account, so you can skip the rest of this section on first run.

If you want to use your own funded account instead, create a password file and a new keystore account, then edit `genesis.json` to fund the printed address. To create a funded account on every node (useful for MetaMask or N-node demos):

```powershell
$N = 6
for ($i = 1; $i -le $N; $i++) {
    New-Item -ItemType Directory -Path "node$i" -Force
    "node$i" | Out-File -FilePath "node$i\password-clean" -Encoding ASCII -NoNewline
    .\geth.exe account new --datadir node$i --password node$i\password-clean
}
```

Save the printed address (it looks like `0x...`). You must edit `private_ethereum_setup\genesis.json` to fund this address and keep `extradata` as `0x`.

Example `genesis.json`:

```json
{
  "config": {
    "chainId": 12345,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "muirGlacierBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "arrowGlacierBlock": 0,
    "grayGlacierBlock": 0,
    "mergeNetsplitBlock": 0,
    "terminalTotalDifficulty": 0,
    "terminalTotalDifficultyPassed": true,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "blobSchedule": {
      "cancun": { "target": 3, "max": 6, "baseFeeUpdateFraction": 3338477 },
      "prague": { "target": 6, "max": 9, "baseFeeUpdateFraction": 5007716 },
      "osaka": { "target": 6, "max": 9, "baseFeeUpdateFraction": 5007716 }
    }
  },
  "difficulty": "0",
  "gasLimit": "800000000",
  "baseFeePerGas": "0x7",
  "extradata": "0x",
  "alloc": {
    "0x014BFF6c76d88e815075c0323C3904Fe635c2325": {
      "balance": "100000000000000000000000"
    }
  }
}
```

> Replace the `alloc` address with the address printed by `account new`. Keep `extradata` as `0x` (do not put the address there; it would make the genesis hex length odd).

---

## Clean Previous State

Run in PowerShell (admin rights not required):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\clean-state.ps1 -NodeCount 3
```

The default `NodeCount` is 3. Use a larger number if you previously ran with more nodes. This stops processes and deletes generated state (`node*/geth`, `beacondata*`, `validator_wallet*`, `genesis.ssz`, `genesis-pos.json`, logs) but preserves keystore directories and `wallet_setup/`.

To stop only the running processes without deleting data:

```powershell
.\stop-network.ps1
```

---

## One-Click Start: N-Node Interop Devnet

The fastest way to start the network is the interop script. It generates a fresh genesis, initializes all Geth datadirs, and starts N Geth + N beacon + N validator processes.

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\start-interop-network.ps1 -NodeCount 6 -GenesisDelaySeconds 180
```

Wait for the genesis time printed in the beacon logs, then verify:

```powershell
.\check-network-health.ps1 -NodeCount 6 -Watch
```

When `BeaconSyncing` is `False` and `GethPeers` > 0 on every node, send a test transaction:

```powershell
$env:NODE_COUNT = 6
node send_tx_node1_to_node2.js
```

To stop:

```powershell
.\stop-network.ps1
```

---

## One-Click Start: N-Node Wallet-Based Devnet

If you already generated wallet-based validator keys and imported them into `validator_wallet1..N`, use:

```powershell
.\start-wallet-network-n.ps1 -NodeCount 6 -GenesisDelaySeconds 180
```

Prerequisites:
- `wallet_setup\validator_keys\deposit_data.json` exists and contains `N` deposits.
- `wallet_setup\wallet_password.txt` and `wallet_setup\account_password.txt` exist.
- `validator_wallet1..N` directories have been imported.

---

## Port Reference

| Component | Formula for Node `i` | Node 1 | Node 2 | Node 3 | Node 6 |
|-----------|----------------------|--------|--------|--------|--------|
| Geth P2P port | `30305 + i` | `30306` | `30307` | `30308` | `30311` |
| Geth HTTP port | `18544 + i` | `18545` | `18546` | `18547` | `18550` |
| Engine API port | `8550 + i` | `8551` | `8552` | `8553` | `8556` |
| Geth IPC pipe | `geth{i}.ipc` | `geth1.ipc` | `geth2.ipc` | `geth3.ipc` | `geth6.ipc` |
| Beacon gRPC port | `3999 + i` | `4000` | `4001` | `4002` | `4005` |
| Beacon REST port | `3499 + i` | `3500` | `3501` | `3502` | `3505` |
| Beacon P2P TCP | `12999 + i` | `13000` | `13001` | `13002` | `13005` |
| Beacon P2P UDP | `11999 + i` | `12000` | `12001` | `12002` | `12005` |
| Validator wallet | `validator_wallet{i}` | `validator_wallet1` | `validator_wallet2` | `validator_wallet3` | `validator_wallet6` |

Use these formulas when connecting MetaMask, querying RPC, or debugging individual nodes.

---

## Generate 3-Validator PoS Genesis (Manual Steps)

There are three ways to get validator keys:

- **Option A (recommended):** Use Prysm's deterministic interop keys -- fastest, no external tooling needed
- **Option B (advanced):** Generate wallet-based validator keys with the Ethereum Staking Deposit CLI inside WSL
- **Option C (advanced):** Generate wallet-based validator keys with the Python source directly in PowerShell

> **Note:** The released Windows `deposit.exe` binary cannot generate valid deposits for this custom devnet because it does not support `--devnet_chain_setting` in `new-mnemonic`. If you want wallet-based keys, use Option B (WSL) or Option C (Python in PowerShell).

---

### Option A: Interop validators (recommended)

This is the fastest path. Prysm generates `N` deterministic validator keys internally from a built-in seed. No staking CLI, no wallets, no passwords.

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))
$N = 6

.\prysmctl.exe testnet generate-genesis `
  --num-validators=$N `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=$futureTime
```

This creates:
- `genesis.ssz` — beacon chain genesis state with `N` built-in validators
- `genesis-pos.json` — finalized Geth genesis with correct fork timestamps

Use the **Interop Validators** commands later in this guide.

> Replace `$N` with however many nodes/validators you want. Every node gets one validator in the default setup.

---

### Option B: Generate wallet-based validator keys with WSL

This uses the official Linux `deposit` binary inside Windows Subsystem for Linux. It supports `--devnet_chain_setting`, so the deposit signatures are valid for the local devnet without any patching.

#### Enable and install WSL (if not already installed)

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

Restart your machine when prompted. After reboot, Ubuntu will finish setup and ask for a Linux username and password.

Verify WSL is ready:

```powershell
wsl --status
```

#### Step 1 — Download the Linux staking-deposit-cli inside WSL

Open a WSL terminal from PowerShell:

```powershell
wsl
```

Inside WSL, download and extract the Linux staking-deposit-cli:

```bash
cd /mnt/c/BlocksScan/Private-Ethereum-Blockchain-setup-using-Geth/private_ethereum_setup

curl -L -o staking-deposit-cli-linux.tar.gz https://github.com/ethereum/staking-deposit-cli/releases/download/v2.8.0/staking_deposit-cli-948d3fc-linux-amd64.tar.gz
tar -xzf staking-deposit-cli-linux.tar.gz
```

#### Step 2 — Generate keys

Still inside WSL, run the interactive CLI. It will ask for a keystore password, ask you to confirm it, then print a **24-word mnemonic**. Save the mnemonic and password somewhere safe.

```bash
cd /mnt/c/BlocksScan/Private-Ethereum-Blockchain-setup-using-Geth/private_ethereum_setup

mkdir -p wallet_setup/validator_keys

./staking_deposit-cli-948d3fc-linux-amd64/deposit new-mnemonic \
  --num_validators 3 \
  --devnet_chain_setting '{"network_name": "localdev", "genesis_fork_version": "20000089", "genesis_validator_root": "0000000000000000000000000000000000000000000000000000000000000000"}' \
  --folder wallet_setup/validator_keys
```

This creates:
- `wallet_setup/validator_keys/validator_keys/deposit_data-*.json` (nested folder — move it up)
- `wallet_setup/validator_keys/validator_keys/keystore-m_12381_3600_*.json`

#### Step 3 — Prepare files in PowerShell

Exit WSL (`exit`) and run these PowerShell commands:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

# Move files out of the nested folder
Move-Item -Path "wallet_setup\validator_keys\validator_keys\*" -Destination "wallet_setup\validator_keys\" -Force
Remove-Item -Recurse -Force "wallet_setup\validator_keys\validator_keys"

# Rename deposit data file
$path = Get-ChildItem -Path "wallet_setup\validator_keys" -Filter "deposit_data-*.json" | Select-Object -First 1
Remove-Item -Force "wallet_setup\validator_keys\deposit_data.json" -ErrorAction SilentlyContinue
Rename-Item -Path $path.FullName -NewName "deposit_data.json" -Force
```

#### Step 4 — Create password files

Use the **same keystore password you typed in the deposit CLI** (not a placeholder). The wallet password can be anything you choose; Prysm uses it to encrypt the validator wallet.

```powershell
# Replace the value inside the quotes with the actual keystore password from Step 2
"my_keystore_password" | Out-File -FilePath "wallet_setup\account_password.txt" -Encoding ASCII -NoNewline

# Replace the value inside the quotes with a wallet password of your choice
"my_wallet_password"   | Out-File -FilePath "wallet_setup\wallet_password.txt" -Encoding ASCII -NoNewline
```

> **Important:** These files contain secrets. They are listed in `.gitignore` and must never be committed to Git.

#### Step 5 — Import keystores into 3 separate Prysm wallets

Create per-validator directories and copy one keystore into each directory:

```powershell
New-Item -ItemType Directory -Path "wallet_setup\keys1","wallet_setup\keys2","wallet_setup\keys3" -Force

Get-ChildItem -Path "wallet_setup\validator_keys" -Filter "keystore-m_12381_3600_*_0_0-*.json" | ForEach-Object {
    $idx = [int]($_.Name -split '_')[3]
    $dest = "wallet_setup\keys$($idx + 1)"
    Copy-Item -Path $_.FullName -Destination $dest -Force
    Write-Host "Copied $($_.Name) -> $dest"
}
```

If the copy command prints nothing, copy the first three keystores sorted by name:

```powershell
$files = Get-ChildItem -Path "wallet_setup\validator_keys" -Filter "keystore-m_*.json" | Sort-Object Name
for ($i = 0; $i -lt 3; $i++) {
    $dest = "wallet_setup\keys$($i + 1)"
    Copy-Item -Path $files[$i].FullName -Destination $dest -Force
    Write-Host "Copied $($files[$i].Name) -> $dest"
}
```

Then import each keystore directory into its own Prysm wallet:

```powershell
.\validator.exe accounts import --wallet-dir=validator_wallet1 --keys-dir=wallet_setup\keys1 --wallet-password-file=wallet_setup\wallet_password.txt --account-password-file=wallet_setup\account_password.txt --accept-terms-of-use
.\validator.exe accounts import --wallet-dir=validator_wallet2 --keys-dir=wallet_setup\keys2 --wallet-password-file=wallet_setup\wallet_password.txt --account-password-file=wallet_setup\account_password.txt --accept-terms-of-use
.\validator.exe accounts import --wallet-dir=validator_wallet3 --keys-dir=wallet_setup\keys3 --wallet-password-file=wallet_setup\wallet_password.txt --account-password-file=wallet_setup\account_password.txt --accept-terms-of-use
```

#### Step 6 — Generate genesis from the deposit data

```powershell
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))

.\prysmctl.exe testnet generate-genesis `
  --num-validators=0 `
  --deposit-json-file=wallet_setup\validator_keys\deposit_data.json `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=$futureTime
```

> `--num-validators=0` tells Prysm not to create additional interop validators; the 3 validators come entirely from `deposit_data.json`.

This creates:
- `genesis.ssz` — beacon chain genesis state
- `genesis-pos.json` — finalized Geth genesis with correct fork timestamps

---

### Option C: Generate wallet-based validator keys with Python source in PowerShell

If you do not want to use WSL, you can run the staking-deposit-cli Python source directly in PowerShell.

#### Step 1 — Install the Python staking-deposit-cli

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

python -V

Invoke-WebRequest -Uri "https://github.com/ethereum/staking-deposit-cli/archive/refs/tags/v2.8.0.zip" -OutFile "staking-deposit-cli-src.zip"
Expand-Archive -Path "staking-deposit-cli-src.zip" -DestinationPath "." -Force

cd staking-deposit-cli-2.8.0
pip install -r requirements.txt
python setup.py install
cd ..
```

#### Step 2 — Generate keys

Create the output directory first, then run the interactive CLI. It will ask for a keystore password, ask you to confirm it, then print a **24-word mnemonic**. Save the mnemonic and password somewhere safe.

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

New-Item -ItemType Directory -Path "wallet_setup\validator_keys" -Force

python .\staking-deposit-cli-2.8.0\staking_deposit\deposit.py new-mnemonic `
  --num_validators 3 `
  --devnet_chain_setting '{"network_name": "localdev", "genesis_fork_version": "20000089", "genesis_validator_root": "0000000000000000000000000000000000000000000000000000000000000000"}' `
  --folder wallet_setup\validator_keys
```

This creates:
- `wallet_setup\validator_keys\validator_keys\deposit_data-*.json` (nested folder — move it up)
- `wallet_setup\validator_keys\validator_keys\keystore-m_12381_3600_*.json`

Move the files out of the nested folder and rename the deposit data file:

```powershell
Move-Item -Path "wallet_setup\validator_keys\validator_keys\*" -Destination "wallet_setup\validator_keys\" -Force
Remove-Item -Recurse -Force "wallet_setup\validator_keys\validator_keys"

$path = Get-ChildItem -Path "wallet_setup\validator_keys" -Filter "deposit_data-*.json" | Select-Object -First 1
Remove-Item -Force "wallet_setup\validator_keys\deposit_data.json" -ErrorAction SilentlyContinue
Rename-Item -Path $path.FullName -NewName "deposit_data.json" -Force
```

#### Step 3 — Create password files

Use the **same keystore password you typed in the deposit CLI** (not a placeholder). The wallet password can be anything you choose; Prysm uses it to encrypt the validator wallet.

```powershell
# Replace the value inside the quotes with the actual keystore password from Step 2
"my_keystore_password" | Out-File -FilePath "wallet_setup\account_password.txt" -Encoding ASCII -NoNewline

# Replace the value inside the quotes with a wallet password of your choice
"my_wallet_password"   | Out-File -FilePath "wallet_setup\wallet_password.txt" -Encoding ASCII -NoNewline
```

> **Important:** These files contain secrets. They are listed in `.gitignore` and must never be committed to Git.

#### Step 4 — Import keystores into 3 separate Prysm wallets

Same as Option B Step 5.

#### Step 5 — Generate genesis from the deposit data

Same as Option B Step 6.

---

## Initialize the Geth Datadirs

```powershell
$N = 6
for ($i = 1; $i -le $N; $i++) {
    .\geth.exe init --datadir=node$i --state.scheme hash genesis-pos.json
}
```

> **Important:** Use `--state.scheme hash` with Geth 1.17 for this local PoS setup. Replace `$N` with your desired node count.

---

## Quick Start: One-Command Network Launch

If you used Option B or C (wallet-based validators) and imported exactly 3 wallets, use the legacy 3-node script:

```powershell
.\start-wallet-network.ps1
```

For N wallet-based nodes, use:

```powershell
.\start-wallet-network-n.ps1 -NodeCount 6
```

If you used Option A (interop validators), use:

```powershell
.\start-interop-network.ps1 -NodeCount 6
```

The N-node scripts stop old processes, regenerate genesis, initialize datadirs, and start all EL/CL/VC processes automatically.

The 3-node legacy script:
1. Stops any running `geth`, `beacon-chain`, and `validator` processes
2. Clears the validator slashing-protection DB (`%LOCALAPPDATA%\Eth2`)
3. Regenerates `genesis.ssz` and `genesis-pos.json` from `wallet_setup\validator_keys\deposit_data.json`
4. Re-initializes the three Geth datadirs
5. Starts N Geth nodes, N beacon nodes, and N wallet-based validators
6. Meshes Geth nodes via `--bootnodes` and beacon nodes via `--peer`

Wait for the genesis time printed in the beacon windows, then verify:

```powershell
.\check-network-health.ps1 -NodeCount 6 -Watch
```

If you prefer to start each component manually, continue with the next sections.

---

## Manual Start: Geth Node 1

PowerShell window 1:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\geth.exe `
  --datadir node1 `
  --port 30306 `
  --networkid 12345 `
  --syncmode full `
  --state.scheme hash `
  --http --http.port 18545 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" --http.vhosts="*" --http.addr 127.0.0.1 `
  --authrpc.port 8551 --authrpc.addr 127.0.0.1 --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex `
  --ipcpath geth1.ipc
```

Wait until you see `HTTP server started endpoint=127.0.0.1:18545`, then fetch Node 1's enode:

```powershell
$enode1 = (.\geth.exe attach --exec "admin.nodeInfo.enode" http://127.0.0.1:18545).Trim().Trim('"')
Write-Host "Node1 enode: $enode1"
```

> **Important:** If the enode contains your external/public IP, replace that IP with `127.0.0.1` in the `--bootnodes` strings below. The enode must use a reachable IP for Nodes 2 and 3 on this machine.

Example fix:

```powershell
$enode1Local = $enode1 -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:'
Write-Host "Node1 local enode: $enode1Local"
```

---

## Manual Start: Geth Nodes 2 and 3

PowerShell window 2 (replace `\u003cENODE1\u003e` with the local enode value):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\geth.exe `
  --datadir node2 `
  --port 30307 `
  --networkid 12345 `
  --syncmode full `
  --state.scheme hash `
  --http --http.port 18546 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" --http.vhosts="*" --http.addr 127.0.0.1 `
  --authrpc.port 8552 --authrpc.addr 127.0.0.1 --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex `
  --ipcpath geth2.ipc `
  --bootnodes "\u003cENODE1\u003e"
```

PowerShell window 3:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\geth.exe `
  --datadir node3 `
  --port 30308 `
  --networkid 12345 `
  --syncmode full `
  --state.scheme hash `
  --http --http.port 18547 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" --http.vhosts="*" --http.addr 127.0.0.1 `
  --authrpc.port 8553 --authrpc.addr 127.0.0.1 --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex `
  --ipcpath geth3.ipc `
  --bootnodes "\u003cENODE1\u003e"
```

> **Why `--ipcpath`?** Each Geth node needs a unique IPC pipe. Without it, Node 2/3 try to open the default pipe, which Node 1 already owns, causing `Access is denied`.

> For more than 3 nodes, use the formulas in the **Port Reference** table and pass the Node 1 enode to every other node.

---

## Verify Execution Peering

PowerShell window 4:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18545
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18546
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18547
```

If the counts are 0, manually connect them (use the real local enodes):

```powershell
$enode1 = (.\geth.exe attach --exec "admin.nodeInfo.enode" http://127.0.0.1:18545).Trim().Trim('"') -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:'
$enode2 = (.\geth.exe attach --exec "admin.nodeInfo.enode" http://127.0.0.1:18546).Trim().Trim('"') -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:'
$enode3 = (.\geth.exe attach --exec "admin.nodeInfo.enode" http://127.0.0.1:18547).Trim().Trim('"') -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:'

.\geth.exe attach --exec "admin.addPeer('$enode2')" http://127.0.0.1:18545
.\geth.exe attach --exec "admin.addPeer('$enode3')" http://127.0.0.1:18545
.\geth.exe attach --exec "admin.addPeer('$enode1')" http://127.0.0.1:18546
.\geth.exe attach --exec "admin.addPeer('$enode3')" http://127.0.0.1:18546
.\geth.exe attach --exec "admin.addPeer('$enode1')" http://127.0.0.1:18547
.\geth.exe attach --exec "admin.addPeer('$enode2')" http://127.0.0.1:18547
```

---

## Realistic Sync: Start Node 1 First, Then Nodes 2 and 3 (Wallet-Based Validators)

To demonstrate real beacon-chain syncing, start Node 1 first and let it build some chain history. Then start Nodes 2 and 3 so they actually download and verify blocks from Node 1.

The validator commands below use the wallet-based keystores imported earlier. If you used interop genesis instead, see the **Interop Validators** subsection at the end of this section.

### Start Node 1 beacon and validator

PowerShell window 5 — Beacon Node 1:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\beacon-chain.exe `
  --datadir beacondata1 `
  --min-sync-peers 0 `
  --genesis-state genesis.ssz `
  --chain-config-file chain-config.yaml `
  --contract-deployment-block 0 `
  --deposit-contract 0x0000000000000000000000000000000000000000 `
  --rpc-host 127.0.0.1 --rpc-port 4000 `
  --grpc-gateway-host 127.0.0.1 --grpc-gateway-port 3500 `
  --execution-endpoint http://127.0.0.1:8551 `
  --jwt-secret jwt.hex `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --minimum-peers-per-subnet 0 `
  --disable-staking-contract-check `
  --interop-eth1data-votes `
  --p2p-tcp-port 13000 --p2p-udp-port 12000 `
  --accept-terms-of-use
```

PowerShell window 8 — Validator 1:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --datadir validator_wallet1 --wallet-dir validator_wallet1 `
  --wallet-password-file wallet_setup\wallet_password.txt `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4000 `
  --accept-terms-of-use
```

> **Note:** `--datadir` and `--wallet-dir` point to the same directory. The directory holds both the imported wallet and the validator's local slashing-protection database. Each validator process must have its own `--datadir`; otherwise the slashing DB is locked by another process.

Wait until Node 1 has produced at least 20–30 blocks. You can watch it with:

```powershell
while ($true) {
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:18545' -Method POST -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
    Write-Host "Node 1 block: $($r.result)"
    Start-Sleep -Seconds 5
}
```

Once the block number is `0x20` or higher, capture Beacon Node 1's identity:

```powershell
$id = Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/identity' -TimeoutSec 10
$b1id = $id.data.peer_id
$b1addr = $id.data.p2p_addresses | Where-Object { $_ -like "*/tcp/13000/p2p/*" } | Select-Object -First 1
Write-Host "Beacon1 peer id: $b1id"
Write-Host "Beacon1 tcp multiaddr: $b1addr"
```

If the identity endpoint fails, read it from the log:

```powershell
Select-String -Path "beacondata1\*.log" -Pattern "Running node with peer id of" | Select-Object -Last 1
```

> **Note:** Prysm may advertise its external/interface IP (`172.31.x.x` or similar) instead of `127.0.0.1`. Use the exact `p2p_addresses` value printed above in the `--peer` flags for Nodes 2 and 3. If it shows `127.0.0.1`, use that; otherwise use the interface IP.

### Start Nodes 2 and 3 after Node 1 has history

Now start Geth Nodes 2 and 3 (they will sync execution blocks from Node 1), then their beacon nodes (they will sync consensus blocks from Beacon Node 1).

>
> **Important:** Replace `<BEACON1_MULTIADDR>` with the full multiaddr printed by the identity command (e.g. `/ip4/127.0.0.1/tcp/13000/p2p/16Uiu2...` or `/ip4/172.31.176.1/tcp/13000/p2p/16Uiu2...`). Do not use a different peer ID than the one Node 1 reports.

PowerShell window 6 — Beacon Node 2 (replace `<BEACON1_MULTIADDR>`):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\beacon-chain.exe `
  --datadir beacondata2 `
  --min-sync-peers 1 `
  --genesis-state genesis.ssz `
  --chain-config-file chain-config.yaml `
  --contract-deployment-block 0 `
  --deposit-contract 0x0000000000000000000000000000000000000000 `
  --rpc-host 127.0.0.1 --rpc-port 4001 `
  --grpc-gateway-host 127.0.0.1 --grpc-gateway-port 3501 `
  --execution-endpoint http://127.0.0.1:8552 `
  --jwt-secret jwt.hex `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --minimum-peers-per-subnet 1 `
  --disable-staking-contract-check `
  --interop-eth1data-votes `
  --p2p-tcp-port 13001 --p2p-udp-port 12001 `
  --peer <BEACON1_MULTIADDR> `
  --force-clear-db `
  --accept-terms-of-use
```

PowerShell window 7 — Beacon Node 3:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\beacon-chain.exe `
  --datadir beacondata3 `
  --min-sync-peers 1 `
  --genesis-state genesis.ssz `
  --chain-config-file chain-config.yaml `
  --contract-deployment-block 0 `
  --deposit-contract 0x0000000000000000000000000000000000000000 `
  --rpc-host 127.0.0.1 --rpc-port 4002 `
  --grpc-gateway-host 127.0.0.1 --grpc-gateway-port 3502 `
  --execution-endpoint http://127.0.0.1:8553 `
  --jwt-secret jwt.hex `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --minimum-peers-per-subnet 1 `
  --disable-staking-contract-check `
  --interop-eth1data-votes `
  --p2p-tcp-port 13002 --p2p-udp-port 12002 `
  --peer <BEACON1_MULTIADDR> `
  --force-clear-db `
  --accept-terms-of-use
```

PowerShell window 9 — Validator 2:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --datadir validator_wallet2 --wallet-dir validator_wallet2 `
  --wallet-password-file wallet_setup\wallet_password.txt `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4001 `
  --accept-terms-of-use
```

PowerShell window 10 — Validator 3:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --datadir validator_wallet3 --wallet-dir validator_wallet3 `
  --wallet-password-file wallet_setup\wallet_password.txt `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4002 `
  --accept-terms-of-use
```

### Watch the realistic sync

Check Beacon Node 2 and 3 sync status right after startup:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3501/eth/v1/node/syncing'
Invoke-RestMethod -Uri 'http://127.0.0.1:3502/eth/v1/node/syncing'
```

You should see:
- `is_syncing: true`
- `sync_distance` showing how many slots behind Node 1 they are

After a few seconds the `sync_distance` drops to `0` and `is_syncing` becomes `false`. This proves the beacon nodes are genuinely downloading and verifying consensus history from Node 1, just like a real Ethereum node catching up to the network.

> **Why stagger the startup?** In a real network, nodes join after the chain has already produced many blocks. They must download history and catch up. Starting Node 1 first, then Nodes 2 and 3, reproduces this behavior so you can observe `is_syncing: true` dropping to `false`.

### Interop Validators (fallback)

If you generated `genesis.ssz` with `--num-validators=3` (Option C) instead of wallet-based deposit data, use these validator commands. They use deterministic interop keys and do not require imported wallets.

PowerShell window 8 — Validator 1:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --datadir validator_wallet1 --wallet-dir validator_wallet1 `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4000 `
  --interop-num-validators 1 --interop-start-index 0 `
  --accept-terms-of-use
```

PowerShell window 9 — Validator 2:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --datadir validator_wallet2 --wallet-dir validator_wallet2 `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4001 `
  --interop-num-validators 1 --interop-start-index 1 `
  --accept-terms-of-use
```

PowerShell window 10 — Validator 3:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --datadir validator_wallet3 --wallet-dir validator_wallet3 `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4002 `
  --interop-num-validators 1 --interop-start-index 2 `
  --accept-terms-of-use
```

---

## Verify the 3-Node Network

Check execution blocks on all nodes:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:18545' -Method POST -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
Invoke-RestMethod -Uri 'http://127.0.0.1:18546' -Method POST -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
Invoke-RestMethod -Uri 'http://127.0.0.1:18547' -Method POST -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Check beacon sync:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/syncing'
Invoke-RestMethod -Uri 'http://127.0.0.1:3501/eth/v1/node/syncing'
Invoke-RestMethod -Uri 'http://127.0.0.1:3502/eth/v1/node/syncing'
```

Check beacon peering:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/peers' | Select-Object -ExpandProperty data
Invoke-RestMethod -Uri 'http://127.0.0.1:3501/eth/v1/node/peers' | Select-Object -ExpandProperty data
Invoke-RestMethod -Uri 'http://127.0.0.1:3502/eth/v1/node/peers' | Select-Object -ExpandProperty data
```

Check execution peering:

```powershell
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18545
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18546
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18547
```

---

## Check Which Validator Proposed a Block

In PoS, validators take turns proposing blocks. Validator index `0` belongs to Node 1, `1` to Node 2, and `2` to Node 3.

Get the proposer of the latest beacon block:

```powershell
(Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v2/beacon/blocks/head').data.message.proposer_index
```

List proposers for the last 12 slots:

```powershell
$head = [int](Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/beacon/headers/head').data.header.message.slot
for ($s = [math]::Max(0, $head - 11); $s -le $head; $s++) {
  try {
    $b = Invoke-RestMethod -Uri "http://127.0.0.1:3500/eth/v2/beacon/blocks/$s"
    [pscustomobject]@{Slot=$s; Proposer=$b.data.message.proposer_index}
  } catch {
    [pscustomobject]@{Slot=$s; Proposer="missed"}
  }
}
```

This shows the network is rotating block production across the three validators.

---

## Send a Transaction and Verify Propagation

Run `send_tx.js` against Node 1 (it already uses port `18545`):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup
node send_tx.js
```

Expected output:

```text
From: 0x...
Balance before: 100000.0 ETH

--- PoS consensus checks before sending ---
Beacon client: Prysm/v7.1.0 (windows amd64)
Beacon syncing: false | optimistic: false
Current fork: 0x20000093 | epoch: 0
Execution block: 20 | difficulty: 0 | totalDifficulty: n/a | nonce: 0x0000000000000000 | miner: 0x...

Transaction hash: 0x...
Mined in execution block: 21
Gas used: 21000

--- PoS consensus details for the mined block ---
Execution block hash: 0x...
Execution difficulty: 0 | nonce: 0x0000000000000000 | miner: 0x...
Execution extraData: 0x...
Beacon slot: 21 | epoch: 0
Beacon proposer index: 0
Beacon parent root: 0x...
Beacon state root: 0x...
Beacon block root: 0x...

Balance after sender: 99989.999968499999853 ETH
Balance of recipient: 10.0 ETH
```

After the transaction is mined, verify the recipient balance on all nodes:

```powershell
$N = 6
$body = '{"jsonrpc":"2.0","method":"eth_getBalance","params":["RECIPIENT_ADDRESS","latest"],"id":1}'
for ($i = 1; $i -le $N; $i++) {
    $port = 18544 + $i
    Write-Host "Node $i port $port -> " -NoNewline
    Invoke-RestMethod -Uri "http://127.0.0.1:$port" -Method POST -ContentType "application/json" -Body $body | Select-Object -ExpandProperty result
}
```

All nodes should return the same non-zero balance, proving the transaction propagated and state is consistent across the network.

To use the cross-node verification script with more than 3 nodes:

```powershell
$env:NODE_COUNT = 6
node send_tx_node1_to_node2.js
```

### How this proves PoS

`send_tx.js` prints consensus evidence from the beacon node:

- **Beacon client**: Prysm is running and in sync
- **Current fork**: Deneb (`0x20000093`)
- **Execution difficulty**: 0 — no mining happens
- **Execution nonce**: 0 — no PoW nonce is required
- **Block miner**: the validator fee recipient, not a mining pool
- **Beacon slot / epoch / proposer index**: show the block was proposed by a validator selected by the PoS protocol
- **Beacon state root / block root**: cryptographic anchors of the consensus state

Because the execution block has zero difficulty and zero nonce, yet the chain advances and includes transactions, the network is clearly running Proof-of-Stake (Gasper) consensus, not Proof-of-Work.

---

## Send a Transaction from Node 1 Wallet to Node 2 Wallet

This demo sends ETH from the funded wallet in `node1/keystore` to a separate wallet stored in `node2/keystore`. The transaction is submitted through Node 1's RPC, but the balance change is visible on all nodes because they share the same blockchain state.

### Create a recipient wallet in Node 2

If `node2/keystore` is empty, create a wallet:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

"node2" | Out-File -FilePath "node2\password-clean" -Encoding ASCII -NoNewline

.\geth.exe account new --datadir node2 --password node2\password-clean
```

Save the printed address.

### Run the Node 1 to Node 2 transaction script

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

# Default is 3 nodes; set NODE_COUNT for larger networks
$env:NODE_COUNT = 6
node send_tx_node1_to_node2.js
```

Expected output:

```text
Loading Node 1 sender wallet...
Sender address (Node 1): 0x...

Loading Node 2 recipient wallet...
Recipient address (Node 2): 0x...

--- Balances before transaction ---
Node 1 sender balance: 100000.0 ETH
Node 2 recipient balance: 0.0 ETH

--- PoS consensus check before sending ---
Beacon client: Prysm/v7.1.0 (windows amd64)
Beacon syncing: false | optimistic: false
Current fork: 0x20000093 | epoch: 0
Execution block: 20 | difficulty: 0 | nonce: 0x0000000000000000 | miner: 0x...

Sending 10 ETH from Node 1 wallet to Node 2 wallet via Node 1 RPC...
Transaction hash: 0x...
Mined in execution block: 21
Gas used: 21000

--- PoS consensus details for the mined block ---
Execution block hash: 0x...
Execution difficulty: 0 | nonce: 0x0000000000000000 | miner: 0x...
Beacon slot: 21 | epoch: 0
Beacon proposer index: 0
Beacon block root: 0x...

--- Balances after transaction ---
Node 1 sender balance: 99989.999968499999706 ETH
Node 2 recipient balance: 10.0 ETH

--- Cross-node verification ---
Node on port 18545 -> sender: 99989.999968499999706 ETH, recipient: 10.0 ETH
Node on port 18546 -> sender: 99989.999968499999706 ETH, recipient: 10.0 ETH
Node on port 18547 -> sender: 99989.999968499999706 ETH, recipient: 10.0 ETH

Note: The transaction was submitted through Node 1 RPC, but the balance change is visible on all nodes because they share the same blockchain state.
```

This demonstrates that ETH moves from one address to another on the shared ledger, regardless of which Geth node receives the signed transaction first.

---

## Connect MetaMask to the Devnet

MetaMask can talk to **one Geth RPC endpoint at a time**. Because all nodes share the same chain state, any node works.

> **Already have the original funded account?** If `node1\keystore` contains the pre-funded account (`0x014BFF6c76d88e815075c0323C3904Fe635c2325`), you can export its private key directly with `node export-private-key.js` and import it into MetaMask, skipping the wallet-generation step below.

### Generate funded wallets for each node

Run this once to create one wallet per node, fund each in `genesis.json`, and export the private keys:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

# Create 5 wallets (one per node), fund each with 100,000 ETH
$env:WALLET_COUNT = 5
node create-funded-wallets.js
```

This writes:
- `node1/keystore/` ... `node5/keystore/` — Geth keystores
- `node1/password-clean` ... `node5/password-clean` — ASCII passwords
- `metamask-wallets.json` — addresses + private keys + RPC URLs
- `metamask-wallets.csv` — same data in CSV format

> **Security:** `metamask-wallets.json` and `.csv` contain private keys. Keep them local and never commit them.

You must regenerate `genesis-pos.json` and re-initialize the Geth datadirs after changing `genesis.json`:

```powershell
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))
$N = 5

.\prysmctl.exe testnet generate-genesis `
  --num-validators=$N `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=$futureTime

for ($i = 1; $i -le $N; $i++) {
    .\geth.exe init --datadir=node$i --state.scheme hash genesis-pos.json
}
```

Then start the network:

```powershell
.\start-interop-network.ps1 -NodeCount 5 -GenesisDelaySeconds 180
```

### Import a private key into MetaMask

1. Open `metamask-wallets.csv`.
2. Copy the `privateKey` for the node you want to use.
3. In MetaMask, click the account menu → **Import account** → paste the private key → **Import**.

### Add the custom network in MetaMask

| Setting | Value |
|---|---|
| Network name | `Local PoS Devnet` |
| New RPC URL | `http://127.0.0.1:18545` (or any node port) |
| Chain ID | `12345` |
| Currency symbol | `ETH` |
| Block explorer URL | leave blank |

Available RPC URLs for 5 nodes:
- Node 1: `http://127.0.0.1:18545`
- Node 2: `http://127.0.0.1:18546`
- Node 3: `http://127.0.0.1:18547`
- Node 4: `http://127.0.0.1:18548`
- Node 5: `http://127.0.0.1:18549`

If MetaMask says "Unable to connect", make sure the selected Geth node is running and try another node's RPC URL.

### Use the built-in MetaMask wallet page

Open `private_ethereum_setup\metamask-wallet.html` in a browser with MetaMask installed. It will:
- Add the `Local PoS Devnet` network
- Connect your MetaMask account
- Show the account balance
- Let you send ETH to another address

### Export a private key from an existing keystore

If you already have a Geth keystore and want its private key for MetaMask:

```powershell
node export-private-key.js
```

By default it reads `node1\keystore` and `node1\password-clean`. Override with:

```powershell
$env:KEYSTORE_DIR = "node2\keystore"
$env:PASSWORD_FILE = "node2\password-clean"
node export-private-key.js
```

---

## Test 5-Node PoS with MetaMask

This section walks through a complete end-to-end test: start a 5-node devnet, import funded accounts into MetaMask, send a transaction, and verify it propagated to all nodes.

### 1. Prepare wallets and genesis

If you have not already generated the 5 funded wallets:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

$env:WALLET_COUNT = 5
node create-funded-wallets.js
```

Then regenerate the PoS genesis and initialize all 5 datadirs:

```powershell
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))
$N = 5

.\prysmctl.exe testnet generate-genesis `
  --num-validators=$N `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=$futureTime

for ($i = 1; $i -le $N; $i++) {
    .\geth.exe init --datadir=node$i --state.scheme hash genesis-pos.json
}
```

### 2. Start the 5-node network

```powershell
.\start-interop-network.ps1 -NodeCount 5 -GenesisDelaySeconds 180
```

Wait for genesis time, then run the health check:

```powershell
.\check-network-health.ps1 -NodeCount 5 -Watch
```

Press `Ctrl+C` to exit once all 5 nodes show `BeaconSyncing = False` and `GethPeers > 0`.

Also verify all nodes are on the same head block:

```powershell
node test_5node_sync.js
```

Expected output:

```text
Node 1 (port 18545): block 24 - OK
Node 2 (port 18546): block 24 - OK
Node 3 (port 18547): block 24 - OK
Node 4 (port 18548): block 24 - OK
Node 5 (port 18549): block 24 - OK
All reachable nodes are in sync.
```

### 3. Import accounts into MetaMask

Open `metamask-wallets.csv` and import the private keys for Node 1 and Node 2:

1. In MetaMask: account menu → **Import account** → paste Node 1 private key → rename to `Node 1 Wallet`.
2. Repeat for Node 2 and rename to `Node 2 Wallet`.

Add the custom network in MetaMask:

| Setting | Value |
|---|---|
| Network name | `Local PoS Devnet` |
| New RPC URL | `http://127.0.0.1:18545` |
| Chain ID | `12345` |
| Currency symbol | `ETH` |

### 4. Send a transaction via MetaMask

1. Select `Node 1 Wallet` in MetaMask.
2. Click **Send**.
3. Paste the `Node 2 Wallet` address.
4. Enter an amount, e.g. `10` ETH, and confirm.
5. Wait ~12–24 seconds for the next block.

You can also use the local wallet page:

```powershell
start metamask-wallet.html
```

Select the Node 1 RPC, connect, and send to the Node 2 address.

### 5. Verify propagation across all 5 nodes

Run the automated test script:

```powershell
# Send 10 ETH from Node 1 wallet to Node 2 wallet via Node 3 RPC
$env:SENDER_NODE = 1
$env:RECIPIENT_NODE = 2
$env:RPC_NODE = 3
$env:AMOUNT_ETH = 10
node test_metamask_tx.js
```

Expected output:

```text
RPC node: http://127.0.0.1:18547 (Node 3)
Sender (Node 1): 0x...
Recipient (Node 2): 0x...

--- Balances before ---
Sender balance: 100000.0 ETH
Recipient balance: 100000.0 ETH

Sending 10 ETH...
Transaction hash: 0x...
Mined in block: 31

--- Cross-node balance verification ---
Node 1 (port 18545) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 2 (port 18546) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 3 (port 18547) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 4 (port 18548) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 5 (port 18549) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
```

All 5 nodes should show the same balances, proving the transaction was included in a PoS block and propagated across the network.

### 6. Verify via MetaMask

1. Switch MetaMask to `Node 2 Wallet`.
2. Refresh the balance — it should show `100010` ETH.
3. Optionally switch the RPC URL to `http://127.0.0.1:18549` (Node 5). The balance should be identical.

### Automated end-to-end run

To run the entire 5-node PoS + MetaMask test in one command:

```powershell
.\run-5node-metamask-test.ps1
```

This script stops old processes, generates 5 wallets, starts the devnet, waits for blocks, sends a cross-node transaction, verifies propagation, and stops the network. A detailed execution report is written to `5_pos_metamask.md` and a full log to `5node-metamask-test.log`.

---

## Network Keypair Reference

| Item | Value / Index | Notes |
|------|---------------|-------|
| Funded sender | `0x014BFF6c76d88e815075c0323C3904Fe635c2325` | Pre-funded in `private_ethereum_setup\genesis.json`, used by `send_tx.js` and `send_tx_node1_to_node2.js` |
| Node 2 recipient | first keystore in `node2\keystore` | Created with `geth account new --datadir node2`, receives transfers in demos |
| Fee recipient | `0x98608ADf9c785d54f40cDcf6700E990771b19226` | Used by Prysm validator for block rewards |
| Validator 1 | index `0` | Connected to Beacon Node 1 (`127.0.0.1:4000`) |
| Validator 2 | index `1` | Connected to Beacon Node 2 (`127.0.0.1:4001`) |
| Validator 3 | index `2` | Connected to Beacon Node 3 (`127.0.0.1:4002`) |

---

## Notes

- **N nodes:** `3N` processes must stay running — N Geth, N beacon, N validator, plus your verification shell.
- Use separate PowerShell windows for each process when starting manually.
- HTTP RPC runs on ports `18545`, `18546`, `18547`, ... `18544 + N`.
- Engine API uses ports `8551`, `8552`, `8553`, ... `8550 + N` with JWT auth.
- Beacon gRPC uses ports `4000`, `4001`, `4002`, ... `3999 + N`; REST gateways use `3500`, `3501`, `3502`, ... `3499 + N`.
- Each Geth node needs a unique `--ipcpath` in multi-node mode to avoid pipe conflicts.
- The `password-clean` file must be plain ASCII with no BOM; `Out-File -Encoding ASCII -NoNewline` creates this correctly.
- This is a local devnet. Do not use it for production.

---

## Troubleshooting

### `geth` is not recognized
Use `.\geth.exe` instead of `geth`, or add the `private_ethereum_setup` folder to your system PATH.

### Geth exits with terminal total difficulty error
You are using a genesis file meant for Clique. Use the provided `private_ethereum_setup\genesis.json` and regenerate `genesis-pos.json` with Prysm.

### Beacon node says "node is optimistic" or `el_offline` stays true
Ensure Geth is fully started and the Engine API connection is healthy. Check that `jwt.hex` is the same for both clients.

### `sync_distance` is greater than 0 but `is_syncing` is false
This means the beacon node sees a higher head but has **no peer** to download from. Verify peering:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3501/eth/v1/node/peers' | Select-Object -ExpandProperty data
```

If the list is empty:
1. Check Node 1's identity and copy the exact `p2p_addresses` value:
   ```powershell
   Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/identity' | Select-Object -ExpandProperty data
   ```
2. Make sure the `--peer` flag on Nodes 2/3 uses that exact peer ID and IP.
3. Verify Node 1 is listening on the IP shown by the identity endpoint (it may be `172.31.x.x` instead of `127.0.0.1`).
4. Check Windows Firewall allows Prysm on ports `13000`–`13002` (TCP) and `12000`–`12002` (UDP).

### Beacon nodes peer but head slots diverge slightly
This is normal when the network is producing blocks quickly. Small gaps of 1–3 slots with `sync_distance > 0` and `is_syncing: false` usually resolve within seconds. To see `is_syncing: true`, do a staggered start: stop Nodes 2/3, let Node 1 produce 30+ slots, then restart Nodes 2/3.

### Validator fails with slashing protection errors
Stop the validator, delete its slashing-protection database, and restart with `--force-clear-db` on the beacon node only when doing a fresh genesis:

```powershell
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:LOCALAPPDATA\Eth2"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "validator_wallet*"
```

### `send_tx.js` says "invalid password"
Ensure `node1\password-clean` was created with `-Encoding ASCII -NoNewline` and that the first keystore in `node1\keystore` belongs to the funded address.

### Chain does not produce blocks
Use a future `--genesis-time` (e.g. 120–180 seconds from now) and make sure the validators are running before that time.

### Geth nodes do not peer on localhost
Fetch Node 1's enode and use `--bootnodes` on Nodes 2/3, or use `admin.addPeer` manually. NAT can advertise an external IP; replace the external IP with `127.0.0.1` in the enode string when all nodes are on the same machine.

### `Fatal: Error starting protocol stack: open \.	ubeackslashgeth.ipc: Access is denied`
You are running multiple Geth nodes without unique `--ipcpath` values. Add `--ipcpath geth1.ipc`, `--ipcpath geth2.ipc`, and `--ipcpath geth3.ipc` to each node respectively.

### MetaMask shows "Unable to connect" or wrong chain ID
1. Make sure the selected Geth node is running and its HTTP port is reachable:
   ```powershell
   Invoke-RestMethod -Uri 'http://127.0.0.1:18545' -Method POST -ContentType 'application/json' -Body '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
   ```
2. Try another node's RPC URL (MetaMask can only use one at a time).
3. Ensure the Geth startup flags include `--http.corsdomain=* --http.vhosts=* --http.addr 127.0.0.1`.
4. If you restarted the devnet with a new genesis, reset MetaMask's account activity for this network: MetaMask → Settings → Advanced → Clear activity tab data.

### MetaMask balance does not update after a transaction
Wait 12–24 seconds for the next block to be produced. The devnet uses 12-second slots. If it still does not update, switch the RPC URL to another node or refresh the page.

### Want a fresh start

Stop all processes, then delete state for all nodes:

```powershell
.\stop-network.ps1
.\clean-state.ps1 -NodeCount 6
```

This removes `node$i\geth`, `beacondata$i`, `validator_wallet$i`, `genesis.ssz`, `genesis-pos.json`, logs, and the Prysm slashing DB. Keystore directories and `wallet_setup/` are preserved.

Then repeat from the genesis generation step.

---

## Expanding the Network: Create Any Number of Nodes

The 3-node setup is just an example. You can create a network with **any number of nodes** by changing the `NodeCount` parameter in the one-click scripts, or by following the general pattern below. The rules are:

1. Each Geth node needs a unique datadir, P2P port, HTTP port, Engine API port, and IPC pipe.
2. Each beacon node needs a unique datadir, gRPC port, REST port, P2P ports, and one `--peer` pointing to the bootstrap node.
3. Each validator needs its own imported wallet directory and password file (wallet-based) or its own `--interop-start-index` (interop).
4. To have `V` validators active from genesis, generate `V` wallet-based keystores + deposit data, then regenerate `genesis.ssz` with `--deposit-json-file` and `--num-validators=0`.

The easiest path is to use the scripts at the top of this guide:

```powershell
# Interop validators (recommended for testing)
.\start-interop-network.ps1 -NodeCount 6

# Wallet-based validators
.\start-wallet-network-n.ps1 -NodeCount 6
```

The rest of this section shows the manual equivalent for learning and customization.

### Stop everything

```powershell
.\stop-network.ps1
```

### Choose your node count

Pick a total number of nodes `N` (for example `N=6`). This creates Nodes 1 through N.

### Create a Node directory and account for each new node

For every new node `i` from `1` to `N`:

```powershell
$N = 6
for ($i = 1; $i -le $N; $i++) {
    New-Item -ItemType Directory -Path "node$i" -Force
    "node$i" | Out-File -FilePath "node$i\password-clean" -Encoding ASCII -NoNewline
    .\geth.exe account new --datadir node$i --password node$i\password-clean
}
```

If you want any of these addresses funded at genesis, add them to `genesis.json` under `alloc` before the next step.

### Generate wallet-based validator keys and deposit data

For a real network, generate `N` keystores and a single `deposit_data.json` with the WSL or Python staking-deposit-cli commands from Option B or C in the genesis section. For this example, assume you already have `N` keystore files and `deposit_data.json` in `wallet_setup\validator_keys\`.

Put each keystore into its own directory for import:

```powershell
$N = 5
for ($i = 1; $i -le $N; $i++) {
    New-Item -ItemType Directory -Path "wallet_setup\keys$i" -Force
    # Copy keystore-m_12381_3600_($i-1)_0_0-*.json into wallet_setup\keys$i
}
```

Import each keystore into its own Prysm wallet:

```powershell
$N = 5
for ($i = 1; $i -le $N; $i++) {
    .\validator.exe accounts import `
      --wallet-dir=validator_wallet$i `
      --keys-dir=wallet_setup\keys$i `
      --wallet-password-file=wallet_setup\wallet_password.txt `
      --account-password-file=wallet_setup\account_password.txt `
      --accept-terms-of-use
}
```

### Regenerate genesis from wallet deposit data

```powershell
$N = 5
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))

.\prysmctl.exe testnet generate-genesis `
  --num-validators=0 `
  --deposit-json-file=wallet_setup\validator_keys\deposit_data.json `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=$futureTime
```

> `--num-validators=0` prevents Prysm from creating extra interop validators. The `N` active validators come entirely from the deposit data.

### Initialize all Geth datadirs

```powershell
$N = 5
for ($i = 1; $i -le $N; $i++) {
    .\geth.exe init --datadir=node$i --state.scheme hash genesis-pos.json
}
```

### Start Geth nodes

For each node `i`, use the ports from the table below. Node 1 has no `--bootnodes`; Nodes 2..N use Node 1's enode.

```powershell
$N = 5

# Get Node 1 enode first after starting Node 1, then pass it to others.
# Example for node i:
# $p2p = 30305 + $i
# $http = 18544 + $i
# $auth = 8550 + $i
```

For Node `i`:

```powershell
$N = 5
$i = 1  # change to 2, 3, 4, 5

$gethP2P = 30305 + $i
$gethHttp = 18544 + $i
$gethAuth = 8550 + $i
$gethIpc = "geth$i.ipc"

# Node 1 starts without --bootnodes. Other nodes boot from Node 1.
$bootnodes = if ($i -eq 1) { "" } else { "--bootnodes `"$env:NODE1_ENODE`"" }

$cmd = ".\geth.exe --datadir node$i --port $gethP2P --networkid 12345 --syncmode full --state.scheme hash " +
       "--http --http.port $gethHttp --http.api eth,net,web3,engine,admin --http.corsdomain=* --http.vhosts=* --http.addr 127.0.0.1 " +
       "--authrpc.port $gethAuth --authrpc.addr 127.0.0.1 --authrpc.vhosts=* --authrpc.jwtsecret jwt.hex --ipcpath $gethIpc $bootnodes"

Invoke-Expression $cmd
```

### Start Beacon nodes

For Node `i`:

```powershell
$N = 5
$i = 1  # change for each node

$beaconGrpc = 3999 + $i
$beaconRest = 3499 + $i
$beaconTcp = 12999 + $i
$beaconUdp = 11999 + $i
$gethAuth = 8550 + $i
$minSyncPeers = if ($i -eq 1) { 0 } else { 1 }
$peerFlag = if ($i -eq 1) { "" } else { "--peer `"$env:BEACON1_MULTIADDR`"" }

$cmd = ".\beacon-chain.exe --datadir beacondata$i --min-sync-peers $minSyncPeers --genesis-state genesis.ssz " +
       "--chain-config-file chain-config.yaml --contract-deployment-block 0 --deposit-contract 0x0000000000000000000000000000000000000000 " +
       "--rpc-host 127.0.0.1 --rpc-port $beaconGrpc --grpc-gateway-host 127.0.0.1 --grpc-gateway-port $beaconRest " +
       "--execution-endpoint http://127.0.0.1:$gethAuth --jwt-secret jwt.hex --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 " +
       "--minimum-peers-per-subnet 1 --disable-staking-contract-check --interop-eth1data-votes " +
       "--p2p-tcp-port $beaconTcp --p2p-udp-port $beaconUdp $peerFlag --force-clear-db --accept-terms-of-use"

Invoke-Expression $cmd
```

### Start Validators

For Node `i`:

```powershell
$N = 5
$i = 1  # change for each node

$beaconGrpc = 3999 + $i

.\validator.exe `
  --datadir validator_wallet$i --wallet-dir validator_wallet$i `
  --wallet-password-file wallet_setup\wallet_password.txt `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:$beaconGrpc `
  --accept-terms-of-use
```

### Port reference for Node i

| Component | Formula for Node `i` | Example Node 4 |
|-----------|----------------------|----------------|
| Geth P2P port | `30305 + i` | `30309` |
| Geth HTTP port | `18544 + i` | `18548` |
| Engine API port | `8550 + i` | `8554` |
| Geth IPC pipe | `geth{i}.ipc` | `geth4.ipc` |
| Beacon gRPC port | `3999 + i` | `4003` |
| Beacon REST port | `3499 + i` | `3503` |
| Beacon P2P TCP | `12999 + i` | `13003` |
| Beacon P2P UDP | `11999 + i` | `12003` |
| Validator wallet | `validator_wallet{i}` | `validator_wallet4` |

### Important rules

- A new **Geth node** can join anytime with `--bootnodes` or `admin.addPeer`.
- A new **beacon node** can sync from existing peers with `--peer` and `--min-sync-peers 1`.
- A new **validator** can only be added from genesis (via wallet keystores and deposit data, as shown here) or through a real deposit contract and activation queue. This devnet has no real deposit contract, so genesis regeneration with new deposit data is the only option.

---

## Architecture

The diagram below shows the 3-node example. The same layered structure scales to any number of nodes: each Geth pairs with one beacon node, each beacon node pairs with one validator, and all Geth nodes peer with each other while all beacon nodes peer via libp2p.

```
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │ Geth 1   │◄──────►│ Geth 2   │◄──────►│ Geth 3   │ ... (N nodes)
        │:18545    │  p2p   │:18546    │  p2p   │:18547    │
        └────┬─────┘        └────┬─────┘        └────┬─────┘
             │ Engine API        │ Engine API        │ Engine API
             ▼                   ▼                   ▼
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │ Beacon 1 │◄──────►│ Beacon 2 │◄──────►│ Beacon 3 │
        │:4000     │ libp2p │:4001     │ libp2p │:4002     │
        └────┬─────┘        └────┬─────┘        └────┬─────┘
             │ gRPC              │ gRPC              │ gRPC
             ▼                   ▼                   ▼
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │Validator1│        │Validator2│        │Validator3│
        └──────────┘        └──────────┘        └──────────┘
```

For an arbitrary number of nodes, use the port formulas in the **Port Reference** table and the one-click scripts (`start-interop-network.ps1` or `start-wallet-network-n.ps1`).

---

## Detailed PoS Guide

For the full technical explanation, see [`POSE_SETUP_GUIDE.md`](./POSE_SETUP_GUIDE.md).

---

## Credits

Original Linux setup by LifnaJos. This Windows PoS adaptation was created to support Geth 1.17 and modern Ethereum consensus.
