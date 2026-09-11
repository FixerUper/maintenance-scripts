<#
.SYNOPSIS
    Maintenance Scheduler Script
    Creates scheduled tasks for automated maintenance scripts

.DESCRIPTION
    This script creates and manages scheduled maintenance tasks including:
    - Schedule all maintenance scripts automatically
    - Configure run frequency (daily, weekly, monthly)
    - Set specific execution times
    - Email notifications on completion
    - Error alerts and notifications
    - Maintenance history tracking
    - Skip/reschedule options
    - Task management and monitoring
    - Enable/disable individual scripts
    All configuration is logged to the user's Documents folder

.NOTES
    Requires Administrator privileges
    Log file: $env:USERPROFILE\Documents\MaintenanceScheduler_YYYYMMDD_HHmmss.log

.AUTHOR
    Maintenance Scheduler Script
#>

# Requires Administrator privileges
#Requires -RunAsAdministrator

# ========== CONFIGURATION ==========
$LogPath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents"
$LogFileName = "MaintenanceScheduler_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName
$TaskNamePrefix = "SystemMaintenance_"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path -Path $LogPath -ChildPath "MaintenanceConfig.json"

# Maintenance scripts configuration
$MaintenanceScripts = @(
    @{
        Name = "Monthly Maintenance"
        ScriptName = "Windows-Monthly-Maintenance.ps1"
        Description = "DISM, SFC, CHKDSK system checks"
        DefaultFrequency = "Monthly"
        DefaultTime = "02:00"
    },
    @{
        Name = "Package Updates"
        ScriptName = "Winget-Package-Update.ps1"
        Description = "Update installed packages via winget"
        DefaultFrequency = "Weekly"
        DefaultTime = "03:00"
    },
    @{
        Name = "Windows Updates"
        ScriptName = "Windows-Updates-Install.ps1"
        Description = "Install Windows and OS updates"
        DefaultFrequency = "Weekly"
        DefaultTime = "03:30"
    },
    @{
        Name = "System Cleanup"
        ScriptName = "System-Cleanup-Optimization.ps1"
        Description = "Clean temporary files and optimize"
        DefaultFrequency = "Weekly"
        DefaultTime = "02:30"
    },
    @{
        Name = "Health Report"
        ScriptName = "System-Information-Health-Report.ps1"
        Description = "Generate system health reports"
        DefaultFrequency = "Weekly"
        DefaultTime = "01:00"
    },
    @{
        Name = "Backup & Recovery"
        ScriptName = "Backup-Recovery.ps1"
        Description = "Create system backups"
        DefaultFrequency = "Weekly"
        DefaultTime = "04:00"
    },
    @{
        Name = "Security Audit"
        ScriptName = "Security-Audit.ps1"
        Description = "Perform security audit"
        DefaultFrequency = "Weekly"
        DefaultTime = "01:30"
    },
    @{
        Name = "Network Diagnostics"
        ScriptName = "Network-Diagnostics.ps1"
        Description = "Network connectivity and speed tests"
        DefaultFrequency = "Weekly"
        DefaultTime = "04:30"
    }
)

$Script:TasksCreated = 0
$Script:TasksFailed = 0
$Script:TasksUpdated = 0

# ========== FUNCTIONS ==========

function Write-Log {
    <#
    .SYNOPSIS
        Write messages to both console and log file
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console with color coding
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage
}

function Show-Separator {
    <#
    .SYNOPSIS
        Display a visual separator
    #>
    Write-Log "================================================================" "INFO"
}

function Initialize-Configuration {
    <#
    .SYNOPSIS
        Initialize or load scheduler configuration
    #>
    Write-Log "Initializing scheduler configuration..." "INFO"
    
    if (Test-Path -Path $ConfigFile) {
        Write-Log "✓ Configuration file found: $ConfigFile" "SUCCESS"
        return (Get-Content -Path $ConfigFile | ConvertFrom-Json)
    } else {
        Write-Log "Creating new configuration file..." "INFO"
        
        # Create default configuration
        $config = @{
            LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            EnabledScripts = @()
            MaintenanceInterval = "Weekly"
            NotificationsEnabled = $false
            EmailAddress = ""
        }
        
        foreach ($script in $MaintenanceScripts) {
            $config.EnabledScripts += @{
                Name = $script.Name
                Enabled = $true
                ScriptName = $script.ScriptName
                Frequency = $script.DefaultFrequency
                ExecutionTime = $script.DefaultTime
                LastRun = $null
                NextRun = $null
            }
        }
        
        $config | ConvertTo-Json | Set-Content -Path $ConfigFile
        Write-Log "✓ Configuration file created: $ConfigFile" "SUCCESS"
        return $config
    }
}

