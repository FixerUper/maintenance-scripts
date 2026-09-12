<#
.SYNOPSIS
    Maintenance Scheduler Script

.DESCRIPTION
    Creates and manages scheduled tasks for automated maintenance scripts.

.NOTES
    Requires Administrator privileges.
    Logs and configuration are stored in C:\temp.
#>

#Requires -RunAsAdministrator

# =========================
# CONFIGURATION
# =========================

$LogPath = "C:\temp"

if (-not (Test-Path -LiteralPath $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$LogFileName = "MaintenanceScheduler_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$ConfigFile = Join-Path -Path $LogPath -ChildPath "MaintenanceConfig.json"

$TaskNamePrefix = "SystemMaintenance_"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskPath = "\Microsoft\Windows\SystemMaintenance\"

$Script:TasksCreated = 0
$Script:TasksFailed = 0
$Script:TasksUpdated = 0

$MaintenanceScripts = @(
    @{
        Name            = "Monthly Maintenance"
        ScriptName      = "Windows-Monthly-Maintenance.ps1"
        Description     = "DISM, SFC, and CHKDSK system checks"
        DefaultFrequency = "Monthly"
        DefaultTime     = "02:00"
    },
    @{
        Name            = "Package Updates"
        ScriptName      = "Winget-Package-Update.ps1"
        Description     = "Update installed packages using winget"
        DefaultFrequency = "Weekly"
        DefaultTime     = "03:00"
    },
    @{
        Name            = "Windows Updates"
        ScriptName      = "Windows-Updates-Install.ps1"
        Description     = "Install Windows and operating system updates"
        DefaultFrequency = "Weekly"
        DefaultTime     = "03:30"
    },
    @{
        Name            = "System Cleanup"
        ScriptName      = "System-Cleanup-Optimization.ps1"
        Description     = "Clean temporary files and optimize the system"
        DefaultFrequency = "Weekly"
        DefaultTime     = "02:30"
    },
    @{
        Name            = "Health Report"
        ScriptName      = "System-Information-Health-Report.ps1"
        Description     = "Generate system health reports"
        DefaultFrequency = "Weekly"
        DefaultTime     = "01:00"
    },
    @{
        Name            = "Backup and Recovery"
        ScriptName      = "Backup-Recovery.ps1"
        Description     = "Create system backups"
        DefaultFrequency = "Weekly"
        DefaultTime     = "04:00"
    },
    @{
        Name            = "Security Audit"
        ScriptName      = "Security-Audit.ps1"
        Description     = "Perform a security audit"
        DefaultFrequency = "Weekly"
        DefaultTime     = "01:30"
    },
    @{
        Name            = "Network Diagnostics"
        ScriptName      = "Network-Diagnostics.ps1"
        Description     = "Run network connectivity and speed tests"
        DefaultFrequency = "Weekly"
        DefaultTime     = "04:30"
    }
)

# =========================
# LOGGING
# =========================

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO" {
            Write-Host $LogMessage -ForegroundColor White
        }
        "WARNING" {
            Write-Host $LogMessage -ForegroundColor Yellow
        }
        "ERROR" {
            Write-Host $LogMessage -ForegroundColor Red
        }
        "SUCCESS" {
            Write-Host $LogMessage -ForegroundColor Green
        }
    }

    try {
        Add-Content -LiteralPath $LogFile -Value $LogMessage -ErrorAction Stop
    }
    catch {
        Write-Host "Unable to write to log file: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}

function Show-Separator {
    Write-Log ("=" * 70) "INFO"
}

# =========================
# CONFIGURATION MANAGEMENT
# =========================

function Initialize-Configuration {
    Write-Log "Initializing scheduler configuration..." "INFO"

    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $Config = Get-Content -LiteralPath $ConfigFile -Raw |
                ConvertFrom-Json

            Write-Log "Configuration loaded from: $ConfigFile" "SUCCESS"
            return $Config
        }
        catch {
            Write-Log "Configuration file is invalid. Creating a new one." "WARNING"
        }
    }

    $EnabledScripts = foreach ($ScriptDefinition in $MaintenanceScripts) {
        [PSCustomObject]@{
            Name          = $ScriptDefinition.Name
            Enabled       = $true
            ScriptName    = $ScriptDefinition.ScriptName
            Frequency     = $ScriptDefinition.DefaultFrequency
            ExecutionTime = $ScriptDefinition.DefaultTime
            LastRun       = $null
            NextRun       = $null
        }
    }

    $Config = [PSCustomObject]@{
        LastUpdated          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        EnabledScripts       = @($EnabledScripts)
        MaintenanceInterval  = "Weekly"
        NotificationsEnabled = $false
        EmailAddress         = ""
    }

    Save-Configuration -Config $Config
    Write-Log "New configuration created: $ConfigFile" "SUCCESS"

    return $Config
}

