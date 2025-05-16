$computers = @("PC01", "PC02", "Server01")
foreach ($name in $computers) {
    if (Test-Connection -ComputerName $name -Count 1 -Quiet) {
        Write-Host "$name is online" -ForegroundColor Green
    } else {
        Write-Host "$name is offline" -ForegroundColor Red
    }
}
# This script checks the connectivity of a list of computers and outputs their status.
# It uses the Test-Connection cmdlet to ping each computer and checks if it is online or offline.