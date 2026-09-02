# ===========================================================
# Script to deploy resources on Azure and install the Tanium
# agent on the first deployd Windows server
# Arjan de Jong, 8/18/2026
# ===========================================================

# ============================================================
# PROVIDERS
# ============================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  use_cli = false
}
# ============================================================
# DATA
# ============================================================

  data "azurerm_image" "SRV202_unpatched" {
  name                = "Win_SRV2022_unpatched_demo"
  resource_group_name = "RG_NA_lab"
}

# ============================================================
# LOCALS
# ============================================================

locals {
  outbound_ports = {
    "HTTP"  = { port = "80",  priority = 100 }
    "HTTPS" = { port = "443", priority = 110 }
  }

  inbound_ports = {
    "SSH"         = { port = "22",          priority = 100 }
    "RPC-WMI"     = { port = "135",         priority = 110 }
    "NetBIOS"     = { port = "139",         priority = 120 }
    "SMB"         = { port = "445",         priority = 130 }
    "WMI-Dynamic" = { port = "49152-65535", priority = 140 }
  }

 }

# ============================================================
# RESOURCE GROUP  (data source — must already exist)
# ============================================================
data "azurerm_resource_group" "lab" {
  name = var.lab_resource_group
}

# ============================================================
# NETWORKING
# ============================================================
resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vnet_na_lab_single"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = ["172.16.0.0/24"]
}

resource "azurerm_subnet" "lab_subnet" {
  name                 = "sn_na_lab_single"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = ["172.16.0.0/26"]
}

# NSG with dynamic outbound rules
resource "azurerm_network_security_group" "lab_nsg" {
  name                = "nsg_na_lab_vm_single"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  dynamic "security_rule" {
    for_each = local.outbound_ports
    content {
      name                       = "Allow-${security_rule.key}"
      priority                   = security_rule.value.priority
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      source_address_prefix      = "*"
      destination_port_range     = security_rule.value.port
      destination_address_prefix = "*"
    }
  }
  dynamic "security_rule" {
    for_each = local.inbound_ports
    content {
      name                       = "Allow-In-${security_rule.key}"
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_port_range     = security_rule.value.port
      destination_address_prefix = "*"
  }
}
}

# Associate NSG at the subnet level — applies to all VMs at once
  resource "azurerm_subnet_network_security_group_association" "lab_nsg_subnet" {
  subnet_id                 = azurerm_subnet.lab_subnet.id
  network_security_group_id = azurerm_network_security_group.lab_nsg.id
}

# One NIC per VM instance
resource "azurerm_network_interface" "lab_nic" {
  
  name                = "nic-TaniumServer"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.lab_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}


# ============================================================
# WINDOWS VIRTUAL MACHINES
# ============================================================
resource "azurerm_windows_virtual_machine" "lab_vm" {
  
  # Azure Windows VM names: max 15 chars; "wn-" + 6 random = 9 chars ✓
  name = "TaniumServer"
  location            = data.azurerm_resource_group.lab.location
  resource_group_name = data.azurerm_resource_group.lab.name
  size                = "Standard_B2ls_v2"

  admin_username = var.admin_user
  admin_password = var.admin_pwd
  timezone       = "Central Standard Time"
  patch_mode = "Manual"
  automatic_updates_enabled = false
  source_image_id = data.azurerm_image.SRV202_unpatched.id

  network_interface_ids = [
    azurerm_network_interface.lab_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
   
  tags = {
        os_type = "windows"
  }
}


resource "azurerm_virtual_machine_extension" "tanium_init_dat" {
  name                 = "Winfirewall"
  virtual_machine_id   = azurerm_windows_virtual_machine.lab_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  protected_settings = jsonencode({
  commandToExecute = join(" & ", [
      "netsh advfirewall firewall add rule name=Lab-Allow-SSH dir=in action=allow protocol=TCP localport=22 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-RPC-WMI dir=in action=allow protocol=TCP localport=135 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-NetBIOS dir=in action=allow protocol=TCP localport=139 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-SMB dir=in action=allow protocol=TCP localport=445 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-WMI-Dynamic dir=in action=allow protocol=TCP localport=49152-65535 profile=any"
    ]) 
  })
}

resource "azurerm_virtual_machine_extension" "windows_firewall_rules" {
  
  name                 = "WindowsFirewallRules"
  virtual_machine_id   = azurerm_windows_virtual_machine.lab_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

    settings = jsonencode({
    commandToExecute = join(" & ", [
      "netsh advfirewall firewall add rule name=Lab-Allow-SSH dir=in action=allow protocol=TCP localport=22 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-RPC-WMI dir=in action=allow protocol=TCP localport=135 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-NetBIOS dir=in action=allow protocol=TCP localport=139 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-SMB dir=in action=allow protocol=TCP localport=445 profile=any",
      "netsh advfirewall firewall add rule name=Lab-Allow-WMI-Dynamic dir=in action=allow protocol=TCP localport=49152-65535 profile=any"
    ])
  })
}

