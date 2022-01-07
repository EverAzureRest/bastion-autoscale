@description('Bastion Name')
param bastionName string = '${toLower(uniqueString(resourceGroup().id))}-bastion'

@description('vNet Name')
param vnetName string = 'bastionVNET'

@description('Bastion Subnet Name')
param bastionSubnetName string = 'AzureBastionSubnet'

@description('vnet CIDR range')
param vnetCIDR string = '10.1.0.0/16'

@description('subnet CIDR range')
param bastionSubnetCIDR string = '10.1.2.0/24'

@description('initial number of bastion scale units - min 2')
param scaleUnits int = 2

@description('Runbook public Uri')
param runbookuri string = 'https://raw.githubusercontent.com/EverAzureRest/bastion-autoscale/main/scale-bastioninstance.ps1'

var location = '${resourceGroup().location}'
var publicIPName = '${bastionName}-pip'
var workspaceName = '${toLower(uniqueString(resourceGroup().id))}-workspace'
var automationAccountName = '${toLower(uniqueString(resourceGroup().id))}-automation'

resource vNET 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetCIDR
      ]
    }
    subnets: [
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetCIDR
        }
      }
    ]
  }
}

resource bastionSubnet 'Microsoft.Network/virtualnetworks/subnets@2015-06-15' = {
  parent: vNET
  name: bastionSubnetName
  properties: {
    addressPrefix: bastionSubnetCIDR
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: publicIPName
  location: location
  sku: {
    name:'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2021-05-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConfig1'
        properties: {
          subnet: {
            id: bastionSubnet.id
          }
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    scaleUnits: scaleUnits
  }
}

resource logsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  
}

resource bastionDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'bastionDiagnostics'
  scope: bastion
  properties: {
    workspaceId: logsWorkspace.id
  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2021-06-22' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2019-06-01' = {
  name: 'scale-bastioninstance'
  location: location
  parent: automationAccount
  properties: {
    publishContentLink: {
      uri: runbookuri
      version: ''
    }
    runbookType: 'PowerShell'
  }
}

resource webHook 'Microsoft.Automation/automationAccounts/webhooks@2015-10-31' = {
  name: 'autoscaleWebhook'
  parent: automationAccount
  properties: {
    isEnabled: true
    runbook: {
      name: runbook.name
    }
  }
}

//Assign Managed Identity for Automation Account to the Netework Contributor role - a more scoped custom role may be desirable
resource automationAccountRoleAssingment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: 'AzureAutomationRoleAssigment'
  scope: bastion
  properties: {
    principalId: '${automationAccount.identity.principalId}'
    roleDefinitionId: '4d97b98b-1d4f-4787-a291-c67834d212e7'
  }
}

resource sessionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'bastionsess'
  location: location
  properties: {
    evaluationFrequency: 'PT5M'
    windowSize: 'PT30M'
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 20
          name: 'metric1'
          metricNamespace: 'microsoft.network/bastionhosts'
          metricName: 'sessions'
          operator: 'GreaterThanOrEqual'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    severity: 3
    enabled: true
    scopes: [
      bastion.id
    ]
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2021-09-01' = {
  name: 'bastionAutoScale'
  location: location
  properties: {
    automationRunbookReceivers: [
      {
        automationAccountId: automationAccount.id
        isGlobalRunbook: true
        name: webHook.name
        runbookName: runbook.name
        webhookResourceId: webHook.id
      }
    ]
    enabled: true
    groupShortName: 'bastionSessions'
  }
}
