

# variables configured in form:
$entraidGUID = $form.gridUsers.Id
$displayName = $form.gridUsers.DisplayName
$employeeID = $form.gridUsers.employeeID

$currentUPN = $form.gridUsers.UserPrincipalName
$changeUpn = if ([string]::IsNullOrWhiteSpace($form.blnUPN)) { $false } else { [System.Convert]::ToBoolean($form.blnUPN) }
$newUPN = $form.NewUPN

$currentMail = $form.gridUsers.Mail
$currentMailNickname = $form.gridUsers.MailNickname
$changeMail = if ([string]::IsNullOrWhiteSpace($form.blnMail)) { $false } else { [System.Convert]::ToBoolean($form.blnMail) }
$newMail = $form.NewMail

# global variables (Automation --> Variable library):
# Outcommented as these are set from Global Variables
# $EntraIdTenantId = ''
# $EntraIdAppId = ''
# $EntraIdCertificateBase64String = ''
# $EntraIdCertificatePassword = ''
# $YouforceTenantId = ''
# $YouforceClientId = ''
# $YouforceClientSecret = ''

$YouforceAuthenticationUri = "https://connect.visma.com/connect/token"
$YouforceBaseUri = "https://api.youforce.com"

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region Entra ID functions
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
#endregion Entra ID functions

#region EntraID
try {
    $actionMessage = "updating Entra ID user"

    # Calculate mailnickname automatically from mail (part before @)
    $newMailNickname = if ($changeMail -and -not [string]::IsNullOrWhiteSpace($newMail)) { $newMail.Split("@")[0] }

    # Build account object dynamically based on what should be changed
    $account = [PSCustomObject]@{}

    if ($changeUpn) {
        $account | Add-Member -MemberType NoteProperty -Name 'userPrincipalName' -Value $newUPN
    }

    if ($changeMail) {
        $account | Add-Member -MemberType NoteProperty -Name 'mail' -Value $newMail
        $account | Add-Member -MemberType NoteProperty -Name 'mailNickname' -Value $newMailNickname
    }

    # Setup Connection with Entra/Exo
    Write-Verbose 'connecting to MS-Entra'
    $certificate = Get-MSEntraCertificate
    $entraToken = Get-MSEntraAccessToken -Certificate $certificate
    #Add the authorization header to the request
    $authorization = @{
        Authorization  = "Bearer $entraToken"
        'Content-Type' = "application/json"
        Accept         = "application/json"
    }

    $baseUpdateUri = "https://graph.microsoft.com/"
    $updateUri = $baseUpdateUri + "v1.0/users/$($entraidGUID)"
    $body = $account | ConvertTo-Json -Depth 10

    $null = Invoke-RestMethod -Uri $updateUri -Method PATCH -Headers $authorization -Body $body -Verbose:$false

    # Build success message based on what was changed
    $changedAttributes = @()
    if ($changeUpn) {
        $changedAttributes += "[userPrincipalName] from [$currentUPN] to [$newUPN]"
    }
    if ($changeMail) {
        $changedAttributes += "[mail] from [$currentMail] to [$newMail]"
        $changedAttributes += "[mailNickname] from [$($currentMailNickname)] to [$newMailNickname]"
    }
    $auditMessage = "Successfully updated Entra ID user [$displayName] attributes $($changedAttributes -join ' and ')"
    Write-Information $auditMessage
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default)
        System            = "Entra ID" # optional (free format text)
        Message           = $auditMessage
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error)
        TargetDisplayName = $displayName # optional (free format text)
        TargetIdentifier  = $([string]$entraidGUID) # optional (free format text)
    }
    #send result back
    Write-Information -Tags "Audit" -MessageData $log
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
    $Log = @{
        Action            = "UpdateAccount" # optional. ENUM (undefined = default)
        System            = "Entra ID" # optional (free format text)
        Message           = $auditMessage # required (free format text)
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error)
        TargetDisplayName = $displayName # optional (free format text)
        TargetIdentifier  = $([string]$entraidGUID) # optional (free format text)
    }
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
#endregion EntraID

#region Youforce functions
function Resolve-YouforceError {
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
        Write-Output $httpErrorObj
    }
}
#endregion Youforce functions

