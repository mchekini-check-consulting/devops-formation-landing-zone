#!/bin/bash
terraform apply \
  -target='module.hub.azurerm_api_management_api_policy.routing' \
  -target='module.hub.azurerm_api_management_api_operation.catchall_options' \
  -target='module.hub.azurerm_api_management_api_operation.catchall_patch' \
  -target='module.hub.azurerm_api_management_api_operation.catchall_post' \
  -target='module.hub.azurerm_api_management_api_operation.catchall_put' \
  -target='module.hub.azurerm_api_management_api_operation.payments_post' \
  -target='module.hub.azurerm_api_management_named_value.catalog_rate_limit' \
  -target='module.hub.azurerm_api_management_named_value.fraud_check_url' \
  -target='module.hub.azurerm_api_management_named_value.order_rate_limit' \
  -target='module.hub.azurerm_api_management_named_value.payment_rate_limit' \
  -target='module.hub.azurerm_subnet_network_security_group_association.apim' \
  -target='module.hub.azurerm_network_security_group.apim' \
  -target='module.hub.azurerm_subnet.subnet-apim' \
  -target='module.spoke.azurerm_linux_function_app.fraud_check["dev"]' \
  -target='module.spoke.azurerm_role_assignment.fraud_check_storage["dev"]' \
  -target='module.spoke.azurerm_service_plan.fraud_check["dev"]' \
  -target='module.spoke.azurerm_storage_account.fraud_check["dev"]' \
  -target='module.spoke.azurerm_user_assigned_identity.fraud_check["dev"]'
