# Ann Arbor charter school cloud infrastructure

## Design

Azure East US 2, one VNet (10.20.0.0/16), internal subnet
(10.20.1.0/24), external subnet (10.20.2.0/24).

| VM | Subnet | Private IP | Size | Intended role |
|---|---|---|---|---|
| DC01 | Internal | 10.20.1.10 | F4s_v2 | Domain controller and DNS |
| DC02 | Internal | 10.20.1.11 | F4s_v2 | Domain controller and DNS |
| CA01 | Internal | 10.20.1.12 | F4s_v2 | Certificate authority |
| NPS01 | Internal | 10.20.1.13 | F4s_v2 | NPS/RADIUS |
| LINUX-INT01 | Internal | 10.20.1.20 | F2s_v2 | Internal Linux server |
| LINUX-INT02 | Internal | 10.20.1.21 | F2s_v2 | Internal Linux server |
| LINUX-EXT01 | External | 10.20.2.20 | F2s_v2 | External Linux server |
| LINUX-EXT02 | External | 10.20.2.21 | F2s_v2 | External Linux server |
| FW01 | External | 10.20.2.4 | F2s_v2 | strongSwan/nftables firewall |

Windows VMs use Windows Server 2022, four vCPUs and 8 GiB RAM.
Linux VMs use Ubuntu 22.04 LTS, two vCPUs and 4 GiB RAM.
Default image OS disk capacities are used with Standard_LRS managed disks.
The separate firewall is additional to the eight required school servers.

## Open in VS Code on Windows

1. Download the project ZIP and right-click it, then choose **Extract All**.
2. Open VS Code. Choose **File > Open Folder**.
3. Select the extracted `charter-school-terraform` folder containing `main.tf`.
4. Press **Ctrl+Shift+X**, search **HashiCorp Terraform**, and install the extension
   published by **HashiCorp**.
5. Click `main.tf` in Explorer on the left. Its language should be **Terraform**.
6. If needed, press **Ctrl+K**, release, then **M**, type **Terraform**, and select it.
7. To replace a file's code, click inside its editor, press **Ctrl+A**, paste code
   intended for that file with **Ctrl+V**, and save with **Ctrl+S**.
8. The supplied files already contain the code, so opening them is sufficient.

All `.tf` files in this folder form one Terraform project. Keep the templates
folder alongside them. README uses Markdown; the firewall template uses YAML
with Terraform substitutions. Select Terraform only for `.tf` files.

## Check configuration without creating cloud resources

Install Terraform CLI using https://developer.hashicorp.com/terraform/install.
Reopen VS Code after installation. Use **Terminal > New Terminal** and run
these commands one at a time in the project folder:

```powershell
terraform version
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

The HashiCorp extension and the Terraform CLI are separate installations.
These checks need an internet connection to download the provider. They do not
need your Azure account or live school VPN details. Validation checks schema
and references, not Azure capacity or running VPN/server services.

## Live deployment inputs

Only proceed with a live deployment if it is part of your assignment or you
intend to pay Azure charges. VM sizes and quota must be available in your
subscription and chosen region. Obtain the actual school network and VPN peer
details. Confirm school_cidr does not overlap 10.20.0.0/16.

Install Azure CLI from https://learn.microsoft.com/cli/azure/install-azure-cli.
Sign in with `az login` and select your subscription using
`az account set --subscription YOUR_SUBSCRIPTION_ID`.

Copy `terraform.tfvars.example` to `terraform.tfvars` and replace every example
value. Store the private file outside Git. Use the content of your public SSH
key (the `.pub` file), never the private key. You can generate a key on Windows
using `ssh-keygen -t rsa -b 4096`. Use an existing key or choose a new filename
if prompted about overwriting a key. Use a complex Windows password meeting
Azure requirements and the required private VPN pre-shared key.

The CIDR and peer IP in the example file are examples, not live school values.

```powershell
terraform init
terraform plan
```

Review the plan. If deploying, use `terraform apply` and review its confirmation.
When finished with a lab deployment, `terraform destroy` removes the resources
managed by this project after confirmation. Removing infrastructure deletes
its VM disks and data. Save any needed work first.

## Firewall and VPN behavior

Cloud-init installs strongSwan and nftables and writes initial configuration.
The school peer must match IKEv2, AES256/SHA256, DH/PFS group 14, IKE lifetime
8 hours and IPsec lifetime 1 hour. The remote peer must accept both cloud
subnets as traffic selectors. Use the firewall public IP as its cloud identity.
IKE/NAT-T UDP 500 and 4500 are limited to the supplied school public IP.
NAT traversal is forced to work through Azure's public IP mapping.

Both subnet route tables send school-bound traffic to FW01. The internal
subnet also sends its default route through FW01. nftables permits VPN traffic
between the school LAN and the two cloud subnets. It allows internal server
web, DNS and NTP egress, with NAT for internet traffic. Internal/external
cross-subnet traffic is denied by the server NIC NSGs unless rules are added.
Same-subnet and school LAN access are permitted by the initial server NSGs.
Narrow school access to the necessary ports/accounts for an actual rollout.

External Linux servers have private addresses and no published public services
in this baseline. Publishing an application needs coordinated firewall DNAT,
forwarding and NIC NSG rules plus an installed application. General internet
egress for external Linux servers needs an explicit outbound design, such as
a NAT Gateway, before installing applications or downloading their updates.
Do not add a default route to FW01's own subnet pointing to FW01, which can
break its own outbound path.

Cloud-init completion and a healthy tunnel must be checked after deployment.
On FW01 check `sudo cloud-init status --wait`, `sudo ipsec statusall`,
`sudo nft list ruleset`, and `sysctl net.ipv4.ip_forward`. Azure VM Run Command
can inspect initial setup when the tunnel is unavailable. Azure resource
creation alone does not prove cloud-init or the VPN completed successfully.
The firewall is one point of failure, matching the initial single-appliance design.

## Windows service configuration after provisioning

This project provisions the four Windows VMs and records their intended roles.
Complete Windows service configuration after provisioning:

1. Use the school's owned domain to select the real Active Directory DNS name.
2. Configure DC01 with AD DS/DNS and create the forest.
3. Configure DC02 as an additional domain controller and confirm replication.
4. Set server/client DNS to DC01 and DC02 and verify name resolution.
5. Join CA01 and NPS01 to the domain.
6. Configure Certificate Services on CA01 and its enrollment permissions.
7. Configure NPS, register it in AD, and add the real RADIUS clients/policies.
8. Test domain authentication, certificate enrollment and RADIUS access.

These identity-service steps need the actual school domain and policies.
Backups, log retention and operational monitoring described in the paper
also require implementation during a real rollout.

## GitHub submission

Upload all `.tf` files, `templates/firewall.yaml.tftpl`, `README.md`,
`terraform.tfvars.example`, `.gitignore`, and `.terraform.lock.hcl`.
Preserve the templates directory. Upload the extracted project files, not only
the ZIP. Make the repository public and add its URL to the paper.

Do not upload `.terraform/`, state files, private `terraform.tfvars`, private
keys or saved plan files. GitHub's browser upload may not apply `.gitignore`,
so select only the listed submission files. Terraform state contains the
Windows password and the VPN secret rendered into firewall custom data.
The guest cloud-init files can also contain the VPN secret. Protect both.

## Validation and scope

See `VALIDATION.txt` for the checks performed on this package. Azure deployment,
VPN connectivity and Windows domain-service operation require live validation.
The design uses the paper's MSCA interpretation of Microsoft Certificate Authority.