function Save-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    try {
        $Config.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $Config |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $ConfigFile -Encoding UTF8

        Write-Log "Configuration saved: $ConfigFile" "SUCCESS"
    }
    catch {
        Write-Log "Error saving configuration: $($_.Exception.Message)" "ERROR"
    }
}

# =========================
# SCRIPT VERIFICATION
# =========================

function Verify-ScriptFiles {
    Write-Log "VERIFYING MAINTENANCE SCRIPT FILES" "INFO"
    Show-Separator

    $MissingScripts = @()

    foreach ($ScriptDefinition in $MaintenanceScripts) {
        $MaintenanceScriptPath = Join-Path `
            -Path $ScriptPath `
            -ChildPath $ScriptDefinition.ScriptName

        if (Test-Path -LiteralPath $MaintenanceScriptPath) {
            Write-Log "Found: $($ScriptDefinition.ScriptName)" "SUCCESS"
        }
        else {
            Write-Log "Missing: $($ScriptDefinition.ScriptName)" "ERROR"
            $MissingScripts += $ScriptDefinition.ScriptName
        }
    }

    if ($MissingScripts.Count -gt 0) {
        Write-Log "$($MissingScripts.Count) maintenance script(s) not found." "ERROR"
        Write-Log "Expected script location: $ScriptPath" "WARNING"
        return $false
    }

    Write-Log "All maintenance scripts were verified." "SUCCESS"
    return $true
}

# =========================
# SCHEDULED TASK FUNCTIONS
# =========================

