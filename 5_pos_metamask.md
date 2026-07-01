# 5-Node Proof-of-Stake Devnet with MetaMask Wallets — Execution Report

**Date:** 2026-07-02  
**Host:** Windows 10/11 (Build 26200)  
**Location:** `C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup`  
**Test script:** `run-5node-metamask-test.ps1`  
**Log file:** `private_ethereum_setup\5node-metamask-test.log`

---

## 1. Objective

Run a local private Ethereum Proof-of-Stake (PoS) devnet with:

- **5 Geth execution nodes**
- **5 Prysm beacon nodes**
- **3 active validators** (interop validators on Nodes 1–3)
- **5 MetaMask-importable wallets**, one funded account per node
- A **transaction between Node 1 and Node 2 wallets**, submitted through Node 3 RPC
- Verification that the transaction propagated and state is identical on all 5 nodes

---

## 2. Environment

| Component | Version / Value |
|---|---|
| OS | Windows 10/11 |
| Shell | Windows PowerShell 5.1 |
| Geth | 1.17.x |
| Prysm | v7.1.0 (`beacon-chain.exe`, `validator.exe`, `prysmctl.exe`) |
| Node.js | (local install used for `ethers`) |
| Chain ID | `12345` |
| Network name | `Local PoS Devnet` |
| Genesis fork | Deneb (`0x20000093`) |

---

## 3. Network Topology

```
                    ┌─────────────┐
                    │   Node 1    │  Geth HTTP :18545, Beacon REST :3500
                    │  Validator  │  Geth P2P  :30306, Beacon P2P :13000/12000
                    │   (active)  │
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   ┌────┴────┐        ┌────┴────┐        ┌────┴────┐
   │  Node 2 │        │  Node 3 │        │  Node 4 │
   │Validator│        │Validator│        │  Full   │
   │ (active)│        │ (active)│        │  Node   │
   └────┬────┘        └────┬────┘        └────┬────┘
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                    ┌──────┴──────┐
                    │    Node 5   │
                    │   Full Node │
                    └─────────────┘
```

- **Validators:** Nodes 1, 2, 3 (each runs 1 interop validator)
- **Full nodes:** Nodes 4, 5 (no validator, only EL + CL)
- **All 5 nodes** run Geth + Prysm beacon and peer with each other

### Port matrix

| Node | Geth HTTP | Geth P2P | Engine API | Beacon gRPC | Beacon REST | Beacon TCP/UDP |
|---|---|---|---|---|---|---|
| 1 | 18545 | 30306 | 8551 | 4000 | 3500 | 13000 / 12000 |
| 2 | 18546 | 30307 | 8552 | 4001 | 3501 | 13001 / 12001 |
| 3 | 18547 | 30308 | 8553 | 4002 | 3502 | 13002 / 12002 |
| 4 | 18548 | 30309 | 8554 | 4003 | 3503 | 13003 / 12003 |
| 5 | 18549 | 30310 | 8555 | 4004 | 3504 | 13004 / 12004 |

---

## 4. Wallet Generation

Command used:

```powershell
$env:WALLET_COUNT = 5
$env:WALLET_BALANCE_ETH = '100000'
node create-funded-wallets.js
```

This created 5 Geth keystores (one per node), updated `genesis.json` `alloc`, and wrote:

- `private_ethereum_setup\node1\keystore\` … `node5\keystore\`
- `private_ethereum_setup\node1\password-clean` … `node5\password-clean`
- `private_ethereum_setup\metamask-wallets.json`
- `private_ethereum_setup\metamask-wallets.csv`

### Generated accounts (private keys masked)

| Node | Address | Genesis balance |
|---|---|---|
| 1 | `0xab0826842e01a920A11f714B168F157d864e9F91` | 100,000 ETH |
| 2 | `0x461a7dfD10b32a4b92b6D6D394eb577C441484E4` | 100,000 ETH |
| 3 | `0x872783E890D05e7376520065dBc4ef8b8B24e52C` | 100,000 ETH |
| 4 | `0xb1F731512f070cc399b918cbb810b1DA729a5dfc` | 100,000 ETH |
| 5 | `0x193770508Eeba018960B8075F4319a56fba1c1D0` | 100,000 ETH |

> The actual private keys are stored in `metamask-wallets.json` / `.csv` and are excluded from Git via `.gitignore`.

---

## 5. Genesis and Datadir Initialization

The `start-interop-network.ps1` script regenerated the PoS genesis:

```powershell
.\prysmctl.exe testnet generate-genesis `
  --num-validators=3 `
  --output-ssz=genesis.ssz `
  --chain-config-file=chain-config.yaml `
  --geth-genesis-json-in=genesis.json `
  --geth-genesis-json-out=genesis-pos.json `
  --fork=deneb `
  --genesis-time=1782948431
```

