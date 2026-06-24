# Proof-of-Stake (PoS) Local Setup Guide for Geth 1.17 + Prysm on Windows

This guide converts the local private Ethereum network from Clique (Proof of Authority) to **Proof-of-Stake (PoS)** using **Geth 1.17** as the execution client and **Prysm** as the consensus client.

> ⚠️ This is significantly more complex than the Clique setup. You will run three processes: Geth execution client, Prysm beacon node, and Prysm validator.

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
  "extradata": "0x000000000000000000000000000000000000000000000000000000000000000098608ADf9c785d54f40cDcf6700E990771b192260000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
    "0x98608ADf9c785d54f40cDcf6700E990771b19226": { "balance": "100000000000000000000000" },
    "0x7B25e791D24A3F5c453A9E5468cF6cEa2243092C": { "balance": "120000000000000000000000" }
  }
}
```

Key changes:
- Removed `clique` (no longer used)
- `terminalTotalDifficulty`: 0 — merge happens immediately
- `shanghaiTime` and `cancunTime`: 0 — enable withdrawals and blobs from genesis
- `difficulty`: 0 — PoS blocks have no difficulty
- `baseFeePerGas` and `blobSchedule` — required by Geth 1.17 for Cancun

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

> **Note:** `ELECTRA_FORK_EPOCH` and `FULU_FORK_EPOCH` are set far in the future to avoid fork version conflicts with mainnet.

---

## Step 3 — Generate JWT Secret

The execution client and consensus client authenticate with each other using a JWT token.

```powershell
$jwt = -join ((1..32) | ForEach-Object { "{0:X2}" -f (Get-Random -Maximum 256) })
$jwt | Out-File -FilePath "jwt.hex" -Encoding ascii -NoNewline
```

---

## Step 4 — Generate Validator Keys and Genesis State

```powershell
.\prysmctl.exe testnet generate-genesis `
  --num-validators=1 `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=0
```

This creates:
- `genesis.ssz` — beacon chain genesis state
- `genesis-pos.json` — finalized Geth genesis (includes timestamps set by Prysm)

---

## Step 5 — Initialize Geth

Geth must be initialized with the **hash** state scheme and the generated `genesis-pos.json`:

```powershell
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node1\geth"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node2\geth"

.\geth.exe init --datadir node1 --state.scheme hash genesis-pos.json
.\geth.exe init --datadir node2 --state.scheme hash genesis-pos.json
```

> **Important:** Geth 1.17 defaults to `path` state scheme, which does not work well with this local PoS setup. Use `--state.scheme hash`.

---

## Step 6 — Start Geth Execution Client

This starts Geth with the Engine API enabled for Prysm.

> **Port note:** Port `8545` is commonly used by Docker/XDC nodes. This guide uses `18545` for the HTTP RPC to avoid conflicts. Change if needed.

```powershell
.\geth.exe `
  --datadir node1 `
  --port 30306 `
  --networkid 123454321 `
  --nodiscover `
  --maxpeers 0 `
  --syncmode full `
  --state.scheme hash `
  --http `
  --http.port 18545 `
  --http.api eth,net,web3,engine,admin `
  --http.corsdomain="*" `
  --http.vhosts="*" `
  --http.addr 127.0.0.1 `
  --authrpc.port 8551 `
  --authrpc.addr 127.0.0.1 `
  --authrpc.vhosts="*" `
  --authrpc.jwtsecret jwt.hex
```

Critical flags explained:
- `--syncmode full` — required for PoS payload validation
- `--nodiscover --maxpeers 0` — prevents Geth from waiting for p2p sync
- `--state.scheme hash` — required state scheme
- `--authrpc.*` — exposes the Engine API for Prysm

Wait for Geth to fully start.

---

## Step 7 — Start Prysm Beacon Node

In a new PowerShell window:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\beacon-chain.exe `
  --datadir beacondata `
  --min-sync-peers 0 `
  --genesis-state genesis.ssz `
  --chain-config-file chain-config.yaml `
  --contract-deployment-block 0 `
  --deposit-contract 0x0000000000000000000000000000000000000000 `
  --rpc-host 127.0.0.1 `
  --grpc-gateway-host 127.0.0.1 `
  --execution-endpoint http://127.0.0.1:8551 `
  --jwt-secret jwt.hex `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --minimum-peers-per-subnet 0 `
  --disable-staking-contract-check `
  --interop-eth1data-votes `
  --no-discovery `
  --force-clear-db `
  --accept-terms-of-use
