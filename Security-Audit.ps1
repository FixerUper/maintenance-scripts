<#
.SYNOPSIS
    Windows Security Audit Script

.DESCRIPTION
    Audits Windows Defender, Firewall, Windows Update, local accounts,
    password policy, the built-in Administrator account, security events,
    BitLocker, and User Account Control.

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

$LogFileName = 'SecurityAudit_{0}.log' -f `
    (Get-Date -Format 'yyyyMMdd_HHmmss')

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

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = '[{0}] [{1}] {2}' -f $timestamp, $Level, $Message

    switch ($Level) {
        'INFO' {
            Write-Host $logMessage -ForegroundColor White
        }

        'WARNING' {
            Write-Host $logMessage -ForegroundColor Yellow
        }

        'ERROR' {
            Write-Host $logMessage -ForegroundColor Red
        }

        'SUCCESS' {
            Write-Host $logMessage -ForegroundColor Green
        }
    }

    try {
        Add-Content `
            -Path $LogFile `
            -Value $logMessage `
            -Encoding UTF8 `
            -ErrorAction Stop
    }
    catch {
        Write-Host `
            "Unable to write to log file: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

function Show-Separator {
    Write-Log `
        -Message ('=' * 72) `
        -Level 'INFO'
}

function Get-StatusLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
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
        $defenderService = Get-Service `
            -Name 'WinDefend' `
            -ErrorAction SilentlyContinue

        if ($null -eq $defenderService) {
            Write-Log `
                'Windows Defender service was not found.' `
                'ERROR'

            $Script:SecurityIssuesFound++
            return
        }

        $serviceRunning = $defenderService.Status -eq 'Running'

        Write-Log `
            -Message "Service Status: $($defenderService.Status)" `
            -Level (Get-StatusLevel -Success $serviceRunning)

        if ($serviceRunning) {
            $Script:SecurityPass++
        }
        else {
            Write-Log `
                'Windows Defender service is not running.' `
                'ERROR'

            $Script:SecurityIssuesFound++
        }

        $defenderStatus = Get-MpComputerStatus `
            -ErrorAction Stop

        if ($null -eq $defenderStatus) {
            Write-Log `
                'Detailed Defender status is unavailable.' `
                'WARNING'

            $Script:SecurityWarnings++
            return
        }

        $realTimeEnabled = [bool]$defenderStatus.RealTimeProtectionEnabled

        Write-Log `
            -Message "Real-time Protection: $realTimeEnabled" `
            -Level (Get-StatusLevel -Success $realTimeEnabled)

        if ($realTimeEnabled) {
            $Script:SecurityPass++
        }
        else {
            Write-Log `
                'Real-time protection is disabled.' `
                'ERROR'

            $Script:SecurityIssuesFound++
        }

        # QuickScanOutOfDate is not available on all Windows versions.
        # Use QuickScanAge or QuickScanEndTime instead.
        $quickScanAge = $null
        $quickScanEndTime = $null

        $propertyNames = @(
            $defenderStatus.PSObject.Properties.Name
        )

        if ($propertyNames -contains 'QuickScanAge') {
            $quickScanAge = $defenderStatus.QuickScanAge
        }

        if ($propertyNames -contains 'QuickScanEndTime') {
            $quickScanEndTime = $defenderStatus.QuickScanEndTime
        }

        $maximumQuickScanAgeDays = 7
        $quickScanOutOfDate = $false
        $quickScanUnavailable = $false

        if ($null -ne $quickScanAge) {
            # Defender may use UInt32::MaxValue when no scan exists.
            if ([uint32]$quickScanAge -eq [uint32]::MaxValue) {
                $quickScanUnavailable = $true
            }
            else {
                $quickScanOutOfDate =
                    [uint32]$quickScanAge -gt $maximumQuickScanAgeDays
            }
        }
        elseif ($null -ne $quickScanEndTime) {
            $quickScanOutOfDate =
                $quickScanEndTime -lt `
                (Get-Date).AddDays(-$maximumQuickScanAgeDays)
        }
        else {
            $quickScanUnavailable = $true
        }

        if ($quickScanUnavailable) {
            Write-Log `
                'No quick scan has been recorded or scan status is unavailable.' `
                'WARNING'

            $Script:SecurityWarnings++
        }
        elseif ($quickScanOutOfDate) {
            Write-Log `
                "Quick scan is out of date. Age: $quickScanAge day(s)." `
                'WARNING'

            $Script:SecurityWarnings++
        }
        else {
            if ($null -ne $quickScanAge) {
                Write-Log `
                    "Quick scan is current. Age: $quickScanAge day(s)." `
                    'SUCCESS'
            }
            else {
                Write-Log `
                    "Quick scan is current. Last scan: $quickScanEndTime" `
                    'SUCCESS'
            }

            $Script:SecurityPass++
        }

        if ($null -ne $defenderStatus.FullScanAge) {
            $fullScanAge = [uint32]$defenderStatus.FullScanAge

            if ($fullScanAge -eq [uint32]::MaxValue) {
                Write-Log `
                    'No full scan has been recorded.' `
                    'WARNING'

                $Script:SecurityWarnings++
            }
            else {
                Write-Log `
                    "Full Scan Age: $fullScanAge day(s)" `
                    'INFO'

                if ($fullScanAge -gt 30) {
                    Write-Log `
                        'Last full scan was more than 30 days ago.' `
                        'WARNING'

                    $Script:SecurityWarnings++
                }
            }
        }

        if ($propertyNames -contains 'AntivirusSignatureVersion') {
            Write-Log `
                "Antivirus Signature Version: $($defenderStatus.AntivirusSignatureVersion)" `
                'INFO'
        }

        if ($propertyNames -contains 'AntispywareSignatureVersion') {
            Write-Log `
                "Antispyware Signature Version: $($defenderStatus.AntispywareSignatureVersion)" `
                'INFO'
        }
    }
    catch {
        Write-Log `
            -Message "Error checking Windows Defender: $($_.Exception.Message)" `
            -Level 'ERROR'

        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Test-WindowsFirewall {
    Write-Log 'WINDOWS FIREWALL STATUS' 'INFO'
    Show-Separator

    try {
        $profiles = @('Domain', 'Private', 'Public')
        $allEnabled = $true

        foreach ($profile in $profiles) {
            $firewallProfile = Get-NetFirewallProfile `
                -Name $profile `
                -ErrorAction SilentlyContinue

            if ($null -eq $firewallProfile) {
                Write-Log `
                    "$profile firewall profile was not found." `
                    'WARNING'

                $Script:SecurityWarnings++
                $allEnabled = $false
                continue
            }

            $enabled = [bool]$firewallProfile.Enabled

            Write-Log `
                -Message "$profile Profile Enabled: $enabled" `
                -Level (Get-StatusLevel -Success $enabled)

            if ($enabled) {
                $Script:SecurityPass++
            }
            else {
                Write-Log `
                    "$profile firewall profile is disabled." `
                    'ERROR'

                $Script:SecurityIssuesFound++
                $allEnabled = $false
            }
        }

        if ($allEnabled) {
            Write-Log `
                'All firewall profiles are enabled.' `
                'SUCCESS'
        }
    }
    catch {
        Write-Log `
            -Message "Error checking Windows Firewall: $($_.Exception.Message)" `
            -Level 'ERROR'

        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Test-WindowsUpdate {
    Write-Log 'WINDOWS UPDATE STATUS' 'INFO'
    Show-Separator

    try {
        $updateService = Get-Service `
            -Name 'wuauserv' `
            -ErrorAction SilentlyContinue

        if ($null -eq $updateService) {
            Write-Log `
                'Windows Update service was not found.' `
                'ERROR'

            $Script:SecurityIssuesFound++
        }
        else {
            $updateRunning = $updateService.Status -eq 'Running'

            Write-Log `
                -Message "Update Service Status: $($updateService.Status)" `
                -Level (Get-StatusLevel `
                    -Success $updateRunning `
                    -FailureLevel 'WARNING')

            if ($updateRunning) {
                $Script:SecurityPass++
            }
            else {
                Write-Log `
                    'Windows Update service is not running.' `
                    'WARNING'

                $Script:SecurityWarnings++
            }
        }

        $installedUpdates = @(
            Get-CimInstance `
                -ClassName Win32_QuickFixEngineering `
                -ErrorAction SilentlyContinue
        )

        if ($installedUpdates.Count -eq 0) {
            Write-Log `
                'No installed update information was returned.' `
                'WARNING'

            $Script:SecurityWarnings++
        }
        else {
            Write-Log `
                "Installed Updates Found: $($installedUpdates.Count)" `
                'INFO'

            $latestUpdate = $installedUpdates |
                Where-Object {
                    $null -ne $_.InstalledOn -and
                    $_.InstalledOn.ToString().Trim() -ne ''
                } |
                Sort-Object InstalledOn -Descending |
                Select-Object -First 1

            if ($null -ne $latestUpdate) {
                Write-Log `
                    "Latest Installed Update: $($latestUpdate.HotFixID)" `
                    'INFO'

                Write-Log `
                    "Latest Installed Date: $($latestUpdate.InstalledOn)" `
                    'INFO'
            }
        }
    }
    catch {
        Write-Log `
            -Message "Error checking Windows Update: $($_.Exception.Message)" `
            -Level 'ERROR'

        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Audit-UserAccounts {
    Write-Log 'USER ACCOUNT AUDIT' 'INFO'
    Show-Separator

    try {
        $users = @(Get-LocalUser -ErrorAction Stop)

        $administrators = @(
            Get-LocalGroupMember `
                -Group 'Administrators' `
                -ErrorAction SilentlyContinue
        )

        Write-Log `
            "Total Local User Accounts: $($users.Count)" `
            'INFO'

        foreach ($user in $users) {
            Write-Log `
                "User: $($user.Name)" `
                'INFO'

            Write-Log `
                "Enabled: $($user.Enabled)" `
                (Get-StatusLevel `
                    -Success ([bool]$user.Enabled) `
                    -FailureLevel 'WARNING')

            if ($null -ne $user.LastLogon) {
                Write-Log `
                    "Last Logon: $($user.LastLogon)" `
                    'INFO'
            }
            else {
                Write-Log `
                    'Last Logon: Never or unavailable' `
                    'INFO'
            }

            $isAdministrator = $false

            foreach ($member in $administrators) {
                if (
                    $member.Name -match "\\$([regex]::Escape($user.Name))$" -or
                    $member.Name -eq $user.Name
                ) {
                    $isAdministrator = $true
                    break
                }
            }

            if ($isAdministrator) {
                Write-Log `
                    'Member of local Administrators group.' `
                    'WARNING'

                $Script:SecurityWarnings++
            }
        }

        $Script:SecurityPass++
    }
    catch {
        Write-Log `
            -Message "Error auditing user accounts: $($_.Exception.Message)" `
            -Level 'ERROR'

        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Check-PasswordPolicy {
    Write-Log 'PASSWORD POLICY AUDIT' 'INFO'
    Show-Separator

    $temporaryPolicyFile = $null

    try {
        $temporaryPolicyFile = Join-Path `
            -Path ([System.IO.Path]::GetTempPath()) `
            -ChildPath (
                'SecurityPolicy_{0}.inf' -f `
                    ([guid]::NewGuid().ToString('N'))
            )

        Write-Log `
            'Exporting local security policy...' `
            'INFO'

        $null = secedit.exe `
            /export `
            /cfg $temporaryPolicyFile `
            /quiet 2>&1

        if (-not (Test-Path -LiteralPath $temporaryPolicyFile)) {
            Write-Log `
                'Unable to export local security policy.' `
                'WARNING'

            $Script:SecurityWarnings++
            return
        }

        $policyContent = Get-Content `
            -LiteralPath $temporaryPolicyFile `
            -ErrorAction Stop

        $policyItems = @(
            'MinimumPasswordLength'
            'MaximumPasswordAge'
            'MinimumPasswordAge'
            'PasswordHistorySize'
            'PasswordComplexity'
            'LockoutBadCount'
            'LockoutDuration'
            'ResetLockoutCount'
        )

        foreach ($item in $policyItems) {
            $match = $policyContent |
                Select-String `
                    -Pattern "^\s*$item\s*=" `
                    -SimpleMatch:$false |
                Select-Object -First 1

            if ($null -ne $match) {
                Write-Log `
                    $match.Line.Trim() `
                    'INFO'
            }
        }

        $Script:SecurityPass++
    }
    catch {
        Write-Log `
            -Message "Error checking password policy: $($_.Exception.Message)" `
            -Level 'WARNING'

        $Script:SecurityWarnings++
    }
    finally {
        if (
            $null -ne $temporaryPolicyFile -and
            (Test-Path -LiteralPath $temporaryPolicyFile)
        ) {
            Remove-Item `
                -LiteralPath $temporaryPolicyFile `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }

    Write-Log '' 'INFO'
}

function Check-AdministratorAccount {
    Write-Log 'BUILT-IN ADMINISTRATOR ACCOUNT STATUS' 'INFO'
    Show-Separator

    try {
        $adminAccount = Get-LocalUser `
            -Name 'Administrator' `
            -ErrorAction SilentlyContinue

        if ($null -eq $adminAccount) {
            Write-Log `
                'Built-in Administrator account was not found.' `
                'INFO'

            $Script:SecurityPass++
            return
        }

        Write-Log `
            "Administrator Account Found: $($adminAccount.Name)" `
            'INFO'

        Write-Log `
            "Enabled: $($adminAccount.Enabled)" `
            (Get-StatusLevel `
                -Success (-not [bool]$adminAccount.Enabled) `
                -FailureLevel 'WARNING')

        if ($null -ne $adminAccount.LastLogon) {
            Write-Log `
                "Last Logon: $($adminAccount.LastLogon)" `
                'INFO'
        }

        if ($adminAccount.Enabled) {
            Write-Log `
                'Built-in Administrator account is enabled.' `
                'ERROR'

            Write-Log `
                'Consider disabling it if it is not required.' `
                'WARNING'

            $Script:SecurityIssuesFound++
        }
        else {
            Write-Log `
                'Built-in Administrator account is disabled.' `
                'SUCCESS'

            $Script:SecurityPass++
        }
    }
    catch {
        Write-Log `
            -Message "Error checking Administrator account: $($_.Exception.Message)" `
            -Level 'ERROR'

        $Script:SecurityIssuesFound++
    }

    Write-Log '' 'INFO'
}

function Scan-SecurityEventLog {
    Write-Log 'SECURITY EVENT LOG ANALYSIS' 'INFO'
    Show-Separator

    try {
        $startDate = (Get-Date).AddDays(-7)

        $failedLogons = @(
            Get-WinEvent `
                -FilterHashtable @{
                    LogName   = 'Security'
                    Id        = 4625
                    StartTime = $startDate
                } `
                -ErrorAction SilentlyContinue
        )

        $failedCount = $failedLogons.Count

        Write-Log `
            -Message "Failed Logon Attempts - Last 7 Days: $failedCount" `
            -Level (Get-StatusLevel `
                -Success ($failedCount -le 10) `
                -FailureLevel 'WARNING')

        if ($failedCount -gt 10) {
            Write-Log `
                'High number of failed logon attempts detected.' `
                'WARNING'

            $Script:SecurityWarnings++
        }
        else {
            $Script:SecurityPass++
        }

        $auditEvents = @(
            Get-WinEvent `
                -FilterHashtable @{
                    LogName   = 'Security'
                    Id        = 4625, 4719, 1102
                    StartTime = $startDate
                } `
                -ErrorAction SilentlyContinue
        )

        Write-Log `
            "Selected Security Events - Last 7 Days: $($auditEvents.Count)" `
            'INFO'
    }
    catch {
        Write-Log `
            -Message "Could not retrieve Security event logs: $($_.Exception.Message)" `
            -Level 'WARNING'

        $Script:SecurityWarnings++
    }

    Write-Log '' 'INFO'
}

function Check-BitLocker {
    Write-Log 'BITLOCKER ENCRYPTION STATUS' 'INFO'
    Show-Separator

    try {
        $volumes = @(
            Get-BitLockerVolume `
                -ErrorAction SilentlyContinue
        )

        if ($volumes.Count -eq 0) {
            Write-Log `
                'BitLocker information is unavailable or no volumes were found.' `
                'WARNING'

            $Script:SecurityWarnings++
            return
        }

        foreach ($volume in $volumes) {
            Write-Log `
                "Drive: $($volume.MountPoint)" `
                'INFO'

            Write-Log `
                "Protection Status: $($volume.ProtectionStatus)" `
                'INFO'

            Write-Log `
                "Volume Status: $($volume.VolumeStatus)" `
                'INFO'

            Write-Log `
                "Encryption Percentage: $($volume.EncryptionPercentage)%" `
                'INFO'

            $protected = "$($volume.ProtectionStatus)" -eq 'On'

            if ($protected) {
                Write-Log `
                    'BitLocker protection is enabled.' `
                    'SUCCESS'

                $Script:SecurityPass++
            }
            else {
                Write-Log `
                    'BitLocker protection is not enabled.' `
                    'WARNING'

                $Script:SecurityWarnings++
            }
        }
    }
    catch {
        Write-Log `
            -Message "Error checking BitLocker status: $($_.Exception.Message)" `
            -Level 'WARNING'

        $Script:SecurityWarnings++
    }

    Write-Log '' 'INFO'
}

function Check-UserAccountControl {
    Write-Log 'USER ACCOUNT CONTROL STATUS' 'INFO'
    Show-Separator

    try {
        $uacPath =
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'

        $uac = Get-ItemProperty `
            -Path $uacPath `
            -Name 'EnableLUA' `
            -ErrorAction Stop

        $uacEnabled = $uac.EnableLUA -eq 1

        Write-Log `
            -Message "UAC Enabled: $uacEnabled" `
            -Level (Get-StatusLevel -Success $uacEnabled)

        if ($uacEnabled) {
            $Script:SecurityPass++
        }
        else {
            Write-Log `
                'User Account Control is disabled.' `
                'ERROR'

            $Script:SecurityIssuesFound++
        }
    }
    catch {
        Write-Log `
            -Message "Error checking UAC status: $($_.Exception.Message)" `
            -Level 'WARNING'

        $Script:SecurityWarnings++
    }

    Write-Log '' 'INFO'
}

function Show-SecurityReport {
    Write-Log '' 'INFO'
    Show-Separator
    Write-Log 'SECURITY AUDIT SUMMARY REPORT' 'INFO'
    Show-Separator

    Write-Log `
        -Message "Security Issues Found: $($Script:SecurityIssuesFound)" `
        -Level (Get-StatusLevel `
            -Success ($Script:SecurityIssuesFound -eq 0))

    Write-Log `
        -Message "Security Warnings: $($Script:SecurityWarnings)" `
        -Level (Get-StatusLevel `
            -Success ($Script:SecurityWarnings -eq 0) `
            -FailureLevel 'WARNING')

    Write-Log `
        "Security Checks Passed: $($Script:SecurityPass)" `
        'SUCCESS'

    $totalChecks =
        $Script:SecurityIssuesFound +
        $Script:SecurityWarnings +
        $Script:SecurityPass

    if ($totalChecks -gt 0) {
        $securityScore = [math]::Round(
            ($Script:SecurityPass / $totalChecks) * 100,
            0
        )

        if ($securityScore -ge 80) {
            $scoreLevel = 'SUCCESS'
        }
        elseif ($securityScore -ge 60) {
            $scoreLevel = 'WARNING'
        }
        else {
            $scoreLevel = 'ERROR'
        }
    }
    else {
        $securityScore = 0
        $scoreLevel = 'WARNING'
    }

    Write-Log `
        "Overall Security Score: $securityScore%" `
        $scoreLevel

    Write-Log '' 'INFO'
    Write-Log 'RECOMMENDATIONS:' 'INFO'

    if ($Script:SecurityIssuesFound -gt 0) {
        Write-Log `
            'Address critical security issues immediately.' `
            'ERROR'

        Write-Log `
            'Review the ERROR entries in this report.' `
            'ERROR'
    }

    if ($Script:SecurityWarnings -gt 0) {
        Write-Log `
            'Review and address security warnings.' `
            'WARNING'
    }

    Write-Log `
        'Keep Windows and security software updated.' `
        'INFO'

    Write-Log `
        'Run full antivirus scans regularly.' `
        'INFO'

    Write-Log `
        'Review security event logs periodically.' `
        'INFO'

    Write-Log `
        'Use strong, unique passwords.' `
        'INFO'
}

function Main {
    try {
        if (-not (Test-Path -LiteralPath $LogPath)) {
            New-Item `
                -ItemType Directory `
                -Path $LogPath `
                -Force `
                -ErrorAction Stop |
                Out-Null
        }

        New-Item `
            -ItemType File `
            -Path $LogFile `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Show-Separator
        Write-Log 'SYSTEM SECURITY AUDIT SCRIPT' 'INFO'
        Write-Log `
            "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            'INFO'

        Write-Log `
            "Log File: $LogFile" `
            'INFO'

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

        Write-Log `
            "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
            'INFO'

        Write-Log `
            "Log file saved to: $LogFile" `
            'INFO'

        Show-Separator

        Write-Host ''
        Write-Host `
            "Audit complete. Log saved to: $LogFile" `
            -ForegroundColor Cyan
    }
    catch {
        Write-Host `
            "Fatal script error: $($_.Exception.Message)" `
            -ForegroundColor Red

        throw
    }
}

# ---------------------------------------------------------------------
# START SCRIPT
# ---------------------------------------------------------------------

Main
