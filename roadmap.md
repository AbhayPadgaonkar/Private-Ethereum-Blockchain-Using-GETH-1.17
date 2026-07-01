# Roadmap: Private Ethereum PoS Devnet

## Context

- **Repo:** `C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth`
- **Stack:** Geth 1.17.3 + Prysm v7.1.0 on Windows 10/11, PowerShell
- **Network:** Custom local PoS devnet, `chainId: 12345`, `CONFIG_NAME: localdev`
- **Current state:** A 3-node setup is fully verified end-to-end using **interop validators** (Option A). Transactions propagate and balances are consistent across nodes.
- **Hive repo:** `C:\BlocksScan\hive` exists locally with client definitions for `go-ethereum`, `prysm-bn`, and `prysm-vc`, plus simulators.

## Task 1 — Staking CLI validator approach (or verified fallback)

### Goal
Produce a wallet-based validator path that works on Windows without requiring a real deposit contract, so `genesis.ssz` is generated from real EIP-2335 keystores and a matching `deposit_data.json`.

### Current blocker
The released Windows `deposit.exe` and Linux `deposit` binary v2.8.0 do not support `--devnet_chain_setting` in `new-mnemonic`, so they cannot generate deposits for `GENESIS_FORK_VERSION: 0x20000089`. Using `--chain mainnet` produces deposits signed for mainnet fork version and Prysm rejects them with `no active validator indices`.

### Sub-tasks
1. Verify the exact failure mode by running the current binary with `--devnet_chain_setting` and capture logs.
2. Try the Python source install path in PowerShell:
   - Install Python 3.11+ and `pip`.
   - Clone `ethereum/staking-deposit-cli` and run `pip install -r requirements.txt && pip install .`.
   - Run `python ./staking_deposit/deposit.py new-mnemonic --devnet_chain_setting ...` and validate `deposit_data.json` fork version matches `chain-config.yaml`.
3. If Python source works, wrap the steps in a PowerShell helper (`generate-wallet-validators.ps1`) that:
   - Creates `wallet_setup/validator_keys`.
   - Writes `account_password.txt` and `wallet_password.txt`.
   - Imports keystores into `validator_wallet1/2/3`.
4. Regenerate `genesis.ssz` with `prysmctl testnet generate-genesis --deposit-json-file=... --num-validators=0`.
5. Start the network with `start-wallet-network.ps1` and confirm:
   - All 3 beacon nodes reach `is_syncing: false` with `sync_distance: 0`.
   - Validator logs show successful block proposals/attestations.
   - `send_tx.js` still works.

### Fallback
If the Python source path cannot be made reliable on Windows within a reasonable time, document the limitation and keep **Option A (interop validators)** as the recommended path. Update README and audit report to reflect this.

### Success criteria
- A user can run one PowerShell command or a short documented sequence to generate wallet-based validators and start a working network.
- README clearly states which path is verified and which is experimental.

### Estimated effort
Medium (1–2 days if Python source path works; 2–3 hours if fallback only).

### Owners
Primary: repository maintainer.

### Dependencies
- Python 3.11+ available on Windows.
- `staking-deposit-cli` source compatible with current `chain-config.yaml`.

---

## Task 2 — Test PoS consensus on more than 5 nodes

### Goal
Scale the devnet from 3 nodes to **at least 6 nodes** (6 Geth + 6 beacon + 6 validators) and verify consensus, sync, and transaction propagation.

### Sub-tasks
1. Decide node count: 6 or 9. Six is enough to exceed the "more than 5" requirement and keeps local resource usage reasonable.
2. Define the port matrix:
   - Geth P2P: 30306–30311.
   - Geth HTTP: 18545–18550.
   - Geth auth RPC: 8551–8556.
   - Beacon gRPC: 4000–4005.
   - Beacon REST: 3500–3505.
   - Beacon libp2p TCP/UDP: 13000/12000–13005/12005.
3. Update `start-wallet-network.ps1` to accept a `NodeCount` parameter and loop creation of Geth, beacon, and validator processes. Ensure bootnode/peer wiring works dynamically:
   - Node 1 starts with no bootnode.
   - Nodes 2..N use Node 1 as Geth bootnode and Node 1's ENR as initial beacon peer.
4. Generate or import enough validators:
   - Option A: use `--num-validators=6` (interop).
   - Option B: generate 6 wallet-based keystores.
5. Run the scaled network on a machine with at least 32 GB RAM and fast SSD. Monitor:
   - CPU/RAM per process.
   - Geth peer counts on each node.
   - Beacon sync status across all nodes.
   - Slot/epoch progression.
6. Execute `send_tx.js` against Node 1 and verify the balance is identical on Nodes 1–6.
7. Add a health-check script (`check-network-health.ps1`) that prints:
   - Each Geth block number.
   - Each beacon sync state.
   - Peer counts.

### Success criteria
- All 6+ nodes sync to the same head.
- Validators rotate proposer duties across indices.
- Transactions are included and visible on every node.
- Health-check script returns clean status.

### Risks
- 18 processes (6 EL + 6 CL + 6 VC) consume significant RAM/CPU on Windows.
- Windows default ephemeral port range and firewall rules may need tuning.
- Genesis delay may need to be larger for a slower startup.

### Estimated effort
Medium–high (2–3 days including debugging).

### Owners
Primary: repository maintainer.

---

## Task 3 — Configure Hive framework to run against local Geth

### Goal
Create a Hive client definition that packages our exact Geth 1.17 + Prysm v7.1.0 + `chain-config.yaml` and run at least one Hive simulator successfully.

