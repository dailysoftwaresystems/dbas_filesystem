$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$Src = Join-Path $ProjectRoot "web\libs\src\dbas_filesystem_worker.js"
$Out = Join-Path $ProjectRoot "web\libs\dbas_filesystem_worker.js"

if (-not (Test-Path $Src)) {
    Write-Error "Source file not found: $Src"
    exit 1
}

# Install esbuild if not available
if (-not (Get-Command esbuild -ErrorAction SilentlyContinue)) {
    Write-Host "esbuild not found, installing via npm..."
    npm install -g esbuild
}

Write-Host "Minifying worker..."
esbuild $Src --minify --outfile=$Out --target=es2020

$OrigSize = (Get-Item $Src).Length
$MinSize = (Get-Item $Out).Length
$Reduction = [math]::Round(($OrigSize - $MinSize) / $OrigSize * 100)
Write-Host "Done: $OrigSize bytes -> $MinSize bytes ($Reduction% reduction)"
