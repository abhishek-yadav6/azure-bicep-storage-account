@description('Azure region for the VM')
param location string

@description('Name of the web server VM')
param vmName string

@description('Human-readable label for this web server, shown on its test page (e.g. "Web Server 1")')
param webLabel string

@description('VM size for the web server')
param vmSize string = 'Standard_B1s'

@description('Admin username for the VM')
param adminUsername string

@secure()
@description('Admin password for the VM')
param adminPassword string

@description('Resource ID of the subnet the NIC is deployed into')
param subnetId string

@description('Resource ID of the load balancer backend address pool this VM joins')
param backendPoolId string

@description('Resource ID of the load balancer inbound NAT rule that forwards SSH to this VM')
param natRuleId string

@description('Resource ID of the availability set this VM joins')
param availabilitySetId string

@description('Blob endpoint of the storage account used for boot diagnostics')
param bootDiagnosticsStorageUri string

var cloudInit = replace(loadTextContent('../cloud-init/web-server.yaml'), '__WEB_INDEX__', webLabel)

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          loadBalancerBackendAddressPools: [
            {
              id: backendPoolId
            }
          ]
          loadBalancerInboundNatRules: [
            {
              id: natRuleId
            }
          ]
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    availabilitySet: {
      id: availabilitySetId
    }
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(cloudInit)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: bootDiagnosticsStorageUri
      }
    }
  }
}

output vmId string = vm.id
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
