# Wallet-Based Validator Startup Script for Private PoS Devnet
# This script:
#   1. Stops any running geth/beacon-chain/validator processes
#   2. Clears validator slashing-protection DB
#   3. Regenerates genesis.ssz and genesis-pos.json from wallet-based deposit data
#   4. Re-initializes Geth datadirs
#   5. Starts 3 Geth nodes, 3 beacon nodes, and 3 wallet-based validators
#
# PREREQUISITE: You must generate wallet-based validator keys first.
# See README.md "Generate 3-Validator PoS Genesis" -> Option A.

$baseDir = "C:\BlocksScan\Private-Ethereum-Blockchain-setup-using-Geth\private_ethereum_setup"
Set-Location $baseDir

# Validate prerequisites
$depositJsonDir = "$baseDir\wallet_setup\validator_keys"
$depositJson = "$depositJsonDir\deposit_data.json"
$walletPass = "$baseDir\wallet_setup\wallet_password.txt"
$accountPass = "$baseDir\wallet_setup\account_password.txt"

# The staking CLI names the file deposit_data-<timestamp>.json; prysmctl expects deposit_data.json
if (-not (Test-Path -LiteralPath $depositJson)) {
    $fallback = Get-ChildItem -Path $depositJsonDir -Filter "deposit_data-*.json" | Select-Object -First 1
    if ($fallback) {
        Rename-Item -Path $fallback.FullName -NewName "deposit_data.json" -Force
        Write-Host "Renamed $($fallback.Name) to deposit_data.json"
    }
}

if (-not (Test-Path -LiteralPath $depositJson)) {
    Write-Error @"
Missing deposit data: $depositJson

You must generate wallet-based validator keys before running this script.
Run the Ethereum Staking Deposit CLI in PowerShell:

  .\staking_deposit-cli-948d3fc-windows-amd64\deposit.exe new-mnemonic `
    --num_validators 3 --chain mainnet --folder wallet_setup\validator_keys

Then create password files and import the keystores. See README.md for full steps.
"@
    exit 1
}

if (-not (Test-Path -LiteralPath $walletPass)) {
    Write-Error "Missing wallet password file: $walletPass`nCreate it with:`n  `"YOUR_WALLET_PASSWORD`" | Out-File -FilePath `"wallet_setup\wallet_password.txt`" -Encoding ASCII -NoNewline"
    exit 1
}

if (-not (Test-Path -LiteralPath $accountPass)) {
    Write-Error "Missing account password file: $accountPass`nCreate it with:`n  `"YOUR_KEYSTORE_PASSWORD`" | Out-File -FilePath `"wallet_setup\account_password.txt`" -Encoding ASCII -NoNewline"
    exit 1
}

# Verify each validator wallet was imported
for ($i = 1; $i -le 3; $i++) {
    if (-not (Test-Path -LiteralPath "$baseDir\validator_wallet$i\direct\accounts\all-accounts.keystore.json")) {
        Write-Error "Missing imported validator wallet: validator_wallet$i`nRun the validator.exe accounts import commands from README.md Step 4 first."
        exit 1
    }
}

function Start-GethNode($num, $p2p, $http, $auth, $ipc, $bootnodes) {
    $argList = @(
        "--datadir", "node$num",
        "--port", "$p2p",
        "--networkid", "123454321",
        "--syncmode", "full",
        "--state.scheme", "hash",
        "--http", "--http.port", "$http",
        "--http.api", "eth,net,web3,engine,admin",
        "--http.corsdomain=*", "--http.vhosts=*", "--http.addr", "127.0.0.1",
        "--authrpc.port", "$auth", "--authrpc.addr", "127.0.0.1", "--authrpc.vhosts=*",
        "--authrpc.jwtsecret", "jwt.hex",
        "--ipcpath", "$ipc"
    )
    if ($bootnodes) {
        $argList += "--bootnodes"
        $argList += $bootnodes
    }
    Start-Process -FilePath "$baseDir\geth.exe" -ArgumentList $argList -WorkingDirectory $baseDir -WindowStyle Normal
}

function Start-BeaconNode($num, $grpc, $rest, $execPort, $p2pTcp, $p2pUdp, $minSyncPeers, $peer) {
    $argList = @(
        "--datadir", "beacondata$num",
        "--min-sync-peers", "$minSyncPeers",
        "--genesis-state", "genesis.ssz",
        "--chain-config-file", "chain-config.yaml",
        "--contract-deployment-block", "0",
        "--deposit-contract", "0x0000000000000000000000000000000000000000",
        "--rpc-host", "127.0.0.1", "--rpc-port", "$grpc",
        "--grpc-gateway-host", "127.0.0.1", "--grpc-gateway-port", "$rest",
        "--execution-endpoint", "http://127.0.0.1:$execPort",
        "--jwt-secret", "jwt.hex",
        "--suggested-fee-recipient", "0x98608ADf9c785d54f40cDcf6700E990771b19226",
        "--minimum-peers-per-subnet", "1",
        "--disable-staking-contract-check",
        "--interop-eth1data-votes",
        "--p2p-tcp-port", "$p2pTcp", "--p2p-udp-port", "$p2pUdp",
        "--force-clear-db",
        "--accept-terms-of-use"
    )
    if ($peer) {
        $argList += "--peer"
        $argList += $peer
    }
    Start-Process -FilePath "$baseDir\beacon-chain.exe" -ArgumentList $argList -WorkingDirectory $baseDir -WindowStyle Normal
}

