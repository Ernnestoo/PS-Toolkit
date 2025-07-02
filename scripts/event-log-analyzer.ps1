# Event Log Analyzer Script
# This script analyzes Windows Event Logs across multiple computers to identify:
# - Recent errors and warnings from System and Application logs
# - Event patterns and frequency analysis
# - Critical events that may require immediate attention
# - Comprehensive reporting with filtering and export capabilities

[CmdletBinding()]
param(
    # Array of computer names to analyze (default: local machine)
    [Parameter(Mandatory=$false)]
    [string[]]$ComputerNames = @("localhost"),
    
    # Number of hours to look back for events (default: 24 hours)
    [Parameter(Mandatory=$false)]
    [int]$Hours = 24,
    
    # Event log names to analyze (default: System and Application)
    [Parameter(Mandatory=$false)]
    [string[]]$LogNames = @("System", "Application"),
    
    # Event levels to include (Error, Warning, Information, Critical)
    [Parameter(Mandatory=$false)]
    [string[]]$Levels = @("Error", "Warning"),
    
    # Output file path for CSV export (default: current directory)
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$PWD\EventLogReport.csv",
    
    # Maximum number of events to retrieve per log (prevents overwhelming output)
    [Parameter(Mandatory=$false)]
    [int]$MaxEvents = 1000,
    
    # Filter events by specific Event IDs (optional)
    [Parameter(Mandatory=$false)]
    [int[]]$EventIDs = @(),
    
    # Show only unique events (group by Event ID and Source)
    [Parameter(Mandatory=$false)]
    [switch]$UniqueOnly,
    
    # Generate HTML report in addition to CSV
    [Parameter(Mandatory=$false)]
    [switch]$HTMLReport
)

Write-Host "=== Windows Event Log Analyzer ===" -ForegroundColor White
Write-Host "Analyzing event logs from the last $Hours hours..." -ForegroundColor Yellow
Write-Host "Target computers: $($ComputerNames -join ', ')" -ForegroundColor Cyan
Write-Host "Log sources: $($LogNames -join ', ')" -ForegroundColor Cyan
Write-Host "Event levels: $($Levels -join ', ')" -ForegroundColor Cyan

# Calculate the start time for event filtering
$startTime = (Get-Date).AddHours(-$Hours)
Write-Host "Analyzing events since: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

# Initialize array to store all collected events
$allEvents = @()
$computerStats = @{}

foreach ($computer in $ComputerNames) {
    Write-Host "`nProcessing $computer..." -ForegroundColor Cyan
    $computerEventCount = 0
    
    # Initialize statistics for this computer
    $computerStats[$computer] = @{
        TotalEvents = 0
        ErrorCount = 0
        WarningCount = 0
        CriticalCount = 0
        LogsProcessed = 0
        LogsSkipped = 0
    }
    
    foreach ($logName in $LogNames) {
        try {
            Write-Host "  Scanning $logName log..." -ForegroundColor Gray
            
            # Build filter hashtable for Get-WinEvent
            $filterHash = @{
                LogName = $logName
                StartTime = $startTime
            }
            
            # Convert level names to numeric values for filtering
            $levelNumbers = foreach($level in $Levels) { 
                switch($level) {
                    "Critical" { 1 }
                    "Error" { 2 }
                    "Warning" { 3 }
                    "Information" { 4 }
                    "Verbose" { 5 }
                }
            }
            $filterHash.Level = $levelNumbers
            
            # Add Event ID filter if specified
            if ($EventIDs.Count -gt 0) {
                $filterHash.ID = $EventIDs
            }
            
            # Query events with error handling
            $events = Get-WinEvent -ComputerName $computer -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction Stop
            
            # Process each event and add to collection
            foreach ($event in $events) {
                # Safely truncate message to prevent CSV issues
                $truncatedMessage = if ($event.Message) {
                    $event.Message.Substring(0, [Math]::Min(500, $event.Message.Length)).Replace("`n", " ").Replace("`r", "")
                } else {
                    "No message available"
                }
                
                # Create detailed event object
                $eventObject = [PSCustomObject]@{
                    Computer = $computer
                    LogName = $logName
                    Level = $event.LevelDisplayName
                    EventID = $event.Id
                    Source = $event.ProviderName
                    TimeCreated = $event.TimeCreated
                    Message = $truncatedMessage
                    TaskCategory = $event.TaskDisplayName
                    Keywords = $event.KeywordsDisplayNames -join "; "
                    ProcessID = $event.ProcessId
                    ThreadID = $event.ThreadId
                    UserName = if ($event.UserId) { $event.UserId.Value } else { "N/A" }
                    MachineName = $event.MachineName
                }
                
                $allEvents += $eventObject
                $computerEventCount++
                
                # Update statistics
                switch ($event.LevelDisplayName) {
                    "Error" { $computerStats[$computer].ErrorCount++ }
                    "Warning" { $computerStats[$computer].WarningCount++ }
                    "Critical" { $computerStats[$computer].CriticalCount++ }
                }
            }
            
            $computerStats[$computer].LogsProcessed++
            $computerStats[$computer].TotalEvents += $events.Count
            
            Write-Host "    Found $($events.Count) events in $logName" -ForegroundColor Green
        }
        catch {
            $computerStats[$computer].LogsSkipped++
            Write-Warning ("Could not access $logName log on ${computer}: " + $_.Exception.Message)
        }
    }
    
    Write-Host "  Total events from $computer`: $computerEventCount" -ForegroundColor Yellow
}

