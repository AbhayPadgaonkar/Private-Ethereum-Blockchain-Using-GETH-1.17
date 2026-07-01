# Check the health of an N-node private PoS devnet.
# Usage: .\check-network-health.ps1 [-NodeCount 6] [-Watch]
param(
    [int]$NodeCount = 3,
    [switch]$Watch
)

function Get-GethHttpPort($i) { return 18544 + $i }
function Get-BeaconRestPort($i) { return 3499 + $i }

function Test-Node($i) {
    $http = Get-GethHttpPort $i
    $rest = Get-BeaconRestPort $i

    $result = [pscustomobject]@{
        Node = $i
        GethHttp = $http
        BeaconRest = $rest
        GethBlock = $null
        GethPeers = $null
        BeaconSyncing = $null
        BeaconSyncDistance = $null
        BeaconPeers = $null
        HeadSlot = $null
        Error = $null
    }

    try {
        $blockResp = Invoke-RestMethod -Uri "http://127.0.0.1:$http" -Method POST -ContentType "application/json" -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' -TimeoutSec 3 -ErrorAction Stop
        $result.GethBlock = [int]$blockResp.result
    } catch {
        $result.Error = "Geth unreachable on port $http"
        return $result
    }

    try {
        $peerResp = Invoke-RestMethod -Uri "http://127.0.0.1:$http" -Method POST -ContentType "application/json" -Body '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' -TimeoutSec 3 -ErrorAction Stop
        $result.GethPeers = [int]$peerResp.result
    } catch {
        $result.GethPeers = "?"
    }

    try {
        $syncResp = Invoke-RestMethod -Uri "http://127.0.0.1:$rest/eth/v1/node/syncing" -TimeoutSec 3 -ErrorAction Stop
        $result.BeaconSyncing = $syncResp.data.is_syncing
        $result.BeaconSyncDistance = [int]$syncResp.data.sync_distance
    } catch {
        $result.Error = ($result.Error, "Beacon REST unreachable on port $rest" -join "; ").Trim("; ")
        return $result
    }

    try {
        $peerResp = Invoke-RestMethod -Uri "http://127.0.0.1:$rest/eth/v1/node/peers" -TimeoutSec 3 -ErrorAction Stop
        $result.BeaconPeers = $peerResp.data.Length
    } catch {
        $result.BeaconPeers = "?"
    }

    try {
        $headResp = Invoke-RestMethod -Uri "http://127.0.0.1:$rest/eth/v1/beacon/headers/head" -TimeoutSec 3 -ErrorAction Stop
        $result.HeadSlot = [int]$headResp.data.header.message.slot
    } catch {
        $result.HeadSlot = "?"
    }

    return $result
}

do {
    Clear-Host
    Write-Host "=== Network Health ($NodeCount nodes) ===" -ForegroundColor Cyan
    $rows = @()
    for ($i = 1; $i -le $NodeCount; $i++) {
        $rows += Test-Node $i
    }
    $rows | Format-Table Node, GethHttp, BeaconRest, GethBlock, GethPeers, BeaconSyncing, BeaconSyncDistance, BeaconPeers, HeadSlot, Error -AutoSize

    $allGood = $rows | Where-Object { $_.Error -or $_.BeaconSyncing -eq $true -or $_.GethPeers -eq 0 }
    if (-not $allGood) {
        Write-Host "All nodes are reachable, synced, and peered." -ForegroundColor Green
    } else {
        Write-Host "Some nodes are still syncing or unreachable." -ForegroundColor Yellow
    }

    if (-not $Watch) { break }
    Start-Sleep -Seconds 5
} while ($Watch)
