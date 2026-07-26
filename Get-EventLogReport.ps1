<#
.SYNOPSIS
    Queries the System log for Error events and the Security log for
    failed logon events (Event ID 4625) in the last 24 hours.
    Combines both into a single timestamped text report.

.NOTES
    Run in an elevated PowerShell session (Run as Administrator) —
    the Security log requires admin rights to read.
#>

# ---- Config ----
$OutputPath = "C:\Reports\EventLogReport.txt"
$HoursBack  = 24
$StartTime  = (Get-Date).AddHours(-$HoursBack)

# Make sure the output folder exists
$OutputFolder = Split-Path $OutputPath
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# ---- Query System log: Errors in last 24 hours ----
$SystemErrors = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    Level     = 2   # 2 = Error
    StartTime = $StartTime
} -ErrorAction SilentlyContinue

# ---- Query Security log: Event ID 4625 (failed logon) in last 24 hours ----
$FailedLogons = Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4625
    StartTime = $StartTime
} -ErrorAction SilentlyContinue

# ---- Build report ----
$Lines = @()
$Lines += "Event Log Report"
$Lines += "Generated: $(Get-Date)"
$Lines += "Covering last $HoursBack hours (since $StartTime)"
$Lines += "=" * 60
$Lines += ""
$Lines += "SYSTEM LOG - ERROR EVENTS"
$Lines += "-" * 60

if ($SystemErrors) {
    foreach ($EventItem in $SystemErrors) {
        $Lines += "Time:     $($EventItem.TimeCreated)"
        $Lines += "Event ID: $($EventItem.Id)"
        $Lines += "Source:   $($EventItem.ProviderName)"
        $CleanMessage = $EventItem.Message -replace "`r`n", ' '
        $Lines += "Message:  $CleanMessage"
        $Lines += ""
    }
} else {
    $Lines += "No Error events found in the last $HoursBack hours."
    $Lines += ""
}

$Lines += "=" * 60
$Lines += ""
$Lines += "SECURITY LOG - FAILED LOGON EVENTS (ID 4625)"
$Lines += "-" * 60

if ($FailedLogons) {
    foreach ($EventItem in $FailedLogons) {
        # Pull key details out of the event's property data
        $EventXml    = [xml]$EventItem.ToXml()
        $TargetUser  = ($EventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
        $SourceIP    = ($EventXml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'

        $Lines += "Time:       $($EventItem.TimeCreated)"
        $Lines += "Target User: $TargetUser"
        $Lines += "Source IP:   $SourceIP"
        $Lines += ""
    }
} else {
    $Lines += "No failed logon events (4625) found in the last $HoursBack hours."
    $Lines += ""
}

# ---- Write report to file ----
$Lines | Out-File -FilePath $OutputPath -Encoding UTF8

# ---- Console summary ----
Write-Host "System errors found:  $($SystemErrors.Count)" -ForegroundColor Cyan
Write-Host "Failed logons found:  $($FailedLogons.Count)" -ForegroundColor Cyan
Write-Host "Report saved to: $OutputPath" -ForegroundColor Green
