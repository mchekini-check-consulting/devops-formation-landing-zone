resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  # Pas de version fixee : EKS utilise la derniere version stable disponible
  # au moment de l'apply. A figer explicitement plus tard si besoin de
  # controler les mises a jour dans le temps.

  vpc_config {
    subnet_ids              = aws_subnet.eks[*].id
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # Pas de enabled_cluster_log_types : logging CloudWatch desactive pour
  # limiter les couts sur ce cluster de formation.

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# Isole les composants critiques (CoreDNS, controllers) sur un pool dedie
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.eks[*].id
  instance_types  = [var.system_instance_type]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
  ]
}

# Pas d'image_id : EKS resout l'AMI AL2023 standard et fusionne notre
# user_data (config nodeadm additionnelle) avec son propre bootstrap de
# jonction au cluster. maxPods=110 -- cf. addon vpc-cni (ENABLE_PREFIX_DELEGATION),
# le kubelet ne recalcule pas ce plafond tout seul a partir du CNI.
resource "aws_launch_template" "apps" {
  name_prefix   = "lt-${var.team_name}-${var.project_name}-apps-"
  instance_type = var.apps_instance_type

  # AL2023 + launch template custom exige un MIME multipart : sans
  # l'enveloppe, EKS ne peut pas fusionner ce NodeConfig avec son propre
  # bootstrap de jonction au cluster (erreur "not in MIME multipart format").
  user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: 110

    --//--
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tags = var.tags
}

# Charge applicative generale -- fixe pour l'instant, autoscaling reporte (Karpenter)
resource "aws_eks_node_group" "apps" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "apps"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.eks[*].id

  launch_template {
    id      = aws_launch_template.apps.id
    version = aws_launch_template.apps.latest_version
  }

  scaling_config {
    desired_size = var.apps_min_count
    min_size     = var.apps_min_count
    max_size     = var.apps_min_count
  }

  labels = {
    workload = "apps"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
  ]
}

# Pool dedie base de donnees -- taint + label pour isoler ce workload
resource "aws_eks_node_group" "db" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "db"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.eks[*].id
  instance_types  = [var.db_instance_type]

  scaling_config {
    desired_size = var.db_node_count
    min_size     = var.db_node_count
    max_size     = var.db_node_count
  }

  labels = {
    workload = "database"
  }

  taint {
    key    = "workload"
    value  = "database"
    effect = "NO_SCHEDULE"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
  ]
}
