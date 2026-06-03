<#
.SYNOPSIS
Imports a cert from win-acme (WACS) renewal into Azure AD Application Proxy for all applications that are using it. You likely want to use a wildcard certificate for this purpose.

.DESCRIPTION
Note that this script is intended to be run via the install script plugin from win-acme (WACS) via the batch script wrapper. As such, we use positional parameters to avoid issues with using a dash in the cmd line. 

Proper information should be available here

https://simple-acme.com/reference/plugins/installation/script

or more generally, here

https://simple-acme.com/manual/advanced-use/examples/

.PARAMETER PfxPath
The absolute path to the pfx file that will be uploaded to Azure. Typically use '{CacheFile}'

.PARAMETER CertPass
The password for the pfx file. Typically use '{CachePassword}'

.PARAMETER TenantId
The Azure AD tenant ID (GUID).

.PARAMETER ClientId
The application (client) ID of the app registration used to authenticate. The app must have the
'Application.ReadWrite.All' application permission granted and admin-consented in the tenant.

.PARAMETER ClientSecret
The client secret of the app registration.

.EXAMPLE

ImportAzureApplicationProxy.ps1 <PfxPath> <CertPass> <TenantId> <ClientId> <ClientSecret>

.NOTES
Authentication uses the OAuth 2.0 client credentials flow via Connect-MgGraph -ClientSecretCredential,
which requires Microsoft.Graph module v2.0 or later:
  Install-Module Microsoft.Graph -Scope AllUsers


#>

param(
    [Parameter(Position=0,Mandatory=$false)][string]$PfxPath,
    [Parameter(Position=1,Mandatory=$true)][string]$CertPass,
    [Parameter(Position=2,Mandatory=$true)][string]$TenantId,
    [Parameter(Position=3,Mandatory=$true)][string]$ClientId,
    [Parameter(Position=4,Mandatory=$true)][string]$ClientSecret
)

# Convert the password for the certificate to a secure string
$SecureCertPass = ConvertTo-SecureString -String $CertPass -AsPlainText -Force


if (!(Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Throw "Missing Microsoft.Graph module, install with 'Install-Module -Name Microsoft.Graph -Scope AllUsers'"
}

# Connect to Microsoft Graph using client credentials (application secret)
$SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecureSecret
$null = Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome


# It's easier, apparently, to search for the service principals that are tagged with WindowsAzureActiveDirectoryOnPremApp,
# then match them to the Get-AzureADApplication output by AppId.
# Get-AzureADApplication doesn't have any way to filter only for ones using the application proxy, and 
# Get-AzureADApplicationProxyApplication requires an ObjectId, there's no way to just list them all.
$aadapServPrinc = Get-MgServicePrincipal -Property Displayname,Id,Appid,Tags -All | where-object {$_.Tags -Contains "WindowsAzureActiveDirectoryOnPremApp"}

# Now we get a list of all Azure AD Applications
$aadapps = Get-MgApplication -All | Sort-Object -Property AppId

# The AppId between $aadapServPrinc and $aadapps is the same for each of the applications using Azure AD Application Proxy.
# What we need to get is the ObjectId from $aadapps for each application that was in $aadapServPrinc
$aadProxyApps = New-Object System.Collections.ArrayList
#$aadproxyapps = $aadapServPrinc | Foreach-Object { $aadapps -match $_.AppId}
foreach ($Principal in $aadapServPrinc){
    write-host $Principal.AppId
    foreach($App in $aadapps){
       if($Principal.AppId -eq $App.AppId){
            $aadProxyApps.add($App)
        }
    }
}
# Now $aadaproxyapps has just the Get-MgApplication objects for applications that use the Azure AD Application Proxy.

"Found $($aadproxyapps.count) applications to update"

# Get the matching objects from Get-AzureADApplicationProxyApplication and show the certificate being used
#$aadproxyapps | Foreach-Object { 
foreach($proxyApp in $aadproxyapps){
    $proxyapp = Get-MgBetaApplication -ApplicationId $ProxyApp.Id -Select DisplayName,AppId,Id,OnPremisesPublishing
    Write-Host "Checking $($proxyapp.OnPremisesPublishing.ExternalUrl)"
    Write-Host "Existing certificate is:"
    $($proxyapp.OnPremisesPublishing.VerifiedCustomDomainCertificatesMetadata)
#    
}

# The documentation says "If you have one certificate that includes many of your applications, you only need to upload it with one application and it will also be assigned to the other relevant applications."
# That does not seem to be the case. Updating the certificate for one application only updated that single application, the rest keep using the old certificate.
# Perhaps it just takes a bit to update, but I thought it safer to just update all of them.

$aadproxyapps | Foreach-Object {
    "Updating certificate for $($_.DisplayName)"
    Set-AzureADApplicationProxyApplicationCustomDomainCertificate -ObjectId $_.ObjectId -PfxFilePath $PfxPath -Password $SecureCertPass
}


Disconnect-MgGraph
