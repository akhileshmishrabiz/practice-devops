# System Monitor Exercise

## Problem Statement

Your production servers need continuous monitoring to ensure optimal performance and prevent downtime. Manual system checks are time-consuming and often missed during critical periods. You need an automated solution that regularly collects and reports key system metrics, maintaining a historical record of system health for analysis and troubleshooting.

The system should monitor:
- **Disk Space Utilization**: Track storage usage to prevent disk full scenarios
- **IP Configuration**: Monitor network interfaces and IP assignments
- **System Uptime**: Track server availability and restart events
- **Memory Usage**: Monitor RAM consumption to detect memory leaks

## Requirements

### Core Functionality
1. **System Metrics Collection**: Gather disk, network, uptime, and memory information
2. **Automated Scheduling**: Run every 2 hours via crontab
3. **Report Generation**: Create timestamped reports with all metrics
4. **Historical Management**: Maintain only the 5 most recent reports
5. **Storage Location**: Save reports in `/usr/local/` directory

### Technical Specifications
- Script must be executable and handle errors gracefully
- Reports should be human-readable with clear formatting
- Automatic cleanup of old reports to prevent disk space issues
- Proper logging of script execution and any errors

## Expected Metrics

### 1. Disk Space Utilization
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G  8.5G   11G  44% /
/dev/sda2       100G   45G   50G  47% /home
tmpfs           2.0G     0  2.0G   0% /tmp
```

### 2. IP Configuration
```
Interface: eth0
  inet 192.168.1.100/24
  ether 00:1b:21:12:34:56
  status: UP

Interface: lo
  inet 127.0.0.1/8
  status: UP
```

### 3. System Uptime
```
System Uptime: 15 days, 3 hours, 45 minutes
Load Average: 0.25, 0.30, 0.28
```

### 4. Memory Information
```
Total Memory: 8GB
Used Memory: 4.2GB (52.5%)
Free Memory: 3.8GB (47.5%)
Available Memory: 6.1GB
Swap Usage: 512MB / 2GB (25%)
```

## Testing Instructions

### 1. Setup
```bash
# Create the script directory
sudo mkdir -p /usr/local/system-reports

# Create the monitoring script
sudo nano /usr/local/bin/system_monitor.sh

# Make it executable
sudo chmod +x /usr/local/bin/system_monitor.sh

# Test the script manually
sudo /usr/local/bin/system_monitor.sh
```

### 2. Crontab Configuration
```bash
# Open crontab for editing
sudo crontab -e

# Add the following line to run every 2 hours
0 */2 * * * /usr/local/bin/system_monitor.sh

# Verify crontab entry
sudo crontab -l
```

### 3. Manual Testing
```bash
# Run the script multiple times to test report rotation
sudo /usr/local/bin/system_monitor.sh
sudo /usr/local/bin/system_monitor.sh
sudo /usr/local/bin/system_monitor.sh

# Check generated reports
ls -la /usr/local/system-reports/

# View a report
cat /usr/local/system-reports/system_report_*.txt
```

### 4. Validation Steps
1. **Report Generation**: Verify reports are created with correct timestamps
2. **Content Accuracy**: Check all four metrics are properly collected
3. **File Rotation**: Confirm only 5 most recent reports are kept
4. **Crontab Execution**: Wait for scheduled run and verify new report creation
5. **Error Handling**: Test with insufficient permissions or disk space

### 5. Expected File Structure
```
/usr/local/system-reports/
├── system_report_2025-07-11_14-00-01.txt
├── system_report_2025-07-11_12-00-01.txt
├── system_report_2025-07-11_10-00-01.txt
├── system_report_2025-07-11_08-00-01.txt
└── system_report_2025-07-11_06-00-01.txt
```

### 6. Troubleshooting
- **Permission Issues**: Ensure script runs with appropriate privileges
- **Crontab Not Working**: Check system cron service is running
- **Missing Commands**: Verify required utilities (df, ip, free, uptime) are available
- **Disk Space**: Monitor `/usr/local/` directory size
- **Log Errors**: Check system logs for cron execution errors

## Success Criteria
- Script successfully collects all four types of system information
- Reports are generated automatically every 2 hours
- Historical reports are properly managed (only 5 kept)
- System administrators can easily review system health trends
- No manual intervention required for routine monitoring
