variable "subscription_id" {
  description = "Azure subscription ID, required for a live plan or deployment."
  type        = string
}

variable "location" {
  description = "Azure hosting region."
  type        = string
  default     = "eastus2"
}

variable "windows_size" {
  type        = string
  description = "Four vCPUs and 8 GiB RAM."
  default     = "Standard_F4s_v2"
}

variable "linux_size" {
  type        = string
  description = "Two vCPUs and 4 GiB RAM."
  default     = "Standard_F2s_v2"
}

variable "windows_admin_password" {
  description = "Private Windows administrator password."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.windows_admin_password) >= 16
    error_message = "Use at least 16 characters and meet Azure Windows password complexity requirements."
  }
}

variable "linux_ssh_public_key" {
  description = "Contents of your SSH public key, never your private key."
  type        = string
}

variable "school_cidr" {
  description = "Actual school LAN IPv4 CIDR. Must not overlap 10.20.0.0/16."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.school_cidr)) && var.school_cidr != "0.0.0.0/0"
    error_message = "Supply the school's specific IPv4 network in CIDR notation."
  }
}

variable "school_vpn_public_ip" {
  description = "Actual public IPv4 address of the school's VPN peer."
  type        = string
  validation {
    condition     = can(cidrnetmask("${var.school_vpn_public_ip}/32"))
    error_message = "Supply one IPv4 address without /32."
  }
}

variable "vpn_shared_key" {
  description = "Private VPN pre-shared key agreed with the school's network team."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{32,128}$", var.vpn_shared_key))
    error_message = "Use 32 to 128 letters, digits, underscores or hyphens."
  }
}
