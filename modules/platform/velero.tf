resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = "8.1.0"
  namespace        = "velero"
  create_namespace = true

  values = [
    templatefile("${path.root}/k8s/velero/velero-values.yaml", {
      storage_account   = var.velero_storage_account
      storage_container = var.velero_storage_container
      resource_group    = var.velero_resource_group
      subscription_id   = var.velero_subscription_id
      uami_client_id    = var.velero_uami_client_id
    })
  ]

}