# Demo/Test script for network scanning functionality
# This shows the structure and tests components without actual network scanning

Write-Host "=== SecurityServiceAgent Network Scanner Demo ===" -ForegroundColor Green

# Test the SecurityServiceAgent detection function
Write-Host "`n1. Testing SecurityServiceAgent detection:" -ForegroundColor Cyan
$agentInstalled = & ".\security-service-agent-installed.ps1"
Write-Host "SecurityServiceAgent detected: $agentInstalled" -ForegroundColor $(if($agentInstalled) {"Green"} else {"Red"})

# Test network range detection (simulated)
Write-Host "`n2. Testing network range detection:" -ForegroundColor Cyan
try {
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'})[0]
    if ($localIP) {
        $networkBase = ($localIP.IPAddress.Split('.')[0..2] -join '.')
        $networkRange = "$networkBase.0/24"
        Write-Host "Detected network range: $networkRange" -ForegroundColor Green
    } else {
        Write-Host "No suitable network interface found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Network detection failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test the discovery script help
Write-Host "`n3. Discovery script parameters:" -ForegroundColor Cyan
Get-Help ".\discover-and-install-security-agent.ps1" -Parameter *

# Test the advanced scanner script help
Write-Host "`n4. Advanced scanner script parameters:" -ForegroundColor Cyan
Get-Help ".\scan-and-install-security-agent.ps1" -Parameter *

Write-Host "`n=== Demo Complete ===" -ForegroundColor Green
Write-Host "The network scanning functionality is ready for deployment in a Windows domain environment." -ForegroundColor Yellow