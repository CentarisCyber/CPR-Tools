# VSS_Check - Security One-Liners

A collection of PowerShell one-liners for quick security checks that return boolean true/false values. These can be run from remote devices to assess security posture.

## Available Checks

### System Checks
- **is-admin.ps1** - Check if running as administrator
- **is-rdp-enabled.ps1** - Check if RDP is enabled
- **is-bitlocker-enabled.ps1** - Check if BitLocker is enabled on C: drive
- **has-recent-hotfix.ps1** - Check for recent Windows updates (within 90 days)
- **vss.ps1** - Check if Volume Shadow Copy services are running

### Network and User Checks
- **multiple-subnets-detected.ps1** - Check if multiple subnets are detected
- **current-user-is-local-admin.ps1** - Check if current user is local admin
- **dns-filtering-detected.ps1** - Check if DNS filtering is in use
- **external-ip-differs-from-local.ps1** - Check if external IP differs from local

### Security Agent Checks
- **MDR-agent-installed.ps1** - Check if known malware protection is installed
- **backup-agent-installed.ps1** - Check if known backup agents are installed
- **security-service-agent-installed.ps1** - Check if SecurityServiceAgent is installed
- **firewall-mgmt-ports-open.ps1** - Check if management ports (22, 443, 3389) are open in firewall

### Network Security Management
- **discover-and-install-security-agent.ps1** - Scan local network for devices and auto-install SecurityServiceAgent
- **scan-and-install-security-agent.ps1** - Advanced network scanner with comprehensive agent management

For detailed network scanning examples and usage patterns, see [NETWORK-SCANNER-EXAMPLES.md](NETWORK-SCANNER-EXAMPLES.md).

### DNS Security Checks (require domain parameter)
- **has-spf.ps1** - Check if domain has SPF record
- **has-dmarc.ps1** - Check if domain has DMARC record  
- **has-dkim.ps1** - Check if domain has DKIM record

## Quick Start

For copy/paste one-liners that don't require file downloads, see [ONE-LINERS.md](ONE-LINERS.md).

For batch execution of all checks, use `run-all-checks.ps1`.

## Usage

### Basic Checks (no parameters)
```powershell
# Run a simple check
.\is-admin.ps1

# Run multiple checks
.\is-admin.ps1; .\is-rdp-enabled.ps1; .\vss.ps1
```

### Remote Execution
```powershell
# Execute on remote machine
Invoke-Command -ComputerName "RemotePC" -ScriptBlock {
    Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/CentarisCyber/VSS_Check/main/is-admin.ps1" -UseBasicParsing).Content
}

# Or download and run
Invoke-Command -ComputerName "RemotePC" -FilePath ".\is-admin.ps1"
```

### Domain-specific Checks
```powershell
# Check SPF for your domain
.\has-spf.ps1 -Domain "yourdomain.com"

# Check DMARC for your domain
.\has-dmarc.ps1 -Domain "yourdomain.com"

# Check DKIM with custom selector
.\has-dkim.ps1 -Selector "selector1" -Domain "yourdomain.com"
```

### Network Management and Agent Deployment
```powershell
# Scan local network and install SecurityServiceAgent where missing
.\discover-and-install-security-agent.ps1 -AgentUrl "https://yourserver.com/SecurityServiceAgent.msi"

# Dry run to see what would be installed
.\discover-and-install-security-agent.ps1 -AgentUrl "https://yourserver.com/SecurityServiceAgent.msi" -WhatIf

# Scan specific subnet with credentials
$cred = Get-Credential
.\discover-and-install-security-agent.ps1 -SubnetRange "10.0.1.0/24" -AgentUrl "https://yourserver.com/SecurityServiceAgent.msi" -Credential $cred

# Advanced scanning with comprehensive features
.\scan-and-install-security-agent.ps1 -SubnetRange "192.168.1.0/24" -AgentPath "C:\installers\agent.msi" -Credential $cred
```

### Batch Execution
```powershell
# Run all checks using the batch script
.\run-all-checks.ps1 -Domain "yourdomain.com" -DkimSelector "selector1"

# Or run all basic checks and collect results manually
$results = @{
    IsAdmin = .\is-admin.ps1
    RdpEnabled = .\is-rdp-enabled.ps1
    BitlockerEnabled = .\is-bitlocker-enabled.ps1
    RecentHotfix = .\has-recent-hotfix.ps1
    VssRunning = .\vss.ps1
    MultipleSubnets = .\multiple-subnets-detected.ps1
    UserIsAdmin = .\current-user-is-local-admin.ps1
    DnsFiltering = .\dns-filtering-detected.ps1
    MalwareAgent = .\MDR-agent-installed.ps1
    SecurityServiceAgent = .\security-service-agent-installed.ps1
    BackupAgent = .\backup-agent-installed.ps1
    MgmtPortsOpen = .\firewall-mgmt-ports-open.ps1
    ExternalIpDiffers = .\external-ip-differs-from-local.ps1
}
$results | ConvertTo-Json
```

## Notes

- All scripts return `$true`, `$false`, or `$null` (for checks that cannot be determined)
- Scripts are designed to handle errors gracefully and return `$false` when checks fail
- Some checks require administrator privileges for full functionality
- DNS checks require internet connectivity
- External IP check requires internet connectivity to ipify.org

## Security Agents Detected

The malware-agent-installed.ps1 script looks for these security solutions:
- Huntress
- SentinelOne  
- CrowdStrike
- Sophos
- Cylance
- Carbon Black
- Microsoft Defender

The backup-agent-installed.ps1 script looks for these backup solutions:
- Veeam
- Acronis
- Datto
- ShadowProtect
- Commvault
- Rubrik

## DNS Filtering Services Detected

The dns-filtering-detected.ps1 script checks for these known DNS filtering services:
- OpenDNS (208.67.222.222, 208.67.220.220)
- Cloudflare for Families (1.1.1.2, 1.1.1.3)
- Quad9 (9.9.9.9)
- CleanBrowsing (185.228.168.9, 185.228.169.9)
- AdGuard (94.140.14.14)