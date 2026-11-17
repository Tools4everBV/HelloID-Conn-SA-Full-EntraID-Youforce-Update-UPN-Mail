# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Entra ID","User Management") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> EntraIdAppId
$tmpName = @'
EntraIdAppId
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> EntraIdCertificateBase64String
$tmpName = @'
EntraIdCertificateBase64String
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});

#Global variable #3 >> EntraIdCertificatePassword
$tmpName = @'
EntraIdCertificatePassword
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True"});

#Global variable #4 >> YouforceClientSecret
$tmpName = @'
YouforceClientSecret
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #5 >> EntraIdTenantId
$tmpName = @'
EntraIdTenantId
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #6 >> YouforceClientId
$tmpName = @'
YouforceClientId
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #7 >> YouforceTenantId
$tmpName = @'
YouforceTenantId
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}

        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }

        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
	Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "Entra-ID-Youforce-account-update-mail-upn | Entra-ID-Get-Active-Users-DisplayName-Mail-Upn" #>
$tmpPsScript = @'
# Variables configured in form
$searchValue = $datasource.searchValue
if ($searchValue -eq "*") {
    $filter = "`$filter=accountEnabled eq true or accountEnabled eq false" # Get all users
}
else {
    $filter = "`$search=`"displayName:$searchValue`" OR `"userPrincipalName:$searchValue`" OR `"mail:$searchValue`""
}

# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Fixed values
$propertiesToSelect = @(
    "id",
    "userPrincipalName",
    "displayName",
    "employeeID",
    "department",
    "jobTitle",
    "companyName",
    "mail",
    "mailNickname"
) # Properties to select from Microsoft Graph API, comma separated

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-MicrosoftGraphAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            elseif ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)"
            }
            elseif ($errorDetailsObject.error.details.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)"
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Certificate,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $AppId,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $TenantId
    )
    try {
        # Get the DER encoded bytes of the certificate
        $derBytes = $Certificate.RawData

        # Compute the SHA-256 hash of the DER encoded bytes
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($derBytes)
        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create a JWT (JSON Web Token) header
        $header = @{
            'alg'      = 'RS256'
            'typ'      = 'JWT'
            'x5t#S256' = $base64Thumbprint
        } | ConvertTo-Json
        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))

        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'
        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)

        # Create a JWT payload
        $payload = [Ordered]@{
            'iss' = "$($AppId)"
            'sub' = "$($AppId)"
            'aud' = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour
            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago
            'iat' = $currentUnixTimestamp
            'jti' = [Guid]::NewGuid().ToString()
        } | ConvertTo-Json
        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Extract the private key from the certificate
        $rsaPrivate = $Certificate.PrivateKey
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))

        # Sign the JWT
        $signatureInput = "$base64Header.$base64Payload"
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')
        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Ensure the certificate has a private key
        if (-not $Certificate.HasPrivateKey -or -not $Certificate.PrivateKey) {
            throw "The certificate does not have a private key."
        }

        # Create the JWT token
        $jwtToken = "$($base64Header).$($base64Payload).$($base64Signature)"

        $createEntraAccessTokenBody = @{
            grant_type            = 'client_credentials'
            client_id             = $AppId
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/token"
            Body        = $createEntraAccessTokenBody
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Verbose     = $false
            ErrorAction = 'Stop'
        }

        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams
        Write-Output $createEntraAccessTokenResponse.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"
    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword

    # Create access token
    $actionMessage = "creating access token"
    $entraToken = Get-MSEntraAccessToken -Certificate $certificate -AppId $EntraIdAppId -TenantId $EntraIdTenantId

    # Create headers
    $actionMessage = "creating headers"
    $headers = @{
        "Authorization"    = "Bearer $($entraToken)"
        "Accept"           = "application/json"
        "Content-Type"     = "application/json"
        "ConsistencyLevel" = "eventual" # Needed to filter on specific attributes (https://docs.microsoft.com/en-us/graph/aad-advanced-queries)
    }

    # Get Microsoft Entra ID Users
    # API docs: https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0&tabs=http
    $actionMessage = "querying Microsoft Entra ID Users matching search value [$searchValue]"
    $microsoftEntraIDUsers = [System.Collections.ArrayList]@()
    do {
        $getMicrosoftEntraIDUsersSplatParams = @{
            Uri         = "https://graph.microsoft.com/v1.0/users?$filter&`$select=$($propertiesToSelect -join ',')&`$top=999&`$count=true"
            Headers     = $headers
            Method      = "GET"
            Verbose     = $false
            ErrorAction = "Stop"
        }
        if (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDUsersResponse.'@odata.nextLink')) {
            $getMicrosoftEntraIDUsersSplatParams["Uri"] = $getMicrosoftEntraIDUsersResponse.'@odata.nextLink'
        }
        
        $getMicrosoftEntraIDUsersResponse = $null
        $getMicrosoftEntraIDUsersResponse = Invoke-RestMethod @getMicrosoftEntraIDUsersSplatParams
    
        # Select only specified properties to limit memory usage
        $getMicrosoftEntraIDUsersResponse.Value = $getMicrosoftEntraIDUsersResponse.Value | Select-Object $propertiesToSelect

        if ($getMicrosoftEntraIDUsersResponse.Value -is [array]) {
            [void]$microsoftEntraIDUsers.AddRange($getMicrosoftEntraIDUsersResponse.Value)
        }
        else {
            [void]$microsoftEntraIDUsers.Add($getMicrosoftEntraIDUsersResponse.Value)
        }
    } while (-not[string]::IsNullOrEmpty($getMicrosoftEntraIDUsersResponse.'@odata.nextLink'))
    Write-Information "Queried Microsoft Entra ID Users matching search value [$searchValue]. Result count: $(($microsoftEntraIDUsers | Measure-Object).count)"

    # Send results to HelloID
    $actionMessage = "sending results to HelloID"
    $microsoftEntraIDUsers | ForEach-Object {
        Write-Output $_
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
'@ 
$tmpModel = @'
[{"key":"id","type":0},{"key":"userPrincipalName","type":0},{"key":"displayName","type":0},{"key":"employeeId","type":0},{"key":"department","type":0},{"key":"jobTitle","type":0},{"key":"companyName","type":0},{"key":"mail","type":0},{"key":"mailNickname","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchValue","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
Entra-ID-Youforce-account-update-mail-upn | Entra-ID-Get-Active-Users-DisplayName-Mail-Upn
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "True" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "Entra-ID-Youforce-account-update-mail-upn | Entra-ID-Get-Active-Users-DisplayName-Mail-Upn" #>

<# Begin: DataSource "Entra-ID-Youforce-account-update-mail-upn | Entra-ID-Uniqueness-Validation" #>
$tmpPsScript = @'
#region init
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

$outputText = [System.Collections.Generic.List[PSCustomObject]]::new()

# Global variables
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# variables configured in form:
$userId = $dataSource.gridUsers.Id
$mailCurrent = $dataSource.gridUsers.Mail
$upnCurrent = $dataSource.gridUsers.userPrincipalName

$changeMail = if ([string]::IsNullOrWhiteSpace($dataSource.blnMail)) { $false } else { [System.Convert]::ToBoolean($dataSource.blnMail) }
$mailNew = $dataSource.NewMail
$changeUpn = if ([string]::IsNullOrWhiteSpace($dataSource.blnUPN)) { $false } else { [System.Convert]::ToBoolean($dataSource.blnUPN) }
$upnNew = $dataSource.NewUPN

# Calculate mailnickname automatically from mail (part before @)
$mailNicknameNew = if ($changeMail -and -not [string]::IsNullOrWhiteSpace($mailNew)) { $mailNew.Split("@")[0] } else { "" }
#endregion init

#region functions
function Get-MSEntraAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Certificate
    )
    try {
        # Get the DER encoded bytes of the certificate
        $derBytes = $Certificate.RawData

        # Compute the SHA-256 hash of the DER encoded bytes
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($derBytes)
        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Create a JWT (JSON Web Token) header
        $header = @{
            'alg'      = 'RS256'
            'typ'      = 'JWT'
            'x5t#S256' = $base64Thumbprint
        } | ConvertTo-Json
        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))

        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'
        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)

        # Create a JWT payload
        $payload = [Ordered]@{
            'iss' = "$EntraIdAppId"
            'sub' = "$EntraIdAppId"
            'aud' = "https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token"
            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour
            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago
            'iat' = $currentUnixTimestamp
            'jti' = [Guid]::NewGuid().ToString()
        } | ConvertTo-Json
        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')

        # Extract the private key from the certificate
        $rsaPrivate = $Certificate.PrivateKey
        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))

        # Sign the JWT
        $signatureInput = "$base64Header.$base64Payload"
        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')
        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')
	
        # Extract the private key from the certificate
        if (-not $Certificate.HasPrivateKey -or -not $Certificate.PrivateKey) {
            throw "The certificate does not have a private key."
        }

        # Create the JWT token
        $jwtToken = "$($base64Header).$($base64Payload).$($base64Signature)"

        $createEntraAccessTokenBody = @{
            grant_type            = 'client_credentials'
            client_id             = $EntraIdAppId
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion      = $jwtToken
            resource              = 'https://graph.microsoft.com'
        }

        $createEntraAccessTokenSplatParams = @{
            Uri         = "https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token"
            Body        = $createEntraAccessTokenBody
            Method      = 'POST'
            ContentType = 'application/x-www-form-urlencoded'
            Verbose     = $false
            ErrorAction = 'Stop'
        }

        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams
        Write-Output $createEntraAccessTokenResponse.access_token
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-MSEntraCertificate {
    [CmdletBinding()]
    param()
    try {
        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
function Resolve-MicrosoftGraphAPIError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            elseif ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)"
            }
            elseif ($errorDetailsObject.error.details.message) {
                $httpErrorObj.FriendlyMessage = "$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)"
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion functions

#region lookup
try {
    $actionMessage = "validating new UPN, mail, and mail nickname values"
    Write-Information "Validating new UPN, mail, and mail nickname values"

    if (-not ($changeMail -or $changeUpn)) {
        $outputText.Add([PSCustomObject]@{
                Message  = "Neither UPN nor mail change selected"
                IsError  = $true
                Property = "UPN/mail"
            })
    }

    if ($changeUpn -and $upnCurrent -eq $upnNew) {
        $outputText.Add([PSCustomObject]@{
                Message  = "UPN [$upnCurrent] not changed"
                IsError  = $true
                Property = "UPN"
            })
    } elseif ($changeUpn -and [string]::IsNullOrWhiteSpace($upnNew)) {
        $outputText.Add([PSCustomObject]@{
                Message  = "UPN [$upnCurrent] is empty"
                IsError  = $true
                Property = "UPN"
            })
    }

    if ($changeMail -and $mailCurrent -eq $mailNew) {
        $outputText.Add([PSCustomObject]@{
                Message  = "Mail [$mailCurrent] not changed"
                IsError  = $true
                Property = "mail"
            })
    } elseif ($changeMail -and [string]::IsNullOrWhiteSpace($mailNew)) {
        $outputText.Add([PSCustomObject]@{
                Message  = "Mail [$mailCurrent] is empty"
                IsError  = $true
                Property = "mail"
            })
    }
    
    if (-not($outputText.isError -contains $true)) {
        $actionMessage = "checking Entra ID for uniqueness"

        # Setup Connection with Entra/Exo
        Write-Information 'Checking Entra ID for uniqueness, connecting to MS-Entra'
        $certificate = Get-MSEntraCertificate
        $entraToken = Get-MSEntraAccessToken -Certificate $certificate
    
        #Add the authorization header to the request
        $authorization = @{
            Authorization  = "Bearer $entraToken";
            'Content-Type' = "application/json";
            Accept         = "application/json";
        } 

        $graphApiUrl = "https://graph.microsoft.com/v1.0/users"
        $select = '&$select=id,displayName,userPrincipalName,mail,mailNickname,proxyAddresses' + '&$top=999'
        
        # Build filter dynamically based on what's being changed
        $filterConditions = [System.Collections.Generic.List[string]]::new()
        if ($changeUpn) {
            $filterConditions.Add("userPrincipalName eq '$upnNew'")
            $filterConditions.Add("proxyAddresses/any(p:p eq '$upnNew')")
        }
        if ($changeMail) {
            $filterConditions.Add("mail eq '$mailNew'")
            $filterConditions.Add("proxyAddresses/any(p:p eq '$mailNew')")
            $filterConditions.Add("mailNickname eq '$mailNicknameNew'")
        }
        
        $filter = $filterConditions -join ' or '
        $searchUri = $graphApiUrl + '?$filter=' + $filter + $select

        $entraIDUserParams = @{
            Uri     = $searchUri
            Method  = 'Get'
            Headers = $authorization
            Verbose = $false
        }

        $entraIDUsersResponse = Invoke-RestMethod @entraIDUserParams

        $entraIDUsers = $entraIDUsersResponse.value
        while (![string]::IsNullOrEmpty($entraIDUsersResponse.'@odata.nextLink')) {
            $entraIDUsersResponse = Invoke-RestMethod -Uri $entraIDUsersResponse.'@odata.nextLink' -Method Get -Headers $authorization -Verbose:$false
            $entraIDUsers += $entraIDUsersResponse.value
        }  

        
        Write-Warning "user: [$($entraIDUsers | ConvertTo-Json)]"

        # Filter out the user that will be updated
        $filteredEntraIDUsers = $entraIDUsers | Where-Object { $_.id -ne $userId }

        Write-Warning "filteredUsers: [$($filteredEntraIDUsers | ConvertTo-Json)]"

        foreach ($record in $filteredEntraIDUsers) {
            if ($record.userPrincipalName -eq $upnNew -and $changeUpn) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "UPN [$upnNew] not unique, found on [$($record.displayName)]"
                        IsError  = $true
                        Property = "UPN"
                    })
            }
            if ($record.mail -eq $mailNew -and $changeMail) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "Mail [$mailNew] not unique, found on [$($record.displayName)]"
                        IsError  = $true
                        Property = "mail"
                    })
            }
            if ($record.mailNickname -eq $mailNicknameNew -and $changeMail) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "Mail nickname [$mailNicknameNew] not unique, found on [$($record.displayName)]"
                        IsError  = $true
                        Property = "mailNickname"
                    })
            }
            if ((($record.proxyAddresses -eq "SMTP:$mailNew") -or ($record.proxyAddresses -eq "smtp:$mailNew")) -and $changeMail) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "Proxy address [$mailNew] not unique, found on [$($record.displayName)]"
                        IsError  = $true
                        Property = "proxyAddresses"
                    })
            }
            if ((($record.proxyAddresses -eq "SMTP:$upnNew") -or ($record.proxyAddresses -eq "smtp:$upnNew")) -and $changeUpn) {
                $outputText.Add([PSCustomObject]@{
                        Message  = "Proxy address [$upnNew] not unique, found on [$($record.displayName)]"
                        IsError  = $true
                        Property = "proxyAddresses"
                    })
            }
            
        }
    }

    if ($outputText.isError -contains - $true) {
        $outputMessage = "Invalid:"
    }
    else {
        $outputMessage = "Valid:"
        if ($changeUpn) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "UPN [$upnNew] unique"
                    IsError  = $false
                    Property = "UPN"
                })
        }
        if ($changeMail) {
            $outputText.Add([PSCustomObject]@{
                    Message  = "Mail [$mailNew] unique"
                    IsError  = $false
                    Property = "mail"
                })
            $outputText.Add([PSCustomObject]@{
                    Message  = "Mail nickname [$mailNicknameNew] unique"
                    IsError  = $false
                    Property = "mailNickname"
                })
        }
    }

    foreach ($text in $outputText) {
        $outputMessage += "`n" + $($text.Message)
    }

    Write-Output $outputMessage      
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
}  
#endregion lookup
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"gridUsers","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"blnMail","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"NewMail","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"blnUPN","type":0,"options":0},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"NewUPN","type":0,"options":0}]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
Entra-ID-Youforce-account-update-mail-upn | Entra-ID-Uniqueness-Validation
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "True" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "Entra-ID-Youforce-account-update-mail-upn | Entra-ID-Uniqueness-Validation" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Entra ID Youforce Account - Update mail/upn" #>
$tmpSchema = @"
[{"label":"Select user account","fields":[{"key":"searchfield","templateOptions":{"label":"Search field (wildcard search in Display name, UserPrincipalName and mail)","placeholder":"Display name, UserPrincipalName, or mail (use * to search all users)","required":true,"minLength":1},"type":"input","summaryVisibility":"Hide element","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"gridUsers","templateOptions":{"label":"Select user account","required":true,"grid":{"columns":[{"headerName":"Employee Id","field":"employeeId"},{"headerName":"Display Name","field":"displayName"},{"headerName":"Mail","field":"mail"},{"headerName":"User Principal Name","field":"userPrincipalName"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchValue","otherFieldValue":{"otherFieldKey":"searchfield"}}]}},"useFilter":true,"useDefault":false,"searchPlaceHolder":"Search this data","allowCsvDownload":false},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Details","fields":[{"key":"blnMail","templateOptions":{"label":"Update email (including mail nickname)","useSwitch":true,"checkboxLabel":""},"type":"boolean","defaultValue":false,"summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"formRowMail","templateOptions":{},"fieldGroup":[{"key":"CurrentMail","templateOptions":{"label":"Current email address","useDataSource":false,"useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"mail","readonly":true},"hideExpression":"!model[\"blnMail\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"NewMail","templateOptions":{"label":"New Email Address","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"mail","pattern":"^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"},"validation":{"messages":{"pattern":"The entered value is not a valid email format."}},"hideExpression":"!model[\"blnMail\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"blnUPN","templateOptions":{"label":"Update user principal name","useSwitch":true,"checkboxLabel":""},"type":"boolean","defaultValue":false,"summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"formRowUPN","templateOptions":{},"fieldGroup":[{"key":"CurrentUPN","templateOptions":{"label":"Current user principal name","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"userPrincipalName","readonly":true},"hideExpression":"!model[\"blnUPN\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"NewUPN","templateOptions":{"label":"New user principal name","useDependOn":true,"dependOn":"gridUsers","dependOnProperty":"userPrincipalName","pattern":"^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"},"validation":{"messages":{"pattern":"The entered value is not a valid UPN format."}},"hideExpression":"!model[\"blnUPN\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"validate","templateOptions":{"label":"Validation","readonly":true,"useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[{"propertyName":"gridUsers","otherFieldValue":{"otherFieldKey":"gridUsers"}},{"propertyName":"blnMail","otherFieldValue":{"otherFieldKey":"blnMail"}},{"propertyName":"NewMail","otherFieldValue":{"otherFieldKey":"NewMail"}},{"propertyName":"blnUPN","otherFieldValue":{"otherFieldKey":"blnUPN"}},{"propertyName":"NewUPN","otherFieldValue":{"otherFieldKey":"NewUPN"}}]}},"displayField":"output","minLength":1,"pattern":"^Valid:[\\s\\S]*","required":true},"validation":{"messages":{"pattern":"No valid value"}},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Entra ID Youforce Account - Update mail/upn
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null} 
$delegatedFormName = @'
Entra ID Youforce Account - Update mail/upn
'@
$tmpTask = @'
{"name":"Entra ID Youforce Account - Update mail/upn","script":"\n\n# variables configured in form:\n$entraidGUID = $form.gridUsers.Id\n$displayName = $form.gridUsers.DisplayName\n$employeeID = $form.gridUsers.employeeID\n\n$currentUPN = $form.gridUsers.UserPrincipalName\n$changeUpn = if ([string]::IsNullOrWhiteSpace($form.blnUPN)) { $false } else { [System.Convert]::ToBoolean($form.blnUPN) }\n$newUPN = $form.NewUPN\n\n$currentMail = $form.gridUsers.Mail\n$currentMailNickname = $form.gridUsers.MailNickname\n$changeMail = if ([string]::IsNullOrWhiteSpace($form.blnMail)) { $false } else { [System.Convert]::ToBoolean($form.blnMail) }\n$newMail = $form.NewMail\n\n# global variables (Automation --> Variable library):\n# Outcommented as these are set from Global Variables\n# $EntraIdTenantId = ''\n# $EntraIdAppId = ''\n# $EntraIdCertificateBase64String = ''\n# $EntraIdCertificatePassword = ''\n# $YouforceTenantId = ''\n# $YouforceClientId = ''\n# $YouforceClientSecret = ''\n\n$YouforceAuthenticationUri = \"https://connect.visma.com/connect/token\"\n$YouforceBaseUri = \"https://api.youforce.com\"\n\n$VerbosePreference = \"SilentlyContinue\"\n$InformationPreference = \"Continue\"\n$WarningPreference = \"Continue\"\n\n#region Entra ID functions\nfunction Get-MSEntraAccessToken {\n    [CmdletBinding()]\n    param(\n        [Parameter(Mandatory)]\n        $Certificate\n    )\n    try {\n        # Get the DER encoded bytes of the certificate\n        $derBytes = $Certificate.RawData\n\n        # Compute the SHA-256 hash of the DER encoded bytes\n        $sha256 = [System.Security.Cryptography.SHA256]::Create()\n        $hashBytes = $sha256.ComputeHash($derBytes)\n        $base64Thumbprint = [System.Convert]::ToBase64String($hashBytes).Replace('+', '-').Replace('/', '_').Replace('=', '')\n\n        # Create a JWT (JSON Web Token) header\n        $header = @{\n            'alg'      = 'RS256'\n            'typ'      = 'JWT'\n            'x5t#S256' = $base64Thumbprint\n        } | ConvertTo-Json\n        $base64Header = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header))\n\n        # Calculate the Unix timestamp (seconds since 1970-01-01T00:00:00Z) for 'exp', 'nbf' and 'iat'\n        $currentUnixTimestamp = [math]::Round(((Get-Date).ToUniversalTime() - ([datetime]'1970-01-01T00:00:00Z').ToUniversalTime()).TotalSeconds)\n\n        # Create a JWT payload\n        $payload = [Ordered]@{\n            'iss' = \"$EntraIdAppId\"\n            'sub' = \"$EntraIdAppId\"\n            'aud' = \"https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token\"\n            'exp' = ($currentUnixTimestamp + 3600) # Expires in 1 hour\n            'nbf' = ($currentUnixTimestamp - 300) # Not before 5 minutes ago\n            'iat' = $currentUnixTimestamp\n            'jti' = [Guid]::NewGuid().ToString()\n        } | ConvertTo-Json\n        $base64Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)).Replace('+', '-').Replace('/', '_').Replace('=', '')\n\n        # Extract the private key from the certificate\n        $rsaPrivate = $Certificate.PrivateKey\n        $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()\n        $rsa.ImportParameters($rsaPrivate.ExportParameters($true))\n\n        # Sign the JWT\n        $signatureInput = \"$base64Header.$base64Payload\"\n        $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($signatureInput), 'SHA256')\n        $base64Signature = [System.Convert]::ToBase64String($signature).Replace('+', '-').Replace('/', '_').Replace('=', '')\n\n        # Extract the private key from the certificate\n        if (-not $Certificate.HasPrivateKey -or -not $Certificate.PrivateKey) {\n            throw \"The certificate does not have a private key.\"\n        }\n\n        # Create the JWT token\n        $jwtToken = \"$($base64Header).$($base64Payload).$($base64Signature)\"\n\n        $createEntraAccessTokenBody = @{\n            grant_type            = 'client_credentials'\n            client_id             = $EntraIdAppId\n            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'\n            client_assertion      = $jwtToken\n            resource              = 'https://graph.microsoft.com'\n        }\n\n        $createEntraAccessTokenSplatParams = @{\n            Uri         = \"https://login.microsoftonline.com/$EntraIdTenantId/oauth2/token\"\n            Body        = $createEntraAccessTokenBody\n            Method      = 'POST'\n            ContentType = 'application/x-www-form-urlencoded'\n            Verbose     = $false\n            ErrorAction = 'Stop'\n        }\n\n        $createEntraAccessTokenResponse = Invoke-RestMethod @createEntraAccessTokenSplatParams\n        Write-Output $createEntraAccessTokenResponse.access_token\n    }\n    catch {\n        $PSCmdlet.ThrowTerminatingError($_)\n    }\n}\n\nfunction Get-MSEntraCertificate {\n    [CmdletBinding()]\n    param()\n    try {\n        $rawCertificate = [system.convert]::FromBase64String($EntraIdCertificateBase64String)\n        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $EntraIdCertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)\n        Write-Output $certificate\n    }\n    catch {\n        $PSCmdlet.ThrowTerminatingError($_)\n    }\n}\nfunction Resolve-MicrosoftGraphAPIError {\n    [CmdletBinding()]\n    param (\n        [Parameter(Mandatory)]\n        [object]\n        $ErrorObject\n    )\n    process {\n        $httpErrorObj = [PSCustomObject]@{\n            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber\n            Line             = $ErrorObject.InvocationInfo.Line\n            ErrorDetails     = $ErrorObject.Exception.Message\n            FriendlyMessage  = $ErrorObject.Exception.Message\n        }\n        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {\n            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message\n        }\n        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {\n            if ($null -ne $ErrorObject.Exception.Response) {\n                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\n                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {\n                    $httpErrorObj.ErrorDetails = $streamReaderResponse\n                }\n            }\n        }\n        try {\n            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json -ErrorAction Stop)\n            if ($errorDetailsObject.error_description) {\n                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description\n            }\n            elseif ($errorDetailsObject.error.message) {\n                $httpErrorObj.FriendlyMessage = \"$($errorDetailsObject.error.code): $($errorDetailsObject.error.message)\"\n            }\n            elseif ($errorDetailsObject.error.details.message) {\n                $httpErrorObj.FriendlyMessage = \"$($errorDetailsObject.error.details.code): $($errorDetailsObject.error.details.message)\"\n            }\n            else {\n                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails\n            }\n        }\n        catch {\n            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails\n        }\n        Write-Output $httpErrorObj\n    }\n}\n#endregion Entra ID functions\n\n#region EntraID\ntry {\n    $actionMessage = \"updating Entra ID user\"\n\n    # Calculate mailnickname automatically from mail (part before @)\n    $newMailNickname = if ($changeMail -and -not [string]::IsNullOrWhiteSpace($newMail)) { $newMail.Split(\"@\")[0] }\n\n    # Build account object dynamically based on what should be changed\n    $account = [PSCustomObject]@{}\n\n    if ($changeUpn) {\n        $account | Add-Member -MemberType NoteProperty -Name 'userPrincipalName' -Value $newUPN\n    }\n\n    if ($changeMail) {\n        $account | Add-Member -MemberType NoteProperty -Name 'mail' -Value $newMail\n        $account | Add-Member -MemberType NoteProperty -Name 'mailNickname' -Value $newMailNickname\n    }\n\n    # Setup Connection with Entra/Exo\n    Write-Verbose 'connecting to MS-Entra'\n    $certificate = Get-MSEntraCertificate\n    $entraToken = Get-MSEntraAccessToken -Certificate $certificate\n    #Add the authorization header to the request\n    $authorization = @{\n        Authorization  = \"Bearer $entraToken\"\n        'Content-Type' = \"application/json\"\n        Accept         = \"application/json\"\n    }\n\n    $baseUpdateUri = \"https://graph.microsoft.com/\"\n    $updateUri = $baseUpdateUri + \"v1.0/users/$($entraidGUID)\"\n    $body = $account | ConvertTo-Json -Depth 10\n\n    $null = Invoke-RestMethod -Uri $updateUri -Method PATCH -Headers $authorization -Body $body -Verbose:$false\n\n    # Build success message based on what was changed\n    $changedAttributes = @()\n    if ($changeUpn) {\n        $changedAttributes += \"[userPrincipalName] from [$currentUPN] to [$newUPN]\"\n    }\n    if ($changeMail) {\n        $changedAttributes += \"[mail] from [$currentMail] to [$newMail]\"\n        $changedAttributes += \"[mailNickname] from [$($currentMailNickname)] to [$newMailNickname]\"\n    }\n    $auditMessage = \"Successfully updated Entra ID user [$displayName] attributes $($changedAttributes -join ' and ')\"\n    Write-Information $auditMessage\n    $Log = @{\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default)\n        System            = \"Entra ID\" # optional (free format text)\n        Message           = $auditMessage\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error)\n        TargetDisplayName = $displayName # optional (free format text)\n        TargetIdentifier  = $([string]$entraidGUID) # optional (free format text)\n    }\n    #send result back\n    Write-Information -Tags \"Audit\" -MessageData $log\n}\ncatch {\n    $ex = $PSItem\n    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or\n        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\n        $errorObj = Resolve-MicrosoftGraphAPIError -ErrorObject $ex\n        $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\n        $warningMessage = \"Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\n    }\n    else {\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\n    }\n    $Log = @{\n        Action            = \"UpdateAccount\" # optional. ENUM (undefined = default)\n        System            = \"Entra ID\" # optional (free format text)\n        Message           = $auditMessage # required (free format text)\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error)\n        TargetDisplayName = $displayName # optional (free format text)\n        TargetIdentifier  = $([string]$entraidGUID) # optional (free format text)\n    }\n    Write-Information -Tags \"Audit\" -MessageData $log\n    Write-Warning $warningMessage\n    Write-Error $auditMessage\n}\n#endregion EntraID\n\n#region Youforce functions\nfunction Resolve-YouforceError {\n    [CmdletBinding()]\n    param (\n        [Parameter(Mandatory)]\n        [object]\n        $ErrorObject\n    )\n    process {\n        $httpErrorObj = [PSCustomObject]@{\n            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber\n            Line             = $ErrorObject.InvocationInfo.Line\n            ErrorDetails     = $ErrorObject.Exception.Message\n            FriendlyMessage  = $ErrorObject.Exception.Message\n        }\n        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {\n            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message\n        }\n        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {\n            if ($null -ne $ErrorObject.Exception.Response) {\n                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()\n                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {\n                    $httpErrorObj.ErrorDetails = $streamReaderResponse\n                }\n            }\n        }\n        Write-Output $httpErrorObj\n    }\n}\n#endregion Youforce functions\n\n#region Youforce\n# Only update Youforce if mail is being changed and employeeID is present\nif ($changeMail -and -not ([string]::IsNullOrEmpty($employeeID))) {\n    try {\n        $actionMessage = \"creating new session for Youforce API\"\n        $authorizationBody = @{\n            'grant_type'    = \"client_credentials\"\n            'client_id'     = $YouforceClientId\n            'client_secret' = $YouforceClientSecret\n            'tenant_id'     = $YouforceTenantId\n        }\n\n        $splatAccessTokenParams = @{\n            Uri             = $YouforceAuthenticationUri\n            Headers         = @{'Cache-Control' = \"no-cache\" }\n            Method          = 'POST'\n            ContentType     = \"application/x-www-form-urlencoded\"\n            Body            = $authorizationBody\n            UseBasicParsing = $true\n        }\n        Write-Verbose \"Creating Access Token at uri '$($splatAccessTokenParams.Uri)'\"\n\n        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false\n        if ($null -eq $result.access_token) {\n            throw $result\n        }\n\n        $headers = @{\n            'Authorization' = \"Bearer $($result.access_token)\"\n            'Accept'        = \"application/json\"\n        }\n        Write-Verbose \"Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'\"\n\n        $actionMessage = \"retrieving correlated account from Youforce API for person [$employeeID]\"\n        $splatWebRequest = @{\n            Uri             = \"$YouforceBaseUri/iam/v1.0/persons/$($employeeID)\"\n            Headers         = $headers\n            Method          = 'GET'\n            ContentType     = \"application/json\"\n            UseBasicParsing = $true\n        }\n        $correlatedAccount = Invoke-RestMethod @splatWebRequest\n\n        if ($null -eq $correlatedAccount.id) {\n            throw 'No employee found in Youforce'\n        }\n\n        $actionMessage = \"checking and updating business email attribute in Youforce for person [$employeeID]\"\n        if ($null -ne $correlatedAccount.emailAddresses) {\n            $businessEmailAddress = $correlatedAccount.emailAddresses | Where-Object { $_.type -eq \"Business\" }\n            $businessEmailAddressOld = $businessEmailAddress.address\n            if ([string]::IsNullOrEmpty($businessEmailAddressOld)) {\n                $businessEmailAddressOld = ''\n            }\n        }\n        else {\n            $businessEmailAddressOld = ''\n        }\n\n        if ($businessEmailAddressOld -ne $newMail) {\n            $body = [PSCustomObject]@{\n                'emailAddress' = $newMail\n            }\n            $body = $body | ConvertTo-Json -Depth 10\n            $splatWebRequest = @{\n                Uri             = \"$YouforceBaseUri/iam/v1.0/ContactDetails/$($correlatedAccount.personCode)\"\n                Headers         = $headers\n                Method          = 'POST'\n                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))\n                ContentType     = \"application/json;charset=utf-8\"\n                UseBasicParsing = $true\n            }\n            $null = Invoke-RestMethod @splatWebRequest\n\n            $auditMessage = \"Successfully updated Youforce personCode [$($correlatedAccount.personCode)] attributes [businessmail] from [$businessEmailAddressOld] to [$newMail]\"\n            Write-Information $auditMessage\n            $Log = @{\n                Action            = \"UpdateAccount\"\n                System            = \"Youforce\"\n                Message           = $auditMessage\n                IsError           = $false\n                TargetDisplayName = $displayName\n                TargetIdentifier  = $correlatedAccount.personCode\n            }\n            Write-Information -Tags \"Audit\" -MessageData $log\n        }\n        else {\n            $auditMessage = \"Successfully checked Youforce person [$($correlatedAccount.personCode)] attributes [businessmail] [$businessEmailAddressOld], no changes needed\"\n            Write-Information $auditMessage\n            $Log = @{\n                Action            = \"UpdateAccount\"\n                System            = \"Youforce\"\n                Message           = $auditMessage\n                IsError           = $false\n                TargetDisplayName = $displayName\n                TargetIdentifier  = $correlatedAccount.personCode\n            }\n            Write-Information -Tags \"Audit\" -MessageData $log\n        }\n    }\n    catch {\n        $ex = $PSItem\n        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or\n            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\n            $errorObj = Resolve-YouforceError -ErrorObject $ex\n            $warningMessage = \"Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)\"\n            $auditMessage = \"Error $($actionMessage). Error: $($errorObj.FriendlyMessage)\"\n        }\n        else {\n            $warningMessage = \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\n            $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\n        }\n        $log = @{\n            Action            = \"UpdateAccount\" # optional. ENUM (undefined = default)\n            System            = \"Youforce\" # optional (free format text)\n            Message           = $auditMessage # required (free format text)\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error)\n            TargetDisplayName = $displayName # optional (free format text)\n            TargetIdentifier  = if ($null -ne $correlatedAccount.personCode) { $correlatedAccount.personCode } else { [string]$employeeID }\n        }\n        Write-Information -Tags \"Audit\" -MessageData $log\n        Write-Warning $warningMessage\n        Write-Error $auditMessage\n    }\n}\nelse {\n    if (-not $changeMail) {\n        $auditMessage = \"Skipped update attributes [businessmail] of Youforce person [$displayName]: mail change not requested\"\n    }\n    elseif ([string]::IsNullOrEmpty($employeeID)) {\n        $auditMessage = \"Skipped update attributes [businessmail] of Youforce person [$displayName] to [$newMail]: employeeID is empty\"\n    }\n    else {\n        $auditMessage = \"Skipped update attributes [businessmail] of Youforce person [$displayName]\"\n    }\n\n    Write-Information $auditMessage\n    $Log = @{\n        Action            = \"UpdateAccount\"\n        System            = \"Youforce\"\n        Message           = $auditMessage\n        IsError           = $false\n        TargetDisplayName = $displayName\n        TargetIdentifier  = $([string]$employeeID)\n    }\n    Write-Information -Tags \"Audit\" -MessageData $log\n}\n#endregion Youforce\n","runInCloud":true}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-envelope" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

