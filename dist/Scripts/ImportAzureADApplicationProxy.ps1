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

.PARAMETER TargetAppId
The Application (client) ID of the Enterprise Application whose certificate should be updated.
Find this value in Entra ID > Enterprise Applications > <your app> > Application ID.

.EXAMPLE

ImportAzureApplicationProxy.ps1 <PfxPath> <CertPass> <TenantId> <ClientId> <ClientSecret> <TargetAppId>

.NOTES
Authentication uses the OAuth 2.0 client credentials flow via Connect-MgGraph -ClientSecretCredential,
which requires Microsoft.Graph module v2.0 or later:
  Install-Module Microsoft.Graph -Scope AllUsers


#>

#Requires -Version 7.4
#Requires -Modules @{ ModuleName = "Microsoft.Graph.Authentication";    ModuleVersion = "2.0"  }
#Requires -Modules @{ ModuleName = "Microsoft.Graph.Applications";      ModuleVersion = "2.0"  }
#Requires -Modules @{ ModuleName = "Microsoft.Graph.Beta.Applications"; ModuleVersion = "2.10" }

param(
    [Parameter(Position=0,Mandatory=$false)][string]$PfxPath,
    [Parameter(Position=1,Mandatory=$true)][string]$CertPass,
    [Parameter(Position=2,Mandatory=$true)][string]$TenantId,
    [Parameter(Position=3,Mandatory=$true)][string]$ClientId,
    [Parameter(Position=4,Mandatory=$true)][string]$ClientSecret,
    [Parameter(Position=5,Mandatory=$true)][string]$TargetAppId
)

# Connect to Microsoft Graph using client credentials (application secret)
$SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $SecureSecret
$null = Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential -NoWelcome


$app = Get-MgApplication -Filter "AppId eq '$TargetAppId'" -ErrorAction Stop
if (-not $app) { Throw "No application found with Application ID '$TargetAppId'." }
"Targeting application: $($app.DisplayName)"

$appDetail = Get-MgBetaApplication -ApplicationId $app.Id -Select DisplayName,AppId,Id,OnPremisesPublishing
Write-Host "External URL : $($appDetail.OnPremisesPublishing.ExternalUrl)"
Write-Host "Current certificate:"
$appDetail.OnPremisesPublishing.VerifiedCustomDomainCertificatesMetadata

$certParams = @{
    onPremisesPublishing = @{
        verifiedCustomDomainKeyCredential = @{
            type  = "X509CertAndPassword"
            value = [convert]::ToBase64String([System.IO.File]::ReadAllBytes($PfxPath))
        }
        verifiedCustomDomainPasswordCredential = @{
            value = $CertPass
        }
    }
}

"Updating certificate for $($app.DisplayName)"
Update-MgBetaApplication -ApplicationId $app.Id -BodyParameter $certParams


Disconnect-MgGraph
