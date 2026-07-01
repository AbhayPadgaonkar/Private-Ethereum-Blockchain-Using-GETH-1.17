# Working Explanation: Private Ethereum PoS Devnet on Windows

This document explains how the 3-node private Ethereum Proof-of-Stake (PoS) devnet works, both in plain language and with technical detail. It covers the roles of Geth, Prysm beacon nodes, and Prysm validators, how they talk to each other, and what each command in the setup does.

---

## Table of Contents

1. [Big Picture](#big-picture)
2. [The Three Components](#the-three-components)
3. [Why Three Nodes?](#why-three-nodes)
4. [How the Chain Starts](#how-the-chain-starts)
5. [Step-by-Step Command Explanation](#step-by-step-command-explanation)
6. [Networking and Ports](#networking-and-ports)
7. [Block Production Flow](#block-production-flow)
8. [Transaction Flow](#transaction-flow)
9. [Syncing Behavior](#syncing-behavior)
10. [Security and Devnet Reality](#security-and-devnet-reality)

---

## Big Picture

Imagine a small private Ethereum network running on your own Windows machine. It has three full nodes. Each node contains:

- **Geth** — the execution client (the ledger and EVM)
- **Beacon chain** — the consensus client (the PoS coordinator)
- **Validator** — the key signer that participates in consensus

Together these 9 processes (3 Geth + 3 beacon + 3 validator) form a complete Ethereum PoS network. No real ETH is used. No mining happens. The chain advances because validators take turns proposing blocks.

**Plain analogy:**
- Geth is the bank's accounting computer.
- Beacon chain is the auctioneer that decides whose turn it is to publish the next ledger page.
- Validator is the authorized signatory who signs the ledger page when chosen.

---

## The Three Components

### 1. Geth (Execution Client)

**What it does:**
- Stores account balances, smart contract code, and world state
- Executes transactions using the Ethereum Virtual Machine (EVM)
- Builds execution blocks when instructed by the beacon node
- Peers with other Geth nodes to gossip transactions and blocks

**Plain terms:**
Geth is where the actual blockchain state lives. If you send 10 ETH from Alice to Bob, Geth updates their balances. If you deploy a smart contract, Geth stores it.

**Technical detail:**
Geth maintains several databases:
- `chaindata/` — block bodies, receipts, headers
- `trie/` — account and storage tries
- `blobpool/` — temporary blob transaction pool

In PoS mode, Geth does **not** mine. Instead it exposes the **Engine API** on an authenticated port (`8551`, `8552`, `8553`). The beacon node calls this API to tell Geth:
- "Build a block on top of this parent hash"
- "Here is the new payload; validate and apply it"
- "This block is finalized"

Communication uses a shared JWT secret (`jwt.hex`) so only the paired beacon node can control Geth.

---

### 2. Beacon Chain (Consensus Client)

**What it does:**
- Tracks PoS time in slots and epochs
- Decides which validator proposes the next block
- Gossips beacon blocks and attestations to other beacon nodes
- Finalizes blocks so they cannot be reverted
- Tells Geth what to do via the Engine API

**Plain terms:**
The beacon chain is the conductor of an orchestra. It keeps the beat (slots), points to the next musician (proposer), and makes sure everyone plays the same tune (consensus).

**Technical detail:**
The beacon chain runs the Gasper consensus protocol (a combination of LMD GHOST and Casper FFG).

- **Slots:** Every 12 seconds is one slot. In each slot, one validator is chosen to propose a beacon block.
- **Epochs:** 32 slots = one epoch (~6.4 minutes).
- **Attestations:** Validators vote on what they think is the correct head of the chain.
- **Finality:** After two epochs of strong attestation support, blocks are finalized.

In our devnet, the slot time and other parameters are defined in `chain-config.yaml`.

The beacon node has several APIs:
- **gRPC** (`4000`, `4001`, `4002`) — validators connect here to receive duties and submit signed blocks/attestations
- **REST API** (`3500`, `3501`, `3502`) — for querying sync status, peers, blocks, etc.
- **libp2p** (`13000`/`12000`, `13001`/`12001`, `13002`/`12002`) — for peer-to-peer gossip with other beacon nodes

---

### 3. Validator

**What it does:**
- Holds the BLS private keys for one or more validators
- Signs block proposals when selected by the protocol
- Signs attestations every epoch
- Submits signed messages to its beacon node

**Plain terms:**
The validator is a signing service. It does not decide what the block contains; it just signs what the beacon node tells it to sign. Having the keys means it represents a 32 ETH stake.

**Technical detail:**
Validators are identified by a public key (a BLS12-381 pubkey). Each validator has:
- A **validator index** in the beacon state (`0`, `1`, `2` in our devnet)
- A **withdrawal credential**
- A **32 ETH effective balance** baked into genesis

The validator process reads its keys from a **Prysm wallet** (`validator_wallet1`, `validator_wallet2`, `validator_wallet3`, ...). Each validator process must have its own wallet and its own `--datadir`, because Prysm keeps a slashing-protection database there. Running two validators with the same `--datadir` would lock the database and could cause double-signing.

---

## Why Multiple Nodes?

Ethereum PoS needs enough validators to reach consensus. A single validator can technically run a chain, but it cannot demonstrate:

- **Peering:** nodes finding and syncing from each other
- **Block rotation:** different validators proposing blocks
- **Finality:** enough attestations to finalize epochs
- **Realistic sync:** a late-joining node catching up to history

With three validators (the minimum practical number), we can show:
- Validator 0 proposes slot 0, validator 1 proposes slot 1, validator 2 proposes slot 2
- Nodes 2 and 3 can start after Node 1 and sync blocks
- Transactions propagate through execution-layer peering

**Scaling to N nodes:** The same pattern generalizes. With `N` validators, proposer duties rotate through indices `0` to `N-1`. More nodes consume more RAM/CPU but make the devnet look more like a real network. The one-click scripts (`start-interop-network.ps1`, `start-wallet-network-n.ps1`) and `check-network-health.ps1` handle the port arithmetic and startup ordering for any `N`.

**Trade-off:** This is still a tiny network. A handful of validators is enough for a devnet but would be insecure for production.

---

## How the Chain Starts

Starting the chain is a multi-step dance:

1. **Generate validator keys** with the Ethereum Staking Deposit CLI. This produces:
   - `keystore-m_*.json` — encrypted BLS signing keys
   - `deposit_data-*.json` — deposit messages that embed 32 ETH stakes into genesis

2. **Import keystores** into three separate Prysm wallets.

3. **Generate the beacon genesis state** with `prysmctl`. This:
   - Reads `deposit_data.json` (wallet-based) or uses `--num-validators=N` (interop)
   - Creates `genesis.ssz` — the initial beacon state with your N validators
   - Creates `genesis-pos.json` — the Geth genesis with correct PoS fork settings

4. **Initialize Geth datadirs** with `geth init`. This writes the genesis block into each Geth database.

5. **Start Node 1 first.** Geth and beacon node come up. Validator 1 connects and waits for genesis time.

6. **At genesis time**, validator 0 proposes the first block. The chain starts.

7. **Start Nodes 2..N.** They connect to Node 1 and sync execution + consensus history.

---

## Step-by-Step Command Explanation

### Clean previous state

```powershell
.\clean-state.ps1 -NodeCount 6
```

Or manually:

```powershell
Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$N = 6
for ($i = 1; $i -le $N; $i++) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i/geth"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "beacondata$i"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "validator_wallet$i"
}
Remove-Item -Force *.log -ErrorAction SilentlyContinue
Remove-Item -Force genesis.ssz, genesis-pos.json -ErrorAction SilentlyContinue
```

**Plain:** Kill old processes and delete old data so we start fresh.

**Technical:** Stale chaindata, beacon state, and validator wallets would conflict with a new genesis. Geth will refuse to init over mismatched genesis hash. Prysm may complain about stale genesis time. Deleting everything forces a clean rebuild.

---

### Generate validator keys

```powershell
New-Item -ItemType Directory -Path "wallet_setup\validator_keys" -Force

.\staking_deposit-cli-948d3fc-windows-amd64\deposit.exe new-mnemonic `
  --num_validators 3 `
  --chain mainnet `
  --folder wallet_setup\validator_keys
```

**Plain:** Create 3 validator accounts with secret keys. Save the mnemonic and password.

**Technical:**
- The CLI derives BLS12-381 key pairs from a random mnemonic using EIP-2334 paths (`m/12381/3600/<index>/0/0`).
- Each keystore is encrypted with the password you type (EIP-2335 format).
- Each deposit message contains the pubkey, withdrawal credentials, and a signature proving control of the pubkey.
- `--chain mainnet` selects the BLS signing domain; it does **not** put anything on real Ethereum.
- The CLI creates files inside a nested `validator_keys` folder; move them up before continuing.

---

### Create password files

```powershell
"my_keystore_password" | Out-File -FilePath "wallet_setup\account_password.txt" -Encoding ASCII -NoNewline
"my_wallet_password"   | Out-File -FilePath "wallet_setup\wallet_password.txt" -Encoding ASCII -NoNewline
```

**Plain:** Save the passwords as plain text files so Prysm can read them automatically.

**Technical:**
- `account_password.txt` decrypts the EIP-2335 keystores during import.
- `wallet_password.txt` encrypts the Prysm wallet that stores the imported keys.
- `-Encoding ASCII -NoNewline` ensures no BOM or trailing newline, which can cause password mismatch.

---

### Import keystores into Prysm wallets

```powershell
New-Item -ItemType Directory -Path "wallet_setup\keys1","wallet_setup\keys2","wallet_setup\keys3" -Force

Get-ChildItem -Path "wallet_setup\validator_keys" -Filter "keystore-m_12381_3600_*_0_0-*.json" | ForEach-Object {
    $idx = [int]($_.Name -split '_')[3]
    $dest = "wallet_setup\keys$($idx + 1)"
    Copy-Item -Path $_.FullName -Destination $dest -Force
}

.\validator.exe accounts import --wallet-dir=validator_wallet1 --keys-dir=wallet_setup\keys1 --wallet-password-file=wallet_setup\wallet_password.txt --account-password-file=wallet_setup\account_password.txt --accept-terms-of-use
```

**Plain:** Put each validator's key into its own folder, then import each folder into its own Prysm wallet.

**Technical:**
- Each `validator.exe` process needs its own wallet directory and `--datadir` to avoid slashing-DB conflicts.
- The import decrypts the keystore with the account password and re-encrypts it under the Prysm wallet password.
- The wallet stores an `all-accounts.keystore.json` file containing the imported pubkey.

---

### Generate PoS genesis

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

**Plain:** Build the very first beacon state and the matching Geth genesis file.

**Technical:**
- `--num-validators=0` means "do not create extra interop validators."
- `--deposit-json-file` reads our 3 real deposits and activates those validators.
- `genesis.ssz` is the SSZ-encoded initial beacon state.
- `genesis-pos.json` is the Geth genesis patched with correct PoS fork timestamps (`shanghaiTime`, `cancunTime`).
- `--fork=deneb` sets the initial consensus fork to Deneb.
- `--genesis-time=$futureTime` gives us 180 seconds to start validators before the chain begins.

---

### Initialize Geth datadirs

```powershell
.\geth.exe init --datadir=node1 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir=node2 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir=node3 --state.scheme hash genesis-pos.json
```

**Plain:** Tell each Geth node what the first block looks like.

**Technical:**
- `geth init` writes the genesis block into the database.
- `--state.scheme hash` uses the older hash-based state trie layout, which is more stable for Geth 1.17 in this local PoS setup.
- Each datadir (`node1`, `node2`, `node3`) gets its own copy of the same genesis.

---

### Start Geth Node 1

```powershell
.\geth.exe `
  --datadir node1 `
  --port 30306 `
  --networkid 123454321 `
  --syncmode full `
  --state.scheme hash `
  --http --http.port 18545 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" --http.vhosts="*" --http.addr 127.0.0.1 `
  --authrpc.port 8551 --authrpc.addr 127.0.0.1 --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex `
  --ipcpath geth1.ipc
```

**Plain:** Start the first Ethereum execution node.

**Technical:**
- `--datadir node1` — use the `node1` database.
- `--port 30306` — Geth peer-to-peer port.
- `--networkid 123454321` — private network identifier; must match on all nodes.
- `--syncmode full` — keep full blocks and receipts.
- `--http.port 18545` — JSON-RPC for sending transactions and queries.
- `--http.api eth,net,web3,engine,admin` — enabled RPC namespaces.
- `--authrpc.port 8551` — authenticated Engine API for the beacon node.
- `--authrpc.jwtsecret jwt.hex` — shared secret that proves the beacon node is allowed to use the Engine API.
- `--ipcpath geth1.ipc` — unique IPC pipe so multiple Geth nodes on the same machine do not collide.

---

### Start Geth Nodes 2 and 3

Same as Node 1, but with different ports/datadirs and `--bootnodes <ENODE1>`.

**Plain:** Start the other two execution nodes and connect them to Node 1.

**Technical:**
- `--bootnodes` gives the enode URL of Node 1 so Nodes 2/3 can find a peer.
- Each node uses a different P2P port, HTTP port, Engine port, and IPC path.
- The enode IP may need to be replaced with `127.0.0.1` if Geth advertises an external interface IP.

---

### Start Beacon Node 1

```powershell
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

**Plain:** Start the first consensus coordinator and connect it to Geth Node 1.

**Technical:**
- `--datadir beacondata1` — beacon chain database.
- `--min-sync-peers 0` — Node 1 is the bootstrap; it does not need peers to start.
- `--genesis-state genesis.ssz` — load the initial beacon state.
- `--chain-config-file chain-config.yaml` — local devnet parameters (slot time, fork versions).
- `--deposit-contract 0x0000...0000` — dummy deposit contract because we use genesis deposits.
- `--execution-endpoint http://127.0.0.1:8551` — Engine API URL of Geth Node 1.
- `--jwt-secret jwt.hex` — must match Geth's JWT secret.
- `--suggested-fee-recipient` — address that receives transaction fees for blocks proposed by validators connected to this beacon node.
- `--disable-staking-contract-check` — skip checking a real deposit contract.
- `--interop-eth1data-votes` — use mock eth1 data votes for the devnet.
- `--p2p-tcp-port 13000 --p2p-udp-port 12000` — libp2p ports for beacon peering.

---

### Start Validators

```powershell
.\validator.exe `
  --datadir validator_wallet1 --wallet-dir validator_wallet1 `
  --wallet-password-file wallet_setup\wallet_password.txt `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4000 `
  --accept-terms-of-use
```

**Plain:** Start the signing service for validator 0.

**Technical:**
- `--datadir validator_wallet1` — holds the slashing-protection DB and wallet.
- `--wallet-dir validator_wallet1` — imported wallet directory.
- `--wallet-password-file` — unlocks the Prysm wallet.
- `--beacon-rpc-provider 127.0.0.1:4000` — connects to Beacon Node 1's gRPC.
- The validator asks the beacon node for its duties and signs blocks/attestations when requested.

---

## Networking and Ports

| Component | Node 1 | Node 2 | Node 3 | Purpose |
|-----------|--------|--------|--------|---------|
| Geth P2P | 30306 | 30307 | 30308 | Execution peering |
| Geth HTTP RPC | 18545 | 18546 | 18547 | Transactions/queries |
| Geth Engine API | 8551 | 8552 | 8553 | Beacon → Geth control |
| Geth IPC | geth1.ipc | geth2.ipc | geth3.ipc | Named pipes |
| Beacon gRPC | 4000 | 4001 | 4002 | Validator connection |
| Beacon REST | 3500 | 3501 | 3502 | HTTP API for status |
| Beacon P2P TCP | 13000 | 13001 | 13002 | Consensus peering |
| Beacon P2P UDP | 12000 | 12001 | 12002 | Discovery |

**Why unique IPC paths?** Without `--ipcpath`, all three Geth nodes try to open the default pipe `\\.\pipe\geth.ipc`. Node 1 wins; Nodes 2/3 fail with `Access is denied`.

---

## Block Production Flow

1. **Slot begins.** Beacon Node 1's clock says it is slot `N`.
2. **Proposer selection.** The beacon state determines validator index `N % 3` is the proposer.
3. **Validator signs.** The validator process for that index asks the beacon node for a block to sign, signs it, and returns it.
4. **Beacon block created.** The beacon node wraps the execution payload inside a beacon block.
5. **Execution block built.** Before signing, the beacon node asked Geth via the Engine API to build an execution block containing pending transactions.
6. **Block broadcast.** The proposing beacon node gossips the block to Beacon Nodes 2 and 3.
7. **Attestations.** All validators attest to the new head. After enough attestations, the block is justified and later finalized.
8. **Execution sync.** Geth Nodes 2 and 3 receive the execution block via devp2p from Geth Node 1.

**Plain terms:** Every 12 seconds one validator gets a turn to publish the next page of the ledger. The beacon chain coordinates whose turn it is, and Geth actually writes the transactions.

---

## Transaction Flow

When you run `node send_tx.js`:

1. The script unlocks the funded keystore in `node1\keystore` using `node1\password-clean`.
2. It asks Node 1's Geth RPC for the current nonce and gas price.
3. It signs a transaction sending 10 ETH to a recipient address.
4. It submits the signed transaction to `http://127.0.0.1:18545` (Geth Node 1).
5. Geth Node 1 puts the transaction in its mempool and gossips it to Geth Nodes 2 and 3.
6. The next time the connected validator proposes a block, Geth includes the transaction in the execution payload.
7. The beacon node wraps it into a beacon block and broadcasts it.
8. All Geth nodes execute the transaction and update their state.

**Proof it is PoS:**
- The execution block has `difficulty: 0`.
- The execution block has `nonce: 0x0000000000000000`.
- There is no `ethhash` mining.
- The block still advances because a validator proposed it.

---

## Syncing Behavior

When Node 1 starts alone:
- Beacon Node 1: `is_syncing: false`, `sync_distance: 0`
- It produces blocks starting from genesis.

When Nodes 2 and 3 start later:
- Their beacon nodes see Node 1 has a higher head slot.
- They report `is_syncing: true` and a non-zero `sync_distance`.
- They download old beacon blocks from Node 1 and verify them.
- Once caught up, `is_syncing` becomes `false` and `sync_distance` becomes `0`.

This mirrors how a real Ethereum node joins the network after the chain has been running for a while.

---

## Security and Devnet Reality

**This is not Ethereum mainnet.**

- `chainId` is `12345`, not `1`.
- The 32 ETH deposits are simulated inside `genesis.ssz`; no real ETH moves.
- Validator keys are local test keys.
- The network runs on `127.0.0.1` and is not reachable from the internet.

**Why `--chain mainnet` in the deposit CLI?**
The staking CLI's `--chain` flag only selects the BLS signing domain. It does not broadcast anything. Prysm overrides the real network parameters with `chain-config.yaml` (`CONFIG_NAME: localdev`).

**Never commit secrets.**
- `wallet_setup/` — contains keystores and passwords
- `validator_wallet*/` — contains imported wallets
- `node*/keystore/` — contains funded account keystores

These are listed in `.gitignore` and should stay local.

---

## Summary

This devnet demonstrates a real Ethereum PoS network in miniature:

- **Geth** executes transactions and stores state.
- **Beacon chain** coordinates validators and finalizes blocks.
- **Validators** sign blocks and attestations.
- **Three nodes** prove peering, syncing, and block rotation.
- **Wallet-based validators** make the setup realistic instead of using fake interop keys.

The commands are intentionally explicit so you can see every moving part. For convenience, `start-wallet-network.ps1` automates the whole flow after you have generated and imported validator keys.
