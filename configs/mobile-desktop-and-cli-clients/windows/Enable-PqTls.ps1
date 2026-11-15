# Requires KB5089573 (Windows 11 24H2/25H2) or KB5099536 (Server 2025).
Enable-TlsEccCurve -Name "X25519_MLKEM768" -Position 0
Get-TlsEccCurve | Select-Object -First 5
