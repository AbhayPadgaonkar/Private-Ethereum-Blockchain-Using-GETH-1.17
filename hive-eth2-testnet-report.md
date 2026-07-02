# Hive eth2/testnet Integration Report

**Date:** 2026-07-02
**Host:** Windows 11 Pro (Build 26200), PowerShell 5.1
**Hive repo:** `C:\BlocksScan\hive`
**Devnet repo:** `C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth`
**Clients tested:**
- `go-ethereum-local-117` (Geth v1.17.3)
- `prysm-bn-local-71` (Prysm beacon-chain v7.1.0)
- `prysm-vc-local-71` (Prysm validator v7.1.0)

---

## 1. Objective

Run the Hive `eth2/testnet` simulator against a local, version-pinned Ethereum PoS stack (Geth 1.17.3 + Prysm v7.1.0) and validate that the network starts, produces blocks, and reaches finality.

---

## 2. What was created

### 2.1 Custom Hive clients

Created under `C:\BlocksScan\hive\clients\`:

| Client | Dockerfile base | Binary source | Startup script |
|--------|----------------|---------------|----------------|
| `prysm-bn-local-71` | `debian:bullseye-slim` | `https://github.com/OffchainLabs/prysm/releases/download/v7.1.0/beacon-chain-v7.1.0-linux-amd64` | `prysm_bn.sh` |
| `prysm-vc-local-71` | `debian:bullseye-slim` | `https://github.com/OffchainLabs/prysm/releases/download/v7.1.0/validator-v7.1.0-linux-amd64` | `prysm_vc.sh` |

`go-ethereum-local-117` already existed from previous work.

### 2.2 Hive source patches required on Windows

Two modifications to the Hive framework were necessary to make the `eth2/testnet` simulator build on Windows:

1. **`internal/libdocker/builder.go`** — convert the simulator Dockerfile path to forward slashes before passing it to the Docker API:
   ```go
   buildDockerfile = filepath.ToSlash(p)
   ```
   Without this, Docker receives `testnet\Dockerfile` and fails with:
   ```
   API error (500): Cannot locate specified Dockerfile: testnet\Dockerfile
   ```

2. **`simulators/eth2/testnet/hive_context.txt`** — the file existed as a single line `..` with no trailing newline. Re-creating it with a newline (`..\n`) allowed Hive to parse the parent-directory build context correctly.

### 2.3 Prysm BN/VC startup adaptations

Compared to the upstream `prysm-bn`/`prysm-vc` clients, the local v7.1.0 clients required the following changes:

- Removed `--enable-debug-rpc-endpoints=true` from `prysm_bn.sh` because Prysm v7.1.0 does not define that flag (it has `--disable-debug-rpc-endpoints` instead).
- Updated the VC script to use `--interop-num-validators` when no keystores are supplied, since the simulator generates validator keys internally and passes them via `HIVE_ETH2_NUM_VALIDATORS`.
- Kept `--chain-config-file=/hive/input/config.yaml` and the generated `genesis-state=/hive/input/genesis.ssz`.

---

## 3. Test invocation

```powershell
.\hive.exe `
  --client go-ethereum-local-117,prysm-bn-local-71,prysm-vc-local-71 `
  --sim eth2/testnet `
  --sim.limit ".*" `
  --sim.timelimit 30m `
  -results-root workspace/logs-eth2-testnet-local
```

---

## 4. Test result

- **Suite:** `eth2-testnet`
- **Tests:** 2
- **Passed:** 1 (`eth2-testnets` orchestrator)
- **Failed:** 1 (`transition-testnet-prysm-bn-local-71-go-ethereum-local-117`)

The single actual test case failed during Prysm beacon node startup.

---

## 5. Root cause of failure

Prysm v7.1.0 rejects the `config.yaml` produced by the Hive `eth2/testnet` simulator. The log shows:

```
yaml: unmarshal errors:
  line 89: field GOSSIP_MAX_SIZE not found in type params.BeaconChainConfig
  line 93: field MAX_CHUNK_SIZE not found in type params.BeaconChainConfig
  line 119: field SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY not found in type params.BeaconChainConfig