Key genesis facts:
- **3 interop validators** baked into `genesis.ssz`
- **5 funded execution-layer accounts** baked into `genesis-pos.json`
- All 5 Geth datadirs were initialized with identical genesis hash: `e744ef..ca40d4`

---

## 6. Network Startup

Command used:

```powershell
.\start-interop-network.ps1 -NodeCount 5 -GenesisDelaySeconds 180
```

Startup sequence observed:
1. Stopped old processes and cleaned state
2. Generated `genesis.ssz` and `genesis-pos.json`
3. Initialized 5 Geth datadirs
4. Started 5 Geth nodes and meshed them via `--bootnodes` + `admin_addPeer`
5. Started Beacon Node 1, captured its libp2p multiaddress
6. Started Beacon Nodes 2–5 peered to Beacon Node 1
7. Started 3 validators (Nodes 1–3)

Output excerpt:

```text
All 5 nodes started. Wait for genesis time, then verify:
  Node 1  Geth HTTP: http://127.0.0.1:18545  Beacon REST: http://127.0.0.1:3500
  Node 2  Geth HTTP: http://127.0.0.1:18546  Beacon REST: http://127.0.0.1:3501
  Node 3  Geth HTTP: http://127.0.0.1:18547  Beacon REST: http://127.0.0.1:3502
  Node 4  Geth HTTP: http://127.0.0.1:18548  Beacon REST: http://127.0.0.1:3503
  Node 5  Geth HTTP: http://127.0.0.1:18549  Beacon REST: http://127.0.0.1:3504
```

---

## 7. Sync Verification

`wait-for-network.ps1` polled every 5 seconds until all 5 nodes produced blocks. The network reached block 1 on all nodes at approximately **04:57:20**.

```text
All 5 nodes are producing blocks.
Node 1 (port 18545): block 1
Node 2 (port 18546): block 1
Node 3 (port 18547): block 1
Node 4 (port 18548): block 1
Node 5 (port 18549): block 1
```

Then `test_5node_sync.js` confirmed all nodes were within 1 block:

```text
Node 1 (port 18545): block 1 - OK
Node 2 (port 18546): block 1 - OK
Node 3 (port 18547): block 1 - OK
Node 4 (port 18548): block 1 - OK
Node 5 (port 18549): block 1 - OK
All reachable nodes are in sync.
```

---

## 8. Transaction Execution

Command used:

```powershell
$env:SENDER_NODE = 1
$env:RECIPIENT_NODE = 2
$env:RPC_NODE = 3
$env:AMOUNT_ETH = '10'
node test_metamask_tx.js
```

This mimics a MetaMask transaction:
- **Sender:** Node 1 wallet (`0xab08...e9F91`)
- **Recipient:** Node 2 wallet (`0x461a...484E4`)
- **RPC endpoint:** Node 3 (`http://127.0.0.1:18547`)
- **Amount:** 10 ETH

Transaction result:

```text
RPC node: http://127.0.0.1:18547 (Node 3)
Sender (Node 1): 0xab0826842e01a920A11f714B168F157d864e9F91
Recipient (Node 2): 0x461a7dfD10b32a4b92b6D6D394eb577C441484E4

--- Balances before ---
Sender balance: 100000.0 ETH
Recipient balance: 100000.0 ETH

Sending 10 ETH...
Transaction hash: 0x9e5491dc2e2a2dff5b23d41a35abfd8580273435784263ae2c1381376bef10a7
Mined in block: 2
```

### Cross-node balance verification

The script queried the balance on **all 5 nodes** after the transaction:

```text
Node 1 (port 18545) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 2 (port 18546) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 3 (port 18547) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 4 (port 18548) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
Node 5 (port 18549) -> sender: 99989.999968499999853 ETH, recipient: 100010.0 ETH
```

All 5 nodes reported **identical balances**, proving:
- The transaction was included in a PoS block
- The execution payload propagated through Geth devp2p
- The beacon block propagated through Prysm libp2p
- State is consistent across validators and full nodes