function Start-Validator($num, $grpc) {
    $argList = @(
        "--datadir", "validator_wallet$num",
        "--wallet-dir", "validator_wallet$num",
        "--wallet-password-file", "wallet_setup\wallet_password.txt",
        "--chain-config-file", "chain-config.yaml",
        "--suggested-fee-recipient", "0x98608ADf9c785d54f40cDcf6700E990771b19226",
        "--beacon-rpc-provider", "127.0.0.1:$grpc",
        "--accept-terms-of-use"
    )
    Start-Process -FilePath "$baseDir\validator.exe" -ArgumentList $argList -WorkingDirectory $baseDir -WindowStyle Normal
}

# Stop any existing processes and clear validator DB
Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator') } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:LOCALAPPDATA\Eth2"

# Regenerate genesis with a future timestamp so validators can start before genesis
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds(180).ToUniversalTime() -UFormat %s))
Write-Host "Regenerating genesis with timestamp: $futureTime"
& "$baseDir\prysmctl.exe" testnet generate-genesis `
    --num-validators=0 `
    --deposit-json-file=wallet_setup\validator_keys\deposit_data.json `
    --output-ssz=genesis.ssz `
    --chain-config-file=chain-config.yaml `
    --geth-genesis-json-in=genesis.json `
    --geth-genesis-json-out=genesis-pos.json `
    --fork=deneb `
    --genesis-time=$futureTime

if ($LASTEXITCODE -ne 0) {
    Write-Error "Genesis generation failed"
    exit 1
}

# Re-initialize Geth datadirs (genesis hash changes when timestamp changes)
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue node1\geth, node2\geth, node3\geth
& "$baseDir\geth.exe" init --datadir=node1 --state.scheme hash genesis-pos.json
& "$baseDir\geth.exe" init --datadir=node2 --state.scheme hash genesis-pos.json
& "$baseDir\geth.exe" init --datadir=node3 --state.scheme hash genesis-pos.json

# Start Geth nodes
Start-GethNode -num 1 -p2p 30306 -http 18545 -auth 8551 -ipc "geth1.ipc" -bootnodes $null
Start-Sleep -Seconds 5

$enode1 = (& "$baseDir\geth.exe" attach --exec "admin.nodeInfo.enode" http://127.0.0.1:18545).Trim().Trim('"')
$enode1Local = $enode1 -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:'
Write-Host "Node1 enode: $enode1Local"

Start-GethNode -num 2 -p2p 30307 -http 18546 -auth 8552 -ipc "geth2.ipc" -bootnodes $enode1Local
Start-GethNode -num 3 -p2p 30308 -http 18547 -auth 8553 -ipc "geth3.ipc" -bootnodes $enode1Local
Start-Sleep -Seconds 5

# Start Beacon Node 1 (bootstrap)
Start-BeaconNode -num 1 -grpc 4000 -rest 3500 -execPort 8551 -p2pTcp 13000 -p2pUdp 12000 -minSyncPeers 0 -peer $null
Start-Sleep -Seconds 15

# Get Beacon Node 1 identity for peer connection
$id = Invoke-RestMethod -Uri "http://127.0.0.1:3500/eth/v1/node/identity" -TimeoutSec 10
$b1addr = $id.data.p2p_addresses | Where-Object { $_ -like "*/tcp/13000/p2p/*" } | Select-Object -First 1
Write-Host "Beacon1 multiaddr: $b1addr"

# Start Beacon Nodes 2 and 3
Start-BeaconNode -num 2 -grpc 4001 -rest 3501 -execPort 8552 -p2pTcp 13001 -p2pUdp 12001 -minSyncPeers 1 -peer $b1addr
Start-BeaconNode -num 3 -grpc 4002 -rest 3502 -execPort 8553 -p2pTcp 13002 -p2pUdp 12002 -minSyncPeers 1 -peer $b1addr
Start-Sleep -Seconds 10

# Start Validators
Start-Validator -num 1 -grpc 4000
Start-Sleep -Seconds 2
Start-Validator -num 2 -grpc 4001
Start-Sleep -Seconds 2
Start-Validator -num 3 -grpc 4002

Write-Host ""
Write-Host "All processes started. Check the opened windows for logs."
Write-Host "Wait for genesis time, then verify with:"
Write-Host "  Invoke-RestMethod -Uri 'http://127.0.0.1:3500/eth/v1/node/syncing'"
Write-Host "  Invoke-RestMethod -Uri 'http://127.0.0.1:18545' -Method POST -ContentType 'application/json' -Body '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
Write-Host "  node send_tx.js"
