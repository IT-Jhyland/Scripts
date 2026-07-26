<#
.SYNOPSIS
    Sierra Valley USD - Workstation Onboarding Script (Script A)

.DESCRIPTION
    Standardizes a freshly imaged Windows 11 workstation for domain deployment:
      1. Renames the machine to district naming convention
      2. Sets static DNS servers (campus domain controller / RODC)
      3. Enables Windows Firewall on all profiles
      4. Disables 3 unnecessary services (attack-surface reduction, CIS-aligned)
      5. Outputs a completion report (console + log file)

.NOTES
    Author:   Jon - IT0100 Final Project, Part D
    Run as:   Local Administrator, elevated PowerShell
    Requires: A restart to fully apply the computer rename (handled via -Restart switch)

.PARAMETER NewComputerName
    Target hostname, e.g. SVUSD-CAMPB-WS014

.PARAMETER DnsServers
    Array of DNS server IPs for this campus (typically the local DC/RODC first, HQ DC second)

.PARAMETER InterfaceAlias
    Name of the network adapter to apply DNS settings to (default: "Ethernet")

.PARAMETER Restart
    If specified, restarts the machine automatically after changes (rename requires a restart to fully apply)

.EXAMPLE
    .\Onboard-Workstation.ps1 -NewComputerName "SVUSD-CAMPB-WS014" -DnsServers "10.20.0.10","10.10.0.10" -Restart
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$NewComputerName,

    [Parameter(Mandatory = $true)]
    [string[]]$DnsServers,

    [Parameter(Mandatory = $false)]
    [string]$InterfaceAlias = "Ethernet",

    [switch]$Restart
)

# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
$logPath = "C:\IT\Onboarding-Logs"
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}
$timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile    = Join-Path $logPath "Onboard-$NewComputerName-$timestamp.log"
$oldName    = $env:COMPUTERNAME

# Services considered unnecessary on a standard staff/lab workstation.
# CIS-aligned attack-surface reduction: each of these is either legacy,
# unused on this hardware, or a common lateral-movement / info-disclosure vector.
$servicesToDisable = @(
    @{ Name = "Fax";            Reason = "No fax hardware in use; legacy service, unnecessary attack surface" },
    @{ Name = "RemoteRegistry"; Reason = "Remote registry editing not required; common post-exploitation target" },
    @{ Name = "WMPNetworkSvc";  Reason = "Windows Media Player network sharing not used; reduces exposed network service" }
)

# Report object collected as we go, printed + logged at the end
$report = [ordered]@{
    Timestamp        = $timestamp
    OldComputerName  = $oldName
    NewComputerName  = $NewComputerName
    RenameStatus     = "Not attempted"
    DnsServers       = ($DnsServers -join ", ")
    DnsStatus        = "Not attempted"
    FirewallStatus   = "Not attempted"
    ServicesDisabled = @()
    ServicesFailed   = @()
    OverallResult    = "Incomplete"
}

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "=== Starting onboarding for $oldName -> $NewComputerName ==="

# ----------------------------------------------------------------------------
# 1. Rename computer
# ----------------------------------------------------------------------------
try {
    if ($oldName -ne $NewComputerName) {
        Rename-Computer -NewName $NewComputerName -Force -PassThru | Out-Null
        $report.RenameStatus = "Success (pending restart to fully apply)"
        Write-Log "Renamed computer to $NewComputerName. Restart required to finalize."
    } else {
        $report.RenameStatus = "Skipped - already named $NewComputerName"
        Write-Log "Computer already named $NewComputerName, skipping rename."
    }
} catch {
    $report.RenameStatus = "FAILED: $($_.Exception.Message)"
    Write-Log "ERROR renaming computer: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# 2. Set DNS servers
# ----------------------------------------------------------------------------
try {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServers
    $report.DnsStatus = "Success"
    Write-Log "Set DNS servers on '$InterfaceAlias' to: $($DnsServers -join ', ')"
} catch {
    $report.DnsStatus = "FAILED: $($_.Exception.Message)"
    Write-Log "ERROR setting DNS: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# 3. Enable Windows Firewall on all profiles
# ----------------------------------------------------------------------------
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    $report.FirewallStatus = "Success - Domain, Public, Private all enabled"
    Write-Log "Enabled Windows Firewall on all profiles."
} catch {
    $report.FirewallStatus = "FAILED: $($_.Exception.Message)"
    Write-Log "ERROR enabling firewall: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# 4. Disable unnecessary services
# ----------------------------------------------------------------------------
foreach ($svc in $servicesToDisable) {
    try {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc.Name -StartupType Disabled
            $report.ServicesDisabled += "$($svc.Name) ($($svc.Reason))"
            Write-Log "Disabled service: $($svc.Name) - $($svc.Reason)"
        } else {
            $report.ServicesDisabled += "$($svc.Name) (not present on this system - skipped)"
            Write-Log "Service $($svc.Name) not found on this system, skipping."
        }
    } catch {
        $report.ServicesFailed += "$($svc.Name): $($_.Exception.Message)"
        Write-Log "ERROR disabling $($svc.Name): $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------------
# 5. Completion report
# ----------------------------------------------------------------------------
if ($report.ServicesFailed.Count -eq 0 -and $report.DnsStatus -eq "Success" -and $report.FirewallStatus -like "Success*") {
    $report.OverallResult = "SUCCESS"
} else {
    $report.OverallResult = "COMPLETED WITH ERRORS - review log"
}

Write-Log "=== Onboarding complete: $($report.OverallResult) ==="
Write-Log ""
Write-Log "----- COMPLETION REPORT -----"
$report.GetEnumerator() | ForEach-Object {
    $value = if ($_.Value -is [array]) { $_.Value -join "; " } else { $_.Value }
    Write-Log ("{0,-18}: {1}" -f $_.Key, $value)
}

# Also emit a PowerShell object for pipeline use / CSV export if desired
$reportObject = New-Object PSObject -Property $report
$reportObject | Export-Csv -Path (Join-Path $logPath "Onboard-$NewComputerName-$timestamp.csv") -NoTypeInformation

if ($Restart) {
    Write-Log "Restart flag set. Restarting in 15 seconds..."
    Start-Sleep -Seconds 15
    Restart-Computer -Force
} else {
    Write-Host "`nNOTE: A restart is required to fully apply the computer rename. Run Restart-Computer when ready." -ForegroundColor Yellow
}
