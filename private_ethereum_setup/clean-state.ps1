# Clean previous state for the private PoS devnet.
# Usage: .\clean-state.ps1 [-NodeCount 6]
param(
    [int]$NodeCount = 3
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Stopping any running geth / beacon-chain / validator / prysmctl processes..."
Get-Process | Where-Object { $_.ProcessName -in @('geth','beacon-chain','validator','prysmctl') } | Stop-Process -Force
Start-Sleep -Seconds 3

Write-Host "Removing node data for $NodeCount nodes..."
for ($i = 1; $i -le $NodeCount; $i++) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i\geth"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "node$i\blobpool"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "beacondata$i"
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "validator_wallet$i"
}

Write-Host "Removing generated genesis / runtime files..."
Remove-Item -Force -ErrorAction SilentlyContinue "genesis.ssz"
Remove-Item -Force -ErrorAction SilentlyContinue "genesis-pos.json"
Remove-Item -Force -ErrorAction SilentlyContinue "*.log"
Remove-Item -Force -ErrorAction SilentlyContinue "test_pids.txt"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$env:LOCALAPPDATA\Eth2"

Write-Host "Clean complete. You can now generate genesis and start the network."
