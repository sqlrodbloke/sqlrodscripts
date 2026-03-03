# Install required modules (run once)
Install-Module -Name MicrosoftPowerBIMgmt -Force

#Import module
Import-Module -Name MicrosoftPowerBIMgmt 

#Connect to the Power BI Web Service - this will prompt for your user, you may need to authenticate
Connect-PowerBIServiceAccount


#Using Service Account

# Authenticate with Service Principal
$tenantId = "your-tenant-id"
$appId = "your-app-id"
$appSecret = "your-app-secret" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($appId, $appSecret)

Connect-PowerBIServiceAccount -ServicePrincipal -Credential $credential -Tenant $tenantId

# Then proceed with the password update as shown above



#List the gateways
$gateways = Invoke-PowerBIRestMethod -Url "gateways" -Method Get | ConvertFrom-Json
$gateways.value | Select-Object id, name, type


#From the gateway above - to see the connections you require. Just pass in the ID from the GW you want.


<#
63c50215-c6a0-4809-a755-a155c3f2b649 opdg-dv-powerbi-1-dc1 
c882e124-b20a-428b-acf5-b85a0adffa40 opdg-pr-powerbi-1-dc1 
#>

$gatewayId = "63c50215-c6a0-4809-a755-a155c3f2b649"

$datasources = Invoke-PowerBIRestMethod `
    -Url "gateways/$gatewayId/datasources" `
    -Method Get | ConvertFrom-Json

$datasources.value | Select-Object id, datasourceType, connectionDetails


#Get the public key of the GW
$gateway = Invoke-PowerBIRestMethod `
    -Url "gateways/$gatewayId" `
    -Method Get | ConvertFrom-Json

$publicKey = $gateway.publicKey


#Now add in the new creds - THIS PASSWORD SHOULD BE PULLED FROM A P/W VAULT.
Add-Type -AssemblyName System.Security

$username = "this_is_not_a_user_for_anywhere"
$password = "Nor_Is_this_a_password!"

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$encryptedCreds = New-Object Microsoft.PowerBI.Api.Models.CredentialDetails

$credentialDetails = @{
    credentialType = "Basic"
    credentials     = "{""credentialData"":[{""name"":""username"",""value"":""$username""},{""name"":""password"",""value"":""$password""}]}"
    encryptedConnection = "Encrypted"
    encryptionAlgorithm = "RSA-OAEP"
    privacyLevel = "None"
}



#Now add in the datasource, and set the credentials within it. Pass in the datasource ID of that requried - see above.
$datasourceId = "xxxxxxxxxxxxxxxxx"

Invoke-PowerBIRestMethod `
    -Url "gateways/$gatewayId/datasources/$datasourceId" `
    -Method Patch `
    -Body ($credentialDetails | ConvertTo-Json -Depth 5)