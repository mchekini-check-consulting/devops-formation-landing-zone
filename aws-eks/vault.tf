# Cle KMS pour l'auto-unseal de Vault (seal "awskms"), equivalent AWS du
# seal "azurekeyvault" utilise sur AKS.
resource "aws_kms_key" "vault_unseal" {
  description             = "Auto-unseal Vault (${var.team_name}-${var.project_name})"
  deletion_window_in_days = 7
  tags                    = var.tags
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.team_name}-${var.project_name}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# IRSA scope au service account "vault" dans le namespace "vault" (nom par
# defaut du chart Helm HashiCorp pour un Application ArgoCD nommee "vault").
data "aws_iam_policy_document" "vault_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:vault:vault"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault" {
  name               = "role-${var.team_name}-${var.project_name}-vault"
  assume_role_policy = data.aws_iam_policy_document.vault_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "vault_kms" {
  statement {
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.vault_unseal.arn]
  }
}

resource "aws_iam_role_policy" "vault_kms" {
  name   = "vault-kms-unseal"
  role   = aws_iam_role.vault.id
  policy = data.aws_iam_policy_document.vault_kms.json
}

output "vault_kms_key_id" {
  value = aws_kms_key.vault_unseal.key_id
}

output "vault_iam_role_arn" {
  value = aws_iam_role.vault.arn
}
