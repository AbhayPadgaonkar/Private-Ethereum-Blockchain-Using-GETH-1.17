# Wait for an N-node devnet to start producing blocks.
# Usage: .\wait-for-network.ps1 [-NodeCount 5] [-TimeoutSeconds 300]
param(
    [int]$NodeCount = 5,
    [int]$TimeoutSeconds = 300
)

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $allReady = $true
    $statusLines = @()
    for ($i = 1; $i -le $NodeCount; $i++) {
        $port = 18544 + $i
        try {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$port" -Method POST -ContentType "application/json" -Body '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' -TimeoutSec 2 -ErrorAction Stop
            $block = [int]$resp.result
            $statusLines += "Node $i (port $port): block $block"
            if ($block -le 0) { $allReady = $false }
        } catch {
            $allReady = $false
            $statusLines += "Node $i (port $port): unreachable"
        }
    }
    if ($allReady) {
        Write-Host "`nAll $NodeCount nodes are producing blocks." -ForegroundColor Green
        $statusLines | ForEach-Object { Write-Host $_ }
        exit 0
    }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Waiting for blocks..."
    $statusLines | ForEach-Object { Write-Host "  $_" }
    Start-Sleep -Seconds 5
}
Write-Error "Network did not become ready within $TimeoutSeconds seconds"
exit 1
