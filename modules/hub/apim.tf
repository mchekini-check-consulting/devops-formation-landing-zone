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

resource "azurerm_api_management_api_policy" "routing" {
  api_name            = azurerm_api_management_api.main.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.devops.name

  xml_content = <<-XML
<policies>
  <inbound>
    <base />
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>GET</method>
        <method>POST</method>
        <method>PUT</method>
        <method>DELETE</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
      <expose-headers>
        <header>*</header>
      </expose-headers>
    </cors>
    <choose>
      <when condition="@(context.Request.Url.Path.Contains(&quot;api/products&quot;))">
        <set-backend-service base-url="http://10.1.1.4:4000" />
      </when>
      <when condition="@(context.Request.Url.Path.Contains(&quot;api/orders&quot;))">
        <set-backend-service base-url="http://10.1.1.4:8000" />
      </when>
      <when condition="@(context.Request.Url.Path.Contains(&quot;api/payments&quot;))">
        <set-backend-service base-url="http://10.1.1.4:8082" />
      </when>
      <otherwise>
        <return-response>
          <set-status code="404" reason="Not Found" />
        </return-response>
      </otherwise>
    </choose>
    <set-header name="Origin" exists-action="delete" />
  </inbound>
  <backend>
    <forward-request />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
}

