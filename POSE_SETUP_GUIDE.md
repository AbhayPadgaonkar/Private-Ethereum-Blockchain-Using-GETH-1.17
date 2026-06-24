# Proof-of-Stake (PoS) Local Setup Guide for Geth 1.17 + Prysm on Windows

This guide sets up a local private Ethereum **Proof-of-Stake (PoS)** network using **Geth 1.17** as the execution client and **Prysm** as the consensus client.

This is the same consensus mechanism Ethereum mainnet uses after the Merge (Gasper: Casper FFG + LMD GHOST).

> ⚠️ This is significantly more complex than the old Clique setup. You will run ten processes: 3 Geth execution nodes, 3 Prysm beacon nodes, and 3 Prysm validators.

---

## What You Need

| Component | Purpose | Download |
|-----------|---------|----------|
| `geth.exe` v1.17.x | Execution client | https://geth.ethereum.org/downloads |
| `beacon-chain.exe` | Prysm beacon node | https://github.com/OffchainLabs/prysm/releases |
| `validator.exe` | Prysm validator client | Same Prysm release |
| `prysmctl.exe` | Prysm helper tool | Same Prysm release |

Download all Prysm binaries from the latest release and place them in your `private_ethereum_setup` folder.

---

## Step 1 — Update `genesis.json` for PoS

Geth 1.17 only supports PoS networks. The genesis must declare that the merge already happened at genesis.

Replace your `genesis.json` with this:

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
      "cancun": {
        "target": 3,
        "max": 6,
        "baseFeeUpdateFraction": 3338477
      },
      "prague": {
        "target": 6,
        "max": 9,
        "baseFeeUpdateFraction": 5007716
      },
      "osaka": {
        "target": 6,
        "max": 9,
        "baseFeeUpdateFraction": 5007716
      }
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

Key changes:
- Removed `clique` (no longer used)
- `terminalTotalDifficulty`: 0 — merge happens immediately
- `shanghaiTime` and `cancunTime`: 0 — enable withdrawals and blobs from genesis
- `difficulty`: 0 — PoS blocks have no difficulty
- `extradata`: `0x` — keep it empty to avoid odd-length hex errors
- `baseFeePerGas` and `blobSchedule` — required by Geth 1.17 for Cancun

> The `alloc` address should match the funded keystore created for `send_tx.js`. Use `geth account new` to create it if needed.

---

## Step 2 — Create `chain-config.yaml`

Create `chain-config.yaml` for Prysm:

```yaml
PRESET_BASE: mainnet
CONFIG_NAME: localdev
TERMINAL_TOTAL_DIFFICULTY: 0
TERMINAL_BLOCK_HASH: 0x0000000000000000000000000000000000000000000000000000000000000000
TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH: 18446744073709551615
MIN_GENESIS_ACTIVE_VALIDATOR_COUNT: 1
MIN_GENESIS_TIME: 0
GENESIS_DELAY: 60
GENESIS_FORK_VERSION: 0x20000089
ALTAIR_FORK_VERSION: 0x20000090
ALTAIR_FORK_EPOCH: 0
BELLATRIX_FORK_VERSION: 0x20000091
BELLATRIX_FORK_EPOCH: 0
CAPELLA_FORK_VERSION: 0x20000092
CAPELLA_FORK_EPOCH: 0
DENEB_FORK_VERSION: 0x20000093
DENEB_FORK_EPOCH: 0
ELECTRA_FORK_VERSION: 0x20000094
ELECTRA_FORK_EPOCH: 999999
FULU_FORK_VERSION: 0x20000095
FULU_FORK_EPOCH: 999999
SECONDS_PER_SLOT: 12
SLOTS_PER_EPOCH: 32
EPOCHS_PER_ETH1_VOTING_PERIOD: 4
SLOTS_PER_HISTORICAL_ROOT: 8192
MIN_VALIDATOR_WITHDRAWABILITY_DELAY: 256
SHARD_COMMITTEE_PERIOD: 256
ETH1_FOLLOW_DISTANCE: 1
DEPOSIT_CHAIN_ID: 12345
DEPOSIT_NETWORK_ID: 12345
DEPOSIT_CONTRACT_ADDRESS: 0x4242424242424242424242424242424242424242
INACTIVITY_SCORE_BIAS: 4
INACTIVITY_SCORE_RECOVERY_RATE: 16
EJECTION_BALANCE: 16000000000
MIN_PER_EPOCH_CHURN_LIMIT: 4
CHURN_LIMIT_QUOTIENT: 65536
MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT: 8
```