function Ensure-TaskFolder {
    try {
        $TaskService = New-Object -ComObject Schedule.Service
        $TaskService.Connect()

        $RootFolder = $TaskService.GetFolder("\")

        try {
            $null = $RootFolder.GetFolder($TaskPath.Trim("\"))
        }
        catch {
            $null = $RootFolder.CreateFolder(
                $TaskPath.Trim("\"),
                $null
            )
        }

        return $true
    }
    catch {
        Write-Log "Unable to create or access task folder: $($_.Exception.Message)" `
            "WARNING"
        return $false
    }
}

function Create-ScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Daily", "Weekly", "Monthly")]
        [string]$Frequency,

        [Parameter(Mandatory = $true)]
        [string]$ExecutionTime
    )

    Write-Log "Creating scheduled task: $TaskName" "INFO"

    try {
        $MaintenanceScriptPath = Join-Path `
            -Path $ScriptPath `
            -ChildPath $ScriptName

        if (-not (Test-Path -LiteralPath $MaintenanceScriptPath)) {
            Write-Log "Script not found: $MaintenanceScriptPath" "ERROR"
            $Script:TasksFailed++
            return $false
        }

        if (-not (Ensure-TaskFolder)) {
            $Script:TasksFailed++
            return $false
        }

        $PowerShellArguments = @(
            "-NoProfile"
            "-ExecutionPolicy Bypass"
            "-WindowStyle Hidden"
            "-File `"$MaintenanceScriptPath`""
        ) -join " "

        $Action = New-ScheduledTaskAction `
            -Execute "PowerShell.exe" `
            -Argument $PowerShellArguments

        switch ($Frequency) {
            "Daily" {
                $Trigger = New-ScheduledTaskTrigger `
                    -Daily `
                    -At $ExecutionTime
            }

            "Weekly" {
                $Trigger = New-ScheduledTaskTrigger `
                    -Weekly `
                    -DaysOfWeek Sunday `
                    -At $ExecutionTime
            }

            "Monthly" {
                $Trigger = New-ScheduledTaskTrigger `
                    -Monthly `
                    -DaysOfMonth 1 `
                    -At $ExecutionTime
            }
        }

        $Settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -Compatibility Win8

        $Principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        $ExistingTask = Get-ScheduledTask `
            -TaskName $TaskName `
            -TaskPath $TaskPath `
            -ErrorAction SilentlyContinue

        if ($null -ne $ExistingTask) {
            Write-Log "Task already exists. Updating it." "WARNING"

            Unregister-ScheduledTask `
                -TaskName $TaskName `
                -TaskPath $TaskPath `
                -Confirm:$false

            $Script:TasksUpdated++
        }

        Register-ScheduledTask `
            -TaskName $TaskName `
            -TaskPath $TaskPath `
            -Action $Action `
            -Trigger $Trigger `
            -Settings $Settings `
            -Principal $Principal `
            -Description $Description `
            -Force `
            -ErrorAction Stop

        Write-Log "Task created successfully." "SUCCESS"
        Write-Log "Schedule: $Frequency at $ExecutionTime" "INFO"

        $Script:TasksCreated++
        return $true
    }
    catch {
        Write-Log "Error creating task: $($_.Exception.Message)" "ERROR"
        $Script:TasksFailed++
        return $false
    }
}

function Enable-MaintenanceSchedule {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    Write-Log "CREATING MAINTENANCE SCHEDULE" "INFO"
    Show-Separator

    foreach ($ScriptDefinition in $MaintenanceScripts) {
        $ScriptConfig = @(
            $Config.EnabledScripts |
                Where-Object {
                    $_.ScriptName -eq $ScriptDefinition.ScriptName
                }
        ) | Select-Object -First 1

        if ($null -eq $ScriptConfig -or $ScriptConfig.Enabled -eq $true) {
            $Frequency = $ScriptDefinition.DefaultFrequency
            $ExecutionTime = $ScriptDefinition.DefaultTime

            if ($null -ne $ScriptConfig) {
                if (-not [string]::IsNullOrWhiteSpace($ScriptConfig.Frequency)) {
                    $Frequency = $ScriptConfig.Frequency
                }

                if (-not [string]::IsNullOrWhiteSpace($ScriptConfig.ExecutionTime)) {
                    $ExecutionTime = $ScriptConfig.ExecutionTime
                }
            }

            $SafeName = $ScriptDefinition.Name -replace "[^a-zA-Z0-9]", ""
            $TaskName = "$TaskNamePrefix$SafeName"

            Create-ScheduledTask `
                -TaskName $TaskName `
                -ScriptName $ScriptDefinition.ScriptName `
                -Description $ScriptDefinition.Description `
                -Frequency $Frequency `
                -ExecutionTime $ExecutionTime
        }
        else {
            Write-Log "Skipping disabled script: $($ScriptDefinition.Name)" `
                "WARNING"
        }
    }
}

function Disable-MaintenanceSchedule {
    Write-Log "DISABLING MAINTENANCE SCHEDULE" "INFO"
    Show-Separator

    try {
        $Tasks = @(Get-ScheduledTask `
            -TaskPath $TaskPath `
            -ErrorAction SilentlyContinue)

        if ($Tasks.Count -eq 0) {
            Write-Log "No maintenance tasks found." "INFO"
            return
        }

        foreach ($Task in $Tasks) {
            Write-Log "Disabling: $($Task.TaskName)" "INFO"

            Disable-ScheduledTask `
                -TaskName $Task.TaskName `
                -TaskPath $TaskPath `
                -ErrorAction SilentlyContinue

            Write-Log "Task disabled." "SUCCESS"
        }
    }
    catch {
        Write-Log "Error disabling tasks: $($_.Exception.Message)" "ERROR"
    }
}

function List-ScheduledTasks {
    Write-Log "SCHEDULED MAINTENANCE TASKS" "INFO"
    Show-Separator

    try {
        $Tasks = @(Get-ScheduledTask `
            -TaskPath $TaskPath `
            -ErrorAction SilentlyContinue)

        if ($Tasks.Count -eq 0) {
            Write-Log "No scheduled maintenance tasks found." "WARNING"
            return
        }

        foreach ($Task in $Tasks) {
            $TaskInfo = Get-ScheduledTaskInfo `
                -TaskName $Task.TaskName `
                -TaskPath $TaskPath `
                -ErrorAction SilentlyContinue

            Write-Log "Task: $($Task.TaskName)" "INFO"
            Write-Log "Status: $($Task.State)" `
                $(if ($Task.State -eq "Ready") { "SUCCESS" } else { "WARNING" })

            if ($null -ne $TaskInfo) {
                Write-Log "Last Run: $($TaskInfo.LastRunTime)" "INFO"
                Write-Log "Next Run: $($TaskInfo.NextRunTime)" "INFO"
                Write-Log "Last Result: $($TaskInfo.LastTaskResult)" `
                    $(if ($TaskInfo.LastTaskResult -eq 0) {
                        "SUCCESS"
                    }
                    else {
                        "WARNING"
                    })
            }

            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log "Error listing tasks: $($_.Exception.Message)" "ERROR"
    }
}

# =========================
# TEST AND NOTIFICATION FUNCTIONS
# =========================

function Test-MaintenanceScript {
    Write-Log "TEST RUN MAINTENANCE SCRIPT" "INFO"
    Show-Separator

    for ($Index = 0; $Index -lt $MaintenanceScripts.Count; $Index++) {
        Write-Host "$($Index + 1). $($MaintenanceScripts[$Index].Name)" `
            -ForegroundColor Yellow
    }

    Write-Host "0. Cancel" -ForegroundColor Yellow
    $Selection = Read-Host "Select a script number"

    if ($Selection -notmatch "^\d+$") {
        Write-Log "Invalid selection." "ERROR"
        return
    }

    $SelectedIndex = [int]$Selection - 1

    if ($Selection -eq "0") {
        Write-Log "Test cancelled." "INFO"
        return
    }

    if ($SelectedIndex -lt 0 -or
        $SelectedIndex -ge $MaintenanceScripts.Count) {
        Write-Log "Invalid script selection." "ERROR"
        return
    }

    $SelectedScript = $MaintenanceScripts[$SelectedIndex]
    $SelectedScriptPath = Join-Path `
        -Path $ScriptPath `
        -ChildPath $SelectedScript.ScriptName

    if (-not (Test-Path -LiteralPath $SelectedScriptPath)) {
        Write-Log "Script not found: $SelectedScriptPath" "ERROR"
        return
    }

    Write-Log "Running test: $($SelectedScript.Name)" "INFO"

    try {
        & $SelectedScriptPath
        Write-Log "Test run completed successfully." "SUCCESS"
    }
    catch {
        Write-Log "Test run failed: $($_.Exception.Message)" "ERROR"
    }
}

function Configure-Notifications {
    Write-Log "CONFIGURE EMAIL NOTIFICATIONS" "INFO"
    Show-Separator

    $EnableNotifications = Read-Host `
        "Enable email notifications? Enter Y or N"

    if ($EnableNotifications -match "^[Yy]$") {
        $EmailAddress = Read-Host "Enter the notification email address"

        Write-Log "Email notifications enabled for: $EmailAddress" "SUCCESS"
        Write-Log "SMTP settings must be implemented before sending email." "WARNING"
    }
    else {
        Write-Log "Email notifications disabled." "INFO"
    }
}

# =========================
# DISPLAY FUNCTIONS
# =========================

function Show-ScheduleReport {
    Write-Log "MAINTENANCE SCHEDULER SUMMARY" "INFO"
    Show-Separator

    Write-Log "Tasks Created: $Script:TasksCreated" "SUCCESS"
    Write-Log "Tasks Updated: $Script:TasksUpdated" "INFO"
    Write-Log "Tasks Failed: $Script:TasksFailed" `
        $(if ($Script:TasksFailed -gt 0) { "ERROR" } else { "SUCCESS" })

    Write-Log "Configuration File: $ConfigFile" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Write-Log "Script Path: $ScriptPath" "INFO"
}

function Show-MaintenanceMenu {
    Write-Host ""
    Show-Separator
    Write-Host "MAINTENANCE SCHEDULER MENU" -ForegroundColor Cyan
    Show-Separator

    Write-Host "1. Enable maintenance schedule" -ForegroundColor Yellow
    Write-Host "2. Disable maintenance schedule" -ForegroundColor Yellow
    Write-Host "3. View scheduled tasks" -ForegroundColor Yellow
    Write-Host "4. Test a maintenance script" -ForegroundColor Yellow
    Write-Host "5. Configure email notifications" -ForegroundColor Yellow
    Write-Host "6. Exit" -ForegroundColor Yellow
    Write-Host ""

    return Read-Host "Enter your choice"
}

# =========================
# MAIN
# =========================

function Main {
    Write-Log "MAINTENANCE SCHEDULER SCRIPT STARTED" "INFO"
    Write-Log "Log file: $LogFile" "INFO"
    Write-Log "Configuration file: $ConfigFile" "INFO"
    Write-Log "Script path: $ScriptPath" "INFO"
    Show-Separator

    if (-not (Verify-ScriptFiles)) {
        Write-Log "Required scripts are missing. Exiting." "ERROR"
        return
    }

    $Config = Initialize-Configuration
    $MenuLoop = $true

    while ($MenuLoop) {
        $Choice = Show-MaintenanceMenu

        switch ($Choice) {
            "1" {
                Enable-MaintenanceSchedule -Config $Config
                List-ScheduledTasks
            }

            "2" {
                Disable-MaintenanceSchedule
            }

            "3" {
                List-ScheduledTasks
            }

            "4" {
                Test-MaintenanceScript
            }

            "5" {
                Configure-Notifications
            }

            "6" {
                $MenuLoop = $false
                Write-Log "Exiting scheduler." "INFO"
            }

            default {
                Write-Log "Invalid selection: $Choice" "ERROR"
            }
        }
    }

    Show-ScheduleReport
    Write-Log "MAINTENANCE SCHEDULER SCRIPT COMPLETED" "SUCCESS"
}

Main
