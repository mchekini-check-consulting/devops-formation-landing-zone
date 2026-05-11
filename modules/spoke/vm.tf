locals {
  vm_target_environments = [
    for env in var.environments : env
    if lower(env) != "prod" && contains(var.vm_environments, env)
  ]

  vm_services = {
    front = {
      count = var.vm_count.front
      tier  = "front"
    }
    back = {
      count = var.vm_count.back
      tier  = "back"
    }
  }

  docker_install_cloud_init = <<-EOT
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
      - jq
    runcmd:
      - while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done
      - install -m 0755 -d /etc/apt/keyrings
      - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
      - cat /tmp/docker.asc | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      - chmod a+r /etc/apt/keyrings/docker.gpg
      - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
      - apt-get update
      - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      - systemctl enable docker
      - systemctl start docker
      - usermod -aG docker ${var.vm_admin_username}
      - |
        for FILE in create-service.sh deploy.sh docker-compose.back.yaml docker-compose.front.yaml nginx-proxy.conf; do
          curl -sL \
            "https://raw.githubusercontent.com/juba-touam/start-up-scritps/main/$FILE" \
            -o "/home/${var.vm_admin_username}/$FILE"
        done
      - chmod +x /home/${var.vm_admin_username}/*.sh
      - /home/${var.vm_admin_username}/create-service.sh
  EOT

  vm_instances_list = flatten([
    for env in local.vm_target_environments : [
      for service_name, service_config in local.vm_services : [
        for instance_number in range(1, service_config.count + 1) : {
          key     = "${env}-${service_name}-${format("%02d", instance_number)}"
          env     = env
          service = service_name
          index   = instance_number
          tier    = service_config.tier
        }
      ]
    ]
  ])

  vm_instances = {
    for vm in local.vm_instances_list : vm.key => vm
  }

  front_vm_instances = {
    for k, v in local.vm_instances : k => v
    if v.tier == "front"
  }
}

data "azurerm_key_vault_secret" "admin_ssh_public_key" {
  name         = var.ssh_public_key_secret_name
  key_vault_id = var.key_vault_id
}

resource "azurerm_public_ip" "front" {
  for_each            = local.front_vm_instances
  name                = "pip-${var.team_name}-${var.project_name}-front-${each.value.env}-${format("%02d", each.value.index)}"
  location            = azurerm_resource_group.main[each.value.env].location
  resource_group_name = azurerm_resource_group.main[each.value.env].name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(local.common_tags, {
    Environment = each.value.env
    Tier        = "front"
  })
}

resource "azurerm_network_interface" "vm" {
  for_each = local.vm_instances

  name                = "nic-${var.team_name}-${var.project_name}-${each.value.service}-${each.value.env}-${format("%02d", each.value.index)}"
  location            = azurerm_resource_group.main[each.value.env].location
  resource_group_name = azurerm_resource_group.main[each.value.env].name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = each.value.service == "front" ? azurerm_subnet.subnet-front[each.value.env].id : azurerm_subnet.subnet-back[each.value.env].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value.tier == "front" ? azurerm_public_ip.front[each.key].id : null
  }

  tags = merge(local.common_tags, {
    Environment = each.value.env
    Tier        = each.value.tier
  })
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.vm_instances

  name                = "vm-${var.team_name}-${var.project_name}-${each.value.service}-${each.value.env}-${format("%02d", each.value.index)}"
  location            = azurerm_resource_group.main[each.value.env].location
  resource_group_name = azurerm_resource_group.main[each.value.env].name
  size                = var.vm_size
  admin_username      = var.vm_admin_username

  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  custom_data                     = base64encode(local.docker_install_cloud_init)

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = data.azurerm_key_vault_secret.admin_ssh_public_key.value
  }

  os_disk {
    name                 = "osdisk-${var.team_name}-${var.project_name}-${each.value.service}-${each.value.env}-${format("%02d", each.value.index)}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr[each.value.env].id]
  }

  tags = merge(local.common_tags, {
    Environment = each.value.env
    Tier        = each.value.tier
  })
}

#--------------------------------------------------------------
# Extension AAD SSH Login
#--------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  for_each = local.vm_instances

  name                 = "AADSSHLoginForLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm[each.key].id
  publisher            = "Microsoft.Azure.ActiveDirectory"
  type                 = "AADSSHLoginForLinux"
  type_handler_version = "1.0"

  tags = merge(local.common_tags, {
    Environment = each.value.env
  })
}
