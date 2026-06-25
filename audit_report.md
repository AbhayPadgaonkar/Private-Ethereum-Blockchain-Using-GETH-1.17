# Repository Audit Report

**Repository:** https://github.com/AbhayPadgaonkar/Private-Ethereum-Blockchain-Using-GETH-1.17.git  
**Branch:** main  
**Generated:** 2026-06-25  
**Purpose:** Windows-based private Ethereum Proof-of-Stake (PoS) devnet using Geth 1.17 + Prysm

---

## 1. Executive Summary

This repository has been converted from an older Clique (Proof-of-Authority) style setup to a modern **Proof-of-Stake (PoS)** private devnet. It runs **three Geth execution nodes**, **three Prysm beacon nodes**, and **three Prysm validators** on a single Windows machine.

**Important clarifications:**
- This is **NOT** Ethereum mainnet. It is a completely isolated local devnet.
- `chain-config.yaml` uses `PRESET_BASE: mainnet` only for parameters (slot time, epoch length), but the network has its own genesis, chain ID 12345, and fork versions.
- All binaries (`geth.exe`, `beacon-chain.exe`, `validator.exe`, `prysmctl.exe`) are **downloaded separately** and are not included in the repo.
- Generated files like `genesis-pos.json`, `genesis.ssz`, chaindata, logs, and `node_modules` are runtime artifacts and are intentionally **not committed**.

---

## 2. What Was Done

### 2.1 Documentation Rewritten

- `README.md` rewritten to document the 3-node PoS devnet setup
- `POSE_SETUP_GUIDE.md` updated with full technical PoS instructions
- Removed `README_WINDOWS.md`, `RELEVANCE_TO_XDC_GATEWAY.md`, and `PROJECT_OVERVIEW_AND_USE_CASES.md` to avoid duplication and confusion

### 2.2 Configuration Added

- `private_ethereum_setup/genesis.json` — PoS-ready Geth genesis funding the sender account
- `private_ethereum_setup/chain-config.yaml` — Prysm chain configuration with Deneb fork
- `private_ethereum_setup/jwt.hex` — JWT secret for Engine API authentication between Geth and Prysm

### 2.3 Keystores Added

- `private_ethereum_setup/node1/keystore/` — funded sender wallet used by transaction scripts
- `private_ethereum_setup/node2/keystore/` — recipient wallet for node-to-node demo
- `private_ethereum_setup/node1/password-clean` and `node2/password-clean` — ASCII password files

### 2.4 Transaction Scripts Added

- `private_ethereum_setup/send_tx.js` — sends a transaction and prints PoS consensus evidence
- `private_ethereum_setup/send_tx_node1_to_node2.js` — sends ETH from Node 1 wallet to Node 2 wallet and verifies balances on all nodes

### 2.5 Helper Scripts Added

- `private_ethereum_setup/start_beacon2.bat` — helper to start Beacon Node 2
- `private_ethereum_setup/start_beacon3.bat` — helper to start Beacon Node 3
- `private_ethereum_setup/prysm.bat` — Prysm binary download wrapper (legacy script)
- `private_ethereum_setup/package.json` — Node dependencies (ethers, web3)

---

## 3. Why We Did It

This section explains the rationale behind the major changes. Understanding the "why" makes the setup easier to maintain, debug, and extend.

### 3.1 Moved from Clique/PoA to Proof-of-Stake

- Ethereum mainnet switched to PoS in September 2022 ("The Merge"). A PoA devnet no longer reflects how Ethereum works today.
- PoS requires an execution client (Geth) *and* a consensus client (Prysm). Setting up both is the only way to run a realistic modern Ethereum devnet.
- This also lets us demonstrate real consensus concepts: slots, epochs, validators, attestations, and the Engine API.

### 3.2 Removed the Old README Files

- `README_WINDOWS.md`, `RELEVANCE_TO_XDC_GATEWAY.md`, and `PROJECT_OVERVIEW_AND_USE_CASES.md` described an older, single-node Clique setup or discussed use cases outside the current scope.
- Keeping them caused confusion because their instructions did not match the new PoS files.
- We consolidated everything into `README.md` (end-user guide) and `POSE_SETUP_GUIDE.md` (technical reference).

### 3.3 Created a 3-Node Network Instead of 1 Node

