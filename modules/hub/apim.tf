resource "azurerm_network_security_group" "apim" {
  name                = "nsg-${var.team_name}-apim"
  location            = var.location
  resource_group_name = azurerm_resource_group.network.name

  security_rule {
    name                       = "Allow-APIM-Management"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Allow-LoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "Allow-AzureCloud-Outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "Allow-SQL-Outbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "Allow-KeyVault-Outbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "Allow-Backends-Outbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["4000", "8000", "8082"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "10.1.1.0/24"
  }

  security_rule {
    name                       = "Allow-Keycloak-Outbound"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = local.keycloak_subnet_prefix
  }

  tags = merge(local.common_tags, { Function = "apim" })
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.subnet-apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

resource "azurerm_api_management" "main" {
  name                = "ecom-apim-${var.team_name}"
  resource_group_name = azurerm_resource_group.devops.name
  location            = var.location
  publisher_name      = "apim-${var.team_name}"
  publisher_email     = var.apim_publisher_email
  sku_name            = "Developer_1"

  virtual_network_type = "External"

  virtual_network_configuration {
    subnet_id = azurerm_subnet.subnet-apim.id
  }

  depends_on = [azurerm_subnet_network_security_group_association.apim]

  tags = merge(local.common_tags, { Function = "apim" })
}

#--------------------------------------------------------------
# Routage APIM
#--------------------------------------------------------------
resource "azurerm_api_management_api" "main" {
  name                  = "ecom-api"
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = azurerm_resource_group.devops.name
  revision              = "1"
  display_name          = "Ecom API"
  path                  = ""
  protocols             = ["https"]
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "payments_post" {
  operation_id        = "payments-post"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Payments POST"
  method              = "POST"
  url_template        = "/api/payments"
}

resource "azurerm_api_management_api_operation" "catchall" {
  operation_id        = "catchall"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Catch All"
  method              = "GET"
  url_template        = "/{*path}"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "catchall_post" {
  operation_id        = "catchall-post"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Catch All POST"
  method              = "POST"
  url_template        = "/{*path}"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "catchall_put" {
  operation_id        = "catchall-put"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Catch All PUT"
  method              = "PUT"
  url_template        = "/{*path}"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "catchall_delete" {
  operation_id        = "catchall-delete"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Catch All DELETE"
  method              = "DELETE"
  url_template        = "/{*path}"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "catchall_options" {
  operation_id        = "catchall-options"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Catch All OPTIONS"
  method              = "OPTIONS"
  url_template        = "/{*path}"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "catchall_patch" {
  operation_id        = "catchall-patch"
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  display_name        = "Catch All PATCH"
  method              = "PATCH"
  url_template        = "/{*path}"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_backend" "keycloak" {
  name                = "keycloak-backend"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  protocol            = "http"
  url                 = "https://${azurerm_network_interface.keycloak.ip_configuration[0].private_ip_address}:8443"

  tls {
    validate_certificate_chain = false
    validate_certificate_name  = false
  }
}

resource "azurerm_api_management_api_operation_policy" "payments_post_policy" {
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name
  api_name            = azurerm_api_management_api.main.name
  operation_id        = azurerm_api_management_api_operation.payments_post.operation_id

  xml_content = file("${path.module}/policies/apim-policy-payments.xml")

  depends_on = [
    azurerm_api_management_named_value.fraud_check_url,
    azurerm_api_management_api_policy.routing,
  ]
}

resource "azurerm_api_management_named_value" "fraud_check_url" {
  name                = "fraud-check-url"
  display_name        = "fraud-check-url"
  resource_group_name = azurerm_resource_group.devops.name
  api_management_name = azurerm_api_management.main.name
  value               = var.fraud_check_function_urls["dev"]
  secret              = false
}

resource "azurerm_api_management_named_value" "catalog_rate_limit" {
  name                = "catalog-rate-limit"
  display_name        = "catalog-rate-limit"
  resource_group_name = azurerm_resource_group.devops.name
  api_management_name = azurerm_api_management.main.name
  value               = tostring(var.catalog_rate_limit)
  secret              = false
}

resource "azurerm_api_management_named_value" "order_rate_limit" {
  name                = "order-rate-limit"
  display_name        = "order-rate-limit"
  resource_group_name = azurerm_resource_group.devops.name
  api_management_name = azurerm_api_management.main.name
  value               = tostring(var.order_rate_limit)
  secret              = false
}

resource "azurerm_api_management_named_value" "payment_rate_limit" {
  name                = "payment-rate-limit"
  display_name        = "payment-rate-limit"
  resource_group_name = azurerm_resource_group.devops.name
  api_management_name = azurerm_api_management.main.name
  value               = tostring(var.payment_rate_limit)
  secret              = false
}

resource "azurerm_api_management_api_policy" "routing" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name

  depends_on = [
    azurerm_api_management_backend.keycloak,
    azurerm_api_management_named_value.catalog_rate_limit,
    azurerm_api_management_named_value.order_rate_limit,
    azurerm_api_management_named_value.payment_rate_limit,
  ]

  xml_content = templatefile("${path.module}/policies/apim-policy-routing.xml", {
    frontend_public_ip = var.frontend_public_ip
    backend_vm_ip      = var.backend_vm_ip
    payment_lb_ip      = var.payment_lb_ip
  })
}

