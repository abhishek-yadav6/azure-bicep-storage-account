@description('Azure region for the load balancer and public IP')
param location string

@description('Name of the public IP address')
param publicIpName string = 'two-tier-lb-pip'

@description('Name of the load balancer')
param lbName string = 'two-tier-lb'

var frontendIpConfigName = 'lb-frontend'
var backendPoolName = 'web-backend-pool'
var httpProbeName = 'http-probe'

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: frontendIpConfigName
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
      }
    ]
    probes: [
      {
        name: httpProbeName
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'HttpRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, frontendIpConfigName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, backendPoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, httpProbeName)
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 4
        }
      }
    ]
    inboundNatRules: [
      {
        name: 'SSH-web-vm-1'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, frontendIpConfigName)
          }
          protocol: 'Tcp'
          frontendPort: 50001
          backendPort: 22
        }
      }
      {
        name: 'SSH-web-vm-2'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, frontendIpConfigName)
          }
          protocol: 'Tcp'
          frontendPort: 50002
          backendPort: 22
        }
      }
    ]
  }
}

output lbId string = loadBalancer.id
output backendPoolId string = loadBalancer.properties.backendAddressPools[0].id
output natRule1Id string = loadBalancer.properties.inboundNatRules[0].id
output natRule2Id string = loadBalancer.properties.inboundNatRules[1].id
output publicIpAddress string = publicIp.properties.ipAddress
