<#
.SYNOPSIS
    Windows Security Audit Script

.DESCRIPTION
    Audits Windows Defender, Firewall, Windows Update, local accounts,
    password policy, Administrator account, security events, BitLocker,
    and User Account Control.

.NOTES
    Requires Windows PowerShell 5.1 or PowerShell 7 on Windows.
    Run as Administrator.
    Log files are saved to C:\Temp.
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------

$LogPath = 'C:\Temp'
$LogFileName = "SecurityAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName

$Script:SecurityIssuesFound = 0
$Script:SecurityWarnings = 0
$Script:SecurityPass = 0

# ---------------------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------------------

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogMessage = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        'INFO' {
            Write-Host $LogMessage -ForegroundColor White
        }
        'WARNING' {
            Write-Host $LogMessage -ForegroundColor Yellow
        }
        'ERROR' {
            Write-Host $LogMessage -ForegroundColor Red
        }
        'SUCCESS' {
            Write-Host $LogMessage -ForegroundColor Green
        }
    }

    try {
        Add-Content -Path $LogFile -Value $LogMessage -Encoding UTF8
    }
    catch {
        Write-Host "Unable to write to log file: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

function Show-Separator {
    Write-Log '================================================================' 'INFO'
}

function Get-StatusLevel {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [string]$FailureLevel = 'ERROR'
    )

    if ($Success) {
        return 'SUCCESS'
    }

    return $FailureLevel
}