```

The beacon node will connect to Geth via the Engine API and start producing slots.

---

## Step 8 — Start Prysm Validator

In a third PowerShell window:

```powershell
cd C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup

.\validator.exe `
  --wallet-dir validator_wallet `
  --chain-config-file chain-config.yaml `
  --suggested-fee-recipient 0x98608ADf9c785d54f40cDcf6700E990771b19226 `
  --beacon-rpc-provider 127.0.0.1:4000 `
  --interop-num-validators 1 `
  --interop-start-index 0 `
  --accept-terms-of-use `
  --force-clear-db
```

This uses Prysm's deterministic interop validator keys, which match the keys in `genesis.ssz`.

---

## Step 9 — Verify the Network

Attach to Geth on the HTTP port you chose:

```powershell
.\geth.exe attach http://127.0.0.1:18545
```

Run:

```js
eth.blockNumber
eth.syncing
eth.getBalance("0x98608ADf9c785d54f40cDcf6700E990771b19226")
```

Expected:
- `eth.blockNumber` should increase every 12 seconds
- `eth.syncing` should show `currentBlock` increasing
- Balance should be `1e+23` (100,000 ETH in wei)

Check beacon chain sync status:

```powershell
curl.exe http://127.0.0.1:3500/eth/v1/node/syncing
```

Expected: `is_syncing: false`, `is_optimistic: false`.

---

## Step 10 — Add Node 2 as a Peer (Optional)

Node 2 can connect to Node 1 as an execution-layer peer.

```powershell
.\geth.exe `
  --datadir node2 `
  --port 30307 `
  --networkid 123454321 `
  --nodiscover `
  --maxpeers 1 `
  --syncmode full `
  --state.scheme hash `
  --http `
  --http.port 18546 `
  --http.api eth,net,web3,engine,admin `
  --authrpc.port 8553 `
  --authrpc.jwtsecret jwt.hex `
  --bootnodes "<NODE1_ENODE>"
```

Get Node 1's enode from the Geth console:

```js
admin.nodeInfo.enode
```

---

## Troubleshooting

### "database contains incompatible genesis"
Wipe `node1\geth` and `node2\geth`, then re-run `geth init` with the correct genesis file.

### "Invalid JWT token"
Make sure both Geth and Prysm point to the same `jwt.hex` file.

### "payload attributes are invalid / inconsistent"
This happens when Geth tries to p2p sync. Start Geth with `--nodiscover --maxpeers 0 --syncmode full --state.scheme hash`.

### "node is currently optimistic"
The beacon chain thinks the execution client is not synced. Ensure Geth is fully started and the Engine API connection is healthy. Check that `eth.syncing` is progressing.

### "Could not connect to execution client"
Ensure Geth is running with `--authrpc.port 8551` and `--authrpc.jwtsecret jwt.hex`.

### No blocks produced
Check that the validator is running and that `genesis.ssz` was generated correctly. The validator must be in the genesis state.

### Beacon node stuck at slot 0
Make sure `GENESIS_FORK_VERSION` in `chain-config.yaml` is unique and that `MIN_GENESIS_ACTIVE_VALIDATOR_COUNT` is satisfied.

### Port 8545 already in use
Use a different HTTP port like `18545` as shown in this guide.

---

## Architecture Summary

```
┌─────────────────┐     Engine API (port 8551)     ┌─────────────────┐
│   Geth 1.17     │◄─────── JWT auth ─────────────►│  Prysm Beacon   │
│ Execution Node  │                                   │     Node        │
│   port 18545    │                                   │   port 4000     │
└─────────────────┘                                   └────────┬────────┘
                                                                │
                                                                │ gRPC
                                                                ▼
                                                       ┌─────────────────┐
                                                       │ Prysm Validator │
                                                       │  (proposes      │
                                                       │   blocks)       │
                                                       └─────────────────┘
```

---

## Notes

- This setup uses **interop preset** for fast local testing. Do not use it for production.
- The deposit contract address `0x4242...4242` is a placeholder used by Prysm for local devnets.
- For a real PoS network, you would need 32 ETH per validator and a real deposit contract.
- Block time is 12 seconds per slot (configurable in `chain-config.yaml`).

---

## Alternative: Use Kurtosis or Docker

If this manual setup is too complex, consider using:
- **Kurtosis Ethereum package** — spins up a full PoS devnet in Docker
- **Ethereum Foundation `ethereum-package`** — one-command local PoS testnet

These tools automate Geth + Prysm + validator setup.
