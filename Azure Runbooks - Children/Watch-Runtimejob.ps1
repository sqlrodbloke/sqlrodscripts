function Watch-Runtimejob {
    <#
        Monitors output and reports if failed for supplied jobid
        Use to easily terminate parent Runbook.
    #>   
 Param (
        [string]$AutomationAccount,
        [string]$AAResourceGroup,
        [guid]$jobid    
        )
try{   
    $job=Get-AzAutomationJob -AutomationAccountName $AutomationAccount -ResourceGroupName $AAResourceGroup -Id $jobid
    while (($job.Status -ne 'Completed') -and ($job.status -ne 'Failed')){      
        $output=(Get-AzAutomationJobOutput -AutomationAccountName $AutomationAccount -Id $job.Jobid -ResourceGroupName $AAResourceGroup -Stream "Output")
        Write-Output $output.summary
        Start-Sleep -seconds 5
        $job=Get-AzAutomationJob -AutomationAccountName $AutomationAccount -ResourceGroupName $AAResourceGroup -Id $job.Jobid
        If ($job.status -eq 'Failed') {
            Stop-AzAutomationJob -AutomationAccountName $AutomationAccount -ResourceGroupName $AAResourceGroup -Id $job.Jobid
            Throw " $($job.runbookname) has Failed"
        }
    }
}
catch {
    $exception = $_.Exception.Message
    Write-Host "$exception" -ForegroundColor Red
    Throw "Exception occurred in Function: Check-Runtimejob"
    Exit
   }
}