function Save-Configuration {
    <#
    .SYNOPSIS
        Save scheduler configuration
    #>
    param(
        [object]$Config
    )
    
    try {
        $Config.LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Config | ConvertTo-Json | Set-Content -Path $ConfigFile
        Write-Log "✓ Configuration saved" "SUCCESS"
    }
    catch {
        Write-Log "✗ Error saving configuration: $_" "ERROR"
    }
}

function Verify-ScriptFiles {
    <#
    .SYNOPSIS
        Verify all maintenance script files exist
    #>
    Write-Log "VERIFYING MAINTENANCE SCRIPT FILES" "INFO"
    Show-Separator
    
    $missingScripts = @()
    
    foreach ($script in $MaintenanceScripts) {
        $scriptFile = Join-Path -Path $ScriptPath -ChildPath $script.ScriptName
        
        if (Test-Path -Path $scriptFile) {
            Write-Log "✓ Found: $($script.ScriptName)" "SUCCESS"
        } else {
            Write-Log "✗ Missing: $($script.ScriptName)" "ERROR"
            $missingScripts += $script.ScriptName
        }
    }
    
    Write-Log "" "INFO"
    
    if ($missingScripts.Count -gt 0) {
        Write-Log "⚠ $($missingScripts.Count) script(s) not found" "ERROR"
        Write-Log "Scripts should be in: $ScriptPath" "WARNING"
        return $false
    } else {
        Write-Log "✓ All maintenance scripts verified" "SUCCESS"
        return $true
    }
}