> `ELECTRA_FORK_EPOCH` and `FULU_FORK_EPOCH` are set far in the future to avoid fork version conflicts with mainnet.

---

## Step 3 — Generate JWT Secret

The execution client and consensus client authenticate with each other using a JWT token.

```powershell
$jwt = -join ((1..32) | ForEach-Object { "{0:X2}" -f (Get-Random -Maximum 256) })
$jwt | Out-File -FilePath "jwt.hex" -Encoding ascii -NoNewline
```

A `jwt.hex` file is already provided in the repo.

---

## Step 4 — Clean Previous State

Run in PowerShell (admin rights not required):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator') } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

@('node1/geth','node2/geth','node3/geth','beacondata1','beacondata2','beacondata3','validator_wallet1','validator_wallet2','validator_wallet3') | ForEach-Object {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $_
}
Remove-Item -Force *.log -ErrorAction SilentlyContinue
```

---

## Step 5 — Generate 3-Validator Genesis State

Use a future Unix timestamp so the chain does not start before the validators are ready.

```powershell
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))

.\prysmctl.exe testnet generate-genesis `
  --num-validators=3 `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=$futureTime
```

This creates:
- `genesis.ssz` — beacon chain genesis state
- `genesis-pos.json` — finalized Geth genesis with correct fork timestamps

---

## Step 6 — Initialize the Three Geth Datadirs

Geth must be initialized with the **hash** state scheme and the generated `genesis-pos.json`:

```powershell
.\geth.exe init --datadir=node1 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir=node2 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir=node3 --state.scheme hash genesis-pos.json
```

> **Important:** Geth 1.17 defaults to `path` state scheme, which does not work well with this local PoS setup. Use `--state.scheme hash`.

---

## Step 7 — Start Geth Node 1

PowerShell window 1:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

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

Critical flags explained:
- `--syncmode full` — required for PoS payload validation
- `--state.scheme hash` — required state scheme
- `--authrpc.*` — exposes the Engine API for Prysm
- `--ipcpath geth1.ipc` — unique IPC pipe for this node

Wait for Geth to fully start. You should see `HTTP server started endpoint=127.0.0.1:18545`.

Then fetch Node 1's enode:

```powershell
$enode1 = (.\geth.exe attach --exec "admin.nodeInfo.enode" http://127.0.0.1:18545).Trim().Trim('"')
Write-Host "Node1 enode: $enode1"
```

> **Important:** If the enode contains your external/public IP, replace that IP with `127.0.0.1` in the `--bootnodes` strings below.

Example fix:

```powershell
$enode1Local = $enode1 -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:'
Write-Host "Node1 local enode: $enode1Local"
```

---

## Step 8 — Start Geth Nodes 2 and 3

PowerShell window 2 (replace `<ENODE1>` with the local enode value):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\geth.exe `
  --datadir node2 `
  --port 30307 `
  --networkid 123454321 `
  --syncmode full `
  --state.scheme hash `
  --http --http.port 18546 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" --http.vhosts="*" --http.addr 127.0.0.1 `
  --authrpc.port 8552 --authrpc.addr 127.0.0.1 --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex `
  --ipcpath geth2.ipc `
  --bootnodes "<ENODE1>"
```

PowerShell window 3:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\geth.exe `
  --datadir node3 `
  --port 30308 `
  --networkid 123454321 `
  --syncmode full `
  --state.scheme hash `
  --http --http.port 18547 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" --http.vhosts="*" --http.addr 127.0.0.1 `
  --authrpc.port 8553 --authrpc.addr 127.0.0.1 --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex `
  --ipcpath geth3.ipc `
  --bootnodes "<ENODE1>"
```

> **Why `--ipcpath`?** Each Geth node needs a unique IPC pipe. Without it, Node 2/3 try to open the default pipe, which Node 1 already owns, causing `Access is denied`.

---

## Step 9 — Verify Execution Peering

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

## Step 10 — Start the Three Beacon Nodes

First start Beacon 1 and capture its peer ID. PowerShell window 5:

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

Wait for it to log its peer ID (look for `Running node with peer id of 16Uiu2HAm...`). Then fetch it:

```powershell
# Wait ~10 seconds after startup, then run:
$b1id = (Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/identity' -TimeoutSec 10).data.peer_id
Write-Host "Beacon1 peer id: $b1id"
```

If the identity endpoint fails, read it from the log:

```powershell
Select-String -Path "beacondata1\*.log" -Pattern "Running node with peer id of" | Select-Object -Last 1
```

PowerShell window 6 (replace `<BEACON1_PEER_ID>`):

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\beacon-chain.exe `
  --datadir beacondata2 `
  --min-sync-peers 0 `
  --genesis-state genesis.ssz `
  --chain-config-file chain-config.yaml `
  --contract-deployment-block 0 `
  --deposit-contract 0x0000000000000000000000000000000000000000 `
  --rpc-host 127.0.0.1 --rpc-port 4001 `
  --grpc-gateway-host 127.0.0.1 --grpc-gateway-port 3501 `
  --execution-endpoint http://127.0.0.1:8552 `
  --jwt-secret jwt.hex `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --minimum-peers-per-subnet 0 `
  --disable-staking-contract-check `
  --interop-eth1data-votes `
  --p2p-tcp-port 13001 --p2p-udp-port 12001 `
  --peer /ip4/127.0.0.1/tcp/13000/p2p/<BEACON1_PEER_ID> `
  --force-clear-db `
  --accept-terms-of-use
```

PowerShell window 7:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\beacon-chain.exe `
  --datadir beacondata3 `
  --min-sync-peers 0 `
  --genesis-state genesis.ssz `
  --chain-config-file chain-config.yaml `
  --contract-deployment-block 0 `
  --deposit-contract 0x0000000000000000000000000000000000000000 `
  --rpc-host 127.0.0.1 --rpc-port 4002 `
  --grpc-gateway-host 127.0.0.1 --grpc-gateway-port 3502 `
  --execution-endpoint http://127.0.0.1:8553 `
  --jwt-secret jwt.hex `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --minimum-peers-per-subnet 0 `
  --disable-staking-contract-check `
  --interop-eth1data-votes `
  --p2p-tcp-port 13002 --p2p-udp-port 12002 `
  --peer /ip4/127.0.0.1/tcp/13000/p2p/<BEACON1_PEER_ID> `
  --force-clear-db `
  --accept-terms-of-use
```

---

## Step 11 — Start the Three Validators

PowerShell window 8:

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

PowerShell window 9:

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

PowerShell window 10:

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

This uses Prysm's deterministic interop validator keys, which match the keys in `genesis.ssz`.

---

## Step 12 — Verify the Network

Attach to any Geth node on the HTTP port:

```powershell
.\geth.exe attach http://127.0.0.1:18545
```

Run:

```js
eth.blockNumber
eth.syncing
```

Expected:
- `eth.blockNumber` should increase every 12 seconds
- `eth.syncing` should show `currentBlock` increasing

Check beacon chain sync status:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/syncing'
```

Expected: `is_syncing: false`, `is_optimistic: false`.

---

## Step 13 — Send a Transaction and Verify Propagation

Run the included script against Node 1:

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

After the transaction is mined, verify the recipient balance on all three nodes:

```powershell
$body = '{"jsonrpc":"2.0","method":"eth_getBalance","params":["RECIPIENT_ADDRESS","latest"],"id":1}'

Invoke-RestMethod -Uri 'http://127.0.0.1:18545' -Method POST -ContentType 'application/json' -Body $body
Invoke-RestMethod -Uri 'http://127.0.0.1:18546' -Method POST -ContentType 'application/json' -Body $body
Invoke-RestMethod -Uri 'http://127.0.0.1:18547' -Method POST -ContentType 'application/json' -Body $body
```

All three should return the same non-zero balance, proving the transaction propagated and state is consistent across the network.

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

## Troubleshooting

### "database contains incompatible genesis"
Wipe `node1\geth`, `node2\geth`, `node3\geth`, then re-run `geth init` with the correct genesis file.

### "Invalid JWT token"
Make sure Geth and all Prysm beacon nodes point to the same `jwt.hex` file.

### "payload attributes are invalid / inconsistent"
Ensure Geth is started with `--syncmode full --state.scheme hash`.

### "node is currently optimistic"
The beacon chain thinks the execution client is not synced. Ensure Geth is fully started and the Engine API connection is healthy. Check that `eth.syncing` is progressing.

### "Could not connect to execution client"
Ensure Geth is running with `--authrpc.port 8551` (or 8552/8553) and `--authrpc.jwtsecret jwt.hex`.

### No blocks produced
Check that the validators are running and that `genesis.ssz` was generated correctly. The validators must be in the genesis state.

### Beacon node stuck at slot 0
Make sure `GENESIS_FORK_VERSION` in `chain-config.yaml` is unique and that `MIN_GENESIS_ACTIVE_VALIDATOR_COUNT` is satisfied.

### Port 8545 already in use
Use different HTTP ports like `18545`, `18546`, `18547` as shown in this guide.

### `Fatal: Error starting protocol stack: open \\.\pipe\geth.ipc: Access is denied`
You are running multiple Geth nodes without unique `--ipcpath` values. Add `--ipcpath geth1.ipc`, `--ipcpath geth2.ipc`, and `--ipcpath geth3.ipc` to each node respectively.

### Geth nodes do not peer on localhost
Fetch Node 1's enode and use `--bootnodes` on Nodes 2/3, or use `admin.addPeer` manually. NAT can advertise an external IP; replace the external IP with `127.0.0.1` in the enode string when all nodes are on the same machine.

### Want a fresh start
Stop all processes, then delete:
- `node1\geth`, `node2\geth`, `node3\geth`
- `beacondata1`, `beacondata2`, `beacondata3`
- `validator_wallet1`, `validator_wallet2`, `validator_wallet3`
- `%LOCALAPPDATA%\Eth2`

Then repeat from Step 4.

---

## Architecture Summary

```
        ┌──────────┐        ┌──────────┐        ┌──────────┐
        │ Geth 1   │◄──────►│ Geth 2   │◄──────►│ Geth 3   │
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

---

## Notes

- This setup uses **interop preset** for fast local testing. Do not use it for production.
- The deposit contract address `0x4242...4242` is a placeholder used by Prysm for local devnets.
- For a real PoS network, you would need 32 ETH per validator and a real deposit contract.
- Block time is 12 seconds per slot (configurable in `chain-config.yaml`).
- Each validator needs its own `--datadir` to avoid database lock errors.

---

## Alternative: Use Kurtosis or Docker

If this manual setup is too complex, consider using:
- **Kurtosis Ethereum package** — spins up a full PoS devnet in Docker
- **Ethereum Foundation `ethereum-package`** — one-command local PoS testnet

These tools automate Geth + Prysm + validator setup.
