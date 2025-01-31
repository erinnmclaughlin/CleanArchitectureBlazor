@description('The location into which your Azure resources should be deployed.')
param location string = resourceGroup().location

@description('Select the type of environment you want to provision. Allowed values are Production and Test.')
@allowed([
  'Production'
  'Test'
])
param environmentType string

@description('A unique suffix to add to resource names that need to be globally unique.')
@maxLength(13)
param resourceNameSuffix string = uniqueString(resourceGroup().id)

@description('The administrator login username for the SQL server.')
param sqlServerAdministratorLogin string

@secure()
@description('The administrator login password for the SQL server.')
param sqlServerAdministratorLoginPassword string

@description('The name of the project.')
param projectName string = 'CleanArchitecture'

// Define the names for resources.
var environmentAbbreviation = environmentConfigurationMap[environmentType].environmentAbbreviation
var keyVaultName = 'kv-${projectName}${environmentAbbreviation}'
var appServiceAppName = 'as-${projectName}-${resourceNameSuffix}-${environmentAbbreviation}'
var appServicePlanName = 'plan-${projectName}-${environmentAbbreviation}'
var logAnalyticsWorkspaceName = 'log-${projectName}-${environmentAbbreviation}'
var applicationInsightsName = 'appi-${projectName}-${environmentAbbreviation}'
var sqlServerName = 'sql-${projectName}-${resourceNameSuffix}-${environmentAbbreviation}'
var sqlDatabaseName = '${projectName}-${environmentAbbreviation}'

// Define the connection string to access Azure SQL.
var sqlDatabaseConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabase.name};Persist Security Info=False;User ID=${sqlServerAdministratorLogin};Password=${sqlServerAdministratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// Define the SKUs for each component based on the environment type.
var environmentConfigurationMap = {
  Production: {
    environmentAbbreviation: 'prod'
    appServicePlan: {
      sku: {
        name: 'S1'
        capacity: 1
      }
    }
    storageAccount: {
      sku: {
        name: 'Standard_LRS'
      }
    }
    sqlDatabase: {
      sku: {
        name: 'Standard'
        tier: 'Standard'
      }
    }
  }
  Test: {
    environmentAbbreviation: 'test'
    appServicePlan: {
      sku: {
        name: 'B1'
      }
    }
    storageAccount: {
      sku: {
        name: 'Standard_GRS'
      }
    }
    sqlDatabase: {
      sku: {
        name: 'Standard'
        tier: 'Standard'
      }
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForTemplateDeployment: true
    createMode: 'default'
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: '77bbd9e2-ad94-4850-922f-d9590310e295'
        permissions: {
          certificates: [
            'Get'
            'List'
            'Update'
            'Create'
            'Import'
            'Delete'
            'Recover'
            'Backup'
            'Restore'
            'ManageContacts'
            'ManageIssuers'
            'GetIssuers'
            'ListIssuers'
            'SetIssuers'
            'DeleteIssuers'
          ]
          keys: [
            'Get'
            'List'
            'Update'
            'Create'
            'Import'
            'Delete'
            'Recover'
            'Backup'
            'Restore'
            'GetRotationPolicy'
            'SetRotationPolicy'
            'Rotate'
          ]
          secrets: [
            'Get'
            'List'
            'Set'
            'Delete'
            'Recover'
            'Backup'
            'Restore'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  name: '${keyVault.name}/ConnectionStrings--DefaultConnection'
  properties: {
    value: sqlDatabaseConnectionString
    contentType: 'string'
    attributes: {
      enabled: true
    }
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2021-01-15' = {
  name: appServicePlanName
  location: location
  sku: environmentConfigurationMap[environmentType].appServicePlan.sku
}

resource appServiceApp 'Microsoft.Web/sites@2021-01-15' = {
  name: appServiceAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
    }
  }
}

// resource certificate 'Microsoft.Web/certificates@2022-03-01' = {
//   name: 'cert-CaBlazor'
//   location:  location
//   properties: {
//     canonicalName: appServiceApp.properties.defaultHostName
//     domainValidationMethod: 'http-token'
//     serverFarmId: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
//   }
// }

resource appServiceAppConfig 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'appsettings'
  parent: appServiceApp
  properties: {
    // WEBSITE_LOAD_CERTIFICATES: certificate.properties.thumbprint
    ApplicationInsights__InstrumentationKey: applicationInsights.properties.InstrumentationKey
    ConnectionStrings__DefaultConnection: sqlDatabaseConnectionString
    ApplicationInsights__ConnectionString: applicationInsights.properties.ConnectionString
    KeyVaultUri: keyVault.properties.vaultUri
  }
}

resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2019-09-01' = {
  name: '${keyVaultName}/add'
  properties: {
    accessPolicies: [
      {
        tenantId: appServiceApp.identity.tenantId
        objectId: appServiceApp.identity.principalId
        permissions: {
          keys: [
            'Get'
          ]
          secrets: [
            'List'
            'Get'
          ]
          certificates: [
            'Get'
            'List'
            'Create'
            'Update'
          ]
        }
      }
    ]
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource sqlServer 'Microsoft.Sql/servers@2021-02-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlServerAdministratorLogin
    administratorLoginPassword: sqlServerAdministratorLoginPassword
  }
}

resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2021-02-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: environmentConfigurationMap[environmentType].sqlDatabase.sku
}

output appServiceAppName string = appServiceApp.name
output appServiceAppHostName string = appServiceApp.properties.defaultHostName
output sqlServerFullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
