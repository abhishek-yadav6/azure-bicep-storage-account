@description('Storage Account Name (used for VM boot diagnostics)')
param storageAccountName string

@description('Azure Region')
param location string = resourceGroup().location

@description('Admin username for all VMs (web and database)')
param adminUsername string = 'azureadmin'

@secure()
@minLength(12)
@description('Admin password for all VMs. Must meet Azure complexity requirements (12-123 chars, 3 of: upper, lower, digit, special).')
param adminPassword string

@description('VM size for each web server')
param webVmSize string = 'Standard_B1s'

@description('VM size for the database server')
param dbVmSize string = 'Standard_B2s'

@description('Address space for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the web subnet')
param webSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the database subnet')
param dbSubnetPrefix string = '10.0.2.0/24'

@description('Source address prefix allowed to reach the web tier over SSH (22). Restrict this to your own IP in production.')
param sshSourceAddressPrefix string = '*'

@description('Name of the MySQL database to create on the database server')
param dbName string = 'appdb'

@description('MySQL application username to create on the database server')
param dbUsername string = 'appuser'

@secure()
@minLength(12)
@description('Password for the MySQL application user. Avoid single quotes and backslashes. Must meet Azure complexity requirements.')
param dbPassword string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource availabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = {
  name: 'web-availability-set'
  location: location
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
}

module network 'modules/network.bicep' = {
  name: 'network-deployment'
  params: {
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    webSubnetPrefix: webSubnetPrefix
    dbSubnetPrefix: dbSubnetPrefix
    sshSourceAddressPrefix: sshSourceAddressPrefix
  }
}

module loadBalancer 'modules/loadBalancer.bicep' = {
  name: 'loadbalancer-deployment'
  params: {
    location: location
  }
}

module webVm1 'modules/webVm.bicep' = {
  name: 'web-vm-1-deployment'
  params: {
    location: location
    vmName: 'web-vm-1'
    webLabel: 'Web Server 1'
    vmSize: webVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.webSubnetId
    backendPoolId: loadBalancer.outputs.backendPoolId
    natRuleId: loadBalancer.outputs.natRule1Id
    availabilitySetId: availabilitySet.id
    bootDiagnosticsStorageUri: storageAccount.properties.primaryEndpoints.blob
  }
}

module webVm2 'modules/webVm.bicep' = {
  name: 'web-vm-2-deployment'
  params: {
    location: location
    vmName: 'web-vm-2'
    webLabel: 'Web Server 2'
    vmSize: webVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.webSubnetId
    backendPoolId: loadBalancer.outputs.backendPoolId
    natRuleId: loadBalancer.outputs.natRule2Id
    availabilitySetId: availabilitySet.id
    bootDiagnosticsStorageUri: storageAccount.properties.primaryEndpoints.blob
  }
}

module dbVm 'modules/dbVm.bicep' = {
  name: 'db-vm-deployment'
  params: {
    location: location
    vmSize: dbVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.dbSubnetId
    bootDiagnosticsStorageUri: storageAccount.properties.primaryEndpoints.blob
    dbName: dbName
    dbUsername: dbUsername
    dbPassword: dbPassword
  }
}

output storageAccountId string = storageAccount.id
output loadBalancerPublicIp string = loadBalancer.outputs.publicIpAddress
output webVm1PrivateIp string = webVm1.outputs.privateIp
output webVm2PrivateIp string = webVm2.outputs.privateIp
output dbVmPrivateIp string = dbVm.outputs.privateIp
output sshWebVm1 string = 'ssh ${adminUsername}@${loadBalancer.outputs.publicIpAddress} -p 50001'
output sshWebVm2 string = 'ssh ${adminUsername}@${loadBalancer.outputs.publicIpAddress} -p 50002'
