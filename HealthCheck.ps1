# ===== System Health Check Script =====
$reportPath = "C:\HealthCheckReport.txt"
$report = @()
$report += "System Health Check Report"
$report += "Generated: $(Get-Date)"
$report += "================================`n"

# 1. Check disk space on C: — warn if below 20% free
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
$report += "----- Disk Space Check -----"
$report += "Drive C: Total Size: $([math]::Round($disk.Size / 1GB, 2)) GB"
$report += "Drive C: Free Space: $([math]::Round($disk.FreeSpace / 1GB, 2)) GB"
$report += "Free Percentage: $freePercent%"
if ($freePercent -lt 20) {
    $report += "WARNING: Free disk space is below 20%!"
} else {
    $report += "Disk space is within acceptable range."
}
$report += ""

# 2. Check if Windows Defender is enabled
$report += "----- Windows Defender Status -----"
try {
    $defenderStatus = Get-MpComputerStatus
    $report += "Antivirus Enabled: $($defenderStatus.AntivirusEnabled)"
    $report += "Real-Time Protection Enabled: $($defenderStatus.RealTimeProtectionEnabled)"
    if (-not $defenderStatus.AntivirusEnabled) {
        $report += "WARNING: Windows Defender Antivirus is NOT enabled!"
    }
} catch {
    $report += "Could not retrieve Windows Defender status. It may not be installed or accessible."
}
$report += ""

# 3. List top 10 processes by CPU usage
$report += "----- Top 10 Processes by CPU Usage -----"
$topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, CPU, WorkingSet
$report += ($topProcesses | Format-Table -AutoSize | Out-String)

# 4. Save report to .txt file
$report | Out-File -FilePath $reportPath -Encoding utf8

Write-Host "Health check complete. Report saved to $reportPath"