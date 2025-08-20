# Network Scanner and Security Agent Auto-Installer
# Scans the local network for devices and automatically installs SecurityServiceAgent where missing
# Usage: .\scan-and-install-security-agent.ps1 [-SubnetRange "192.168.1.0/24"] [-AgentPath "C:\temp\agent.msi"] [-Credential $cred] [-WhatIf]

param(
    [string]$SubnetRange = "",  # Auto-detect if not specified
    [string]$AgentPath = "",    # Path to SecurityServiceAgent installer
    [System.Management.Automation.PSCredential]$Credential = $null,
    [switch]$WhatIf = $false,   # Dry run mode
    [switch]$Verbose = $false,
    [int]$TimeoutSeconds = 30,
    [string[]]$ExcludeIPs = @() # IPs to exclude from scanning
)

# Function to get local subnet ranges
function Get-LocalSubnets {
    try {
        $subnets = @()
        $adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -and 
            $_.IPAddress -notlike '127.*' -and 
            $_.IPAddress -notlike '169.254.*' -and
            $_.PrefixLength -ne $null
        }
        
        foreach ($adapter in $adapters) {
            $network = Get-NetworkAddress -IPAddress $adapter.IPAddress -PrefixLength $adapter.PrefixLength
            $subnets += "$network/$($adapter.PrefixLength)"
        }
        
        return $subnets | Select-Object -Unique
    }
    catch {
        Write-Warning "Failed to detect local subnets: $($_.Exception.Message)"
        return @()
    }
}

# Function to calculate network address
function Get-NetworkAddress {
    param([string]$IPAddress, [int]$PrefixLength)
    
    try {
        $ip = [System.Net.IPAddress]::Parse($IPAddress)
        $mask = [System.Net.IPAddress]::Parse((Convert-PrefixToMask -PrefixLength $PrefixLength))
        
        $networkBytes = @()
        for ($i = 0; $i -lt 4; $i++) {
            $networkBytes += $ip.GetAddressBytes()[$i] -band $mask.GetAddressBytes()[$i]
        }
        
        return "$($networkBytes[0]).$($networkBytes[1]).$($networkBytes[2]).$($networkBytes[3])"
    }
    catch {
        return $null
    }
}

# Function to convert prefix length to subnet mask
function Convert-PrefixToMask {
    param([int]$PrefixLength)
    
    $mask = [System.Net.IPAddress]::Parse("0.0.0.0")
    $maskBytes = $mask.GetAddressBytes()
    
    for ($i = 0; $i -lt $PrefixLength; $i++) {
        $byteIndex = [Math]::Floor($i / 8)
        $bitIndex = $i % 8
        $maskBytes[$byteIndex] = $maskBytes[$byteIndex] -bor (128 -shr $bitIndex)
    }
    
    return "$($maskBytes[0]).$($maskBytes[1]).$($maskBytes[2]).$($maskBytes[3])"
}

# Function to scan network for active devices
function Invoke-NetworkScan {
    param([string[]]$Subnets, [string[]]$ExcludeIPs, [int]$TimeoutSeconds)
    
    $activeHosts = @()
    
    foreach ($subnet in $Subnets) {
        Write-Host "Scanning subnet: $subnet" -ForegroundColor Cyan
        
        # Parse subnet (simple implementation for /24 networks)
        if ($subnet -match '^(\d+\.\d+\.\d+)\.\d+/24$') {
            $networkBase = $matches[1]
            
            # Ping sweep
            $jobs = @()
            for ($i = 1; $i -le 254; $i++) {
                $ip = "$networkBase.$i"
                if ($ip -notin $ExcludeIPs) {
                    $jobs += Start-Job -ScriptBlock {
                        param($targetIP, $timeout)
                        if (Test-Connection -ComputerName $targetIP -Count 1 -Quiet -TimeoutSeconds $timeout) {
                            return $targetIP
                        }
                    } -ArgumentList $ip, $TimeoutSeconds
                }
            }
            
            # Wait for ping jobs and collect results
            $jobs | ForEach-Object {
                $result = Receive-Job -Job $_ -Wait
                if ($result) {
                    $activeHosts += $result
                }
                Remove-Job -Job $_
            }
        }
    }
    
    return $activeHosts
}

