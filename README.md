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

## CI/CD (GitHub Actions)

Two workflows live under `.github/workflows/`:

- **`validate.yml`** — runs on every pull request that touches a `.bicep` file. Just runs `az bicep build` on `main.bicep` and every module to catch syntax errors. Needs no Azure credentials.
- **`deploy.yml`** — runs whenever `main.bicep`, `modules/**`, or `cloud-init/**` change on `main` (i.e. right after a PR merges), plus a manual `workflow_dispatch` trigger. It logs into Azure via OIDC and runs the same `az deployment group create` shown above. **This is what actually creates/updates the infrastructure in Azure.**

Nothing deploys until you complete this one-time setup yourself (it needs your own `az login`, so it can't be done from here):

```bash
# Run these locally, logged into the target Azure subscription
APP_NAME="gh-actions-two-tier-app"
RESOURCE_GROUP="rg-two-tier-app"
LOCATION="eastus"
GITHUB_ORG="abhishek-yadav6"
GITHUB_REPO="azure-bicep-storage-account"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# 1. Resource group the app will deploy into
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# 2. App registration + service principal for GitHub Actions to log in as
az ad app create --display-name "$APP_NAME"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"

# 3. Let it manage resources in that resource group only
az role assignment create \
  --assignee "$APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# 4. Trust GitHub Actions running on this repo's main branch — no client secret needed
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "github-main-branch",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'"$GITHUB_ORG"'/'"$GITHUB_REPO"':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
```

Then, in the GitHub repo (**Settings → Secrets and variables → Actions → New repository secret**), add:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | printed above |
| `AZURE_TENANT_ID` | printed above |
| `AZURE_SUBSCRIPTION_ID` | printed above |
| `AZURE_RESOURCE_GROUP` | `rg-two-tier-app` (or whatever you used) |
| `AZURE_LOCATION` | `eastus` (or whatever you used) |
| `STORAGE_ACCOUNT_NAME` | a globally-unique, lowercase, 3-24 char name |
| `ADMIN_USERNAME` | e.g. `azureadmin` |
| `ADMIN_PASSWORD` | meets Azure's complexity rules |
| `DB_NAME` | e.g. `appdb` |
| `DB_USERNAME` | e.g. `appuser` |
| `DB_PASSWORD` | meets Azure's complexity rules |

Once those secrets exist, merging a PR into `main` (or manually running the `deploy.yml` workflow from the Actions tab) triggers the actual Azure deployment. Optionally create a `production` GitHub Environment with required reviewers so a merge pauses for manual approval before it spends money.

## Notes / things to adjust before production use

- `adminPassword`/`dbPassword` use password auth for simplicity. For production, switch to SSH public-key auth on the VMs and consider Azure Database for MySQL (PaaS) instead of a self-managed VM.
- `sshSourceAddressPrefix` defaults to `*` (open to the internet on port 22 via the LB NAT rules). Restrict it to your own IP via the parameter.
- The DB password is embedded in the VM's cloud-init `customData` (base64-encoded, not encrypted) to bootstrap MySQL. For production, use Key Vault references or a post-deployment configuration step instead.
- No Azure Bastion/jump box is included; SSH reaches the web tier via load-balancer NAT rules and the DB tier via the web subnet only.
