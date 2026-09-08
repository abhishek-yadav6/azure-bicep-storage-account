# Two-Tier Azure App (Bicep)

Infrastructure-as-code for a classic two-tier application on Azure:

- **Web tier**: 2 Ubuntu VMs (Nginx), same VNet/subnet, behind a Standard Load Balancer
- **Data tier**: 1 Ubuntu VM (MySQL), in its own subnet, reachable only from the web tier
- **Storage account**: used for VM boot diagnostics

## Architecture

```
                          Internet
                             |
                     [Standard Load Balancer]
                       (public IP, port 80)
                             |
              +--------------+--------------+
              |                             |
        [web-subnet 10.0.1.0/24]     (same VNet: two-tier-vnet, 10.0.0.0/16)
              |                             |
        [web-vm-1: Nginx]           [web-vm-2: Nginx]
              |                             |
              +--------------+--------------+
                             |
                  MySQL (3306) - web subnet only
                             |
                     [db-subnet 10.0.2.0/24]
                             |
                     [db-vm: MySQL Server]
```

- `nsg-web-subnet` allows inbound 80/443 from the internet and 22 (SSH) from `sshSourceAddressPrefix`.
- `nsg-db-subnet` allows inbound 3306 and 22 **only** from the web subnet's address range. The DB VM has no public IP.
- The two web VMs have no public IP either; they're reached through the load balancer's public IP on port 80 (app traffic) and via inbound NAT rules on ports 50001/50002 (SSH).
- The web VMs sit in an aligned availability set for basic fault/update-domain separation.

## Files

- `main.bicep` — orchestrator: storage account, availability set, and the modules below
- `modules/network.bicep` — VNet, subnets, NSGs
- `modules/loadBalancer.bicep` — public IP, Standard Load Balancer, backend pool, health probe, SSH NAT rules
- `modules/webVm.bicep` — one Nginx web server VM (deployed twice)
- `modules/dbVm.bicep` — the MySQL database server VM
- `cloud-init/web-server.yaml` — installs Nginx, writes a test page
- `cloud-init/db-server.yaml` — installs MySQL, creates the app database/user
- `main.parameters.example.json` — example parameters file (no real secrets)

## Deploy

Requires the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) logged in (`az login`) with a subscription selected.

```bash
# 1. Create a resource group
az group create --name rg-two-tier-app --location eastus

# 2. Copy the example parameters file and fill in real values (never commit this file)
cp main.parameters.example.json main.parameters.json
# edit main.parameters.json: storageAccountName (globally unique, lowercase, 3-24 chars),
# adminPassword, dbPassword

# 3. Deploy
az deployment group create \
  --resource-group rg-two-tier-app \
  --template-file main.bicep \
  --parameters main.parameters.json
```

Or pass secrets on the command line instead of storing them in a file:

```bash
az deployment group create \
  --resource-group rg-two-tier-app \
  --template-file main.bicep \
  --parameters storageAccountName=twotierdiagsa001 \
  --parameters adminPassword='<your-password>' dbPassword='<your-db-password>'
```

After deployment, the outputs include the load balancer's public IP — browse to `http://<publicIp>` to hit the web tier (refresh a few times to see the load balancer alternate between `web-vm-1` and `web-vm-2`), and use the printed `sshWebVm1`/`sshWebVm2` commands to SSH into each web server (port 50001/50002 on the same public IP).

## Notes / things to adjust before production use

- `adminPassword`/`dbPassword` use password auth for simplicity. For production, switch to SSH public-key auth on the VMs and consider Azure Database for MySQL (PaaS) instead of a self-managed VM.
- `sshSourceAddressPrefix` defaults to `*` (open to the internet on port 22 via the LB NAT rules). Restrict it to your own IP via the parameter.
- The DB password is embedded in the VM's cloud-init `customData` (base64-encoded, not encrypted) to bootstrap MySQL. For production, use Key Vault references or a post-deployment configuration step instead.
- No Azure Bastion/jump box is included; SSH reaches the web tier via load-balancer NAT rules and the DB tier via the web subnet only.
