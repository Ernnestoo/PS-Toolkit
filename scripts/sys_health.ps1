# System Health Check Script
# This script monitors system health across multiple computers including:
# - Disk space usage and available storage
# - Memory utilization and availability  
# - System uptime since last reboot
# - Overall health status based on thresholds

[CmdletBinding()]
param(
    # Array of computer names to check (default: local machine)
    [Parameter(Mandatory=$false)]
    [string[]]$ComputerNames = @("localhost"),
    
    # Disk usage percentage threshold for warnings (default: 80%)
    [Parameter(Mandatory=$false)]
    [int]$DiskThreshold = 80,
    
    # Memory usage percentage threshold for warnings (default: 85%)
    [Parameter(Mandatory=$false)]
    [int]$MemoryThreshold = 85,
    
    # Output file path for CSV export (default: current directory)
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$PWD\SystemHealth.csv",
    
    # Include additional system information (CPU, services)
    [Parameter(Mandatory=$false)]
    [switch]$Detailed
)

# Initialize results array to store health data from all computers
$results = foreach ($computer in $ComputerNames) {
    try {
        Write-Host "Checking $computer..." -ForegroundColor Yellow
        
        # Query disk information - only get fixed drives (Type 3 = local disk)
        $disks = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $computer -Filter "DriveType=3" -ErrorAction Stop
        
        # Query operating system information for memory and uptime data
        $memory = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $computer -ErrorAction Stop
        
        # Calculate memory statistics (convert from KB to GB for readability)
        $totalRAM = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 2)  # Total RAM in GB
        $freeRAM = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)       # Free RAM in GB
        $usedRAMPercent = [math]::Round((($totalRAM - $freeRAM) / $totalRAM) * 100, 2)  # Used RAM percentage
        
        # Calculate system uptime since last boot
        $bootTime = $memory.ConvertToDateTime($memory.LastBootUpTime)
        $uptime = (Get-Date) - $bootTime
        
        # Get additional system info if detailed mode is enabled
        $cpuUsage = $null
        $criticalServices = $null
        if ($Detailed) {
            try {
                # Get CPU usage (average over 2 seconds for accuracy)
                $cpuUsage = (Get-WmiObject -Class Win32_Processor -ComputerName $computer | 
                           Measure-Object -Property LoadPercentage -Average).Average
                
                # Check status of critical Windows services
                $serviceList = @("Spooler", "Themes", "AudioSrv", "BITS")
                $criticalServices = (Get-Service -ComputerName $computer -Name $serviceList -ErrorAction SilentlyContinue | 
                                   Where-Object {$_.Status -ne "Running"}).Count
            }
            catch {
                Write-Warning "Could not gather detailed info for $computer"
            }
        }
        
        # Process each disk drive and create health report
        foreach ($disk in $disks) {
            # Calculate disk usage percentage
            $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 2)
            
            # Determine overall system status based on thresholds
            $status = "OK"
            $warnings = @()
            
            if ($usedPercent -gt $DiskThreshold) {
                $status = "WARNING"
                $warnings += "Disk $($disk.DeviceID) at $usedPercent%"
            }
            
            if ($usedRAMPercent -gt $MemoryThreshold) {
                $status = "WARNING"
                $warnings += "Memory at $usedRAMPercent%"
            }
            
            # Flag systems that haven't rebooted in over 30 days
            if ($uptime.Days -gt 30) {
                $status = "ATTENTION"
                $warnings += "Uptime: $($uptime.Days) days"
            }
            
            # Create custom object with all health metrics
            $healthObject = [PSCustomObject]@{
                Computer = $computer
                Drive = $disk.DeviceID
                DiskUsedPercent = $usedPercent
                DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                DiskTotalGB = [math]::Round($disk.Size / 1GB, 2)
                MemoryUsedPercent = $usedRAMPercent
                MemoryFreeGB = $freeRAM
                MemoryTotalGB = $totalRAM
                UptimeDays = $uptime.Days
                LastBoot = $bootTime
                Status = $status
                Warnings = ($warnings -join "; ")
                CheckDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            # Add detailed information if requested
            if ($Detailed) {
                $healthObject | Add-Member -NotePropertyName "CPUUsagePercent" -NotePropertyValue $cpuUsage
                $healthObject | Add-Member -NotePropertyName "StoppedServices" -NotePropertyValue $criticalServices
            }
            
            # Output the health object
            $healthObject
        }
        
        Write-Host "$computer checked successfully" -ForegroundColor Green
    }
    catch {
        # Handle errors gracefully and log detailed error information
        Write-Error "Failed to check $computer. Error: $_"
        
        # Return error object to maintain consistent output structure
        [PSCustomObject]@{
            Computer = $computer
            Drive = "N/A"
            DiskUsedPercent = 0
            DiskFreeGB = 0
            DiskTotalGB = 0
            MemoryUsedPercent = 0
            MemoryFreeGB = 0
            MemoryTotalGB = 0
            UptimeDays = 0
            LastBoot = "Unknown"
            Status = "ERROR"
            Warnings = $_.Exception.Message
            CheckDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

# Export results to CSV file for further analysis or reporting
$results | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "`nResults exported to $OutputPath" -ForegroundColor Cyan

# Display summary statistics
$totalComputers = ($results | Select-Object -Unique Computer).Count
$healthyComputers = ($results | Where-Object {$_.Status -eq "OK"}).Count
$warningComputers = ($results | Where-Object {$_.Status -eq "WARNING"}).Count
$errorComputers = ($results | Where-Object {$_.Status -eq "ERROR"}).Count

Write-Host "`n=== HEALTH SUMMARY ===" -ForegroundColor White
Write-Host "Total Computers Checked: $totalComputers" -ForegroundColor White
Write-Host "Healthy: $healthyComputers" -ForegroundColor Green
Write-Host "Warnings: $warningComputers" -ForegroundColor Yellow  
Write-Host "Errors: $errorComputers" -ForegroundColor Red

# Display detailed results table
Write-Host "`n=== DETAILED RESULTS ===" -ForegroundColor White
$results | Format-Table -AutoSize

# Display any warnings or issues found
$issuesFound = $results | Where-Object {$_.Status -ne "OK" -and $_.Warnings -ne ""}
if ($issuesFound) {
    Write-Host "`n=== ISSUES REQUIRING ATTENTION ===" -ForegroundColor Red
    $issuesFound | Select-Object Computer, Status, Warnings | Format-Table -AutoSize
}