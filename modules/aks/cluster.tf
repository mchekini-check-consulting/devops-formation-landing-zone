resource "azurerm_kubernetes_cluster" "aks" {
  name                    = "aks-${var.team_name}-${var.project_name}"
  location                = azurerm_resource_group.aks.location
  resource_group_name     = azurerm_resource_group.aks.name
  dns_prefix              = "aks-${var.team_name}-${var.project_name}"
  private_cluster_enabled = false
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags                    = var.tags

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                        = "system"
    node_count                  = 1
    vm_size                     = var.system_vm_size
    vnet_subnet_id              = azurerm_subnet.aks.id
    only_critical_addons_enabled = true
    temporary_name_for_rotation = "systemtmp"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = var.acr_id
  skip_service_principal_aad_check = true
}