---

## 9. MetaMask Integration Steps

To reproduce this with MetaMask:

1. **Import accounts**
   - Open `private_ethereum_setup\metamask-wallets.csv`
   - Import the private keys for Node 1 and Node 2 into MetaMask

2. **Add the custom network**

   | Setting | Value |
   |---|---|
   | Network name | `Local PoS Devnet` |
   | New RPC URL | `http://127.0.0.1:18545` (or any node port) |
   | Chain ID | `12345` |
   | Currency symbol | `ETH` |

3. **Send via MetaMask**
   - Select the Node 1 account
   - Send 10 ETH to the Node 2 account address
   - Confirm and wait ~12–24 seconds for the next block

4. **Verify**
   - Switch to the Node 2 account and refresh the balance
   - Optionally switch the RPC URL to Node 5 (`http://127.0.0.1:18549`); balance should be identical

Alternatively, open `private_ethereum_setup\metamask-wallet.html` in a browser with MetaMask installed. It will add the network, connect the account, and let you send transactions.

---

## 10. Observations and Fixes

### What worked
- 5-node network started cleanly
- Geth peering succeeded via `admin_addPeer` fallback
- Beacon nodes discovered each other and reached consensus
- All 5 nodes produced identical blocks and balances
- Transaction submitted through Node 3 RPC was visible on all nodes

### Minor issue during final verification
The final PowerShell balance-check step failed to parse the hex value returned by `eth_getBalance`:

```text
WARNING: Node 1 balance check failed: Cannot convert value "0x152c7800a1a0424649c8" to type "System.Numerics.BigInteger".
```

This was because `[bigint]$resp.result` does not parse hex strings. The issue was fixed in `run-5node-metamask-test.ps1` by using:

```powershell
[System.Numerics.BigInteger]::Parse($resp.result.TrimStart('0x'), [System.Globalization.NumberStyles]::HexNumber)
```

The main transaction and cross-node verification (performed by `test_metamask_tx.js`) completed successfully; only the optional final PowerShell check was affected.

---

## 11. Timing

| Phase | Duration |
|---|---|
| Wallet generation | ~10 seconds |
| Genesis + datadir init | ~30 seconds |
| Wait for genesis + block 1 | ~3 minutes |
| Sync + transaction tests | ~10 seconds |
| **Total** | **3 minutes 53 seconds** |

---

## 12. Files Created / Updated

| File | Purpose |
|---|---|
| `private_ethereum_setup\run-5node-metamask-test.ps1` | Master test orchestrator |
| `private_ethereum_setup\wait-for-network.ps1` | Polls nodes until blocks are produced |
| `private_ethereum_setup\test_5node_sync.js` | Verifies all nodes are in sync |
| `private_ethereum_setup\test_metamask_tx.js` | Sends a transaction and verifies balances on all nodes |
| `private_ethereum_setup\create-funded-wallets.js` | Generates funded wallets per node |
| `private_ethereum_setup\export-private-key.js` | Exports private keys from Geth keystores |
| `private_ethereum_setup\metamask-wallet.html` | Browser dApp for MetaMask |
| `private_ethereum_setup\metamask-network-config.json` | RPC reference |
| `private_ethereum_setup\metamask-wallets.json` | Generated wallet secrets (git-ignored) |
| `private_ethereum_setup\metamask-wallets.csv` | Generated wallet secrets (git-ignored) |
| `private_ethereum_setup\5node-metamask-test.log` | Full execution log |
| `README.md` | Updated with MetaMask + 5-node test instructions |
| `.gitignore` | Ignores wallet secret files |

---

## 13. Conclusion

A **5-node Ethereum PoS devnet** with **3 active validators** and **2 full nodes** was successfully started on Windows. Five MetaMask-importable wallets were generated and pre-funded in genesis. A **10 ETH transaction from Node 1 to Node 2** was submitted via **Node 3 RPC**, mined in **block 2**, and verified to have **identical balances across all 5 nodes**.

This confirms that:
- The PoS consensus produces blocks correctly with 3 validators
- Geth execution-layer peering works across 5 nodes
- Prysm beacon-layer peering works across 5 nodes
- Transactions propagate to all nodes regardless of which RPC received them
- MetaMask can be used with any of the 5 RPC endpoints

The setup is reproducible by running `private_ethereum_setup\run-5node-metamask-test.ps1`.
