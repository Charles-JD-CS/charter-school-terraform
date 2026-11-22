# Eight school servers plus one separate firewall appliance.
locals {
  windows = {
    DC01  = { ip = "10.20.1.10", role = "Domain controller and DNS" }
    DC02  = { ip = "10.20.1.11", role = "Domain controller and DNS" }
    CA01  = { ip = "10.20.1.12", role = "Certificate authority" }
    NPS01 = { ip = "10.20.1.13", role = "Network Policy Server" }
  }
  linux = {
    LINUX-INT01 = { ip = "10.20.1.20", subnet = "internal" }
    LINUX-INT02 = { ip = "10.20.1.21", subnet = "internal" }
    LINUX-EXT01 = { ip = "10.20.2.20", subnet = "external" }
    LINUX-EXT02 = { ip = "10.20.2.21", subnet = "external" }
  }
  servers = merge(
    { for name, server in local.windows : name => { ip = server.ip, subnet = "internal" } },
    local.linux
  )
  subnet_ranges = { internal = "10.20.1.0/24", external = "10.20.2.0/24" }
  tags          = { project = "charter-school", environment = "assignment" }
}

resource "azurerm_resource_group" "school" {
  name     = "rg-charter-school"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "school" {
  name                = "vnet-charter-school"
  location            = var.location
  resource_group_name = azurerm_resource_group.school.name
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "school" {
  for_each             = local.subnet_ranges
  name                 = each.key
  resource_group_name  = azurerm_resource_group.school.name
  virtual_network_name = azurerm_virtual_network.school.name
  address_prefixes     = [each.value]
}

# Only the known school LAN can initiate cross-network access to servers.
# Administrators can further narrow ports for their actual application needs.
resource "azurerm_network_security_group" "servers" {
  for_each            = local.subnet_ranges
  name                = "nsg-school-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.school.name
  tags                = local.tags

  security_rule {
    name                       = "AllowSchoolVPN"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.school_cidr
    destination_address_prefix = each.value
  }
  security_rule {
    name                       = "AllowSameSubnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = each.value
    destination_address_prefix = each.value
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "server" {
  for_each            = local.servers
  name                = "${each.key}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.school.name
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.school[each.value.subnet].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
  }
}

resource "azurerm_network_interface_security_group_association" "server" {
  for_each                  = local.servers
  network_interface_id      = azurerm_network_interface.server[each.key].id
  network_security_group_id = azurerm_network_security_group.servers[each.value.subnet].id
}

resource "azurerm_windows_virtual_machine" "server" {
  for_each              = local.windows
  name                  = each.key
  computer_name         = each.key
  location              = var.location
  resource_group_name   = azurerm_resource_group.school.name
  size                  = var.windows_size
  admin_username        = "schooladmin"
  admin_password        = var.windows_admin_password
  network_interface_ids = [azurerm_network_interface.server[each.key].id]
  tags                  = merge(local.tags, { role = each.value.role })
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
  depends_on = [azurerm_network_interface_security_group_association.server]
}

resource "azurerm_linux_virtual_machine" "server" {
  for_each                        = local.linux
  name                            = each.key
  computer_name                   = lower(each.key)
  location                        = var.location
  resource_group_name             = azurerm_resource_group.school.name
  size                            = var.linux_size
  admin_username                  = "schooladmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.server[each.key].id]
  tags                            = merge(local.tags, { role = "${each.value.subnet} Linux server" })
  admin_ssh_key {
    username   = "schooladmin"
    public_key = var.linux_ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  depends_on = [azurerm_network_interface_security_group_association.server]
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-school-firewall"
  location            = var.location
  resource_group_name = azurerm_resource_group.school.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_security_group" "firewall" {
  name                = "nsg-school-firewall"
  location            = var.location
  resource_group_name = azurerm_resource_group.school.name
  tags                = local.tags
  security_rule {
    name                       = "AllowSchoolIPsec"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_ranges    = ["500", "4500"]
    source_address_prefix      = "${var.school_vpn_public_ip}/32"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowSchoolManagement"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.school_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowInternalEgress"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.subnet_ranges.internal
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "firewall" {
  name                  = "FW01-nic"
  location              = var.location
  resource_group_name   = azurerm_resource_group.school.name
  ip_forwarding_enabled = true
  tags                  = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.school["external"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.20.2.4"
    public_ip_address_id          = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_network_interface_security_group_association" "firewall" {
  network_interface_id      = azurerm_network_interface.firewall.id
  network_security_group_id = azurerm_network_security_group.firewall.id
}

resource "azurerm_linux_virtual_machine" "firewall" {
  name                            = "FW01"
  computer_name                   = "fw01"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.school.name
  size                            = var.linux_size
  admin_username                  = "schooladmin"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.firewall.id]
  tags                            = merge(local.tags, { role = "IPsec firewall" })
  # Secret-bearing rendered data lives in Terraform state, never in Git.
  custom_data = base64encode(templatefile("${path.module}/templates/firewall.yaml.tftpl", {
    school_cidr          = var.school_cidr
    school_vpn_public_ip = var.school_vpn_public_ip
    firewall_public_ip   = azurerm_public_ip.firewall.ip_address
    vpn_shared_key       = var.vpn_shared_key
  }))
  admin_ssh_key {
    username   = "schooladmin"
    public_key = var.linux_ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  depends_on = [azurerm_network_interface_security_group_association.firewall]
}

# Both subnets return school-bound traffic through the VPN appliance.
resource "azurerm_route_table" "school" {
  for_each            = local.subnet_ranges
  name                = "rt-school-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.school.name
  tags                = local.tags
}

resource "azurerm_route" "school_vpn" {
  for_each               = local.subnet_ranges
  name                   = "SchoolViaFirewall"
  resource_group_name    = azurerm_resource_group.school.name
  route_table_name       = azurerm_route_table.school[each.key].name
  address_prefix         = var.school_cidr
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.20.2.4"
}

# Internal servers use FW01 for outbound internet traffic and NAT.
resource "azurerm_route" "internal_internet" {
  name                   = "InternetViaFirewall"
  resource_group_name    = azurerm_resource_group.school.name
  route_table_name       = azurerm_route_table.school["internal"].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = "10.20.2.4"
}

resource "azurerm_subnet_route_table_association" "school" {
  for_each       = local.subnet_ranges
  subnet_id      = azurerm_subnet.school[each.key].id
  route_table_id = azurerm_route_table.school[each.key].id
  depends_on     = [azurerm_route.school_vpn, azurerm_route.internal_internet]
}