- One node cannot demonstrate **peer-to-peer sync** or consensus.
- With three nodes we can show:
  - Node 1 producing blocks while Nodes 2/3 sync.
  - Transactions reaching all three execution nodes.
  - Beacon nodes attesting to the same chain head.
- A 3-node setup is the minimum that looks like a real distributed network.

### 3.4 Added Keystores for Node 1 and Node 2

- Geth 1.17.3 removed the `personal` namespace, so we can no longer unlock accounts with `--unlock` or create/send transactions from the Geth console.
- The only practical way to send transactions is to load an existing keystore in Node.js (using `ethers` or `web3`) and sign locally.
- Node 1's keystore contains the pre-funded account.
- Node 2's keystore gives us a realistic **recipient** address for a node-to-node balance-transfer demo.

### 3.5 Added `password-clean` Files

- Windows text editors often save files with a **BOM** (Byte Order Mark) or CRLF line endings.
- Geth and Prysm sometimes fail to read passwords when extra bytes are present.
- `password-clean` files are saved as plain ASCII with no BOM and LF endings, so keystore import and signing work reliably.

### 3.6 Added `jwt.hex`

- After The Merge, the consensus client talks to the execution client over the **Engine API**.
- Geth and Prysm require a shared JWT secret to authenticate that connection.
- We committed a fixed `jwt.hex` so every run uses the same secret; this is acceptable for a local devnet but should **never** be reused on a public network.

### 3.7 Added `chain-config.yaml` with `PRESET_BASE: mainnet`

- `PRESET_BASE: mainnet` only means Prysm uses mainnet *parameter values* (12-second slots, 32 slots per epoch, etc.).
- It does **not** connect to mainnet. We changed `CONFIG_NAME` to `localdev` and set custom fork versions, chain ID, and deposit contract to make this clear.
- Using the mainnet preset avoids having to redefine hundreds of consensus parameters manually.

### 3.8 Chose Deneb as the Target Fork

- Deneb is a stable, recent Ethereum fork that introduces blobs (proto-danksharding).
- Targeting Deneb ensures the devnet supports the latest EL/CL handshake and avoids deprecated fork handling in Prysm v7.

### 3.9 Used `--state.scheme hash`

- Geth 1.17 introduced a new `path` state scheme, but it is still experimental and can be unstable for small local devnets.
- `hash` scheme is the older, well-tested mode and works reliably for a private network.

### 3.10 Gave Each Geth Node Its Own IPC Pipe (`geth1.ipc`, `geth2.ipc`, `geth3.ipc`)

- On Windows, Geth's IPC path becomes a named pipe.
- If all three nodes tried to use the same pipe name, only the first one would start.
- Separate pipe names let us attach `geth attach` or scripts to each node individually.

### 3.11 Set `--min-sync-peers 0` on Node 1 and `--min-sync-peers 1` on Nodes 2/3

- Node 1 is the **bootstrap** node. It must start even before any peers exist, so it cannot require peers to sync.
- Nodes 2 and 3 need at least one peer to download history from, so requiring one peer makes their sync realistic.
- Without this difference, Nodes 2/3 might report `is_syncing: false` at startup even though no actual sync has happened.

### 3.12 Wrote Transaction Scripts in Node.js

- Because Geth 1.17.3 has no `personal` namespace, we cannot unlock accounts inside Geth.
- Node.js lets us load keystores, sign transactions locally, and broadcast them to any RPC endpoint.
- Scripts also let us query multiple nodes in one run and verify that balances are identical across the network.

### 3.13 Used a Future `--genesis-time`

- All beacon nodes and validators must be running before the first slot.
- We generate the genesis 120–180 seconds in the future to give us time to start Geth, Prysm, and validators.
- If genesis time passes while starting, the network gets stuck at slot 0 and shows `el_offline`; the fix is simply to regenerate with a later timestamp.

### 3.14 Did Not Commit Binaries, Chain Data, or Genesis Outputs

- Binaries are large (~300 MB total) and platform-specific.
- Chain data and beacon databases are huge and change on every run.
- `genesis-pos.json` and `genesis.ssz` are regenerated from committed source files.
- Excluding these keeps the repository small, portable, and reproducible.

### 3.15 Wrote This Audit Report

