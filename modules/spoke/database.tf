#--------------------------------------------------------------
# PostgreSQL Flexible Server
#--------------------------------------------------------------

resource "azurerm_private_dns_zone" "postgres_dns" {
  for_each            = toset(var.environments)
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main[each.key].name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_dns_link" {
  for_each              = toset(var.environments)
  name                  = "postgres-dns-link"
  resource_group_name   = azurerm_resource_group.main[each.key].name
  private_dns_zone_name = azurerm_private_dns_zone.postgres_dns[each.key].name
  virtual_network_id    = azurerm_virtual_network.main[each.key].id
  tags                  = var.tags
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  for_each = toset(var.environments)

  name                = "${var.postgres_server_name}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main[each.key].name

  administrator_login    = var.postgres_admin_login
  administrator_password = var.postgres_admin_password

  sku_name   = var.postgres_sku_name
  version    = var.postgres_version
  storage_mb = var.postgres_storage_mb

  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = false

  delegated_subnet_id           = azurerm_subnet.subnet-data[each.key].id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres_dns[each.key].id
  public_network_access_enabled = false

  tags = merge(local.common_tags, {
    Environment = each.key
  })

  lifecycle {
    ignore_changes = [zone]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres_dns_link
  ]
}

resource "azurerm_postgresql_flexible_server_database" "dbs" {
  for_each = {
    for item in flatten([
      for env in var.environments : [
        for db_name, db_config in var.postgres_databases : {
          key       = "${env}-${db_name}"
          env       = env
          db_name   = db_name
          charset   = db_config.charset
          collation = db_config.collation
        }
      ]
    ]) : item.key => item
  }

  name      = each.value.db_name
  server_id = azurerm_postgresql_flexible_server.postgres[each.value.env].id
  charset   = each.value.charset
  collation = each.value.collation

  depends_on = [
    azurerm_postgresql_flexible_server.postgres
  ]
}