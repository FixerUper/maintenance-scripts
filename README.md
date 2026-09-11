# Windows System Maintenance Suite

A comprehensive collection of PowerShell scripts for automated Windows system maintenance, optimization, and monitoring.

## 📋 Table of Contents

- [Overview](#overview)
- [Scripts Included](#scripts-included)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Script Details](#script-details)
- [Scheduling](#scheduling)
- [Output Files](#output-files)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## 📌 Overview

This maintenance suite provides automated tools for:
- **System Optimization** - Clean temporary files, optimize storage
- **Health Monitoring** - Track system performance and hardware status
- **Security** - Comprehensive security audits and threat detection
- **Updates** - Manage Windows and software updates
- **Backups** - Create and manage system backups
- **Diagnostics** - Network connectivity and performance testing
- **Event Logging** - Analyze Windows event logs for issues
- **Automation** - Schedule all maintenance tasks automatically

**Key Benefits:**
✅ Automated maintenance reduces manual work  
✅ Proactive monitoring prevents issues  
✅ Comprehensive reporting for trend analysis  
✅ Security-focused with threat detection  
✅ Easy scheduling with interactive interface  
✅ Detailed logging for troubleshooting  

---

## 📦 Scripts Included

### 1. **System-Cleanup-Optimization.ps1**
Removes temporary files, clears caches, and optimizes system performance.

**Features:**
- Removes temp files from multiple locations
- Clears Windows Update cache
- Empties Recycle Bin
- Removes old log files (30+ days)
- Disables startup bloat applications
- Compacts OS installation
- Reports total space freed

**Run:** `.\System-Cleanup-Optimization.ps1`  
**Frequency:** Weekly  
**Time Required:** 15-30 minutes

---

### 2. **System-Information-Health-Report.ps1**
Generates comprehensive hardware and system health reports.

**Features:**
- Hardware inventory (CPU, RAM, Disk, GPU)
- OS version and build information
- System uptime and last restart
- Disk usage by drive
- RAM usage analysis
- Battery health (if laptop)
- Network adapter information
- BIOS and firmware details
- Export to HTML and CSV
- Historical metrics tracking

**Output Files:**
- `SystemReport_YYYYMMDD_HHmmss.txt` - Text report
- `SystemReport_YYYYMMDD_HHmmss.html` - Formatted HTML report
- `SystemMetricsHistory.csv` - Historical data

**Run:** `.\System-Information-Health-Report.ps1`  
**Frequency:** Weekly  
**Time Required:** 2-5 minutes

---

### 3. **Backup-Recovery.ps1**
Creates system image backups and manages recovery options.

**Features:**
- Backup critical user files
- Create Windows system image
- Backup registry
- List available backups
- Manage backup retention (60-day default)
- Calculate backup sizes
- Automatic cleanup of old backups

**Requirements:**
- External drive or network location for backups
- Sufficient free space (50GB+ recommended)

**Run:** `.\Backup-Recovery.ps1`  
**Frequency:** Weekly  
**Time Required:** 1-2 hours (depending on system size)

---

### 4. **Security-Audit.ps1**
Performs comprehensive system security assessment.

**Features:**
- Windows Defender status and configuration
- Windows Firewall validation (all profiles)
- Windows Update status
- User account audit and permissions
- Password policy checking
- Administrator account status
- User Account Control (UAC) verification
- BitLocker encryption status
- Security event log analysis
- Failed logon attempt detection
- Overall security score calculation

**Output:**
- Color-coded security assessment
- Issues vs. Warnings vs. Passed checks
- Security score (0-100%)
- Actionable recommendations

**Run:** `.\Security-Audit.ps1`  
**Frequency:** Weekly  
**Time Required:** 5-10 minutes

---

### 5. **Network-Diagnostics.ps1**
Performs comprehensive network connectivity and performance assessment.

**Features:**
- Internet connectivity testing
- DNS resolution validation
- DNS server performance testing
- Network adapter health check
- IP configuration audit
- Duplicate IP detection
- Network driver health verification
- Latency testing (3 public DNS servers)
- Network speed estimation
- Network health score

**Tests:**
- Google, Microsoft, GitHub domain resolution
- Google DNS, Cloudflare DNS, OpenDNS performance
- ARP table scanning for conflicts
- Driver status verification
- Download speed measurement

**Run:** `.\Network-Diagnostics.ps1`  
**Frequency:** Weekly  
**Time Required:** 10-15 minutes

---

### 6. **Maintenance-Scheduler.ps1**
Creates and manages scheduled maintenance tasks.

**Features:**
- Verify all maintenance scripts exist
- Create Windows Scheduled Tasks
- Support for Daily/Weekly/Monthly frequencies
- Custom execution times per script
- Interactive menu-driven interface
- Enable/disable individual scripts
- Test run functionality
- Email notification configuration
- Configuration file (JSON)
- Task monitoring and listing

**Menu Options:**
1. Enable maintenance schedule (create all tasks)
2. Disable maintenance schedule (disable all tasks)
3. View scheduled tasks
4. Test run a maintenance script
5. Configure email notifications
6. Exit

**Configuration File:** `MaintenanceConfig.json`

**Default Schedule (All tasks run Sunday):**
- 1:00 AM - Health Report
- 1:30 AM - Security Audit
- 2:00 AM - Monthly Maintenance
- 2:30 AM - System Cleanup
- 3:00 AM - Package Updates
- 3:30 AM - Windows Updates
- 4:00 AM - Backup & Recovery
- 4:30 AM - Network Diagnostics

**Run:** `.\Maintenance-Scheduler.ps1`  
**One-time Setup Required** - Then runs automatically

---

### 7. **Event-Log-Analyzer.ps1**
Analyzes Windows Event Logs for errors, warnings, and security issues.

**Features:**
- System Event Log analysis
- Application Event Log analysis
- Security Event Log analysis
- System crash detection
- Service failure detection
- Failed logon attempt alerts
- Top error source identification
- CSV export for external analysis
- HTML report generation
- Health assessment scoring

**Analysis Period:** Last 7 days  
**Events Analyzed:** Up to 10,000 per log

**Output Files:**
- `EventLogAnalysis_YYYYMMDD_HHmmss.log` - Detailed analysis
- `EventLogReport_YYYYMMDD_HHmmss.html` - Formatted report
- `EventLogExport_YYYYMMDD_HHmmss.csv` - Raw event data

**Run:** `.\Event-Log-Analyzer.ps1`  
**Frequency:** Weekly  
**Time Required:** 5-10 minutes

---

### 8. **Windows-Monthly-Maintenance.ps1**
Performs system check operations (DISM, SFC, CHKDSK).

**Features:**
- DISM system file health check
- System File Checker (SFC) scans
- CHKDSK disk check
- Staged execution with recovery options
- Comprehensive system validation

**Run:** `.\Windows-Monthly-Maintenance.ps1`  
**Frequency:** Monthly  
**Time Required:** 30-60 minutes

---

### 9. **Winget-Package-Update.ps1**
Updates installed packages via Windows Package Manager (winget).

**Features:**
- Automatic package discovery
- Safe update mechanism
- Error handling for failures
- Update summary reporting

**Run:** `.\Winget-Package-Update.ps1`  
**Frequency:** Weekly  
**Time Required:** 10-20 minutes

---

### 10. **Windows-Updates-Install.ps1**
Installs Windows and OS updates with module management.

**Features:**
- Module verification and installation
- Windows Update management
- Feature/Quality update installation
- Restart handling
- Update status reporting

**Run:** `.\Windows-Updates-Install.ps1`  
**Frequency:** Weekly  
**Time Required:** 20-60 minutes (varies with updates)

---

## ⚙️ Requirements

### System Requirements
- **OS:** Windows 10 or Windows 11
- **Admin Rights:** Required for all scripts
- **PowerShell:** Version 5.1 or higher
- **Disk Space:** 10GB+ for backups, reports, and logs

### Script Dependencies
- Windows Task Scheduler (for Maintenance-Scheduler.ps1)
- Windows Backup feature (for System Image in Backup-Recovery.ps1)
- DISM, SFC, CHKDSK utilities (for Monthly-Maintenance.ps1)
- Network connectivity (for some diagnostic tests)

### Optional
- External drive (for backups)
- SMTP server access (for email notifications)
- Winget (Windows Package Manager)

---

## 📥 Installation

### Step 1: Download the Suite
1. Clone or download the repository
2. Extract to a convenient location (e.g., `C:\Maintenance-Scripts`)
3. Ensure all `.ps1` files are in the same directory

### Step 2: Set Execution Policy
Run PowerShell as Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Step 3: Verify Script Files
Check that all 10 scripts are present:
```
System-Cleanup-Optimization.ps1
System-Information-Health-Report.ps1
Backup-Recovery.ps1
Security-Audit.ps1
Network-Diagnostics.ps1
Maintenance-Scheduler.ps1
Event-Log-Analyzer.ps1
Windows-Monthly-Maintenance.ps1
Winget-Package-Update.ps1
Windows-Updates-Install.ps1
README.md
```

### Step 4: Test Individual Scripts
Before setting up automation, test each script:
```powershell
# Run as Administrator
cd C:\Maintenance-Scripts
.\System-Cleanup-Optimization.ps1
```

---

## 🚀 Quick Start

### Option 1: Automated Setup (Recommended)
1. Run PowerShell as Administrator
2. Navigate to script directory: `cd C:\Maintenance-Scripts`
3. Run scheduler: `.\Maintenance-Scheduler.ps1`
4. Select option "1" to enable full maintenance schedule
5. Choose option "3" to verify scheduled tasks
6. Tasks will run automatically on schedule

### Option 2: Manual Individual Runs
```powershell
# System Cleanup
.\System-Cleanup-Optimization.ps1

# Generate Health Report
.\System-Information-Health-Report.ps1

# Create Backup
.\Backup-Recovery.ps1

# Run Security Audit
.\Security-Audit.ps1

# Test Network
.\Network-Diagnostics.ps1

# Analyze Events
.\Event-Log-Analyzer.ps1
```

### Option 3: Manual Task Scheduling
Create manual Windows Scheduled Tasks:
1. Open Task Scheduler (`taskschd.msc`)
2. Create Basic Task
3. Set trigger (Daily/Weekly/Monthly)
4. Set action: PowerShell with script path
5. Set conditions and settings

---

## 📊 Script Details

### Execution Flow

```
Maintenance Suite
├── System-Cleanup-Optimization.ps1 (Weekly)
│   └── Frees disk space
│
├── System-Information-Health-Report.ps1 (Weekly)
│   └── Tracks system health trends
│
├── Security-Audit.ps1 (Weekly)
│   └── Identifies security vulnerabilities
│
├── Network-Diagnostics.ps1 (Weekly)
│   └── Tests connectivity and performance
│
├── Event-Log-Analyzer.ps1 (Weekly)
│   └── Detects errors and threats
│
├── Backup-Recovery.ps1 (Weekly)
│   └── Creates system backups
│
├── Windows-Updates-Install.ps1 (Weekly)
│   └── Applies OS updates
│
├── Winget-Package-Update.ps1 (Weekly)
│   └── Updates third-party software
│
└── Windows-Monthly-Maintenance.ps1 (Monthly)
    └── Deep system checks
```

### Recommended Schedule

**Sunday Morning - Maintenance Window (1:00 AM - 5:00 AM)**

| Time | Task | Duration |
|------|------|----------|
| 1:00 AM | Health Report | 2-5 min |
| 1:30 AM | Security Audit | 5-10 min |
| 2:00 AM | Monthly Maintenance* | 30-60 min |
| 2:30 AM | System Cleanup | 15-30 min |
| 3:00 AM | Package Updates | 10-20 min |
| 3:30 AM | Windows Updates | 20-60 min |
| 4:00 AM | Backup & Recovery | 1-2 hours |
| 4:30 AM | Network Diagnostics | 10-15 min |

*Monthly Maintenance runs monthly instead of weekly

---

## 📁 Output Files

All output files are saved to: `%USERPROFILE%\Documents\`

### Log Files
- `SystemCleanup_YYYYMMDD_HHmmss.log`
- `SystemReport_YYYYMMDD_HHmmss.txt`
- `BackupRecovery_YYYYMMDD_HHmmss.log`
- `SecurityAudit_YYYYMMDD_HHmmss.log`
- `NetworkDiagnostics_YYYYMMDD_HHmmss.log`
- `MaintenanceScheduler_YYYYMMDD_HHmmss.log`
- `EventLogAnalysis_YYYYMMDD_HHmmss.log`

### Report Files
- `SystemReport_YYYYMMDD_HHmmss.html`
- `EventLogReport_YYYYMMDD_HHmmss.html`

### Data Files
- `SystemMetricsHistory.csv` - Historical health data
- `BackupMetadata.csv` - Backup inventory
- `MaintenanceConfig.json` - Scheduler configuration
- `EventLogExport_YYYYMMDD_HHmmss.csv` - Event data

---

## 🔧 Troubleshooting

### Issue: "Access Denied" or "Not Administrator"
**Solution:** Always run PowerShell as Administrator
```powershell
# Right-click PowerShell, select "Run as Administrator"
```

### Issue: "Cannot find path"
**Solution:** Ensure scripts are in the correct directory
```powershell
# Check current location
Get-Location

# Change to script directory
cd C:\Maintenance-Scripts
```

### Issue: "Execution Policy" error
**Solution:** Set execution policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

### Issue: Scheduled tasks not running
**Solution:** Verify task creation
```powershell
# List all scheduled maintenance tasks
Get-ScheduledTask -TaskPath "\Microsoft\Windows\SystemMaintenance\" | Format-List
```

### Issue: Backup destination not found
**Solution:** Connect external drive or create network path
```powershell
# Example: Use external drive E:
# E:\SystemBackups
```

### Issue: "Module not found" errors
**Solution:** Update PowerShell modules
```powershell
# As Administrator
Update-Module
```

---

## ✅ Best Practices

### 1. **Pre-Maintenance Checklist**
- [ ] Back up important files
- [ ] Ensure system is plugged in
- [ ] Close all applications
- [ ] Disable sleep/hibernate
- [ ] Schedule during low-usage times

### 2. **Regular Monitoring**
- Review log files weekly
- Check HTML reports for trends
- Monitor security alerts
- Track backup completion
- Monitor available disk space

### 3. **Backup Strategy**
- Keep backups on separate drive
- Maintain 60+ day retention
- Test backup restoration quarterly
- Monitor backup sizes
- Use external storage

### 4. **Security Guidelines**
- Review Security Audit results
- Address critical issues immediately
- Keep systems updated
- Monitor failed logon attempts
- Check BitLocker status

### 5. **Disk Space Management**
- Monitor available space (maintain >20% free)
- Regularly clean old logs
- Manage backup retention
- Remove old reports (archive if needed)
- Check for disk space issues

### 6. **Update Management**
- Install Windows Updates weekly
- Test updates before full deployment
- Review update logs
- Schedule updates during maintenance windows
- Keep drivers updated

### 7. **Network Maintenance**
- Run diagnostics weekly
- Check for latency issues
- Monitor DNS performance
- Test connectivity to important services
- Review failed connections

---

## 📞 Support & Troubleshooting

### Getting Help
1. Check script log files for error messages
2. Review output HTML reports for details
3. Run scripts individually to isolate issues
4. Check system Event Logs for related errors
5. Verify system meets all requirements

### Common Questions

**Q: How long do maintenance scripts take?**
A: Most run 15-30 minutes; backups and updates may take 1-2 hours

**Q: Can I run scripts manually and automated?**
A: Yes, the scheduler doesn't prevent manual runs

**Q: How much disk space do I need?**
A: 10GB+ for logs, reports, and backups

**Q: Can I change the schedule?**
A: Yes, edit MaintenanceConfig.json or recreate tasks

**Q: Do scripts require internet?**
A: Some tests (DNS, speed test) need internet; most work offline

---

## 📝 Configuration Files

### MaintenanceConfig.json
Edit this file to:
- Enable/disable individual scripts
- Change execution frequencies
- Adjust execution times
- Configure email settings

---

## 🔐 Security Considerations

- All scripts require Administrator privileges
- Scheduled tasks run as SYSTEM account
- Sensitive data is logged locally
- Backup encryption depends on your setup
- Review access permissions to Documents folder
- Protect MaintenanceConfig.json (contains settings)

---

## 📈 Maintenance Benefits

### System Performance
- ✅ 10-20% disk space freed regularly
- ✅ Faster boot times
- ✅ Improved application responsiveness
- ✅ Reduced system clutter

### Security & Stability
- ✅ Proactive threat detection
- ✅ Security vulnerabilities identified
- ✅ System crashes prevented
- ✅ Updates kept current

### Monitoring & Tracking
- ✅ Historical performance data
- ✅ Trend analysis
- ✅ Early problem detection
- ✅ Compliance documentation

### Peace of Mind
- ✅ Automated backups
- ✅ Recovery options available
- ✅ Comprehensive reports
- ✅ Professional monitoring

---

## 🎯 Summary

The Windows System Maintenance Suite provides a complete solution for:

1. **Cleaning** - Remove temporary files and clutter
2. **Monitoring** - Track system health and performance
3. **Securing** - Audit and protect your system
4. **Updating** - Keep Windows and software current
5. **Backing Up** - Protect your data
6. **Diagnosing** - Test network and connectivity
7. **Analyzing** - Review system events and logs
8. **Automating** - Schedule everything automatically

**Get Started Now:**
```powershell
cd C:\Maintenance-Scripts
.\Maintenance-Scheduler.ps1
# Select option 1 to enable full schedule
```

---

**Last Updated:** September 11, 2026  
**Version:** 1.0  
**Status:** Production Ready

For updates and more information, check your Documents folder for generated reports and logs.
