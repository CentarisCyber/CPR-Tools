# Network Device Discovery and Security Agent Auto-Installer
# Discovers active devices on local network and installs SecurityServiceAgent where missing
# Usage: .\discover-and-install-security-agent.ps1 [-SubnetRange "192.168.1.0/24"] [-AgentUrl "https://example.com/agent.msi"] [-Credential $cred] [-WhatIf]

param(
    [string]$SubnetRange = "",
    [string]$AgentUrl = "",
    [System.Management.Automation.PSCredential]$Credential = $null,
    [switch]$WhatIf = $false,
    [int]$TimeoutSeconds = 5,
    [string[]]$ExcludeIPs = @()
)

function Get-LocalNetworkRange {
    try {
        $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'})[0]
        if ($localIP) {
            $networkBase = ($localIP.IPAddress.Split('.')[0..2] -join '.')
            return "$networkBase.0/24"
        }
        return $null
    } catch {
        return $null
    }
}

function Find-ActiveDevices {
    param([string]$Network, [int]$Timeout, [string[]]$Exclude)
    
    $active = @()
    if ($Network -match '^(\d+\.\d+\.\d+)\.0/24$') {
        $base = $matches[1]
        Write-Host "Scanning network: $Network" -ForegroundColor Cyan
        
        $jobs = 1..254 | ForEach-Object {
            $ip = "$base.$_"
            if ($ip -notin $Exclude) {
                Start-Job -ScriptBlock {
                    param($target, $timeout)
                    if (Test-Connection -ComputerName $target -Count 1 -Quiet -TimeoutSeconds $timeout) {
                        return $target
                    }
                } -ArgumentList $ip, $Timeout
            }
        }
        
        $jobs | ForEach-Object {
            $result = Receive-Job -Job $_ -Wait
            if ($result) { $active += $result }
            Remove-Job -Job $_
        }
    }
    return $active
}

function Test-RemoteSecurityAgent {
    param([string]$Computer, [PSCredential]$Cred)
    
    try {
        $params = @{
            ComputerName = $Computer
            ScriptBlock = {
                try {
                    $pattern = 'SecurityServiceAgent'
                    $apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
                            Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
                    if (-not $apps) { return $false }
                    return (($apps -join '|') -match $pattern)
                } catch { return $false }
            }
            ErrorAction = 'Stop'
        }
        if ($Cred) { $params.Credential = $Cred }
        
        return Invoke-Command @params
    } catch {
        return $null
    }
}

function Install-RemoteAgent {
    param([string]$Computer, [string]$Url, [PSCredential]$Cred, [bool]$DryRun)
    
    if ($DryRun) {
        return @{ Success = $true; Message = "WhatIf: Would install agent on $Computer" }
    }
    
    if (-not $Url) {
        return @{ Success = $false; Message = "No agent URL provided" }
    }
    
    try {
        $params = @{
            ComputerName = $Computer
            ScriptBlock = {
                param($agentUrl)
                try {
                    $tempPath = "$env:TEMP\SecurityServiceAgent.msi"
                    Invoke-WebRequest -Uri $agentUrl -OutFile $tempPath -UseBasicParsing
                    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempPath`" /quiet /norestart" -Wait -PassThru
                    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                    return @{
                        Success = $process.ExitCode -eq 0
                        ExitCode = $process.ExitCode
                    }
                } catch {
                    return @{ Success = $false; Error = $_.Exception.Message }
                }
            }
            ArgumentList = $Url
            ErrorAction = 'Stop'
        }
        if ($Cred) { $params.Credential = $Cred }
        
        $result = Invoke-Command @params
        if ($result.Success) {
            return @{ Success = $true; Message = "Installation completed successfully" }
        } else {
            return @{ Success = $false; Message = "Installation failed: Exit code $($result.ExitCode)" }
        }
    } catch {
        return @{ Success = $false; Message = "Installation error: $($_.Exception.Message)" }
    }
}

# Main execution
Write-Host "=== Security Agent Network Scanner ===" -ForegroundColor Green

# Determine network to scan
$networkToScan = if ($SubnetRange) { $SubnetRange } else { Get-LocalNetworkRange }
if (-not $networkToScan) {
    Write-Error "Could not determine network range. Please specify -SubnetRange"
    exit 1
}

Write-Host "Scanning network: $networkToScan" -ForegroundColor Yellow

# Find active devices
$devices = Find-ActiveDevices -Network $networkToScan -Timeout $TimeoutSeconds -Exclude $ExcludeIPs
Write-Host "Found $($devices.Count) active devices" -ForegroundColor Green

# Check each device
$results = @()
foreach ($device in $devices) {
    Write-Host "`nChecking $device..." -ForegroundColor Cyan
    
    $hasAgent = Test-RemoteSecurityAgent -Computer $device -Cred $Credential
    $status = if ($hasAgent -eq $null) { "Unreachable" } 
              elseif ($hasAgent) { "Agent Installed" } 
              else { "No Agent" }
    
    $result = [PSCustomObject]@{
        Computer = $device
        Status = $status
        AgentInstalled = $hasAgent
        InstallationAttempted = $false
        InstallationResult = ""
    }
    
    if ($hasAgent -eq $false) {
        Write-Host "  SecurityServiceAgent not found" -ForegroundColor Red
        if ($AgentUrl -or $WhatIf) {
            Write-Host "  Attempting installation..." -ForegroundColor Yellow
            $installResult = Install-RemoteAgent -Computer $device -Url $AgentUrl -Cred $Credential -DryRun $WhatIf
            $result.InstallationAttempted = $true
            $result.InstallationResult = $installResult.Message
            
            if ($installResult.Success) {
                Write-Host "  ✓ $($installResult.Message)" -ForegroundColor Green
            } else {
                Write-Host "  ✗ $($installResult.Message)" -ForegroundColor Red
            }
        }
    } elseif ($hasAgent -eq $true) {
        Write-Host "  ✓ SecurityServiceAgent found" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Could not connect to device" -ForegroundColor Yellow
    }
    
    $results += $result
}

# Summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Green
$withAgent = ($results | Where-Object { $_.AgentInstalled -eq $true }).Count
$withoutAgent = ($results | Where-Object { $_.AgentInstalled -eq $false }).Count
$unreachable = ($results | Where-Object { $_.AgentInstalled -eq $null }).Count

Write-Host "Devices with agent: $withAgent" -ForegroundColor Green
Write-Host "Devices without agent: $withoutAgent" -ForegroundColor Red
Write-Host "Unreachable devices: $unreachable" -ForegroundColor Yellow

# Return results
return $results