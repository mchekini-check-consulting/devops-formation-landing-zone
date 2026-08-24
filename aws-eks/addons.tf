resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    aws_eks_node_group.system,
    aws_eks_node_group.apps,
    aws_eks_node_group.db,
  ]
}

# vpc-cni tourne deja sur le cluster mais pas comme addon EKS gere (installe
# en composant natif au bootstrap, absent de `aws eks list-addons`) : pas
# d'objet a importer, Terraform doit l'adopter via CreateAddon (OVERWRITE).
# But : activer la prefix delegation -- chaque IP secondaire d'ENI devient un
# prefixe /28 (16 IP) au lieu d'1 IP, ce qui fait passer le plafond de pods
# par noeud de 17 a 110 (cap kubelet) sur des t3.medium, sans ajouter de noeud.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
