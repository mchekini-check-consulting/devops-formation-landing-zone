# ---------------------------------------------------------------------------
# Storage Account (nécessaire pour Azure Functions Consumption plan)
# Le nom doit être globalement unique, ≤ 24 cars, lowercase alphanum.
# On tronque team + project à 8 chars chacun pour rester dans la limite.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "fraud_check" {
  # st + 8 chars team + 8 chars project + env (dev) = 22 chars max ✅
  name = "st${substr(replace(var.team_name, "-", ""), 0, 8)}${substr(replace(var.project_name, "-", ""), 0, 8)}dev"

  resource_group_name      = azurerm_resource_group.main["dev"].name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  tags = merge(local.common_tags, {
    Environment = "dev"
    Component   = "fraud-check"
  })
}

# ---------------------------------------------------------------------------
# App Service Plan — Consumption (serverless, pay-per-use)
# SKU Y1 = Consumption plan Linux
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "fraud_check" {
  name                = "asp-${var.team_name}-${var.project_name}-fraud-check-dev"
  resource_group_name = azurerm_resource_group.main["dev"].name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = merge(local.common_tags, {
    Environment = "dev"
    Component   = "fraud-check"
  })
}

# ---------------------------------------------------------------------------
# Managed Identity dédiée à la Function App (principe du moindre privilège)
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "fraud_check" {
  name                = "id-${var.team_name}-${var.project_name}-fraud-check-dev"
  resource_group_name = azurerm_resource_group.main["dev"].name
  location            = var.location

  tags = merge(local.common_tags, {
    Environment = "dev"
    Component   = "fraud-check"
  })
}

# La Function App a besoin de lire/écrire dans son Storage Account
resource "azurerm_role_assignment" "fraud_check_storage" {
  scope                = azurerm_storage_account.fraud_check.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.fraud_check.principal_id
}

# ---------------------------------------------------------------------------
# Azure Function App (Linux, Python 3.11) — coquille vide
# Le code est déployé séparément via :
#   cd <repo-python> && func azure functionapp publish <name>
# ---------------------------------------------------------------------------
resource "azurerm_linux_function_app" "fraud_check" {

  name                = "func-${var.team_name}-${var.project_name}-fraud-check-dev"
  resource_group_name = azurerm_resource_group.main["dev"].name
  location            = var.location

  service_plan_id            = azurerm_service_plan.fraud_check.id
  storage_account_name       = azurerm_storage_account.fraud_check.name
  storage_account_access_key = azurerm_storage_account.fraud_check.primary_access_key

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.fraud_check.id]
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }

    cors {
      allowed_origins = var.apim_allowed_origins
    }

    ip_restriction {
      virtual_network_subnet_id = var.apim_subnet_id
      name                      = "Allow-APIM-subnet"
      priority                  = 100
      action                    = "Allow"
    }
    
    ip_restriction {
      ip_address = "${var.apim_public_ip}/32"
      name       = "Allow-APIM-public-ip"
      priority   = 110
      action     = "Allow"
    }
    
    ip_restriction_default_action = "Deny"
  }

  app_settings = {
    # --- Runtime Azure Functions ---
    FUNCTIONS_WORKER_RUNTIME    = "python"
    FUNCTIONS_EXTENSION_VERSION = "~4"

    # Indique à Azure que le code arrive via func publish (pas via Terraform), a changer quand y'aura une CICD
    WEBSITE_RUN_FROM_PACKAGE = "1"

    # --- Règles de fraude configurables par env ---
    AMOUNT_LIMIT            = tostring(var.fraud_amount_limit)
    VELOCITY_MAX_CALLS      = tostring(var.fraud_velocity_max_calls)
    VELOCITY_WINDOW_SECONDS = tostring(var.fraud_velocity_window_seconds)
    BLACKLISTED_IPS         = join(",", var.fraud_blacklisted_ips)

    # --- Environnement (utile pour les logs / traces) ---
    ENVIRONMENT = "dev"
  }

  https_only = true

  tags = merge(local.common_tags, {
    Environment = "dev"
    Component   = "fraud-check"
  })

  depends_on = [
    azurerm_role_assignment.fraud_check_storage,
  ]
}