# Function to check if SecurityServiceAgent is installed on remote machine
function Test-SecurityAgentInstalled {
    param([string]$ComputerName, [System.Management.Automation.PSCredential]$Credential)
    
    try {
        $scriptBlock = {
            # Enhanced pattern to include SecurityServiceAgent and common security agents
            $pattern = 'SecurityServiceAgent|Huntress|SentinelOne|CrowdStrike|Sophos|Cylance|Carbon Black|Microsoft Defender'
            $apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
                    Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
            
            if (-not $apps) {
                return $false
            }
            
            # Check for SecurityServiceAgent specifically
            $securityAgentFound = ($apps -join '|') -match 'SecurityServiceAgent'
            
            # Return detailed info
            return @{
                SecurityServiceAgent = $securityAgentFound
                AnySecurityAgent = (($apps -join '|') -match $pattern)
                InstalledAgents = ($apps | Where-Object { $_ -match $pattern })
            }
        }
        
        $params = @{
            ComputerName = $ComputerName
            ScriptBlock = $scriptBlock
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $params.Credential = $Credential
        }
        
        $result = Invoke-Command @params
        return $result
    }
    catch {
        Write-Warning "Failed to check agent on $ComputerName`: $($_.Exception.Message)"
        return $null
    }
}

# Function to install SecurityServiceAgent on remote machine
function Install-SecurityAgent {
    param([string]$ComputerName, [string]$AgentPath, [System.Management.Automation.PSCredential]$Credential, [bool]$WhatIf)
    
    if ($WhatIf) {
        Write-Host "WHATIF: Would install SecurityServiceAgent on $ComputerName" -ForegroundColor Yellow
        return @{ Success = $true; Message = "WhatIf mode - no actual installation" }
    }
    
    try {
        # First, test if we can reach the machine
        if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
            throw "Cannot reach $ComputerName"
        }
        
        $scriptBlock = {
            param($agentPath)
            
            # Check if installer exists
            if (-not (Test-Path $agentPath)) {
                throw "Agent installer not found at $agentPath"
            }
            
            # Install the agent (assuming MSI installer)
            $installProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$agentPath`" /quiet /norestart" -Wait -PassThru
            
            return @{
                ExitCode = $installProcess.ExitCode
                Success = $installProcess.ExitCode -eq 0
                Message = if ($installProcess.ExitCode -eq 0) { "Installation completed successfully" } else { "Installation failed with exit code $($installProcess.ExitCode)" }
            }
        }
        
        $params = @{
            ComputerName = $ComputerName
            ScriptBlock = $scriptBlock
            ArgumentList = $AgentPath
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $params.Credential = $Credential
        }
        
        $result = Invoke-Command @params
        return $result
    }
    catch {
        return @{
            Success = $false
            Message = "Installation failed: $($_.Exception.Message)"
        }
    }
}

# Main execution
function Main {
    Write-Host "=== Security Agent Network Scanner and Auto-Installer ===" -ForegroundColor Green
    Write-Host "Starting at $(Get-Date)" -ForegroundColor Gray
    
    # Determine subnets to scan
    $subnetsToScan = @()
    if ($SubnetRange) {
        $subnetsToScan = @($SubnetRange)
        Write-Host "Using specified subnet range: $SubnetRange" -ForegroundColor Yellow
    } else {
        Write-Host "Auto-detecting local subnets..." -ForegroundColor Yellow
        $subnetsToScan = Get-LocalSubnets
        if ($subnetsToScan.Count -eq 0) {
            Write-Error "No subnets detected. Please specify -SubnetRange parameter."
            return
        }
        Write-Host "Detected subnets: $($subnetsToScan -join ', ')" -ForegroundColor Yellow
    }
    
    # Validate agent path if installation is requested
    if ($AgentPath -and -not $WhatIf) {
        if (-not (Test-Path $AgentPath)) {
            Write-Error "Agent installer not found at: $AgentPath"
            return
        }
        Write-Host "Agent installer: $AgentPath" -ForegroundColor Yellow
    } elseif (-not $AgentPath) {
        Write-Warning "No agent path specified. Will only scan and report, no installation will occur."
    }
    
    # Scan for active devices
    Write-Host "`nScanning for active devices..." -ForegroundColor Cyan
    $activeDevices = Invoke-NetworkScan -Subnets $subnetsToScan -ExcludeIPs $ExcludeIPs -TimeoutSeconds $TimeoutSeconds
    
    if ($activeDevices.Count -eq 0) {
        Write-Host "No active devices found on the network." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($activeDevices.Count) active devices: $($activeDevices -join ', ')" -ForegroundColor Green
    
    # Check each device for SecurityServiceAgent
    $results = @()
    foreach ($device in $activeDevices) {
        Write-Host "`nChecking $device..." -ForegroundColor Cyan
        
        $agentStatus = Test-SecurityAgentInstalled -ComputerName $device -Credential $Credential
        
        if ($agentStatus -eq $null) {
            $results += [PSCustomObject]@{
                ComputerName = $device
                Status = "Unreachable"
                SecurityServiceAgent = $null
                AnySecurityAgent = $null
                InstalledAgents = @()
                InstallationAttempted = $false
                InstallationResult = "N/A - Device unreachable"
            }
            continue
        }
        
        $deviceResult = [PSCustomObject]@{
            ComputerName = $device
            Status = "Reachable"
            SecurityServiceAgent = $agentStatus.SecurityServiceAgent
            AnySecurityAgent = $agentStatus.AnySecurityAgent
            InstalledAgents = $agentStatus.InstalledAgents
            InstallationAttempted = $false
            InstallationResult = "N/A"
        }
        
        if ($agentStatus.SecurityServiceAgent) {
            Write-Host "  ✓ SecurityServiceAgent already installed" -ForegroundColor Green
            $deviceResult.InstallationResult = "Already installed"
        } else {
            Write-Host "  ✗ SecurityServiceAgent NOT installed" -ForegroundColor Red
            if ($agentStatus.AnySecurityAgent) {
                Write-Host "  ℹ Other security agents found: $($agentStatus.InstalledAgents -join ', ')" -ForegroundColor Yellow
            }
            
            # Attempt installation if agent path is provided
            if ($AgentPath -or $WhatIf) {
                Write-Host "  → Attempting installation..." -ForegroundColor Yellow
                $installResult = Install-SecurityAgent -ComputerName $device -AgentPath $AgentPath -Credential $Credential -WhatIf $WhatIf
                $deviceResult.InstallationAttempted = $true
                $deviceResult.InstallationResult = $installResult.Message
                
                if ($installResult.Success) {
                    Write-Host "  ✓ Installation successful" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Installation failed: $($installResult.Message)" -ForegroundColor Red
                }
            }
        }
        
        $results += $deviceResult
    }
    
    # Summary report
    Write-Host "`n=== SUMMARY REPORT ===" -ForegroundColor Green
    Write-Host "Scan completed at $(Get-Date)" -ForegroundColor Gray
    Write-Host "Total devices scanned: $($activeDevices.Count)" -ForegroundColor White
    Write-Host "Devices with SecurityServiceAgent: $(($results | Where-Object { $_.SecurityServiceAgent -eq $true }).Count)" -ForegroundColor Green
    Write-Host "Devices without SecurityServiceAgent: $(($results | Where-Object { $_.SecurityServiceAgent -eq $false }).Count)" -ForegroundColor Red
    Write-Host "Unreachable devices: $(($results | Where-Object { $_.Status -eq 'Unreachable' }).Count)" -ForegroundColor Yellow
    
    if ($AgentPath -or $WhatIf) {
        $successful = ($results | Where-Object { $_.InstallationAttempted -and $_.InstallationResult -match "successful|already installed" }).Count
        $failed = ($results | Where-Object { $_.InstallationAttempted -and $_.InstallationResult -notmatch "successful|already installed" }).Count
        Write-Host "Successful installations: $successful" -ForegroundColor Green
        Write-Host "Failed installations: $failed" -ForegroundColor Red
    }
    
    # Output detailed results
    Write-Host "`n=== DETAILED RESULTS ===" -ForegroundColor Cyan
    return $results
}

# Execute main function
try {
    $scanResults = Main
    $scanResults | Format-Table -AutoSize
    
    # Export results to JSON for further processing
    $jsonResults = $scanResults | ConvertTo-Json -Depth 3
    $reportPath = "SecurityAgentScanReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $jsonResults | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "`nDetailed report saved to: $reportPath" -ForegroundColor Green
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
}