- The repository mixes source files, runtime artifacts, and legacy files. Without a guide, fork maintainers may accidentally commit the wrong things.
- This report documents what is committed, what is not, and why each decision was made.

---

## 4. Committed Files Explained

| File | Status | Purpose |
|------|--------|---------|
| `README.md` | Modified | Main setup guide for 3-node PoS devnet |
| `POSE_SETUP_GUIDE.md` | Added/Modified | Detailed technical PoS guide |
| `private_ethereum_setup/chain-config.yaml` | Added | Prysm chain config (slot time, forks, deposit contract) |
| `private_ethereum_setup/genesis.json` | Modified | Geth genesis with PoS params and funded account |
| `private_ethereum_setup/jwt.hex` | Added | JWT secret for Geth-Prysm Engine API auth |
| `private_ethereum_setup/send_tx.js` | Added | Transaction script with PoS verification output |
| `private_ethereum_setup/send_tx_node1_to_node2.js` | Added | Node 1 to Node 2 transaction demo script |
| `private_ethereum_setup/start_beacon2.bat` | Added | Helper batch for Beacon Node 2 |
| `private_ethereum_setup/start_beacon3.bat` | Added | Helper batch for Beacon Node 3 |
| `private_ethereum_setup/prysm.bat` | Added | Prysm binary download wrapper |
| `private_ethereum_setup/package.json` | Added | Node.js dependencies |
| `private_ethereum_setup/node1/keystore/UTC--...` | Added | Funded sender keystore |
| `private_ethereum_setup/node2/keystore/UTC--...` | Added | Recipient keystore |
| `private_ethereum_setup/node1/password-clean` | Added | Sender keystore password |
| `private_ethereum_setup/node2/password-clean` | Added | Recipient keystore password |

---

## 5. Untracked Files Explained (Not Committed)

These are runtime artifacts generated during local operation. They should **not** be committed.

### 5.1 Binaries (must be downloaded separately)

| File | Why Untracked |
|------|---------------|
| `private_ethereum_setup/geth.exe` | Geth execution client binary (~106 MB) |
| `private_ethereum_setup/beacon-chain.exe` | Prysm beacon node binary (~62 MB) |
| `private_ethereum_setup/validator.exe` | Prysm validator binary (~52 MB) |
| `private_ethereum_setup/prysmctl.exe` | Prysm helper tool binary (~56 MB) |

**Download from:**
- Geth: https://geth.ethereum.org/downloads
- Prysm: https://github.com/OffchainLabs/prysm/releases

### 5.2 Generated Genesis Files

| File | Why Untracked |
|------|---------------|
| `private_ethereum_setup/genesis-pos.json` | Generated by `prysmctl` from `genesis.json` with fork timestamps |
| `private_ethereum_setup/genesis.ssz` | Beacon chain genesis state generated by `prysmctl` |

These are regenerated every time you run `prysmctl testnet generate-genesis`.

### 5.3 Chain Data (Geth)

| Directory | Why Untracked |
|-----------|---------------|
| `private_ethereum_setup/node1/geth/` | Node 1 blockchain database |
| `private_ethereum_setup/node2/geth/` | Node 2 blockchain database |
| `private_ethereum_setup/node3/geth/` | Node 3 blockchain database |

Contains blocks, state, transactions, peer data. Large and machine-specific.

### 5.4 Beacon Data (Prysm)

| Directory | Why Untracked |
|-----------|---------------|
| `private_ethereum_setup/beacondata1/` | Beacon Node 1 database |
| `private_ethereum_setup/beacondata2/` | Beacon Node 2 database |
| `private_ethereum_setup/beacondata3/` | Beacon Node 3 database |

Contains beacon blocks, attestations, validator state.

### 5.5 Validator Wallets (Prysm)

| Directory | Why Untracked |
|-----------|---------------|
| `private_ethereum_setup/validator_wallet1/` | Validator 1 slashing protection DB |
| `private_ethereum_setup/validator_wallet2/` | Validator 2 slashing protection DB |
| `private_ethereum_setup/validator_wallet3/` | Validator 3 slashing protection DB |

### 5.6 Node Modules

| Directory | Why Untracked |
|-----------|---------------|
| `private_ethereum_setup/node_modules/` | NPM dependencies installed by `npm install` |
| `private_ethereum_setup/package-lock.json` | NPM lock file (can be committed but not required) |

