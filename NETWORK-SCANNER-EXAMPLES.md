# SecurityServiceAgent Network Scanner - Usage Examples

## Basic Network Scanning and Agent Installation

### 1. Quick Network Scan (Auto-detect local network)
```powershell
# Simple scan without installation (discovery only)
.\discover-and-install-security-agent.ps1

# Scan and show what would be installed (dry run)
.\discover-and-install-security-agent.ps1 -AgentUrl "https://yourserver.com/SecurityServiceAgent.msi" -WhatIf
```

### 2. Network Scan with Agent Installation
```powershell
# Download and install agent from URL
.\discover-and-install-security-agent.ps1 -AgentUrl "https://yourserver.com/SecurityServiceAgent.msi"

# Scan specific subnet
.\discover-and-install-security-agent.ps1 -SubnetRange "192.168.1.0/24" -AgentUrl "https://yourserver.com/agent.msi"

# Use credentials for domain authentication
$cred = Get-Credential
.\discover-and-install-security-agent.ps1 -AgentUrl "https://yourserver.com/agent.msi" -Credential $cred
```

### 3. Advanced Scanning with Local Installer
```powershell
# Use local MSI file (must be accessible to remote machines)
.\scan-and-install-security-agent.ps1 -SubnetRange "10.0.1.0/24" -AgentPath "\\fileserver\installers\SecurityServiceAgent.msi"

# Exclude specific IPs from scanning
.\scan-and-install-security-agent.ps1 -ExcludeIPs @("192.168.1.1", "192.168.1.10")

# Verbose output with longer timeout
.\scan-and-install-security-agent.ps1 -Verbose -TimeoutSeconds 10
```

## Remote Execution Examples

### Check Single Device
```powershell
# Check if SecurityServiceAgent is installed on specific machine
Invoke-Command -ComputerName "WORKSTATION01" -ScriptBlock {
    try {
        $pattern = 'SecurityServiceAgent'
        $apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
                Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        if (-not $apps) { return $false }
        return (($apps -join '|') -match $pattern)
    } catch { return $false }
}
```

### Install Agent on Single Device
```powershell
# Manual installation on specific machine
Invoke-Command -ComputerName "WORKSTATION01" -ScriptBlock {
    param($agentUrl)
    $tempPath = "$env:TEMP\SecurityServiceAgent.msi"
    Invoke-WebRequest -Uri $agentUrl -OutFile $tempPath -UseBasicParsing
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempPath`" /quiet /norestart" -Wait -PassThru
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    return $process.ExitCode
} -ArgumentList "https://yourserver.com/SecurityServiceAgent.msi"
```

## Batch Operations

### Domain-wide Deployment
```powershell
# Get all computers in domain and install agent
$computers = Get-ADComputer -Filter * | Select-Object -ExpandProperty Name
foreach ($computer in $computers) {
    Write-Host "Processing $computer..."
    try {
        # Check if agent is already installed
        $hasAgent = Invoke-Command -ComputerName $computer -ScriptBlock {
            try {
                $apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | 
                        Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
                return (($apps -join '|') -match 'SecurityServiceAgent')
            } catch { return $false }
        } -ErrorAction Stop
        
        if (-not $hasAgent) {
            Write-Host "Installing agent on $computer..." -ForegroundColor Yellow
            # Install agent here
        } else {
            Write-Host "Agent already installed on $computer" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to process $computer`: $($_.Exception.Message)"
    }
}
```

### Scheduled Compliance Check
```powershell
# Create scheduled task to regularly check and install agent
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"C:\Scripts\discover-and-install-security-agent.ps1`" -AgentUrl `"https://yourserver.com/agent.msi`""
$trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"
$principal = New-ScheduledTaskPrincipal -UserID "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "SecurityAgentCompliance" -Action $action -Trigger $trigger -Principal $principal
```

## Output and Reporting

### JSON Report Generation
```powershell
# Run scan and save results to JSON
$results = .\discover-and-install-security-agent.ps1 -AgentUrl "https://yourserver.com/agent.msi"
$results | ConvertTo-Json -Depth 3 | Out-File "SecurityAgentReport_$(Get-Date -Format 'yyyyMMdd').json"
```

### CSV Report for Management
```powershell
# Convert results to CSV for easy viewing
$results = .\discover-and-install-security-agent.ps1
$results | Select-Object Computer, Status, AgentInstalled, InstallationResult | Export-Csv -Path "SecurityAgentStatus.csv" -NoTypeInformation
```

## Troubleshooting

### Common Issues and Solutions

1. **Access Denied Errors**
   - Ensure running account has administrative privileges on target machines
   - Use domain administrator credentials: `-Credential (Get-Credential)`

2. **Network Connectivity Issues**
   - Verify Windows Remote Management (WinRM) is enabled on target machines
   - Check firewall rules allow PowerShell remoting

3. **Agent Installation Failures**
   - Verify agent URL/path is accessible from target machines
   - Check MSI installer is valid and compatible
   - Review Windows Event Logs on failed machines

4. **Large Network Scanning**
   - Use `-TimeoutSeconds` parameter to adjust network timeouts
   - Consider breaking large subnets into smaller ranges
   - Use `-ExcludeIPs` to skip known servers/infrastructure

### Enable PowerShell Remoting
```powershell
# Run on target machines to enable remoting
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```