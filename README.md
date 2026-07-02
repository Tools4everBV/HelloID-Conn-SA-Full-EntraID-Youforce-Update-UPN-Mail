# HelloID-Conn-SA-Full-EntraID-Youforce-Update-UPN-Mail

| :information_source: Information |
| :------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

HelloID-Conn-SA-Full-EntraID-Youforce-Update-UPN-Mail is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can update User Principal Name (UPN), Mail, and Mail Nickname attributes in Microsoft Entra ID and business email details in Youforce. The following options are available:

1. Search and select the target user from Entra ID
2. Enter new values for UPN and/or Mail
3. Mail Nickname is automatically calculated from the mail address (part before @)
4. Validate uniqueness in Entra ID for userPrincipalName, mail, mailNickname, and proxyAddresses
5. Update UserPrincipalName, Mail, and MailNickname in Entra ID
6. Update business email details in Youforce when a matching employee is found

## Getting started

### Requirements

#### App Registration and certificate setup

Before implementing this connector, configure a Microsoft Entra ID App Registration. During setup, create an App Registration in the Entra portal, assign the necessary API permissions, and generate and assign a certificate.

Follow Microsoft documentation for setting up certificate-based authentication:

- [App-only authentication with certificate (Exchange Online)](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps#set-up-app-only-authentication)

#### Youforce setup

Ensure Youforce is configured with:

- Youforce tenant id
- Youforce client id
- Youforce client secret
- Access to the Youforce IAM API

#### HelloID-specific configuration

Once you have completed the Microsoft and Youforce setup, configure the following HelloID-specific requirements:

- API permissions (application permissions):
	- `User.ReadWrite.All`
- Configure the user-defined variables listed in Connection settings
- Import and configure the delegated form and task scripts

#### Convert .pfx to base64 string

HelloID requires a base64 string to import the certificate. With the example below, it is possible to create a base64 string:

```powershell
$filePath = 'C:\Cert'
$pfxCertName = 'Cert.pfx'
$pfxPath = "$filePath\$pfxCertName"

$fileContentBytes = [System.IO.File]::ReadAllBytes("$pfxPath")
[System.Convert]::ToBase64String($fileContentBytes) | Set-Content "$filePath\HelloID_Cert_Base64.txt"
```

### Connection settings

The following user-defined variables are used by the connector and should be configured in HelloID Service Automation (Automation -> Variable library).

#### Entra ID settings

| Setting                        | Description                                                        | Required |
| ------------------------------ | ------------------------------------------------------------------ | -------- |
| EntraIdTenantId                | The Tenant ID of your Entra ID environment                         | Yes      |
| EntraIdAppId                   | The Application (Client) ID of the App Registration                | Yes      |
| EntraIdCertificateBase64String | The certificate as a base64-encoded string (including private key) | Yes      |
| EntraIdCertificatePassword     | The password for the certificate                                   | Yes      |

#### Youforce settings

| Variable Name        | Description                                                             | Required |
| -------------------- | ----------------------------------------------------------------------- | -------- |
| YouforceClientid     | The Youforce client id used to authenticate to the Youforce IAM API     | Yes      |
| YouforceClientsecret | The Youforce client secret used to authenticate to the Youforce IAM API | Yes      |
| Youforcetenantid     | The Youforce tenant id used during OAuth token retrieval                | Yes      |

## Remarks

### Conditional updates

- Boolean controls: the form includes boolean checkboxes (`blnUPN` and `blnMail`) that allow users to selectively choose which attributes to update. Only selected attributes are sent to Entra ID.
- Youforce updates: Youforce updates are only executed when a mail change is requested (`blnMail` is true) and a matching employee correlation is found.

### Uniqueness validation

- The form validates uniqueness for UPN and Mail before updating.
- Validation checks Entra ID `userPrincipalName`, `mail`, `mailNickname`, and `proxyAddresses`.
- The selected user itself is excluded from the uniqueness check.

### Mail Nickname auto-calculation

- Mail Nickname is automatically calculated from the local part of the new mail address (before @).
- Users do not directly enter Mail Nickname.

### ProxyAddresses behavior

- When the primary SMTP value changes, the previous primary address (`SMTP:`) is converted to an alias (`smtp:`).
- This preserves historical aliases while setting the new primary address.

### Youforce employee matching

- Youforce updates depend on a valid employee correlation between Entra ID and Youforce.
- If no matching Youforce employee is found, Youforce updates are skipped while Entra ID updates can still proceed.

### Youforce target objects

- Youforce person contact details endpoint is used to update business email details.
- Optional identity updates can be handled through the Youforce IAM users identity endpoint.

## Development resources

### Endpoints and operations

The following operations are used by the connector:

| Operation                                                     | Purpose                                                    |
| ------------------------------------------------------------- | ---------------------------------------------------------- |
| Microsoft Graph API (/v1.0/users)                            | Search and retrieve Entra ID users                         |
| Microsoft Graph API (/v1.0/users/{id})                        | Update UPN, mail, mailNickname, and proxyAddresses         |
| https://connect.visma.com/connect/token                       | Retrieve OAuth access token for Youforce                   |
| https://api.youforce.com/iam/v1.0/persons/{EmployeeID}        | Retrieve correlated Youforce person                        |
| https://api.youforce.com/iam/v1.0/ContactDetails/{PersonCode} | Update Youforce business email details                     |

### API and cmdlet documentation

- Microsoft Graph API: https://learn.microsoft.com/en-us/graph/api/overview
- Microsoft Graph Users API: https://learn.microsoft.com/en-us/graph/api/resources/user
- Visma Youforce IAM API documentation: https://oauth.developers.visma.com

## Getting help

> [!TIP]
> _For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/