function Test-WindowsDefender {
    Write-Log 'WINDOWS DEFENDER STATUS' 'INFO'
    Show-Separator

    try {
        $DefenderService = Get-Service -Name 'WinDefend' `
            -ErrorAction SilentlyContinue

        if ($null -eq $DefenderService) {
            Write-Log 'Windows Defender service was not found.' 'ERROR'
            $Script:SecurityIssuesFound++
            return
        }

        $ServiceRunning = $DefenderService.Status -eq 'Running'

        Write-Log "Service Status: $($DefenderService.Status)" `
            (Get-StatusLevel -Success $ServiceRunning)

        if ($ServiceRunning) {
            $Script:SecurityPass++
        }
        else {
            Write-Log 'Windows Defender service is not running.' 'ERROR'
            $Script:SecurityIssuesFound++
        }

        $DefenderStatus = Get-MpComputerStatus `
            -ErrorAction SilentlyContinue

        if ($null -eq $DefenderStatus) {
            Write-Log 'Detailed Defender status is unavailable.' 'WARNING'
            $Script:SecurityWarnings++
            return
        }

        $RealTimeEnabled = [bool]$DefenderStatus.RealTimeProtectionEnabled
        $QuickScanOutOfDate = [bool]$DefenderStatus.QuickScanOutOfDate

        Write-Log "Real-time Protection: $RealTimeEnabled" `
            (Get-StatusLevel -Success $RealTimeEnabled)

        Write-Log "Quick Scan Out Of Date: $QuickScanOutOfDate" `
            (Get-StatusLevel -Success (-not $QuickScanOutOfDate) 'WARNING')

        Write-Log "Full Scan Age (days): $($DefenderStatus.FullScanAge)" 'INFO'
        Write-Log "Antivirus Signature Version: $($DefenderStatus.AntivirusSignatureVersion)" 'INFO'
        Write-Log "Antispyware Signature Version: $($DefenderStatus.AntispywareSignatureVersion)" 'INFO'

        if ($RealTimeEnabled) {
            $Script:SecurityPass++
        }
        else {
            Write-Log 'Real-time protection is disabled.' 'ERROR'
            $Script:SecurityIssuesFound++
        }

        if ($QuickScanOutOfDate) {
            $Script:SecurityWarnings++
        }
        else {
            $Script:SecurityPass++
        }

        if ($null -ne $DefenderStatus.FullScanAge -and
            $DefenderStatus.FullScanAge -gt 30) {
            Write-Log "Last full scan was $($DefenderStatus.FullScanAge) days ago." 'WARNING'
            $Script:SecurityWarnings++
        }
    }
    catch {
        Write-Log "Error checking Windows Defender: $($_.Exception.Message)" 'ERROR'
        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Test-WindowsFirewall {
    Write-Log 'WINDOWS FIREWALL STATUS' 'INFO'
    Show-Separator

    try {
        $Profiles = @('Domain', 'Private', 'Public')
        $AllEnabled = $true

        foreach ($Profile in $Profiles) {
            $FirewallProfile = Get-NetFirewallProfile `
                -Name $Profile `
                -ErrorAction SilentlyContinue

            if ($null -eq $FirewallProfile) {
                Write-Log "$Profile firewall profile was not found." 'WARNING'
                $Script:SecurityWarnings++
                $AllEnabled = $false
                continue
            }

            $Enabled = [bool]$FirewallProfile.Enabled

            Write-Log "$Profile Profile Enabled: $Enabled" `
                (Get-StatusLevel -Success $Enabled)

            if (-not $Enabled) {
                Write-Log "$Profile firewall profile is disabled." 'ERROR'
                $Script:SecurityIssuesFound++
                $AllEnabled = $false
            }
            else {
                $Script:SecurityPass++
            }
        }

        if ($AllEnabled) {
            Write-Log 'All available firewall profiles are enabled.' 'SUCCESS'
        }
    }
    catch {
        Write-Log "Error checking Windows Firewall: $($_.Exception.Message)" 'ERROR'
        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Test-WindowsUpdate {
    Write-Log 'WINDOWS UPDATE STATUS' 'INFO'
    Show-Separator

    try {
        $UpdateService = Get-Service -Name 'wuauserv' `
            -ErrorAction SilentlyContinue

        if ($null -eq $UpdateService) {
            Write-Log 'Windows Update service was not found.' 'ERROR'
            $Script:SecurityIssuesFound++
        }
        else {
            $UpdateRunning = $UpdateService.Status -eq 'Running'

            Write-Log "Update Service Status: $($UpdateService.Status)" `
                (Get-StatusLevel -Success $UpdateRunning)

            if ($UpdateRunning) {
                $Script:SecurityPass++
            }
            else {
                Write-Log 'Windows Update service is not running.' 'WARNING'
                $Script:SecurityWarnings++
            }
        }

        $InstalledUpdates = Get-CimInstance `
            -ClassName Win32_QuickFixEngineering `
            -ErrorAction SilentlyContinue

        if ($null -eq $InstalledUpdates) {
            Write-Log 'No installed update information was returned.' 'WARNING'
            $Script:SecurityWarnings++
        }
        else {
            $UpdateCount = @($InstalledUpdates).Count
            Write-Log "Installed Updates Found: $UpdateCount" 'INFO'

            $LatestUpdate = $InstalledUpdates |
                Where-Object { $_.InstalledOn } |
                Sort-Object InstalledOn -Descending |
                Select-Object -First 1

            if ($null -ne $LatestUpdate) {
                Write-Log "Latest Installed Update: $($LatestUpdate.HotFixID)" 'INFO'
                Write-Log "Latest Installed Date: $($LatestUpdate.InstalledOn)" 'INFO'
            }

            $Script:SecurityPass++
        }
    }
    catch {
        Write-Log "Error checking Windows Update: $($_.Exception.Message)" 'ERROR'
        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Audit-UserAccounts {
    Write-Log 'USER ACCOUNT AUDIT' 'INFO'
    Show-Separator

    try {
        $Users = @(Get-LocalUser -ErrorAction Stop)
        $Administrators = @(
            Get-LocalGroupMember `
                -Group 'Administrators' `
                -ErrorAction SilentlyContinue
        )

        Write-Log "Total Local User Accounts: $($Users.Count)" 'INFO'

        foreach ($User in $Users) {
            Write-Log "User: $($User.Name)" 'INFO'
            Write-Log "Enabled: $($User.Enabled)" `
                (Get-StatusLevel -Success ([bool]$User.Enabled) 'WARNING')

            if ($User.LastLogon) {
                Write-Log "Last Logon: $($User.LastLogon)" 'INFO'
            }
            else {
                Write-Log 'Last Logon: Never or unavailable' 'INFO'
            }

            $IsAdministrator = $false

            foreach ($Member in $Administrators) {
                if ($Member.Name -match "\\$([regex]::Escape($User.Name))$" -or
                    $Member.Name -eq $User.Name) {
                    $IsAdministrator = $true
                    break
                }
            }

            if ($IsAdministrator) {
                Write-Log 'Member of local Administrators group.' 'WARNING'
                $Script:SecurityWarnings++
            }

            Write-Log '' 'INFO'
        }

        $Script:SecurityPass++
    }
    catch {
        Write-Log "Error auditing user accounts: $($_.Exception.Message)" 'ERROR'
        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Check-PasswordPolicy {
    Write-Log 'PASSWORD POLICY AUDIT' 'INFO'
    Show-Separator

    $TempPolicyFile = $null

    try {
        Write-Log 'Exporting local security policy...' 'INFO'

        $TempPolicyFile = Join-Path `
            -Path ([System.IO.Path]::GetTempPath()) `
            -ChildPath "SecurityPolicy_$([guid]::NewGuid().ToString('N')).inf"

        $SeceditOutput = secedit.exe `
            /export `
            /cfg $TempPolicyFile `
            /quiet 2>&1

        if (-not (Test-Path -Path $TempPolicyFile)) {
            Write-Log 'Unable to export local security policy.' 'WARNING'
            $Script:SecurityWarnings++
            return
        }

        $PolicyContent = Get-Content -Path $TempPolicyFile `
            -ErrorAction Stop

        $PolicyItems = @(
            'MinimumPasswordLength',
            'MaximumPasswordAge',
            'MinimumPasswordAge',
            'PasswordHistorySize',
            'PasswordComplexity',
            'LockoutBadCount',
            'LockoutDuration',
            'ResetLockoutCount'
        )

        foreach ($Item in $PolicyItems) {
            $Match = $PolicyContent |
                Select-String -Pattern "^\s*$Item\s*=" |
                Select-Object -First 1

            if ($null -ne $Match) {
                Write-Log $Match.Line.Trim() 'INFO'
            }
        }

        $Script:SecurityPass++
    }
    catch {
        Write-Log "Error checking password policy: $($_.Exception.Message)" 'WARNING'
        $Script:SecurityWarnings++
    }
    finally {
        if ($TempPolicyFile -and (Test-Path -Path $TempPolicyFile)) {
            Remove-Item -Path $TempPolicyFile -Force `
                -ErrorAction SilentlyContinue
        }
    }

    Write-Log '' 'INFO'
}

function Check-AdministratorAccount {
    Write-Log 'BUILT-IN ADMINISTRATOR ACCOUNT STATUS' 'INFO'
    Show-Separator

    try {
        $AdminAccount = Get-LocalUser -Name 'Administrator' `
            -ErrorAction SilentlyContinue

        if ($null -eq $AdminAccount) {
            Write-Log 'Built-in Administrator account was not found.' 'INFO'
            $Script:SecurityPass++
            return
        }

        Write-Log "Administrator Account Found: $($AdminAccount.Name)" 'INFO'
        Write-Log "Enabled: $($AdminAccount.Enabled)" `
            (Get-StatusLevel -Success (-not [bool]$AdminAccount.Enabled))

        Write-Log "Last Logon: $($AdminAccount.LastLogon)" 'INFO'

        if ($AdminAccount.Enabled) {
            Write-Log 'Built-in Administrator account is enabled.' 'ERROR'
            Write-Log 'Consider disabling it if it is not required.' 'WARNING'
            $Script:SecurityIssuesFound++
        }
        else {
            Write-Log 'Built-in Administrator account is disabled.' 'SUCCESS'
            $Script:SecurityPass++
        }
    }
    catch {
        Write-Log "Error checking Administrator account: $($_.Exception.Message)" 'ERROR'
        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Scan-SecurityEventLog {
    Write-Log 'SECURITY EVENT LOG ANALYSIS' 'INFO'
    Show-Separator

    try {
        $StartDate = (Get-Date).AddDays(-7)

        $FailedLogons = @(
            Get-WinEvent `
                -FilterHashtable @{
                    LogName   = 'Security'
                    Id        = 4625
                    StartTime = $StartDate
                } `
                -ErrorAction SilentlyContinue
        )

        $FailedCount = $FailedLogons.Count

        Write-Log "Failed Logon Attempts - Last 7 Days: $FailedCount" `
            (Get-StatusLevel -Success ($FailedCount -le 10) 'WARNING')

        if ($FailedCount -gt 10) {
            Write-Log 'High number of failed logon attempts detected.' 'WARNING'
            $Script:SecurityWarnings++
        }
        else {
            $Script:SecurityPass++
        }

        $AuditFailures = @(
            Get-WinEvent `
                -FilterHashtable @{
                    LogName   = 'Security'
                    Id        = 4625, 4719, 1102
                    StartTime = $StartDate
                } `
                -ErrorAction SilentlyContinue
        )

        Write-Log "Selected Security Events - Last 7 Days: $($AuditFailures.Count)" 'INFO'
    }
    catch {
        Write-Log "Could not retrieve Security event logs: $($_.Exception.Message)" 'WARNING'
        $Script:SecurityWarnings++
    }

    Write-Log '' 'INFO'
}

function Check-BitLocker {
    Write-Log 'BITLOCKER ENCRYPTION STATUS' 'INFO'
    Show-Separator

    try {
        $Volumes = @(Get-BitLockerVolume -ErrorAction SilentlyContinue)

        if ($Volumes.Count -eq 0) {
            Write-Log 'BitLocker information is unavailable or no volumes were found.' 'INFO'
            return
        }

        foreach ($Volume in $Volumes) {
            Write-Log "Drive: $($Volume.MountPoint)" 'INFO'
            Write-Log "Protection Status: $($Volume.ProtectionStatus)" 'INFO'
            Write-Log "Volume Status: $($Volume.VolumeStatus)" 'INFO'
            Write-Log "Encryption Percentage: $($Volume.EncryptionPercentage)%" 'INFO'

            $Protected = "$($Volume.ProtectionStatus)" -eq 'On'

            if ($Protected) {
                Write-Log 'BitLocker protection is enabled.' 'SUCCESS'
                $Script:SecurityPass++
            }
            else {
                Write-Log 'BitLocker protection is not enabled.' 'WARNING'
                $Script:SecurityWarnings++
            }
        }
    }
    catch {
        Write-Log "Error checking BitLocker status: $($_.Exception.Message)" 'WARNING'
        $Script:SecurityWarnings++
    }

    Write-Log '' 'INFO'
}

function Check-UserAccountControl {
    Write-Log 'USER ACCOUNT CONTROL STATUS' 'INFO'
    Show-Separator

    try {
        $UacPath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'

        $Uac = Get-ItemProperty `
            -Path $UacPath `
            -Name EnableLUA `
            -ErrorAction Stop

        $UacEnabled = $Uac.EnableLUA -eq 1

        Write-Log "UAC Enabled: $UacEnabled" `
            (Get-StatusLevel -Success $UacEnabled)

        if ($UacEnabled) {
            $Script:SecurityPass++
        }
        else {
            Write-Log 'User Account Control is disabled.' 'ERROR'
            $Script:SecurityIssuesFound++
        }
    }
    catch {
        Write-Log "Error checking UAC status: $($_.Exception.Message)" 'WARNING'
        $Script:SecurityWarnings++
    }

    Write-Log '' 'INFO'
}

function Show-SecurityReport {
    Write-Log '' 'INFO'
    Show-Separator
    Write-Log 'SECURITY AUDIT SUMMARY REPORT' 'INFO'
    Show-Separator

    Write-Log "Security Issues Found: $($Script:SecurityIssuesFound)" `
        (Get-StatusLevel `
            -Success ($Script:SecurityIssuesFound -eq 0))

    Write-Log "Security Warnings: $($Script:SecurityWarnings)" `
        (Get-StatusLevel `
            -Success ($Script:SecurityWarnings -eq 0) `
            -FailureLevel 'WARNING')

    Write-Log "Security Checks Passed: $($Script:SecurityPass)" 'SUCCESS'

    $TotalChecks =
        $Script:SecurityIssuesFound +
        $Script:SecurityWarnings +
        $Script:SecurityPass

    if ($TotalChecks -gt 0) {
        $SecurityScore = [math]::Round(
            ($Script:SecurityPass / $TotalChecks) * 100,
            0
        )

        if ($SecurityScore -ge 80) {
            $ScoreLevel = 'SUCCESS'
        }
        elseif ($SecurityScore -ge 60) {
            $ScoreLevel = 'WARNING'
        }
        else {
            $ScoreLevel = 'ERROR'
        }

        Write-Log "Overall Security Score: $SecurityScore%" $ScoreLevel
    }

    Write-Log '' 'INFO'
    Write-Log 'RECOMMENDATIONS:' 'INFO'

    if ($Script:SecurityIssuesFound -gt 0) {
        Write-Log 'Address critical security issues immediately.' 'ERROR'
        Write-Log 'Review the ERROR entries in this report.' 'ERROR'
    }

    if ($Script:SecurityWarnings -gt 0) {
        Write-Log 'Review and address security warnings.' 'WARNING'
    }

    Write-Log 'Keep Windows and security software updated.' 'INFO'
    Write-Log 'Run full antivirus scans regularly.' 'INFO'
    Write-Log 'Review security event logs periodically.' 'INFO'
    Write-Log 'Use strong, unique passwords.' 'INFO'

    Show-Separator
}

function Main {
    try {
        if (-not (Test-Path -Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force |
                Out-Null
        }

        New-Item -ItemType File -Path $LogFile -Force |
            Out-Null

        Write-Log '================================================================' 'INFO'
        Write-Log 'SYSTEM SECURITY AUDIT SCRIPT' 'INFO'
        Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
        Write-Log "Log File: $LogFile" 'INFO'
        Show-Separator

        Write-Log 'PHASE 1: ANTIVIRUS PROTECTION' 'INFO'
        Show-Separator
        Test-WindowsDefender

        Write-Log 'PHASE 2: FIREWALL CONFIGURATION' 'INFO'
        Show-Separator
        Test-WindowsFirewall

        Write-Log 'PHASE 3: WINDOWS UPDATE STATUS' 'INFO'
        Show-Separator
        Test-WindowsUpdate

        Write-Log 'PHASE 4: USER ACCOUNT AUDIT' 'INFO'
        Show-Separator
        Audit-UserAccounts

        Write-Log 'PHASE 5: PASSWORD POLICY' 'INFO'
        Show-Separator
        Check-PasswordPolicy

        Write-Log 'PHASE 6: ADMINISTRATOR ACCOUNT' 'INFO'
        Show-Separator
        Check-AdministratorAccount

        Write-Log 'PHASE 7: USER ACCOUNT CONTROL' 'INFO'
        Show-Separator
        Check-UserAccountControl

        Write-Log 'PHASE 8: BITLOCKER ENCRYPTION' 'INFO'
        Show-Separator
        Check-BitLocker

        Write-Log 'PHASE 9: SECURITY EVENT LOG ANALYSIS' 'INFO'
        Show-Separator
        Scan-SecurityEventLog

        Show-SecurityReport

        Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
        Write-Log "Log file saved to: $LogFile" 'INFO'
        Write-Log '================================================================' 'INFO'

        Write-Host ''
        Write-Host "Audit complete. Log saved to: $LogFile" `
            -ForegroundColor Cyan
    }
    catch {
        Write-Log "Fatal script error: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

# ---------------------------------------------------------------------
# START SCRIPT
# ---------------------------------------------------------------------

Main