# Apply unique filtering if requested
if ($UniqueOnly) {
    Write-Host "`nApplying unique event filtering..." -ForegroundColor Yellow
    $originalCount = $allEvents.Count
    $allEvents = $allEvents | Group-Object EventID, Source, Computer | ForEach-Object {
        $group = $_.Group[0]
        $group | Add-Member -NotePropertyName "Occurrences" -NotePropertyValue $_.Count -Force
        $group
    }
    Write-Host "Reduced from $originalCount to $($allEvents.Count) unique events" -ForegroundColor Green
}

# Export results to CSV
Write-Host "`nExporting results..." -ForegroundColor Yellow
$allEvents | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "Results exported to: $OutputPath" -ForegroundColor Green

# Generate HTML report if requested
if ($HTMLReport) {
    $htmlPath = $OutputPath -replace '\.csv$', '.html'
    $htmlContent = $allEvents | ConvertTo-Html -Title "Event Log Analysis Report" -PreContent "<h1>Event Log Analysis Report</h1><p>Generated: $(Get-Date)</p>"
    $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "HTML report generated: $htmlPath" -ForegroundColor Green
}

# Display comprehensive summary
Write-Host "`n=== ANALYSIS SUMMARY ===" -ForegroundColor White
Write-Host "Analysis Period: $($startTime.ToString('yyyy-MM-dd HH:mm:ss')) to $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Total Events Found: $($allEvents.Count)" -ForegroundColor Yellow

# Summary by event level
Write-Host "`n--- Events by Level ---" -ForegroundColor Cyan
$levelSummary = $allEvents | Group-Object Level | Select-Object Name, Count | Sort-Object Count -Descending
$levelSummary | Format-Table -AutoSize

# Summary by computer
Write-Host "--- Events by Computer ---" -ForegroundColor Cyan
foreach ($comp in $ComputerNames) {
    if ($computerStats.ContainsKey($comp)) {
        $stats = $computerStats[$comp]
        Write-Host "$comp`: Total=$($stats.TotalEvents), Errors=$($stats.ErrorCount), Warnings=$($stats.WarningCount), Critical=$($stats.CriticalCount)" -ForegroundColor White
    }
}

# Top event sources
Write-Host "`n--- Top Event Sources ---" -ForegroundColor Cyan
$sourceSummary = $allEvents | Group-Object Source | Select-Object Name, Count | Sort-Object Count -Descending | Select-Object -First 10
$sourceSummary | Format-Table -AutoSize

# Most frequent Event IDs
Write-Host "--- Most Frequent Event IDs ---" -ForegroundColor Cyan
$eventIdSummary = $allEvents | Group-Object EventID | Select-Object Name, Count | Sort-Object Count -Descending | Select-Object -First 10
$eventIdSummary | Format-Table -AutoSize

# Recent critical events (if any)
$criticalEvents = $allEvents | Where-Object {$_.Level -eq "Critical" -or $_.Level -eq "Error"} | Sort-Object TimeCreated -Descending | Select-Object -First 5
if ($criticalEvents) {
    Write-Host "`n=== RECENT CRITICAL/ERROR EVENTS ===" -ForegroundColor Red
    $criticalEvents | Select-Object Computer, TimeCreated, Level, EventID, Source, @{Name="Message";Expression={$_.Message.Substring(0,[Math]::Min(100,$_.Message.Length))}} | Format-Table -Wrap
}

Write-Host "`n=== ANALYSIS COMPLETE ===" -ForegroundColor Green
Write-Host "Review the exported files for detailed analysis" -ForegroundColor Gray