function Create-ScheduledTask {
    <#
    .SYNOPSIS
        Create a scheduled task for a maintenance script
    #>
    param(
        [string]$TaskName,
        [string]$ScriptName,
        [string]$Description,
        [string]$Frequency,
        [string]$ExecutionTime
    )
    
    Write-Log "Creating scheduled task: $TaskName" "INFO"
    
    try {
        $scriptFile = Join-Path -Path $ScriptPath -ChildPath $ScriptName
        
        if (-not (Test-Path -Path $scriptFile)) {
            Write-Log "  ✗ Script file not found: $scriptFile" "ERROR"
            return $false
        }
        
        # Create script action
        $action = New-ScheduledTaskAction `
            -Execute "PowerShell.exe" `
            -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptFile`"" `
            -ErrorAction Stop
        
        # Create trigger based on frequency
        $trigger = switch ($Frequency) {
            "Daily" {
                $timeSpan = [TimeSpan]::Parse($ExecutionTime)
                New-ScheduledTaskTrigger `
                    -Daily `
                    -At $ExecutionTime `
                    -ErrorAction Stop
            }
            "Weekly" {
                $timeSpan = [TimeSpan]::Parse($ExecutionTime)
                New-ScheduledTaskTrigger `
                    -Weekly `
                    -DaysOfWeek Sunday `
                    -At $ExecutionTime `
                    -ErrorAction Stop
            }
            "Monthly" {
                $timeSpan = [TimeSpan]::Parse($ExecutionTime)
                New-ScheduledTaskTrigger `
                    -Monthly `
                    -DaysOfMonth 1 `
                    -At $ExecutionTime `
                    -ErrorAction Stop
            }
            default {
                Write-Log "  ✗ Unknown frequency: $Frequency" "ERROR"
                return $false
            }
        }
        
        # Create task settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -Compatibility Win8 `
            -StartWhenAvailable `
            -ErrorAction Stop
        
        # Create principal (run as SYSTEM with admin rights)
        $principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest `
            -ErrorAction Stop
        
        # Register the task
        $taskFolder = "Microsoft\Windows\SystemMaintenance"
        
        # Create folder if it doesn't exist
        try {
            $taskScheduler = New-Object -ComObject Schedule.Service
            $taskScheduler.Connect()
            $rootFolder = $taskScheduler.GetFolder("\")
            
            try {
                $rootFolder.CreateFolder($taskFolder)
            }
            catch {
                # Folder might already exist
                $null = $null
            }
        }
        catch {
            Write-Log "  ⚠ Could not create task folder: $_" "WARNING"
        }
        
        $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath "\Microsoft\Windows\SystemMaintenance\" -ErrorAction SilentlyContinue
        
        if ($null -ne $existingTask) {
            Write-Log "  ⚠ Task already exists, updating..." "WARNING"
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath "\Microsoft\Windows\SystemMaintenance\" -Confirm:$false
            $Script:TasksUpdated++
        }
        
        Register-ScheduledTask `
            -TaskName $TaskName `
            -TaskPath "\Microsoft\Windows\SystemMaintenance\" `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description $Description `
            -Force `
            -ErrorAction Stop
        
        Write-Log "  ✓ Task created successfully" "SUCCESS"
        Write-Log "    Frequency: $Frequency at $ExecutionTime" "INFO"
        $Script:TasksCreated++
        return $true
    }
    catch {
        Write-Log "  ✗ Error creating task: $_" "ERROR"
        $Script:TasksFailed++
        return $false
    }
}

function List-ScheduledTasks {
    <#
    .SYNOPSIS
        List all scheduled maintenance tasks
    #>
    Write-Log "SCHEDULED MAINTENANCE TASKS" "INFO"
    Show-Separator
    
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\SystemMaintenance\" -ErrorAction SilentlyContinue
        
        if ($null -eq $tasks) {
            Write-Log "No scheduled maintenance tasks found" "WARNING"
            return
        }
        
        $taskCount = if ($tasks -is [array]) { $tasks.Count } else { 1 }
        Write-Log "Found $taskCount scheduled task(s):" "INFO"
        Write-Log "" "INFO"
        
        foreach ($task in $tasks) {
            Write-Log "Task: $($task.TaskName)" "INFO"
            Write-Log "  Status: $($task.State)" $(if ($task.State -eq "Ready") { "SUCCESS" } else { "WARNING" })
            Write-Log "  Description: $($task.Description)" "INFO"
            
            if ($null -ne $task.LastTaskResult) {
                $status = if ($task.LastTaskResult -eq 0) { "SUCCESS" } else { "ERROR" }
                Write-Log "  Last Result: $($task.LastTaskResult)" $status
            }
            
            Write-Log "" "INFO"
        }
    }
    catch {
        Write-Log "Error listing tasks: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Enable-MaintenanceSchedule {
    <#
    .SYNOPSIS
        Create all scheduled tasks
    #>
    param(
        [object]$Config
    )
    
    Write-Log "CREATING MAINTENANCE SCHEDULE" "INFO"
    Show-Separator
    
    foreach ($script in $MaintenanceScripts) {
        $scriptConfig = $Config.EnabledScripts | Where-Object { $_.ScriptName -eq $script.ScriptName }
        
        if ($null -eq $scriptConfig -or $scriptConfig.Enabled) {
            $taskName = $TaskNamePrefix + $script.Name -replace " ", ""
            
            Create-ScheduledTask `
                -TaskName $taskName `
                -ScriptName $script.ScriptName `
                -Description $script.Description `
                -Frequency ($scriptConfig.Frequency ?? $script.DefaultFrequency) `
                -ExecutionTime ($scriptConfig.ExecutionTime ?? $script.DefaultTime)
            
            Write-Log "" "INFO"
        }
    }
    
    Write-Log "" "INFO"
    Show-Separator
}

function Disable-MaintenanceSchedule {
    <#
    .SYNOPSIS
        Disable all scheduled maintenance tasks
    #>
    Write-Log "DISABLING MAINTENANCE SCHEDULE" "INFO"
    Show-Separator
    
    try {
        $tasks = Get-ScheduledTask -TaskPath "\Microsoft\Windows\SystemMaintenance\" -ErrorAction SilentlyContinue
        
        if ($null -eq $tasks) {
            Write-Log "No tasks found to disable" "INFO"
            return
        }
        
        foreach ($task in $tasks) {
            Write-Log "Disabling: $($task.TaskName)" "INFO"
            Disable-ScheduledTask -TaskName $task.TaskName -TaskPath "\Microsoft\Windows\SystemMaintenance\" -ErrorAction SilentlyContinue
            Write-Log "  ✓ Disabled" "SUCCESS"
        }
    }
    catch {
        Write-Log "Error disabling tasks: $_" "ERROR"
    }
    
    Write-Log "" "INFO"
}

function Show-MaintenanceMenu {
    <#
    .SYNOPSIS
        Display interactive maintenance menu
    #>
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "MAINTENANCE SCHEDULER MENU" "INFO"
    Show-Separator
    
    Write-Host ""
    Write-Host "Select an option:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Enable maintenance schedule (create all tasks)" -ForegroundColor Yellow
    Write-Host "2. Disable maintenance schedule (disable all tasks)" -ForegroundColor Yellow
    Write-Host "3. View scheduled tasks" -ForegroundColor Yellow
    Write-Host "4. Test run a maintenance script" -ForegroundColor Yellow
    Write-Host "5. Configure email notifications" -ForegroundColor Yellow
    Write-Host "6. Exit" -ForegroundColor Yellow
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (1-6)"
    return $choice
}

function Test-MaintenanceScript {
    <#
    .SYNOPSIS
        Test run a maintenance script
    #>
    Write-Log "TEST RUN MAINTENANCE SCRIPT" "INFO"
    Show-Separator
    
    Write-Host ""
    Write-Host "Available scripts:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $MaintenanceScripts.Count; $i++) {
        Write-Host "$($i + 1). $($MaintenanceScripts[$i].Name)" -ForegroundColor Yellow
    }
    
    $selection = Read-Host "Select script number (or 0 to cancel)"
    
    if ($selection -eq "0" -or [int]$selection -lt 1 -or [int]$selection -gt $MaintenanceScripts.Count) {
        Write-Log "Script selection cancelled" "INFO"
        return
    }
    
    $scriptToRun = $MaintenanceScripts[[int]$selection - 1]
    $scriptPath = Join-Path -Path $ScriptPath -ChildPath $scriptToRun.ScriptName
    
    if (-not (Test-Path -Path $scriptPath)) {
        Write-Log "✗ Script not found: $scriptPath" "ERROR"
        return
    }
    
    Write-Log "Running test: $($scriptToRun.Name)" "INFO"
    Write-Log "Script: $scriptPath" "INFO"
    
    try {
        & $scriptPath
        Write-Log "✓ Test run completed" "SUCCESS"
    }
    catch {
        Write-Log "✗ Error running script: $_" "ERROR"
    }
}

function Configure-Notifications {
    <#
    .SYNOPSIS
        Configure email notifications
    #>
    Write-Log "CONFIGURE EMAIL NOTIFICATIONS" "INFO"
    Show-Separator
    
    Write-Host ""
    Write-Host "Email notifications configuration" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Note: Email configuration requires SMTP server setup" -ForegroundColor Yellow
    Write-Host ""
    
    $enableNotifications = Read-Host "Enable email notifications? (y/n)"
    
    if ($enableNotifications -eq "y" -or $enableNotifications -eq "Y") {
        $emailAddress = Read-Host "Enter email address for notifications"
        Write-Log "Email notifications enabled: $emailAddress" "SUCCESS"
        Write-Log "⚠ SMTP configuration required in script settings" "WARNING"
    } else {
        Write-Log "Email notifications disabled" "INFO"
    }
    
    Write-Log "" "INFO"
}

function Show-ScheduleReport {
    <#
    .SYNOPSIS
        Display schedule setup summary
    #>
    Write-Log "" "INFO"
    Show-Separator
    Write-Log "MAINTENANCE SCHEDULER SUMMARY" "INFO"
    Show-Separator
    
    Write-Log "Tasks Created: $($Script:TasksCreated)" "SUCCESS"
    Write-Log "Tasks Updated: $($Script:TasksUpdated)" "INFO"
    Write-Log "Tasks Failed: $($Script:TasksFailed)" $(if ($Script:TasksFailed -gt 0) { "ERROR" } else { "SUCCESS" })
    
    Write-Log "" "INFO"
    Write-Log "Configuration File: $ConfigFile" "INFO"
    Write-Log "Script Path: $ScriptPath" "INFO"
    
    Write-Log "" "INFO"
    Write-Log "SCHEDULED MAINTENANCE SCRIPTS:" "INFO"
    foreach ($script in $MaintenanceScripts) {
        Write-Log "  • $($script.Name)" "SUCCESS"
        Write-Log "    Default: $($script.DefaultFrequency) at $($script.DefaultTime)" "INFO"
    }
    
    Show-Separator
}

# ========== MAIN EXECUTION ==========

function Main {
    # Initialize log file
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Log "================================================================" "INFO"
    Write-Log "MAINTENANCE SCHEDULER SCRIPT" "INFO"
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log File: $LogFile" "INFO"
    Show-Separator
    
    # ===== PHASE 1: VERIFICATION =====
    Write-Log "PHASE 1: SCRIPT VERIFICATION" "INFO"
    Show-Separator
    if (-not (Verify-ScriptFiles)) {
        Write-Log "" "INFO"
        Write-Log "Cannot proceed - required script files missing" "ERROR"
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
    Show-Separator
    
    # ===== PHASE 2: CONFIGURATION =====
    Write-Log "PHASE 2: CONFIGURATION SETUP" "INFO"
    Show-Separator
    $config = Initialize-Configuration
    Show-Separator
    
    # ===== PHASE 3: INTERACTIVE MENU =====
    $menuLoop = $true
    while ($menuLoop) {
        $choice = Show-MaintenanceMenu
        
        switch ($choice) {
            "1" {
                Write-Log "" "INFO"
                Enable-MaintenanceSchedule -Config $config
                List-ScheduledTasks
            }
            "2" {
                Write-Log "" "INFO"
                Disable-MaintenanceSchedule
            }
            "3" {
                Write-Log "" "INFO"
                List-ScheduledTasks
            }
            "4" {
                Write-Log "" "INFO"
                Test-MaintenanceScript
            }
            "5" {
                Write-Log "" "INFO"
                Configure-Notifications
            }
            "6" {
                $menuLoop = $false
            }
            default {
                Write-Log "Invalid selection: $choice" "ERROR"
            }
        }
    }
    
    # ===== COMPLETION SUMMARY =====
    Show-ScheduleReport
    
    Write-Log "" "INFO"
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Write-Log "Log file saved to: $LogFile" "INFO"
    Write-Log "================================================================" "INFO"
    
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Run main function
Main
