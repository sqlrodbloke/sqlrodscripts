
param(
    [Parameter(Mandatory=$true)] [string]$TargetSQLserver,
    [Parameter(Mandatory=$true)] [string]$TargetSQLDB, 
    [Parameter(Mandatory=$false)] [string]$TargetSQLTable="dbo.SQLPatch", 
    [Parameter(Mandatory=$false)] [string]$patchfilebasepath="C:\Temp\SqlServerBuildDL")


Add-Type -Assembly System.Web 


<#
Usage: .\Get-SQLPatchVersions.ps1 -TargetSQLserver MyInventoryServer -TargetSQLDB Inventory -patchfilebasepath c:\temp\SqlServerBuildDL

.\Get-SQLPatchVersions.ps1 -TargetSQLserver localhost -TargetSQLDB Inventory -patchfilebasepath c:\temp\SqlServerBuildDL
#>



try {


    $SqlVersion = "2008", "2008 R2", "2012", "2014", "2016", "2017","2019","2022"
 #   $SqlVersion = "2008 R2"
    Write-Host "Pulling Master SQL Version basic info from MS" -ForegroundColor Cyan
    

    #Get info from MS pages - use this for stripping SP/CU levels later
    $urlm = "https://learn.microsoft.com/en-us/troubleshoot/sql/releases/download-and-install-latest-updates#sql-server-complete-version-list-tables";
    $html = (Invoke-WebRequest -Uri $urlm -UseBasicParsing).Content;


    Write-Host "Clearing target table." -ForegroundColor Cyan
    $sqlStmt="TRUNCATE TABLE $TargetSQLTable"
    Invoke-Sqlcmd -ServerInstance $TargetSQLserver -Database $TargetSQLDB -Query $sqlStmt -QueryTimeout 15 -ConnectionTimeout 15 -TrustServerCertificate

    Write-Host "Pulling additional info from Blogpsot Google doc csv" -ForegroundColor Cyan          

    ForEach ($version in $SqlVersion){
    
        $Query = "select * where A='" + $version + "'"
        $patchfilepath=$patchfilebasepath+$Version+'.csv'
        $URLb   = "https://docs.google.com/spreadsheets/d/16Ymdz80xlCzb6CwRFVokwo0onkofVYFoSkc7mYe6pgw/gviz/tq?tq=" `
               + [System.Web.HttpUtility]::UrlEncode($Query) `
            + "&tqx=out:csv"
        Invoke-WebRequest $URLb -OutFile $patchfilepath

        #Import this into CSV format
        $patchinfo=Import-csv $patchfilepath 

        Write-Host "Merging results for $version, extracting SP/CU numbers and loading to SQL table" -ForegroundColor Cyan    

        #Loop through each patch line.
        ForEach ($patch in $patchinfo){
            $index =$null
            $sp=$null
            $cu=$null
            #Tidy killer characters
            $patch.Description=($patch.Description).Replace("'","")

 
            #Now we want to strip out the SP and CU numbers for the patch, we use the MS data for this.
             
                If ($($patch.Version) -eq '10.0') {$searchVersion = $($patch.Build).Replace('.0.','.00.')}
                Else {$searchVersion = $($patch.Build)}


                # find the version text
                $index = $html.IndexOf("<td>$searchVersion</td>");

                if ($index -ne -1) {
                    # find the start of the containing "<tr>"
                    $tr = $html.LastIndexOf("<tr>", $index);

                    # find the text inside the following "<tr>" plus its length
                    $start = $html.IndexOf("<tr>", $tr) + "<tr>".Length;
                    $end = $html.IndexOf("</tr>", $tr);
                    $name = $html.Substring($start, $end - $start);


                    $extract=$name.replace('<td>','') -split "</td>"

                    $detail=@()
                    Foreach ($line in $extract.Trim()){
                        $detail += $line
                    }

                    <# If you want the base detail from MS -just use
                        $build=$detail[0]
                        $sp=$detail[1]
                        $su=$detail[2]
                        $link=$detail[3]
                        $ReleaseDate=$detail[4]
                    #>

                    #Parse CU and SP values
                    $sp=If ($detail[1] -match '^SP[1-9]') {$detail[1].Substring(2,1)}           
            
             
                    $cu=If ($detail[2] -match '^CU[1-9][0-9]') {$detail[2].Substring(2,2)} 
                    If ($cu -eq $null) {
                        $cu=If ($detail[2] -match '^CU[1-9]') {$detail[2].Substring(2,1)}
                    }
                 }

                #Build statement to drop it into SQL
                $sqlStmt="INSERT INTO $TargetSQLTable (SQLServer, Version, Build, SP, CU, FileVersion, Description, Link, ReleaseDate, isSP, isCU, isHF, isRTM, isCTP, isSU, New, TargetVersion, Withdrawn)
                        VALUES ('$($patch.sqlServer)', 
                                '$($patch.Version)',
                                '$($patch.Build)',
                                '$sp',
		                        '$cu',
                                '$($patch.FileVersion)', 
                                '$($patch.Description)',
                                '$($patch.Link)',
                                '$($patch.ReleaseDate)',
                                '$($patch.SP)',
                                '$($patch.CU)',
                                '$($patch.HF)',
                                '$($patch.RTM)',
                                '$($patch.CTP)',
                                 NULL, 
                                '$($patch.New)',
                                NULL,
                                '$($patch.Withdrawn)')"

                    Invoke-Sqlcmd -ServerInstance $TargetSQLserver -Database $TargetSQLDB -Query $sqlStmt -QueryTimeout 15 -ConnectionTimeout 15 -TrustServerCertificate


           
 
                }  
    
    }

     Write-host "Tidying dirty data" -ForegroundColor Cyan

            $sqlstmt="UPDATE $TargetSQLTable SET isSU=CASE WHEN Description LIKE '%Security Update%' THEN 1 ELSE 0 END;
                      UPDATE $TargetSQLTable SET CU= CASE WHEN Description LIKE '%(CU%' THEN SUBSTRING(Description, CHARINDEX('(CU',Description)+3, (CHARINDEX(')',Description)-1)-(CHARINDEX('(CU',Description)+2)) END WHERE isCU=1 and CU=0;
                      UPDATE $TargetSQLTable SET SP=CASE WHEN Description LIKE '%Service Pack%' THEN SUBSTRING(Description, CHARINDEX('Service Pack', Description)+13,(CHARINDEX('(', Description))-(CHARINDEX('Service Pack', Description)+13) ) END WHERE isSP =1 and SP=0;"

            Invoke-Sqlcmd -ServerInstance $TargetSQLserver -Database $TargetSQLDB -Query $sqlStmt -QueryTimeout 15 -ConnectionTimeout 15 -TrustServerCertificate
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
}





<#

CREATE TABLE dbo.SQLPatch (
	SQLServer varchar(10),
	Version varchar(10),
	Build varchar(15),
	SP tinyint,
	CU tinyint,
	FileVersion varchar(20),
	Description varchar(500),
	Link varchar(200),
	ReleaseDate date,
	isSP bit,
	isCU bit,
	isHF bit,
	isRTM bit,
	isCTP bit,
    isSU bit,
	New bit,
	TargetVersion bit,
	Withdrawn bit,
)

UPDATE dbo.SQLPatch SET isSU=1 WHERE Description LIKE '%Security Update%'

UPDATE dbo.SQLPatch
SET CU= CASE WHEN Description LIKE '%(CU%' THEN SUBSTRING(Description, CHARINDEX('(CU',Description)+3, (CHARINDEX(')',Description)-1)-(CHARINDEX('(CU',Description)+2)) END
WHERE isCU=1 and CU=0

UPDATE dbo.SQLPatch
 SET SP=CASE WHEN Description LIKE '%Service Pack%' THEN SUBSTRING(Description, CHARINDEX('Service Pack', Description)+13,(CHARINDEX('(', Description))-(CHARINDEX('Service Pack', Description)+13) ) END
 where isSP =1 and SP=0 


#>