#region Youforce
# Only update Youforce if mail is being changed and employeeID is present
if ($changeMail -and -not ([string]::IsNullOrEmpty($employeeID))) {
    try {
        $actionMessage = "creating new session for Youforce API"
        $authorizationBody = @{
            'grant_type'    = "client_credentials"
            'client_id'     = $YouforceClientId
            'client_secret' = $YouforceClientSecret
            'tenant_id'     = $YouforceTenantId
        }

        $splatAccessTokenParams = @{
            Uri             = $YouforceAuthenticationUri
            Headers         = @{'Cache-Control' = "no-cache" }
            Method          = 'POST'
            ContentType     = "application/x-www-form-urlencoded"
            Body            = $authorizationBody
            UseBasicParsing = $true
        }
        Write-Verbose "Creating Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $result = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false
        if ($null -eq $result.access_token) {
            throw $result
        }

        $headers = @{
            'Authorization' = "Bearer $($result.access_token)"
            'Accept'        = "application/json"
        }
        Write-Verbose "Successfully created Access Token at uri '$($splatAccessTokenParams.Uri)'"

        $actionMessage = "retrieving correlated account from Youforce API for person [$employeeID]"
        $splatWebRequest = @{
            Uri             = "$YouforceBaseUri/iam/v1.0/persons/$($employeeID)"
            Headers         = $headers
            Method          = 'GET'
            ContentType     = "application/json"
            UseBasicParsing = $true
        }
        $correlatedAccount = Invoke-RestMethod @splatWebRequest

        if ($null -eq $correlatedAccount.id) {
            throw 'No employee found in Youforce'
        }

        $actionMessage = "checking and updating business email attribute in Youforce for person [$employeeID]"
        if ($null -ne $correlatedAccount.emailAddresses) {
            $businessEmailAddress = $correlatedAccount.emailAddresses | Where-Object { $_.type -eq "Business" }
            $businessEmailAddressOld = $businessEmailAddress.address
            if ([string]::IsNullOrEmpty($businessEmailAddressOld)) {
                $businessEmailAddressOld = ''
            }
        }
        else {
            $businessEmailAddressOld = ''
        }

        if ($businessEmailAddressOld -ne $newMail) {
            $body = [PSCustomObject]@{
                'emailAddress' = $newMail
            }
            $body = $body | ConvertTo-Json -Depth 10
            $splatWebRequest = @{
                Uri             = "$YouforceBaseUri/iam/v1.0/ContactDetails/$($correlatedAccount.personCode)"
                Headers         = $headers
                Method          = 'POST'
                Body            = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType     = "application/json;charset=utf-8"
                UseBasicParsing = $true
            }
            $null = Invoke-RestMethod @splatWebRequest

            $auditMessage = "Successfully updated Youforce personCode [$($correlatedAccount.personCode)] attributes [businessmail] from [$businessEmailAddressOld] to [$newMail]"
            Write-Information $auditMessage
            $Log = @{
                Action            = "UpdateAccount"
                System            = "Youforce"
                Message           = $auditMessage
                IsError           = $false
                TargetDisplayName = $displayName
                TargetIdentifier  = $correlatedAccount.personCode
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        else {
            $auditMessage = "Successfully checked Youforce person [$($correlatedAccount.personCode)] attributes [businessmail] [$businessEmailAddressOld], no changes needed"
            Write-Information $auditMessage
            $Log = @{
                Action            = "UpdateAccount"
                System            = "Youforce"
                Message           = $auditMessage
                IsError           = $false
                TargetDisplayName = $displayName
                TargetIdentifier  = $correlatedAccount.personCode
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
    }
    catch {
        $ex = $PSItem
        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-YouforceError -ErrorObject $ex
            $warningMessage = "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
            $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        }
        else {
            $warningMessage = "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        }
        $log = @{
            Action            = "UpdateAccount" # optional. ENUM (undefined = default)
            System            = "Youforce" # optional (free format text)
            Message           = $auditMessage # required (free format text)
            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error)
            TargetDisplayName = $displayName # optional (free format text)
            TargetIdentifier  = if ($null -ne $correlatedAccount.personCode) { $correlatedAccount.personCode } else { [string]$employeeID }
        }
        Write-Information -Tags "Audit" -MessageData $log
        Write-Warning $warningMessage
        Write-Error $auditMessage
    }
}
else {
    if (-not $changeMail) {
        $auditMessage = "Skipped update attributes [businessmail] of Youforce person [$displayName]: mail change not requested"
    }
    elseif ([string]::IsNullOrEmpty($employeeID)) {
        $auditMessage = "Skipped update attributes [businessmail] of Youforce person [$displayName] to [$newMail]: employeeID is empty"
    }
    else {
        $auditMessage = "Skipped update attributes [businessmail] of Youforce person [$displayName]"
    }

    Write-Information $auditMessage
    $Log = @{
        Action            = "UpdateAccount"
        System            = "Youforce"
        Message           = $auditMessage
        IsError           = $false
        TargetDisplayName = $displayName
        TargetIdentifier  = $([string]$employeeID)
    }
    Write-Information -Tags "Audit" -MessageData $log
}
#endregion Youforce

