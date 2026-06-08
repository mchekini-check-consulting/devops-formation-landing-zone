resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.apps_vm_size
  min_count             = var.apps_min_count
  max_count             = var.apps_max_count
  auto_scaling_enabled  = true
  vnet_subnet_id        = azurerm_subnet.aks.id
  zones                 = ["1", "3"]
  tags                  = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "db" {
  name                  = "db"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.db_vm_size
  node_count            = var.db_node_count
  auto_scaling_enabled  = false
  vnet_subnet_id        = azurerm_subnet.aks.id
  zones                 = ["1", "3"]
  tags                  = var.tags

  node_taints = ["workload=database:NoSchedule"]

  node_labels = {
    workload = "database"
  }
}
