# One-click start for an N-node private PoS devnet using wallet-based validators.
# Usage: .\start-wallet-network-n.ps1 [-NodeCount 6] [-GenesisDelaySeconds 180]
param(
    [int]$NodeCount = 3,
    [int]$GenesisDelaySeconds = 180
)

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $baseDir

# --- Validate binaries ---
$requiredBinaries = @('geth.exe', 'beacon-chain.exe', 'validator.exe', 'prysmctl.exe')
foreach ($b in $requiredBinaries) {
    if (-not (Test-Path -LiteralPath "$baseDir\$b")) {
        Write-Error "Missing binary: $b. Place it in $baseDir"
        exit 1
    }
}

# --- Validate wallet prerequisites ---
$depositJsonDir = "$baseDir\wallet_setup\validator_keys"
$depositJson = "$depositJsonDir\deposit_data.json"
$walletPass = "$baseDir\wallet_setup\wallet_password.txt"
$accountPass = "$baseDir\wallet_setup\account_password.txt"

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

Generate wallet-based validator keys first (README Option B or C):
  python .\staking-deposit-cli-2.8.0\staking_deposit\deposit.py new-mnemonic `
    --num_validators $NodeCount `
    --devnet_chain_setting '{"network_name": "localdev", "genesis_fork_version": "20000089", "genesis_validator_root": "0000000000000000000000000000000000000000000000000000000000000000"}' `
    --folder wallet_setup\validator_keys

Then create password files and import the keystores.
"@
    exit 1
}

if (-not (Test-Path -LiteralPath $walletPass)) {
    Write-Error "Missing wallet password file: $walletPass"
    exit 1
}
if (-not (Test-Path -LiteralPath $accountPass)) {
    Write-Error "Missing account password file: $accountPass"
    exit 1
}

for ($i = 1; $i -le $NodeCount; $i++) {
    if (-not (Test-Path -LiteralPath "$baseDir\validator_wallet$i\direct\accounts\all-accounts.keystore.json")) {
        Write-Error "Missing imported validator wallet: validator_wallet$i. Run validator.exe accounts import first."
        exit 1
    }
}

if ($NodeCount -lt 1) {
    Write-Error "NodeCount must be at least 1"
    exit 1
}

# --- Stop any existing processes ---
Write-Host "Stopping any running processes..."
Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# --- Clean old state ---
Write-Host "Cleaning old state for $NodeCount nodes..."
for ($i = 1; $i -le $NodeCount; $i++) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i\geth"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i\blobpool"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "beacondata$i"
}
Remove-Item -Force -ErrorAction SilentlyContinue "genesis.ssz"
Remove-Item -Force -ErrorAction SilentlyContinue "genesis-pos.json"
Remove-Item -Force -ErrorAction SilentlyContinue "*.log"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:LOCALAPPDATA\Eth2"

# --- Generate genesis from deposit data ---
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds($GenesisDelaySeconds).ToUniversalTime() -UFormat %s))
Write-Host "Generating wallet-based genesis for $NodeCount validators, genesis time: $futureTime"

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

# --- Initialize Geth datadirs ---
Write-Host "Initializing Geth datadirs..."
for ($i = 1; $i -le $NodeCount; $i++) {
    & "$baseDir\geth.exe" init --datadir=node$i --state.scheme hash genesis-pos.json
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Geth init failed for node$i"
        exit 1
    }
}

# --- Helper functions ---
function Get-GethPort($i) { return 30305 + $i }
function Get-GethHttpPort($i) { return 18544 + $i }
function Get-GethAuthPort($i) { return 8550 + $i }
function Get-BeaconGrpcPort($i) { return 3999 + $i }
function Get-BeaconRestPort($i) { return 3499 + $i }
function Get-BeaconTcpPort($i) { return 12999 + $i }
function Get-BeaconUdpPort($i) { return 11999 + $i }

# --- Start Geth nodes ---
Write-Host "Starting $NodeCount Geth nodes..."

# Node 1 first
$p2p  = Get-GethPort 1
$http = Get-GethHttpPort 1
$auth = Get-GethAuthPort 1
$ipc  = "geth1.ipc"
$argList = @(
    "--datadir", "node1",
    "--port", "$p2p",
    "--networkid", "12345",
    "--syncmode", "full",
    "--state.scheme", "hash",
    "--http", "--http.port", "$http",
    "--http.api", "eth,net,web3,engine,admin",
    "--http.corsdomain=*", "--http.vhosts=*", "--http.addr", "127.0.0.1",
    "--authrpc.port", "$auth", "--authrpc.addr", "127.0.0.1", "--authrpc.vhosts=*",
    "--authrpc.jwtsecret", "jwt.hex",
    "--ipcpath", "$ipc"
)
$null = Start-Process -FilePath "$baseDir\geth.exe" -ArgumentList $argList -WorkingDirectory $baseDir -WindowStyle Normal

# --- Wait for Node 1 RPC and capture enode ---
Write-Host "Waiting for Node 1 RPC..."
$node1Http = Get-GethHttpPort 1
$node1Enode = $null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline -and -not $node1Enode) {
    Start-Sleep -Milliseconds 500
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$node1Http" -Method POST -ContentType "application/json" -Body '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' -TimeoutSec 2 -ErrorAction Stop
        if ($resp.result) {
            $raw = (& "$baseDir\geth.exe" attach --exec "admin.nodeInfo.enode" http://127.0.0.1:$node1Http).Trim().Trim('"')
            # Geth may advertise the external/public IP. Replace the IP with 127.0.0.1 and strip any discport query.
            $node1Enode = ($raw -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:') -replace '\?discport=\d+', ''
            Write-Host "Node 1 enode: $node1Enode"
        }
    } catch {
        # keep waiting
    }
}
if (-not $node1Enode) {
    Write-Error "Node 1 did not start in time. Check the geth window."
    exit 1
}

# Start Nodes 2..N with bootnode
for ($i = 2; $i -le $NodeCount; $i++) {
    $p2p  = Get-GethPort $i
    $http = Get-GethHttpPort $i
    $auth = Get-GethAuthPort $i
    $ipc  = "geth$i.ipc"

    $argList = @(
        "--datadir", "node$i",
        "--port", "$p2p",
        "--networkid", "12345",
        "--syncmode", "full",
        "--state.scheme", "hash",
        "--http", "--http.port", "$http",
        "--http.api", "eth,net,web3,engine,admin",
        "--http.corsdomain=*", "--http.vhosts=*", "--http.addr", "127.0.0.1",
        "--authrpc.port", "$auth", "--authrpc.addr", "127.0.0.1", "--authrpc.vhosts=*",
        "--authrpc.jwtsecret", "jwt.hex",
        "--ipcpath", "$ipc",
        "--bootnodes", "$node1Enode"
    )
    $null = Start-Process -FilePath "$baseDir\geth.exe" -ArgumentList $argList -WorkingDirectory $baseDir -WindowStyle Normal
}

Write-Host "Geth nodes started. Waiting for peering..."
Start-Sleep -Seconds 5

# --- Start Beacon Node 1 (bootstrap) ---
Write-Host "Starting Beacon Node 1..."
$b1Grpc = Get-BeaconGrpcPort 1
$b1Rest = Get-BeaconRestPort 1
$b1Tcp  = Get-BeaconTcpPort 1
$b1Udp  = Get-BeaconUdpPort 1
$g1Auth = Get-GethAuthPort 1

Start-Process -FilePath "$baseDir\beacon-chain.exe" -ArgumentList @(
    "--datadir", "beacondata1",
    "--min-sync-peers", "0",
    "--genesis-state", "genesis.ssz",
    "--chain-config-file", "chain-config.yaml",
    "--contract-deployment-block", "0",
    "--deposit-contract", "0x0000000000000000000000000000000000000000",
    "--rpc-host", "127.0.0.1", "--rpc-port", "$b1Grpc",
    "--grpc-gateway-host", "127.0.0.1", "--grpc-gateway-port", "$b1Rest",
    "--execution-endpoint", "http://127.0.0.1:$g1Auth",
    "--jwt-secret", "jwt.hex",
    "--suggested-fee-recipient", "0x98608ADf9c785d54f40cDcf6700E990771b19226",
    "--minimum-peers-per-subnet", "0",
    "--disable-staking-contract-check",
    "--interop-eth1data-votes",
    "--p2p-tcp-port", "$b1Tcp", "--p2p-udp-port", "$b1Udp",
    "--force-clear-db",
    "--accept-terms-of-use"
) -WorkingDirectory $baseDir -WindowStyle Normal

# --- Wait for Beacon Node 1 identity ---
Write-Host "Waiting for Beacon Node 1 identity..."
$b1Addr = $null
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline -and -not $b1Addr) {
    Start-Sleep -Milliseconds 500
    try {
        $id = Invoke-RestMethod -Uri "http://127.0.0.1:$b1Rest/eth/v1/node/identity" -TimeoutSec 2 -ErrorAction Stop
        $b1Addr = $id.data.p2p_addresses | Where-Object { $_ -like "*/tcp/$b1Tcp/p2p/*" } | Select-Object -First 1
        if ($b1Addr) {
            Write-Host "Beacon 1 multiaddr: $b1Addr"
        }
    } catch {
        # keep waiting
    }
}
if (-not $b1Addr) {
    Write-Error "Beacon Node 1 did not expose identity in time. Check its window."
    exit 1
}

# --- Start Beacon Nodes 2..N ---
Write-Host "Starting Beacon Nodes 2..$NodeCount..."
for ($i = 2; $i -le $NodeCount; $i++) {
    $grpc = Get-BeaconGrpcPort $i
    $rest = Get-BeaconRestPort $i
    $tcp  = Get-BeaconTcpPort $i
    $udp  = Get-BeaconUdpPort $i
    $auth = Get-GethAuthPort $i

    Start-Process -FilePath "$baseDir\beacon-chain.exe" -ArgumentList @(
        "--datadir", "beacondata$i",
        "--min-sync-peers", "1",
        "--genesis-state", "genesis.ssz",
        "--chain-config-file", "chain-config.yaml",
        "--contract-deployment-block", "0",
        "--deposit-contract", "0x0000000000000000000000000000000000000000",
        "--rpc-host", "127.0.0.1", "--rpc-port", "$grpc",
        "--grpc-gateway-host", "127.0.0.1", "--grpc-gateway-port", "$rest",
        "--execution-endpoint", "http://127.0.0.1:$auth",
        "--jwt-secret", "jwt.hex",
        "--suggested-fee-recipient", "0x98608ADf9c785d54f40cDcf6700E990771b19226",
        "--minimum-peers-per-subnet", "1",
        "--disable-staking-contract-check",
        "--interop-eth1data-votes",
        "--p2p-tcp-port", "$tcp", "--p2p-udp-port", "$udp",
        "--peer", "$b1Addr",
        "--force-clear-db",
        "--accept-terms-of-use"
    ) -WorkingDirectory $baseDir -WindowStyle Normal
}

Start-Sleep -Seconds 10

# --- Start Validators ---
Write-Host "Starting $NodeCount validators..."
for ($i = 1; $i -le $NodeCount; $i++) {
    $grpc = Get-BeaconGrpcPort $i

    Start-Process -FilePath "$baseDir\validator.exe" -ArgumentList @(
        "--datadir", "validator_wallet$i",
        "--wallet-dir", "validator_wallet$i",
        "--wallet-password-file", "wallet_setup\wallet_password.txt",
        "--chain-config-file", "chain-config.yaml",
        "--suggested-fee-recipient", "0x98608ADf9c785d54f40cDcf6700E990771b19226",
        "--beacon-rpc-provider", "127.0.0.1:$grpc",
        "--accept-terms-of-use"
    ) -WorkingDirectory $baseDir -WindowStyle Normal

    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "All $NodeCount wallet-based nodes started. Wait for genesis time, then verify:"
for ($i = 1; $i -le $NodeCount; $i++) {
    $http = Get-GethHttpPort $i
    $rest = Get-BeaconRestPort $i
    Write-Host "  Node $i  Geth HTTP: http://127.0.0.1:$http  Beacon REST: http://127.0.0.1:$rest"
}
Write-Host ""
Write-Host "Quick checks:"
Write-Host "  .\check-network-health.ps1 -NodeCount $NodeCount"
Write-Host "  node send_tx_node1_to_node2.js"
