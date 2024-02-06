# Install-Module -Name ThreadJob -Force
# import-module ThreadJob

$TaskName='SQLHeartbeat'
$CMSServer='MYCMSSERVER'
$CMSGroup='PROD'
$Noformat=$false
$Failuresonly=$false

$throttle = [int]$env:NUMBER_OF_PROCESSORS+1
$threaded = $true

$Output=$null
clear

$serverlist=@()

# Get target servers to check from CMS
If ($CMSGroup)
{
    $Serverlist=(Get-DbaRegServer -SqlInstance $CMSServer  -Group $CMSGroup | select Servername).Servername
}
# Or If you want just to include an array of servers you can:
#$serverlist='LAPTOP2','LAPTOP2\NAMED1'

# Or pull from an inventory table:
#$serverlist=Invoke-Sqlcmd -ServerInstance MyinventoryServer -Database MyinventoryDB -Query "Select servername from MyinventoryTable" 

$Totalcount=($Serverlist).count
If ($Totalcount -eq 0){
    Write-Host 'No servers to check' -ForegroundColor Yellow
    Break
}
# Script Block of what we actually want to run.
$GetSQLInfo = {
	param(
		$full_instance
	)       
try{    
	# split server and instance
	if ($full_instance -like '*\*')
	{
		$server = $full_instance.substring(0,$full_instance.IndexOf('\'))
		$instance = $full_instance.Replace("$server\",'')
        $instancename = "MSSQL`$$instance"       
	}
	else
	{
		$server = $full_instance
		$instance = 'MSSQLSERVER'
        $instancename= 'MSSQLSERVER'
        
	}
        # Extra check for fast-fail
        if (Test-Connection -ComputerName $server -Quiet -Count 1)  {         
          $Ispingable=$true
        # Check if SQL service started
         If( (get-service -ComputerName $server  | where Name -eq $instancename).Status -ne 'Stopped' )
          {
           $IsSQLServiceUp=$true
        # Get some data from SQL 
           $sqlstmt="DECLARE @auth varchar(8)
            IF EXISTS (SELECT * FROM sys.dm_exec_connections WHERE auth_scheme='KERBEROS')
	            SET @auth ='KERBEROS'
                ELSE
	            SET @auth ='NTLM'
            SELECT SERVERPROPERTY('ServerName') AS SQLinstance,SERVERPROPERTY('Edition') AS Edition,SERVERPROPERTY('ProductVersion') AS VersionNumber,SERVERPROPERTY('IsHadrEnabled') AS Hadr, @Auth AS AuthScheme,
            (select status_desc from sys.dm_server_services where servicename LIKE 'SQL Server Agent%') AS SQLAgentStatus"        
        try {
              $sqldata=Invoke-Dbaquery -SQLInstance $full_instance -Database 'master' -Query $sqlstmt -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
               
          If ($sqldata){
                $IsSqlresponding=$true  
                # Express detect, blank agent data
                If ($sqldata.Edition -like '*Express*'){       
                    $sqldata.SQLAgentStatus = $null
                }                           
            }
        }
        catch {
            $IsSqlresponding=$false
        }        
        }
        Else {
             $IsSQLServiceUp=$false
        }

        # Build status output from vars
        $Detail=[PSCustomObject]@{
                SQLInstance = $full_instance
                IsPingable = $Ispingable
                IsSQLServiceUp = $IsSQLServiceUp
                IsSqlresponding = $IsSqlresponding}
     
         # Add SQL info if we have any
         If ($sqldata) {

             $Detail | Add-Member -MemberType NoteProperty "Edition" -Value $sqldata.Edition
             $Detail | Add-Member -MemberType NoteProperty "VersionNumber" -Value $sqldata.VersionNumber
             $Detail | Add-Member -MemberType NoteProperty "Hadr" -Value $sqldata.Hadr
             $Detail | Add-Member -MemberType NoteProperty "Authscheme" -Value $sqldata.AuthScheme
             $Detail | Add-Member -MemberType NoteProperty "SQLAgentStatus" -Value $sqldata.SQLAgentStatus
         }
	}
    Else {
        $Detail=[PSCustomObject]@{
                SQLInstance = $full_instance
                IsPingable = $false
        }
    }
    $Detail # Return info 
}
# Theres an error somewhere, return this fact.
catch{
    $Detail=[PSCustomObject]@{
                SQLInstance = "$full_instance - ERROR IN COLLECTION "}
}
}

# End of Script Block

$i=0
ForEach($Server in $serverlist) 
    {
        $i++
        while( @(Get-Job -State Running).Count -ge $Throttle)
        {
            Write-Host "Max concurrency reached...Throttling..." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 2000
        }
      
        Write-Progress -Activity $TaskName -Status "Starting threads..."  -CurrentOperation "$i of $TotalCount Started" -PercentComplete ($i/$TotalCount*100)

        # Call a job for the task for the server  Threaded or normal depending on param
        if (-not $threaded) {
        $ID=(Start-Job -Name $TaskName-$server -ScriptBlock $GetSQLInfo -ArgumentList $server).ID
        }
        Else {
        $ID=(Start-ThreadJob -Name $TaskName-$server -ScriptBlock $GetSQLInfo -ArgumentList $server -ThrottleLimit $Throttle).ID
        }

        Write-Verbose "Started Job $ID for Target: $Server"
    } 

clear
Write-Host "Threads started for all targets. Collating." -ForegroundColor Cyan
$completed=@(Get-Job -State Completed).count

while( @(Get-Job -State Running | Where Name -like "$TaskName*" ).Count -gt 0){
    $completed=@(Get-Job -State Completed).count
    Write-Progress -Activity $TaskName -Status "Completed threads..."  -CurrentOperation "$completed of $TotalCount Completed" -PercentComplete ($completed/$TotalCount*100)
    Start-Sleep -Milliseconds 500
}
Write-Progress -Completed -Activity "Done."
# Return results
$Output=Get-Job | Where Name -like "$TaskName*" | Wait-Job | Receive-Job | Select *  
$Jobs=Get-Job | Where Name -like "$TaskName*" 

If ($Noformat){     
    If (-not $Failuresonly){
        $output | Select SQLInstance, IsPingable, IsSQLServiceUp, IsSQLResponding, Edition, VersionNumber, Hadr, AuthScheme, SQLAgentStatus | Where {$null -ne ($_.SQLInstance)}
    }
    Else {
        foreach ($line in $output){
            If(($line.IsPingable -eq $false ) -or ($line.IsSQLServiceUp -eq $False) -or ($line.IsSQLResponding -eq $false) -or ($line.SQLAgentStatus -eq 'Stopped')) {
                $line | Select SQLInstance, IsPingable, IsSQLServiceUp, IsSQLResponding, Edition, VersionNumber, Hadr, AuthScheme, SQLAgentStatus | Where {$null -ne ($_.SQLInstance)}
              }
        }
    }
}
Else
# Lets present our findings in a pretty way
{
foreach ($line in $output)
{
      If ($line.IsPingable -eq $false) 
      {
        Write-Host "Server: $($line.SQLInstance) " -ForegroundColor Cyan -NoNewline; Write-Host "Is Pingable: $($line.IsPingable)" -ForegroundColor Red
      }

      If (($line.IsPingable -eq $True) -and ($line.IsSQLServiceUp -eq $False) )
      {
        Write-host "Server: $($line.SQLInstance) " -ForegroundColor Cyan -NoNewline; Write-Host "Is Pingable: $($line.IsPingable), " -ForegroundColor Green -NoNewline;`
          Write-host "SQL Service Up: $($line.IsSQLServiceUp) " -ForegroundColor Red    
      }
      If (($line.IsSQLServiceUp -eq $True) -and ($line.IsSQLResponding -eq $false)  )
      {
        Write-host "Server: $($line.SQLInstance) " -ForegroundColor Cyan -NoNewline; Write-Host "Is Pingable: $($line.IsPingable), " -ForegroundColor Green -NoNewline;`
          Write-host "SQL Service Up: $($line.IsSQLServiceUp), " -ForegroundColor Green -NoNewline;  Write-host "SQL Responding: $($line.IsSQLResponding)" -ForegroundColor Red    
      }
     
# SQL Agent down  
      If (($line.IsSQLResponding -eq $True) -and ($line.SQLAgentStatus -eq 'Stopped'))
      {
          Write-host "Server: $($line.SQLInstance) " -ForegroundColor Cyan -NoNewline; Write-Host "Is Pingable: $($line.IsPingable), " -ForegroundColor Green -NoNewline;`
            Write-host "SQL Service Up: $($line.IsSQLServiceUp) " -ForegroundColor Green -NoNewline;  Write-host " SQL Responding: $($line.IsSQLResponding), " -ForegroundColor Green -NoNewline;`
             Write-Host " SQLAgent Status: $($line.SQLAgentStatus), " -ForegroundColor Red -NoNewline; Write-host " Edition: $($line.Edition), Version: $($line.VersionNumber), Hadr: $($line.hadr), Auth: $($line.AuthScheme)" -ForegroundColor Green      
      }

If (-not $Failuresonly){
# ALL OK
    If (($line.Ispingable -eq $True) -and ($line.IsSQLServiceUp -eq $True) -and ($line.IsSQLResponding -eq $true) -and ('Running' -eq $line.SQLAgentStatus))
      {
         Write-host "Server: $($line.SQLInstance) " -ForegroundColor Cyan -NoNewline; Write-Host "Is Pingable: $($line.IsPingable), " -ForegroundColor Green -NoNewline;`
         Write-host "SQL Service Up: $($line.IsSQLServiceUp), " -ForegroundColor Green -NoNewline;  Write-host "SQL Responding: $($line.IsSQLResponding), " -ForegroundColor Green -NoNewline;`
         Write-Host "SQLAgent Status: $($line.SQLAgentStatus), " -ForegroundColor Green -NoNewline; Write-host "Edition: $($line.Edition), Version: $($line.VersionNumber), Hadr: $($line.hadr), Auth: $($line.AuthScheme)" -ForegroundColor Green   
      }    
    If (($line.ConnectSuccess -eq $True) -and ($line.IsPingable -eq $True) -and ($line.IsSQLResponding -eq $true) -and ($null -eq $line.SQLAgentStatus))
      {
         Write-host "Server: $($line.SQLInstance) " -ForegroundColor Cyan -NoNewline; Write-Host "Is Pingable: $($line.IsPingable), " -ForegroundColor Green -NoNewline;`
         Write-host "SQL Service Up: $($line.IsSQLServiceUp), " -ForegroundColor Green -NoNewline;  Write-host "SQL Responding: $($line.IsSQLResponding), " -ForegroundColor Green -NoNewline;`
         Write-Host "SQLAgent Status: N/A, " -ForegroundColor Green -NoNewline; Write-host "Edition: $($line.Edition), Version: $($line.VersionNumber), Hadr: $($line.hadr), Auth: $($line.AuthScheme)" -ForegroundColor Green
      }     
    }
}

Write-Host "`nJOB SUMMARY: " -ForegroundColor DarkGreen
Write-Host "Target Count: $Totalcount"
Write-Host "Not Completed: "($Jobs | Where State -ne 'Completed').count
Write-Host "Completed: "($Jobs | Where State -eq 'Completed').Count
Write-Host "Success %: "(($Jobs | Where State -eq 'Completed').count/$TotalCount*100)

<#Output anything not marked as completed.#>
If (($Jobs | Where State -eq 'Completed').count -ne 0)
{
$Jobs | Where State -ne 'Completed' | Select Id, Name, State
}
}  

<#Now Tidy Up#>
Get-Job | Remove-Job -Force