# Stop all private PoS devnet processes.
# Usage: .\stop-network.ps1

Write-Host "Stopping geth / beacon-chain / validator / prysmctl processes..."
Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') } | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2
$remaining = Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') }
if ($remaining) {
    Write-Warning "Some processes are still running:"
    $remaining | Select-Object ProcessName, Id | Format-Table
} else {
    Write-Host "All blockchain processes stopped."
}
