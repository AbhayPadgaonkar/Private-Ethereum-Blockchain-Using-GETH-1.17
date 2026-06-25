# Private Ethereum Blockchain Setup on Windows using Geth 1.17 + Prysm (PoS)

A Windows-friendly setup for a local private Ethereum network using **Geth 1.17** as the execution client and **Prysm** as the consensus client.

> **Note:** Geth 1.17+ only supports Proof-of-Stake (PoS) networks. The older Clique (Proof of Authority) mining setup does not work with Geth 1.17. This guide uses PoS with Prysm.

This README covers a **three-node devnet** — three Geth execution nodes, three Prysm beacon nodes, and three Prysm validators that peer and sync on the same Windows machine.

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
- `chain-config.yaml` — Prysm chain config
- `jwt.hex` — JWT secret for Geth-Prysm auth

Create a password file and a new keystore account. This account will receive the genesis funds and is used by `send_tx.js`.

```powershell
"node1" | Out-File -FilePath "node1\password-clean" -Encoding ASCII -NoNewline

.\geth.exe account new --datadir node1 --password node1\password-clean
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

Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator') } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

@('node1/geth','node2/geth','node3/geth','beacondata1','beacondata2','beacondata3','validator_wallet1','validator_wallet2','validator_wallet3') | ForEach-Object {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $_
}
Remove-Item -Force *.log -ErrorAction SilentlyContinue
```

---

## Generate 3-Validator PoS Genesis

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

## Initialize the Three Geth Datadirs

```powershell
.\geth.exe init --datadir=node1 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir=node2 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir=node3 --state.scheme hash genesis-pos.json
```

> **Important:** Use `--state.scheme hash` with Geth 1.17 for this local PoS setup.

---

## Start Geth Node 1

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

## Start Geth Nodes 2 and 3

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

## Start the Three Beacon Nodes

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

## Start the Three Validators

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

Check execution peering:

```powershell
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18545
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18546
.\geth.exe attach --exec "admin.peers.length" http://127.0.0.1:18547
```

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

## Network Keypair Reference

| Node | Public Address | Notes |
|------|----------------|-------|
| Funded sender | the address printed by `account new` | Created earlier, funded in `private_ethereum_setup\genesis.json`, used by `send_tx.js` |
| Recipient | the address you send to in `send_tx.js` | Receives test transfers |
| Fee recipient | `0x98608ADf9c785d54f40cDcf6700E990771b19226` | Used by Prysm validator for block rewards |

---

## Notes

- **Three node:** ten processes must stay running — 3 Geth, 3 beacon, 3 validator, plus your verification shell.
- Use separate PowerShell windows for each process.
- HTTP RPC runs on ports `18545`, `18546`, `18547`.
- Engine API uses ports `8551`, `8552`, `8553` with JWT auth.
- Beacon gRPC uses ports `4000`, `4001`, `4002`; REST gateways use `3500`, `3501`, `3502`.
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

### Want a fresh start
Stop all processes, then delete:
- `node1\geth`, `node2\geth`, `node3\geth`
- `beacondata1`, `beacondata2`, `beacondata3`
- `validator_wallet1`, `validator_wallet2`, `validator_wallet3`
- `%LOCALAPPDATA%\Eth2`

Then repeat from the genesis generation step.

---

## Architecture

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

## Detailed PoS Guide

For the full technical explanation, see [`POSE_SETUP_GUIDE.md`](./POSE_SETUP_GUIDE.md).

---

## Credits

Original Linux setup by LifnaJos. This Windows PoS adaptation was created to support Geth 1.17 and modern Ethereum consensus.
