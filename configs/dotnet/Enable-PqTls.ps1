#Requires -RunAsAdministrator
# Puts the hybrid ML-KEM group first in the Schannel supported-groups order.
# Needs Windows Server 2025 with KB5099536 (2026-07-14) or later,
# or Windows 11 24H2/25H2 with KB5089573 or later.
$ErrorActionPreference = 'Stop'
$build = [Environment]::OSVersion.Version
Write-Output "OS build: $build"
if ($build.Build -lt 26100) { throw 'Schannel ML-KEM groups need Windows Server 2025 / Windows 11 24H2 or later.' }

Write-Output 'Before:'; Get-TlsEccCurve
Enable-TlsEccCurve -Name 'X25519_MLKEM768' -Position 0
Write-Output 'After:'; Get-TlsEccCurve

# A Group Policy "ECC Curve Order" setting overrides this; if one is set, edit the GPO instead.
# Reboot so every Schannel user (IIS, HTTP.sys, Kestrel, HttpClient) picks up the new order.
Restart-Computer -Force
