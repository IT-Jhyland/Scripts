<#
.SYNOPSIS
    Reports on local user accounts: name, enabled status, last logon,
    and Administrators group membership. Flags enabled accounts that
    have never logged on. Exports results to CSV.

.NOTES
    Run in an elevated PowerShell session (Run as Administrator).
#>

# ---- Config ----
$OutputPath = "C:\Reports\LocalUserReport.csv"

# Make sure the output folder exists
$OutputFolder = Split-Path $OutputPath
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# Get members of the local Administrators group (works on non-domain-joined too)
$AdminMembers = Get-LocalGroupMember -Group "Administrators" |
    Select-Object -ExpandProperty Name

# Build the report
$Report = Get-LocalUser | ForEach-Object {

    $UserName = $_.Name

    # LocalUser objects don't always expose LastLogon reliably,
    # so cross-check against LastLogon property (may be blank/never)
    $LastLogon = $_.LastLogon

    # Check if this user appears in the Administrators group
    # (Get-LocalGroupMember returns names like "COMPUTERNAME\User" or "DOMAIN\User")
    $IsAdmin = $AdminMembers | Where-Object { $_ -like "*\$UserName" -or $_ -eq $UserName }

    # Flag: enabled AND never logged on
    $NeverLoggedOn = ($_.Enabled -eq $true) -and (-not $LastLogon)

    [PSCustomObject]@{
        UserName        = $UserName
        Enabled         = $_.Enabled
        LastLogon       = if ($LastLogon) { $LastLogon } else { "Never" }
        IsAdministrator = [bool]$IsAdmin
        FlaggedRisk     = $NeverLoggedOn
    }
}

# Display in console
$Report | Format-Table -AutoSize

# Highlight flagged accounts
$Flagged = $Report | Where-Object { $_.FlaggedRisk }
if ($Flagged) {
    Write-Host "`nWARNING: Enabled accounts that have never logged on:" -ForegroundColor Yellow
    $Flagged | Format-Table UserName, Enabled, LastLogon -AutoSize
} else {
    Write-Host "`nNo enabled accounts found with zero logons." -ForegroundColor Green
}

# Export to CSV
$Report | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host "`nReport saved to: $OutputPath" -ForegroundColor Cyan
