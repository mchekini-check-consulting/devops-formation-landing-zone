#--------------------------------------------------------------
# Load Balancer - HA Payment Service
#--------------------------------------------------------------

resource "azurerm_lb" "payment" {
  for_each = toset(var.environments)

  name                = "lb-${var.team_name}-${var.project_name}-payment-${each.key}"
  location            = azurerm_resource_group.main[each.key].location
  resource_group_name = azurerm_resource_group.main[each.key].name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "payment-frontend"
    subnet_id                     = azurerm_subnet.subnet-back[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(local.subnets[each.key].back, 10)
  }

  tags = merge(local.common_tags, {
    Environment = each.key
    Tier        = "backend"
  })
}

resource "azurerm_lb_backend_address_pool" "payment" {
  for_each = azurerm_lb.payment

  name            = "payment-backend-pool"
  loadbalancer_id = each.value.id
}

resource "azurerm_lb_probe" "payment_health" {
  for_each = azurerm_lb.payment

  name                = "payment-health-probe"
  loadbalancer_id     = each.value.id
  protocol            = "Http"
  port                = 8082
  request_path        = "/actuator/health"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "payment" {
  for_each = azurerm_lb.payment

  name                           = "payment-rule"
  loadbalancer_id                = each.value.id
  protocol                       = "Tcp"
  frontend_port                  = 8082
  backend_port                   = 8082
  frontend_ip_configuration_name = "payment-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.payment[each.key].id]
  probe_id                       = azurerm_lb_probe.payment_health[each.key].id
}


#--------------------------------------------------------------
# Association des NICs backend au pool du LB
#--------------------------------------------------------------
resource "azurerm_network_interface_backend_address_pool_association" "payment" {
  for_each = {
    for key, vm in local.vm_instances : key => vm
    if vm.service == "back"
  }

  network_interface_id    = azurerm_network_interface.vm[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.payment[each.value.env].id
}
