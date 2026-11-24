# SPDX-License-Identifier: Apache-2.0
$ErrorActionPreference = 'Stop'
$agentDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $agentDirectory
try {
    cargo build --offline --locked -p meshcentral-ios-bridge
    if ($LASTEXITCODE -ne 0) { throw 'Rust bridge build failed.' }
    Add-Type -Path (Join-Path $PSScriptRoot 'NativeInteropTests.cs')
    [NativeInteropTests]::Run($agentDirectory)
} finally {
    Pop-Location
}