unable to start beacon node: could not set beacon configuration options:
could not configure chain config: version 0x05000000 for fork electra in config devnet
conflicts with existing config named=mainnet: configset cannot add config with conflicting fork version schedule
```

Two distinct issues are visible:

1. **Unknown config fields.** The simulator emits network-level constants (`GOSSIP_MAX_SIZE`, `MAX_CHUNK_SIZE`, `SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY`) directly into `config.yaml`. Newer Prysm versions tolerate or rename these, but Prysm v7.1.0 errors out because they are not part of `BeaconChainConfig`.

2. **Fork version collision.** The simulator only configures up to Deneb (`0x0400000a`) but Prysm v7.1.0's `params.BeaconChainConfig` already knows about Electra (`0x05000000`) and Fulu (`0x06000000`). Because the YAML does not set explicit Electra/Fulu fork epochs/versions, Prysm falls back to its built-in mainnet values, which then conflict with the custom devnet (`ConfigName: devnet`) and cause the fatal `configset cannot add config with conflicting fork version schedule` error.

### Why upstream `prysm-bn` would likely behave the same

The upstream `prysm-bn` client uses the same `--chain-config-file=/hive/input/config.yaml` path and the same simulator-generated config. The only reason the upstream run in this session failed earlier was that the upstream `go-ethereum:latest` client no longer supports the `--unlock` flag used by the testnet simulator's Clique setup, so the test never reached the Prysm startup phase.

---

## 6. Attempted fixes that did not resolve the issue

- Removed unsupported `--enable-debug-rpc-endpoints` flag.
- Switched VC to interop validators.
- Passed an explicit `FORK_CONFIG` build arg to the simulator — the simulator does not consume this ARG; the fork config is hard-coded in `scenarios.go`.
- Rebuilt all images with `--docker.nocache ".*"`.

---

## 7. What would be needed to make the test pass

1. **Patch the simulator's `config.yaml` generation** (`simulators/eth2/common/config/consensus/consensus_config.go`) to:
   - Stop emitting network constants (`GOSSIP_MAX_SIZE`, `MAX_CHUNK_SIZE`, `SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY`) into `config.yaml`, or place them in a separate network config file that Prysm v7.1.0 ignores.
   - Set explicit `ELECTRA_FORK_VERSION`, `ELECTRA_FORK_EPOCH`, `FULU_FORK_VERSION`, and `FULU_FORK_EPOCH` values so Prysm does not fall back to mainnet defaults.

2. **Or update Prysm to a newer release** that tolerates the config format produced by the current Hive simulator. However, that deviates from the goal of testing the exact v7.1.0 stack used locally.

3. **Or use a different simulator** that does not exercise the full consensus config path (e.g., `ethereum/engine` already passes against `go-ethereum-local-117`).

---

## 8. Positive outcomes

Despite the test failure, several integration pieces were proven:

- The custom `go-ethereum-local-117` client builds and runs correctly in Hive; the `ethereum/engine` simulator still passes against it.
- The custom `prysm-bn-local-71` and `prysm-vc-local-71` Docker images build successfully.
- The `eth2/testnet` simulator itself builds and launches after patching the Windows path-separator issue and the `hive_context.txt` newline issue.
- The simulator successfully creates an execution genesis, a beacon genesis state, and validator keys, and starts the Geth container before the Prysm config parse failure.

---

## 9. Files changed in Hive repo

- `internal/libdocker/builder.go` — `filepath.ToSlash(p)` patch
- `simulators/eth2/testnet/hive_context.txt` — added trailing newline
- `clients/prysm-bn-local-71/` — new client
- `clients/prysm-vc-local-71/` — new client

---

## 10. Recommendation

The `eth2/testnet` simulator as it stands in this Hive checkout is **incompatible with Prysm v7.1.0** because of the config-format mismatch. The cleanest path forward is to patch the simulator's consensus config generator to be Prysm-v7.1.0-compatible, or to run a simpler Hive test that validates the local clients independently (execution-only via `ethereum/engine`, which already passes).

Given the time investment already made, the next practical step is to document the blocker and keep the engine-test success as the verified Hive integration result, unless you want to dive into the Go simulator source to fix the YAML generation.
