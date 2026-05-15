#--------------------------------------------------------------
# NSG - Network Security Groups
#--------------------------------------------------------------

# NSG Frontend
resource "azurerm_network_security_group" "front" {
  for_each = toset(var.environments)

  name                = "nsg-${var.team_name}-${var.project_name}-front-${each.key}"
  location            = azurerm_resource_group.main[each.key].location
  resource_group_name = azurerm_resource_group.main[each.key].name

  tags = merge(local.common_tags, {
    Environment = each.key
    Tier        = "frontend"
  })
}

resource "azurerm_network_security_rule" "front_http" {
  for_each = toset(var.environments)

  name                        = "Allow-HTTP-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.front[each.key].name
}

resource "azurerm_network_security_rule" "front_https" {
  for_each = toset(var.environments)

  name                        = "Allow-HTTPS-Inbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.front[each.key].name
}

resource "azurerm_network_security_rule" "front_ssh" {
  for_each = toset([for env in var.environments : env if env != "prod"])

  name                        = "Allow-SSH-Inbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.front[each.key].name
}

resource "azurerm_subnet_network_security_group_association" "front" {
  for_each = toset(var.environments)

  subnet_id                 = azurerm_subnet.subnet-front[each.key].id
  network_security_group_id = azurerm_network_security_group.front[each.key].id
}

#--------------------------------------------------------------
# NSG Backend
#--------------------------------------------------------------

resource "azurerm_network_security_group" "back" {
  for_each = toset(var.environments)

  name                = "nsg-${var.team_name}-${var.project_name}-backend-${each.key}"
  location            = azurerm_resource_group.main[each.key].location
  resource_group_name = azurerm_resource_group.main[each.key].name

  tags = merge(local.common_tags, {
    Environment = each.key
    Tier        = "backend"
  })
}

resource "azurerm_network_security_rule" "back_payments_from_apim" {
  for_each = toset(var.environments)

  name                        = "Allow-Payments-From-APIM"
  priority                    = 103
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8082"
  source_address_prefix       = var.apim_subnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.back[each.key].name
}

resource "azurerm_network_security_rule" "back_orders_from_apim" {
  for_each = toset(var.environments)

  name                        = "Allow-Orders-From-APIM"
  priority                    = 104
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8000"
  source_address_prefix       = var.apim_subnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.back[each.key].name
}

resource "azurerm_network_security_rule" "back_catalog_from_apim" {
  for_each = toset(var.environments)

  name                        = "Allow-Catalog-From-APIM"
  priority                    = 105
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "4000"
  source_address_prefix       = var.apim_subnet_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.back[each.key].name
}

resource "azurerm_network_security_rule" "back_ssh" {
  for_each = toset([for env in var.environments : env if env != "prod"])

  name                        = "Allow-SSH-Inbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.back[each.key].name
}

resource "azurerm_subnet_network_security_group_association" "back" {
  for_each = toset(var.environments)

  subnet_id                 = azurerm_subnet.subnet-back[each.key].id
  network_security_group_id = azurerm_network_security_group.back[each.key].id
}

#--------------------------------------------------------------
# NSG Data
#--------------------------------------------------------------

resource "azurerm_network_security_group" "data" {
  for_each = toset(var.environments)

  name                = "nsg-${var.team_name}-${var.project_name}-data-${each.key}"
  location            = azurerm_resource_group.main[each.key].location
  resource_group_name = azurerm_resource_group.main[each.key].name

  tags = merge(local.common_tags, {
    Environment = each.key
    Tier        = "data"
  })
}

resource "azurerm_network_security_rule" "data_postgres_from_back" {
  for_each = toset(var.environments)

  name                        = "Allow-PostgreSQL-From-Backend"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5432"
  source_address_prefix       = local.subnets[each.key].back
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.data[each.key].name
}

resource "azurerm_network_security_rule" "data_ssh" {
  for_each = toset([for env in var.environments : env if env != "prod"])

  name                        = "Allow-SSH-Inbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.data[each.key].name
}

resource "azurerm_network_security_rule" "data_deny_internet" {
  for_each = toset([for env in var.environments : env if env == "prod"])

  name                        = "Deny-Internet-Outbound"
  priority                    = 4000
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.main[each.key].name
  network_security_group_name = azurerm_network_security_group.data[each.key].name
}

resource "azurerm_subnet_network_security_group_association" "data" {
  for_each = toset(var.environments)

  subnet_id                 = azurerm_subnet.subnet-data[each.key].id
  network_security_group_id = azurerm_network_security_group.data[each.key].id
}
