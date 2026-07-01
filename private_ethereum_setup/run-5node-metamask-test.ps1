# End-to-end test: 5-node PoS devnet + MetaMask wallets + cross-node transaction.
# Usage: .\run-5node-metamask-test.ps1
param(
    [int]$NodeCount = 5,
    [int]$ValidatorCount = 3,
    [int]$GenesisDelaySeconds = 180
)

$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $baseDir

$logFile = Join-Path $baseDir "5node-metamask-test.log"
Start-Transcript -Path $logFile -Force

try {
    $startTime = Get-Date
    Write-Host "`n=== 5-Node PoS + MetaMask Test ===" -ForegroundColor Cyan
    Write-Host "Started at: $startTime"
    Write-Host "Node count: $NodeCount"
    Write-Host "Validator count: $ValidatorCount (interop validators on first $ValidatorCount nodes)"

    # 1. Stop any existing processes
    Write-Host "`n[1/8] Stopping any running blockchain processes..." -ForegroundColor Cyan
    Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # 2. Generate 5 funded wallets
    Write-Host "`n[2/8] Generating $NodeCount funded wallets..." -ForegroundColor Cyan
    $env:WALLET_COUNT = $NodeCount
    $env:WALLET_BALANCE_ETH = '100000'
    node create-funded-wallets.js
    if ($LASTEXITCODE -ne 0) { throw "create-funded-wallets.js failed" }

    # 3. Start the network
    Write-Host "`n[3/8] Starting $NodeCount-node PoS devnet (interop validators)..." -ForegroundColor Cyan
    .\start-interop-network.ps1 -NodeCount $NodeCount -GenesisDelaySeconds $GenesisDelaySeconds
    if ($LASTEXITCODE -ne 0) { throw "start-interop-network.ps1 failed" }

    # 4. Wait for network to produce blocks
    Write-Host "`n[4/8] Waiting for all nodes to produce blocks..." -ForegroundColor Cyan
    $waitTimeout = $GenesisDelaySeconds + 120
    .\wait-for-network.ps1 -NodeCount $NodeCount -TimeoutSeconds $waitTimeout
    if ($LASTEXITCODE -ne 0) { throw "wait-for-network.ps1 failed" }

    # 5. Check sync across all nodes
    Write-Host "`n[5/8] Verifying all nodes are in sync..." -ForegroundColor Cyan
    node test_5node_sync.js
    if ($LASTEXITCODE -ne 0) { throw "test_5node_sync.js failed" }

    # 6. Send test transaction between Node 1 and Node 2 wallets via Node 3 RPC
    Write-Host "`n[6/8] Sending test transaction between wallets..." -ForegroundColor Cyan
    $env:SENDER_NODE = 1
    $env:RECIPIENT_NODE = 2
    $env:RPC_NODE = 3
    $env:AMOUNT_ETH = '10'
    node test_metamask_tx.js
    if ($LASTEXITCODE -ne 0) { throw "test_metamask_tx.js failed" }

    # 7. Verify balances via all 5 nodes one more time
    Write-Host "`n[7/8] Final balance verification across all nodes..." -ForegroundColor Cyan
    $wallets = Get-Content metamask-wallets.json | ConvertFrom-Json
    $sender = $wallets.wallets | Where-Object { $_.node -eq 1 }
    $recipient = $wallets.wallets | Where-Object { $_.node -eq 2 }

    for ($i = 1; $i -le $NodeCount; $i++) {
        $port = 18544 + $i
        try {
            $body = "{`"jsonrpc`":`"2.0`",`"method`":`"eth_getBalance`",`"params`":[`"$($sender.address)`",`"latest`"],`"id`":1}"
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$port" -Method POST -ContentType "application/json" -Body $body -TimeoutSec 5 -ErrorAction Stop
            $bal = [System.Numerics.BigInteger]::Parse($resp.result.TrimStart('0x'), [System.Globalization.NumberStyles]::HexNumber)
            $eth = [math]::Round([double]$bal / 1e18, 18)
            Write-Host "Node $i sender balance: $eth ETH"
        } catch {
            Write-Warning "Node $i balance check failed: $_"
        }
    }

    # 8. Stop network
    Write-Host "`n[8/8] Stopping network..." -ForegroundColor Cyan
    .\stop-network.ps1

    $endTime = Get-Date
    $duration = $endTime - $startTime
    Write-Host "`n=== Test completed successfully ===" -ForegroundColor Green
    Write-Host "Started:  $startTime"
    Write-Host "Finished: $endTime"
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-Host "Log file: $logFile"
} catch {
    Write-Host "`n=== Test failed ===" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host "Stopping any remaining processes..."
    .\stop-network.ps1
    Stop-Transcript
    exit 1
}

Stop-Transcript
