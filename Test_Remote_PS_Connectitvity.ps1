param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

Write-Host "Testing WinRM connectivity to $ComputerName..." -ForegroundColor Cyan

# Step 1: Test WinRM service
try {
    Test-WSMan -ComputerName $ComputerName -ErrorAction Stop
    Write-Host "WinRM service is responding." -ForegroundColor Green
}
catch {
    Write-Host "WinRM test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Step 2: Attempt remote session
Write-Host "`nAttempting remote PowerShell session..." -ForegroundColor Cyan

try {
    $session = New-PSSession -ComputerName $ComputerName -ErrorAction Stop
    Write-Host "Session created successfully." -ForegroundColor Green

    # Step 3: Run a simple command remotely
    $result = Invoke-Command -Session $session -ScriptBlock {
        hostname
    }

    Write-Host "`nRemote command executed successfully." -ForegroundColor Green
    Write-Host "Remote Hostname: $result"

    # Cleanup
    Remove-PSSession $session
}
catch {
    Write-Host "Remote session failed: $($_.Exception.Message)" -ForegroundColor Red
}