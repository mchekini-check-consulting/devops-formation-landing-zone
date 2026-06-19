# =============================================================================
# .tflint.hcl — Configuration TFLint
# Référence : https://github.com/terraform-linters/tflint
# Plugin AzureRM : https://github.com/terraform-linters/tflint-ruleset-azurerm
# =============================================================================

# ── Plugin officiel AzureRM ──────────────────────────────────────────────────
# Téléchargé automatiquement par `tflint --init`
plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# ── Configuration globale ────────────────────────────────────────────────────
config {
  # none : n'analyse que le répertoire courant (les sous-modules sont appelés
  # via --recursive dans la pipeline, pas via ce flag)
  call_module_type = "none"
}

# =============================================================================
# RÈGLES TERRAFORM BUILT-IN
# Documentation : https://github.com/terraform-linters/tflint/tree/master/docs/rules
# =============================================================================

# Bloque l'ancienne syntaxe d'interpolation "${var.foo}" quand "$${var.foo}" suffit
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Bloque l'accès par index legacy (list.0 au lieu de list[0])
rule "terraform_deprecated_index" {
  enabled = true
}

# Signale les variables, outputs et data sources déclarés mais jamais utilisés
rule "terraform_unused_declarations" {
  enabled = true
}

# Force les commentaires # ou // (pas les commentaires HCL natifs /*...*/)
rule "terraform_comment_syntax" {
  enabled = true
}

# Oblige le typage explicite des variables (type = string | number | bool | list | map | object)
rule "terraform_typed_variables" {
  enabled = true
}

# Vérifie que les sources de modules sont pinned à une version
# style = "flexible" : accepte les refs git, les chemins locaux ET les versions semver
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "flexible"
}

# Vérifie la présence d'un bloc terraform { required_version = "..." }
rule "terraform_required_version" {
  enabled = true
}

# Vérifie la présence d'un bloc required_providers avec source et version
rule "terraform_required_providers" {
  enabled = true
}

# Conventions de nommage snake_case pour toutes les ressources
rule "terraform_naming_convention" {
  enabled = true

  resource {
    format = "snake_case"
  }

  data_source {
    format = "snake_case"
  }

  module {
    format = "snake_case"
  }

  variable {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }

  locals {
    format = "snake_case"
  }
}

# Désactivé : trop strict pour un repo de formation (documentation optionnelle)
rule "terraform_documented_outputs" {
  enabled = false
}

rule "terraform_documented_variables" {
  enabled = false
}