### 5.7 Log Files

| Files | Why Untracked |
|-------|---------------|
| `*.log` (root and subdirs) | Execution logs from Geth, Prysm, validators, and test commands |

### 5.8 Temporary/Debug Files

| File | Why Untracked |
|------|---------------|
| `private_ethereum_setup/test_decrypt.js` | Temporary debugging script |
| `private_ethereum_setup/tmp_import_key.json` | Temporary key import file |
| `private_ethereum_setup/walletpass.txt` | Temporary password file |
| `private_ethereum_setup/.beacon1_multiaddr` | Temporary beacon multiaddress cache |
| `account_create.log`, `account_new.log`, etc. | Historical command logs |

---

## 6. Modified but Not Staged Files

These files change during runtime and are not intended for commit:

- `private_ethereum_setup/genesis.json` — may be modified locally to fund different addresses
- `private_ethereum_setup/node1/geth/chaindata/*` — runtime blockchain database
- `private_ethereum_setup/node1/geth/nodes/*` — runtime peer data
- `private_ethereum_setup/node1/geth/transactions.rlp` — pending transaction pool
- `private_ethereum_setup/node1/password` — old binary password file (use `password-clean` instead)
- `private_ethereum_setup/node2/geth/chaindata/*` — runtime blockchain database
- `private_ethereum_setup/node2/geth/nodes/*` — runtime peer data

---

## 7. This Is Not Mainnet

**Common confusion:** Seeing `PRESET_BASE: mainnet` in `chain-config.yaml` and `Prysm/v7.1.0` in logs makes people think this connects to Ethereum mainnet.

**Facts:**
- `CONFIG_NAME: localdev` explicitly marks this as a local devnet
- `chainId: 12345` in `genesis.json` is not mainnet (mainnet is `1`)
- `GENESIS_FORK_VERSION: 0x20000089` is different from mainnet's `0x00000000`
- `DEPOSIT_CONTRACT_ADDRESS: 0x4242...4242` is a placeholder, not the real mainnet deposit contract
- There are no real ETH deposits; validators are created with `prysmctl testnet generate-genesis`
- The network runs on `127.0.0.1` only and does not connect to the public internet

---

## 8. How to Use This Repository

1. **Download binaries** into `private_ethereum_setup/`
2. **Run `npm install`** to install Node dependencies
3. **Generate genesis:**
   ```powershell
   $futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))
   .\prysmctl.exe testnet generate-genesis --num-validators=3 --output-ssz=genesis.ssz --chain-config-file=chain-config.yaml --geth-genesis-json-in=genesis.json --geth-genesis-json-out=genesis-pos.json --fork=deneb --genesis-time=$futureTime
   ```
4. **Initialize Geth:**
   ```powershell
   .\geth.exe init --datadir=node1 --state.scheme hash genesis-pos.json
   .\geth.exe init --datadir=node2 --state.scheme hash genesis-pos.json
   .\geth.exe init --datadir=node3 --state.scheme hash genesis-pos.json
   ```
5. **Start the 3-node network** following `README.md`
6. **Run transactions:**
   ```powershell
   node send_tx.js
   node send_tx_node1_to_node2.js
   ```

---

## 9. Recommended `.gitignore`

To avoid accidentally committing runtime artifacts, add this `.gitignore`:

```gitignore
# Binaries
*.exe

# Generated genesis files
genesis-pos.json
genesis.ssz

# Chain data
node1/geth/
node2/geth/
node3/geth/
beacondata/
beacondata1/
beacondata2/
beacondata3/

# Validator wallets
validator_wallet/
validator_wallet1/
validator_wallet2/
validator_wallet3/

# Node modules
node_modules/
package-lock.json

# Logs
*.log

# Temporary files
*.tmp
tmp_*
test_*.js
walletpass.txt
.beacon1_multiaddr

# Old password files
node1/password
node2/password
node3/password
```

---

## 10. Summary for Forkers

- This repo contains **source code, config, and scripts** for a local PoS devnet.
- It does **not** contain binaries, chain data, or generated genesis files.
- It does **not** connect to mainnet or any public network.
- After forking, download the required binaries, run `npm install`, generate the genesis, and follow `README.md`.
- All runtime artifacts are generated locally and should remain untracked.
