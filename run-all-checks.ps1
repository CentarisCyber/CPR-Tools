# Quick Security Batch Check
# Usage: .\run-all-checks.ps1 [-Domain "yourdomain.com"] [-DkimSelector "default"]
param(
    [string]$Domain = 'example.com',
    [string]$DkimSelector = 'default'
)

$results = [ordered]@{
    Timestamp = (Get-Date).ToString("o")
    Hostname = $env:COMPUTERNAME
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
    SPF_Present = .\has-spf.ps1 -Domain $Domain
    DMARC_Present = .\has-dmarc.ps1 -Domain $Domain
    DKIM_Present = .\has-dkim.ps1 -Selector $DkimSelector -Domain $Domain
}

$results | ConvertTo-Json