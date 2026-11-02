# Standalone Windows test. Does not change app settings or save employee data.
$ErrorActionPreference = 'Stop'
$configPath = Join-Path $PSScriptRoot '../.env'
$configLine = Get-Content -LiteralPath $configPath | Where-Object { $_ -match '^\s*GOOGLE_MAPS_API_KEY\s*=' } | Select-Object -First 1
if (!$configLine) { throw 'Google Maps key is not configured.' }
$locationKey = ($configLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
$routers = @{}
for ($scan = 0; $scan -lt 3; $scan++) {
    $scanText = netsh wlan show networks mode=bssid | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Windows could not scan nearby Wi-Fi. Check location permission.' }
    $blocks = [regex]::Matches($scanText, '(?ims)^\s*BSSID\s+\d+\s*:\s*([0-9a-f:]{17})(.*?)(?=^\s*(?:BSSID\s+\d+|SSID\s+\d+)\s*:|\z)')
    foreach ($block in $blocks) {
        $routerId = $block.Groups[1].Value.ToLowerInvariant()
        $firstOctet = [Convert]::ToInt32($routerId.Substring(0, 2), 16)
        # Google excludes locally administered and multicast addresses.
        if (($firstOctet -band 3) -ne 0) { continue }
        $router = @{ macAddress = $routerId }
        $signal = [regex]::Match($block.Groups[2].Value, '(?im)^\s*Signal\s*:\s*(\d+)\s*%')
        if ($signal.Success) { $router.signalStrength = [int]([int]$signal.Groups[1].Value / 2 - 100) }
        $routers[$routerId] = $router
    }
    if ($scan -lt 2) { Start-Sleep -Seconds 2 }
}
Write-Output ('Suitable Wi-Fi routers found: ' + $routers.Count)
if ($routers.Count -lt 2) { Write-Output 'Insufficient Wi-Fi coverage: Google requires at least two suitable stationary routers. No location lookup sent.'; exit 2 }
$body = @{ considerIp = $false; wifiAccessPoints = @($routers.Values) } | ConvertTo-Json -Depth 4
try {
    $result = Invoke-RestMethod -Uri ('https://www.googleapis.com/geolocation/v1/geolocate?key=' + $locationKey) -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20
    $result | ConvertTo-Json -Depth 4
} catch {
    if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
    else { Write-Output 'Location lookup failed. No location returned.' }
    exit 1
}
