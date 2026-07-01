# One-click start for an N-node private PoS devnet using Prysm interop validators.
# Usage: .\start-interop-network.ps1 [-NodeCount 6] [-GenesisDelaySeconds 180]
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

if (-not (Test-Path -LiteralPath "$baseDir\genesis.json") -or
    -not (Test-Path -LiteralPath "$baseDir\chain-config.yaml") -or
    -not (Test-Path -LiteralPath "$baseDir\jwt.hex")) {
    Write-Error "Missing genesis.json, chain-config.yaml, or jwt.hex"
    exit 1
}

if ($NodeCount -lt 1) {
    Write-Error "NodeCount must be at least 1"
    exit 1
}

# --- Stop any existing processes ---
Write-Host "Stopping any running processes..."
Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# --- Clean old state (only generated state, keep keystore/node dirs) ---
Write-Host "Cleaning old state for $NodeCount nodes..."
for ($i = 1; $i -le $NodeCount; $i++) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i\geth"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i\blobpool"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "beacondata$i"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "validator_wallet$i"
}
Remove-Item -Force -ErrorAction SilentlyContinue "genesis.ssz"
Remove-Item -Force -ErrorAction SilentlyContinue "genesis-pos.json"
Remove-Item -Force -ErrorAction SilentlyContinue "*.log"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:LOCALAPPDATA\Eth2"

# --- Generate genesis ---
# When running more nodes than validators, only 3 validators are active. The rest are full (non-validating) nodes.
$validatorCount = [Math]::Min(3, $NodeCount)
$futureTime = [int][double]::Parse((Get-Date -Date (Get-Date).AddSeconds($GenesisDelaySeconds).ToUniversalTime() -UFormat %s))
Write-Host "Generating interop genesis for $validatorCount validators and $NodeCount nodes, genesis time: $futureTime"

# Helper functions for port math
function Get-GethPort($i) { return 30305 + $i }
function Get-GethHttpPort($i) { return 18544 + $i }
function Get-GethAuthPort($i) { return 8550 + $i }
function Get-BeaconGrpcPort($i) { return 3999 + $i }
function Get-BeaconRestPort($i) { return 3499 + $i }
function Get-BeaconTcpPort($i) { return 12999 + $i }
function Get-BeaconUdpPort($i) { return 11999 + $i }

& "$baseDir\prysmctl.exe" testnet generate-genesis `
    --num-validators=$validatorCount `
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
            break
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

# --- Deterministic Geth peering fallback ---
# --bootnodes is sometimes ignored on localhost/NAT setups. Explicitly mesh all nodes via admin_addPeer.
Write-Host "Ensuring all Geth nodes are peered..."
$allEnodes = @()
for ($i = 1; $i -le $NodeCount; $i++) {
    $http = Get-GethHttpPort $i
    $deadline = (Get-Date).AddSeconds(15)
    $enode = $null
    while ((Get-Date) -lt $deadline -and -not $enode) {
        try {
            $raw = (& "$baseDir\geth.exe" attach --exec "admin.nodeInfo.enode" http://127.0.0.1:$http).Trim().Trim('"')
            $enode = ($raw -replace '@\d+\.\d+\.\d+\.\d+:', '@127.0.0.1:') -replace '\?discport=\d+', ''
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if ($enode) {
        $allEnodes += $enode
    } else {
        Write-Warning "Could not capture enode for node$i"
    }
}

for ($i = 1; $i -le $NodeCount; $i++) {
    $http = Get-GethHttpPort $i
    $selfPort = Get-GethPort $i
    foreach ($enode in $allEnodes) {
        # Skip self by matching the port in the enode TCP section
        if ($enode -match ":$selfPort\b") { continue }
        $jsonBody = (@{
            jsonrpc = "2.0"
            method = "admin_addPeer"
            params = @($enode)
            id = 1
        } | ConvertTo-Json -Compress)
        try {
            $null = Invoke-RestMethod -Uri "http://127.0.0.1:$http" -Method POST -ContentType "application/json" -Body $jsonBody -TimeoutSec 3 -ErrorAction Stop
        } catch {
            Write-Warning "addPeer failed for node$i -> $enode"
        }
    }
}

Start-Sleep -Seconds 3

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

Write-Host "Starting $NodeCount validators (only the first 3 have active interop keys)..."
$validatorCount = [Math]::Min(3, $NodeCount)
for ($i = 1; $i -le $validatorCount; $i++) {
    $grpc = Get-BeaconGrpcPort $i
    $startIndex = $i - 1

    Start-Process -FilePath "$baseDir\validator.exe" -ArgumentList @(
        "--datadir", "validator_wallet$i",
        "--wallet-dir", "validator_wallet$i",
        "--chain-config-file", "chain-config.yaml",
        "--suggested-fee-recipient", "0x98608ADf9c785d54f40cDcf6700E990771b19226",
        "--beacon-rpc-provider", "127.0.0.1:$grpc",
        "--interop-num-validators", "1",
        "--interop-start-index", "$startIndex",
        "--accept-terms-of-use"
    ) -WorkingDirectory $baseDir -WindowStyle Normal

    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "All $NodeCount nodes started. Wait for genesis time, then verify:"
for ($i = 1; $i -le $NodeCount; $i++) {
    $http = Get-GethHttpPort $i
    $rest = Get-BeaconRestPort $i
    Write-Host "  Node $i  Geth HTTP: http://127.0.0.1:$http  Beacon REST: http://127.0.0.1:$rest"
}
Write-Host ""
Write-Host "Quick checks:"
Write-Host "  .\check-network-health.ps1 -NodeCount $NodeCount"
Write-Host "  node send_tx_node1_to_node2.js"
