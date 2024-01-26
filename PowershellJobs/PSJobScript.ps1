<#
Install-Module -Name ThreadJob -Force
import-module ThreadJob
#>

$TaskName='GetSQLInfo'
$throttle = (Get-WmiObject –class Win32_processor).NumberOfCores 
clear

# Our list of targets goes here.
$Serverlist=@()
$Serverlist='Server1','Server2','Server3'


# Script Block of what you actually want to run.
$GetSQLInfo = {

    Param($server)
    $sqloutput=(Invoke-Sqlcmd -ServerInstance $server -Database master -Query 'SELECT @@servername AS Servername, getdate() as dt')

[pscustomobject]@{
        Returnedserver=$sqloutput.Servername
        Returnedtime=$sqloutput.dt
    }
}
# End of Script Block to run.



$i=0
ForEach($Server in $serverlist) 
    {
        $i++
        while( @(Get-Job -State Running).Count -ge $Throttle)
        {
            Write-Host "Max concurrency reached...Throttling..." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500
        }
    
      
        #Call a job for the task for the server  
        Start-Job -Name $TaskName-$server -ScriptBlock $GetSQLInfo -ArgumentList $server 
        #Or a Threaded Job
        #Start-ThreadJob -Name $TaskName-$server -ScriptBlock $GetSQLInfo -ArgumentList $server -ThrottleLimit $throttle
       
    } 
 
Write-Host "Threads started for all targets. Collating." -ForegroundColor Green

#Return results from the jobs
Get-Job | Wait-Job | Receive-Job | Select ReturnedServer, Returnedtime


<#Now Tidy Up#>
Get-Job | Remove-Job -Force
