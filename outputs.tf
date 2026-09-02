# ============================================================
# OUTPUTS
# ============================================================

output "linux_vms" {
  description = "Linux VM names and private IP addresses"
  value = {
    for k, vm in azurerm_linux_virtual_machine.lab_vm :
    vm.name => azurerm_network_interface.lab_nic[k].private_ip_address
  }
}

output "windows_vms" {
  description = "Windows VM names and private IP addresses"
  value = {
    for k, vm in azurerm_windows_virtual_machine.lab_vm :
    vm.name => azurerm_network_interface.lab_nic[k].private_ip_address
  }
}

output "all_vm_names" {
  description = "Flat list of every VM name created"
  value = concat(
    [for vm in azurerm_linux_virtual_machine.lab_vm   : vm.name],
    [for vm in azurerm_windows_virtual_machine.lab_vm : vm.name]
  )
}
