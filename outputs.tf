output "server_private_ips" {
  description = "Eight school server addresses."
  value       = { for name, server in local.servers : name => server.ip }
}

output "firewall_public_ip" {
  description = "Use this endpoint when configuring the school VPN peer."
  value       = azurerm_public_ip.firewall.ip_address
}

output "resource_group" {
  value = azurerm_resource_group.school.name
}