### Current Hive state
- `C:\BlocksScan\hive` has:
  - `clients/go-ethereum/Dockerfile` and `geth.sh`
  - `clients/prysm-bn/Dockerfile` and `prysm_bn.sh`
  - `clients/prysm-vc/Dockerfile` and `prysm_vc.sh`
  - Simulators: `eth2/testnet`, `ethereum/rpc-compat`, `ethereum/engine`, `ethereum/sync`, etc.
- Existing Hive client definitions pull `ethereum/client-go:latest` and `gcr.io/prysmaticlabs/prysm/beacon-chain:latest`. They do not match our pinned versions or custom chain config.

### Sub-tasks
1. Create a new Hive client directory `clients/go-ethereum-local-117`:
   - Dockerfile copies the local Windows `geth.exe` into a Windows container, OR builds Geth 1.17.3 from source in a Linux container.
   - Prefer Linux container path for Hive compatibility (Hive expects Linux clients).
   - Include our `genesis.json` and `mapper.jq` equivalent.
2. Create `clients/prysm-bn-local-71`:
   - Dockerfile builds or copies Prysm beacon-chain v7.1.0.
   - Includes `chain-config.yaml`, `genesis.ssz`, `jwt.hex`.
   - Startup script mounts these under `/hive/input`.
3. Create `clients/prysm-vc-local-71`:
   - Dockerfile copies Prysm validator v7.1.0.
   - Accepts keystores and secrets via `/hive/input/keystores` and `/hive/input/secrets`.
4. Generate validator keystores and deposit data for Hive:
   - Use the same approach as Task 1 (Python source) or interop validators if wallet path is not ready.
   - For Hive interop path, modify `prysm_vc.sh` to launch with `--interop-num-validators` instead of importing keystores.
5. Choose a simulator to run first:
   - **Recommended:** `eth2/testnet` for full PoS network smoke test.
   - Alternative: `ethereum/engine` for Engine API compliance.
   - Alternative: `ethereum/rpc-compat` for JSON-RPC coverage.
6. Create a Hive invocation script (`run-hive.ps1`) with the correct `--client` names and `--sim` argument.
7. Run Hive, capture logs, and document any failures.

### Success criteria
- `hive.exe --sim eth2/testnet --client go-ethereum-local-117,prysm-bn-local-71,prysm-vc-local-71` completes without fatal errors.
- At least one test case reports `pass`.
- Logs are committed under a `hive-results/` folder (or added to `.gitignore`).

### Risks
- Hive is primarily designed for Linux Docker containers. Running on Windows may require Docker Desktop with WSL2 backend.
- Our custom `genesis.ssz` and `chain-config.yaml` may not match what Hive simulators expect.
- Prysm v7.1.0 CLI flags may differ from the latest upstream assumed by existing Hive scripts.

### Estimated effort
High (3–5 days).

### Owners
Primary: repository maintainer with possible Hive upstream guidance.

---

## Task 4 — Implement MetaMask support for the devnet

### Goal
Let users connect MetaMask to any local Geth node and import the funded account (or any locally created account) to send/receive transactions.

### Sub-tasks
1. Verify RPC connectivity:
   - Node 1: `http://127.0.0.1:18545`
   - Node 2: `http://127.0.0.1:18546`
   - Node 3: `http://127.0.0.1:18547`
   - Confirm `--http.corsdomain=*` and `--http.vhosts=*` are present in startup.
2. Document MetaMask custom network settings:
   - Network name: `Local Geth Devnet`
   - RPC URL: `http://127.0.0.1:18545` (or 18546/18547)
   - Chain ID: `12345`
   - Currency symbol: `ETH`
   - Block explorer: leave empty.
3. Create `export-private-key.ps1` that:
   - Reads `node1/keystore/UTC--...`.
   - Decrypts with `node1/password-clean` using `ethers`.
   - Prints the private key so the user can import it into MetaMask.
4. Add instructions for creating additional accounts:
   - `geth account new --datadir node2 --password node2/password-clean`
   - Import the new account's private key into MetaMask.
   - Fund it from the prefunded account via MetaMask or `send_tx.js`.
5. Add a MetaMask section to `README.md` and a small troubleshooting note about:
   - `Unable to connect` when Geth is not running.
   - Chain ID mismatch warnings.
   - No block explorer warnings.
6. Optional: create a Node.js helper (`create_funded_wallet.js`) that generates a new wallet, imports it into a local Geth node, and funds it from the genesis account.

### Success criteria
- A user can add the custom network and import the funded account in MetaMask.
- Sending ETH from the funded account to a new account succeeds and is confirmed on-chain.
- Balance updates are visible in MetaMask after the transaction is mined.

### Risks
- MetaMask caches chain data; switching networks may require a refresh if the local chain is restarted.
- Windows firewall may block `127.0.0.1` HTTP requests from the browser; usually not an issue but worth documenting.

### Estimated effort
Low (a few hours to half a day).

### Owners
Primary: repository maintainer.

---

## Cross-cutting concerns

- Keep all generated files out of git: `node*/geth/`, `beacondata*/`, `validator_wallet*/`, `genesis.ssz`, `genesis-pos.json`, logs, keystores.
- Update `.gitignore` before adding new scripts that produce artifacts.
- Maintain documentation parity: every script added should be referenced in `README.md` or `WORKING_EXPLANATION.md`.
- Re-run the existing `send_tx.js` smoke test after every significant change.
- Prefer deterministic interop validators for speed; keep wallet-based path as the advanced/optional route until fully verified.

## Suggested order of execution

1. **Task 4** (MetaMask) — quick win, no consensus risk.
2. **Task 1** (Staking CLI) — unlocks wallet-based validators and feeds into Task 3.
3. **Task 2** (Scale to 6+ nodes) — tests the setup at scale; use whichever validator path is verified.
4. **Task 3** (Hive) — most complex; do after the local setup is stable and reproducible.
