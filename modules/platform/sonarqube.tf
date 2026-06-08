resource "random_password" "sonarqube_admin" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]<>?"
}

resource "random_password" "sonarqube_db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]<>?"
}

resource "random_password" "sonarqube_monitoring" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]<>?"
}

resource "azurerm_key_vault_secret" "sonarqube_admin_password" {
  name         = "sonar-admin-password"
  value        = random_password.sonarqube_admin.result
  key_vault_id = var.key_vault_id

  tags = {
    Team      = var.team_name
    Component = "sonarqube"
    ManagedBy = "Terraform"
  }
}

resource "azurerm_key_vault_secret" "sonarqube_db_password" {
  name         = "sonar-db-password"
  value        = random_password.sonarqube_db.result
  key_vault_id = var.key_vault_id

  tags = {
    Team      = var.team_name
    Component = "sonarqube"
    ManagedBy = "Terraform"
  }
}

resource "azurerm_key_vault_secret" "sonarqube_monitoring_passcode" {
  name         = "sonar-monitoring-passcode"
  value        = random_password.sonarqube_monitoring.result
  key_vault_id = var.key_vault_id

  tags = {
    Team      = var.team_name
    Component = "sonarqube"
    ManagedBy = "Terraform"
  }
}

resource "helm_release" "sonarqube" {
  name             = "sonarqube"
  repository       = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart            = "sonarqube"
  version          = var.sonarqube_chart_version
  namespace        = "sonarqube"
  create_namespace = true
  timeout          = 600
  wait             = true
  wait_for_jobs    = true

  values = [
    templatefile("${path.root}/k8s/sonarqube/sonarqube-values.yaml", {
      sonar_admin_password = random_password.sonarqube_admin.result
      pg_password          = random_password.sonarqube_db.result
      monitoring_passcode  = random_password.sonarqube_monitoring.result
    })
  ]

  depends_on = [
    azurerm_key_vault_secret.sonarqube_admin_password,
    azurerm_key_vault_secret.sonarqube_db_password,
  ]
}
