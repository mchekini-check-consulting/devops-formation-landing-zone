output "key_vault_id" {
  value = module.hub.key_vault_id
}

output "key_vault_name" {
  value = module.hub.key_vault_name
}


output "acr_login_server" {
  description = "URL du registre ACR pour pull les images (docker pull <url>/<image>:<tag>)"
  value       = module.hub.acr_login_server
}

output "acr_id" {
  description = "ID de l'ACR pour les role assignments"
  value       = module.hub.acr_id
}

#--------------------------------------------------------------
# PostgreSQL Outputs
#--------------------------------------------------------------

output "postgres_fqdns" {
  description = "FQDNs des serveurs PostgreSQL par environnement (utilisez ces URLs pour vous connecter)"
  value       = module.spoke.postgres_fqdns
}

output "postgres_server_ids" {
  description = "IDs des serveurs PostgreSQL par environnement"
  value       = module.spoke.postgres_server_ids
}

output "postgres_server_names" {
  description = "Noms des serveurs PostgreSQL par environnement"
  value       = module.spoke.postgres_server_names
}