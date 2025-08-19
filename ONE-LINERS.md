# Remote-Friendly One-Liners for Security Checks
# These can be executed directly via Invoke-Expression without downloading files

## Basic Security Checks (copy/paste these for remote execution)

### Check if running as administrator
```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

### Check if RDP is enabled
```powershell
try {(Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections -eq 0} catch {$false}
```

### Check if BitLocker is enabled on C: drive
```powershell
try {$b = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue; if (-not $b) {$false} else {($b.ProtectionStatus -eq 'On') -or ($b.ProtectionStatus -eq 1)}} catch {$false}
```

### Check for recent Windows updates (within 90 days)
```powershell
try {$h = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1; if (-not $h) {$false} else {$h.InstalledOn -gt (Get-Date).AddDays(-90)}} catch {$false}
```

### Check if Volume Shadow Copy services are running
```powershell
$services = @('System Event Notification Service','Background Intelligent Transfer Service','COM\+ Event System','Microsoft Software Shadow Copy Provider','Volume Shadow Copy'); try {(Get-Service | Where-Object {$_.DisplayName -in $services -and $_.Status -eq 'Running' }).Count -eq 5} catch { $false }
```

### Check if multiple subnets are detected
```powershell
try {((Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -and $_.IPAddress -notlike '127.*'}) | ForEach-Object {($_.IPAddress.Split('.')[0..2] -join '.')} | Select-Object -Unique).Count -gt 1} catch {$false}
```

### Check if current user is local admin
```powershell
try {$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; (Get-LocalGroupMember -Group Administrators -ErrorAction SilentlyContinue | Where-Object {$_.SID -eq $userSid -or $_.Name -match $env:USERNAME}).Count -gt 0} catch {([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
```

### Check if DNS filtering is detected
```powershell
try {$known = @('208.67.222.222','208.67.220.220','1.1.1.2','1.1.1.3','9.9.9.9','185.228.168.9','185.228.169.9','94.140.14.14'); $servers = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses; if (-not $servers) {$false} else {($servers | Where-Object {$known -contains $_}).Count -gt 0}} catch {$false}
```

### Check if malware agent is installed
```powershell
try {$pattern = 'Huntress|SentinelOne|CrowdStrike|Sophos|Cylance|Carbon Black|Microsoft Defender|CrowdStrike'; $apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue; if (-not $apps) {$false} else {(($apps -join '|') -match $pattern)}} catch {$false}
```

### Check if backup agent is installed
```powershell
try {$pattern = 'Veeam|Acronis|Datto|ShadowProtect|Commvault|Rubrik'; $apps = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue; if (-not $apps) {$false} else {(($apps -join '|') -match $pattern)}} catch {$false}
```

### Check if firewall management ports are open
```powershell
try {$rules = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue; if (-not $rules) {$false} else {$found = $false; foreach ($r in $rules) {$pf = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue; $af = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue; if ($pf -and $af) {$ports = ($pf.LocalPort -split ',') | ForEach-Object {$_.Trim()}; $remoteAny = $af.RemoteAddress -in @('Any','0.0.0.0/0','::/0'); if ($remoteAny -and ($ports -match '^(22|443|3389)$')) {$found = $true; break}}}; $found}} catch {$false}
```

### Check if external IP differs from local
```powershell
try {$ext = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=text' -UseBasicParsing -ErrorAction Stop).Trim(); $localIPs = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -and $_.IPAddress -notlike '127.*'}).IPAddress; if (-not $localIPs) {$null} else {-not ($localIPs -contains $ext)}} catch {$null}
```

## DNS Security Checks (replace 'yourdomain.com' with actual domain)

### Check if domain has SPF record
```powershell
$Domain = 'yourdomain.com'; try {$txt = (Resolve-DnsName -Name $Domain -Type TXT -ErrorAction SilentlyContinue).Strings -join ' '; if (-not $txt) {$false} else {($txt -match 'v=spf1')}} catch {$false}
```

### Check if domain has DMARC record
```powershell
$Domain = 'yourdomain.com'; try {$txt = (Resolve-DnsName -Name "_dmarc.$Domain" -Type TXT -ErrorAction SilentlyContinue).Strings -join ' '; if (-not $txt) {$false} else {($txt -match 'v=dmarc1')}} catch {$false}
```

### Check if domain has DKIM record (replace 'default' with actual selector)
```powershell
$Selector = 'default'; $Domain = 'yourdomain.com'; try {$txt = (Resolve-DnsName -Name "$Selector._domainkey.$Domain" -Type TXT -ErrorAction SilentlyContinue).Strings -join ' '; if (-not $txt) {$false} else {($txt -match 'v=DKIM1' -or $txt -match 'k=rsa')}} catch {$false}
```

## Remote Execution Examples

### Execute single check on remote machine
```powershell
Invoke-Command -ComputerName "RemotePC" -ScriptBlock {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
```

### Execute multiple checks and get JSON results
```powershell
Invoke-Command -ComputerName "RemotePC" -ScriptBlock {
    $results = @{
        Timestamp = (Get-Date).ToString("o")
        Hostname = $env:COMPUTERNAME
        IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        RdpEnabled = try {(Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections -eq 0} catch {$false}
        VssRunning = try {$services = @('System Event Notification Service','Background Intelligent Transfer Service','COM\+ Event System','Microsoft Software Shadow Copy Provider','Volume Shadow Copy'); (Get-Service | Where-Object {$_.DisplayName -in $services -and $_.Status -eq 'Running' }).Count -eq 5} catch { $false }
    }
    $results | ConvertTo-Json
}
```