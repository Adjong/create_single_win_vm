# Variable section for lab resources

variable "tanium_init_dat" {
  type        = string
  sensitive   = true
  description = "Base64-encoded content of tanium-init.dat from your Tanium Cloud portal"
}

variable "tanium_server" {
  type        = string
  description = "Tanium Cloud tenant FQDN (e.g. yourorg-ams-zsb1.cloud.tanium.com)"
}

variable "AZ_Region" {
  type    = string
  default = "centralus"
}

variable "lab_resource_group" {
  type        = string
  description = "Resource group for all lab activities"
  default     = "RG_NA_lab"
}

variable "admin_user" {
  type    = string
  default = "testadmin"
}

variable "admin_pwd" {
  type      = string
  sensitive = true
}

variable "auto_shutdown_time" {
  type        = string
  description = "Daily auto-shutdown time in HHMM format (24h)"
  default     = "1700"
}

variable "auto_shutdown_timezone" {
  type    = string
  default = "Central Standard Time"
}

variable "virtual_machines" {
  description = "Map of VM profiles. Each entry is expanded into 'instance_count' VMs with random names."
  type = map(object({
    instance_count = number        # How many VMs of this type to create
    os_type        = string        # "linux" or "windows"
    size           = string
    publisher      = string
    offer          = string
    sku            = string
    version        = string
  }))

  default = {

    
    # ── Windows Server ───────────────────────────────────────────────
    "win-server" = {
      instance_count = 1
      os_type        = "windows"
      size           = "Standard_B2ls_v2"
      publisher      = "MicrosoftWindowsServer"
      offer          = "WindowsServer"
      sku            = "2022-Datacenter-smalldisk"
      version        = "latest"
    }

      }

  validation {
    condition = alltrue([
      for k, v in var.virtual_machines : contains(["linux", "windows"], v.os_type)
    ])
    error_message = "Each VM entry's os_type must be either \"linux\" or \"windows\"."
  }
}
