@description('Azure region for the VM')
param location string

@description('Name of the database server VM')
param vmName string = 'db-vm'

@description('VM size for the database server')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM')
param adminUsername string

@secure()
@description('Admin password for the VM')
param adminPassword string

@description('Resource ID of the subnet the NIC is deployed into')
param subnetId string

@description('Blob endpoint of the storage account used for boot diagnostics')
param bootDiagnosticsStorageUri string

@description('Name of the MySQL database to create')
param dbName string = 'appdb'

@description('MySQL application username to create')
param dbUsername string = 'appuser'

@secure()
@description('Password for the MySQL application user. Avoid single quotes and backslashes.')
param dbPassword string

var cloudInit = replace(replace(replace(loadTextContent('../cloud-init/db-server.yaml'), '__DB_NAME__', dbName), '__DB_USER__', dbUsername), '__DB_PASSWORD__', dbPassword)

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
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
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
