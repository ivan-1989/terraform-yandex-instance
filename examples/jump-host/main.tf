data "yandex_client_config" "client" {}


#resource "random_id" "unique" {
##   min = 1000
##   max = 9999
#   byte_length = 8
#}

resource "random_id" "unique_name" {
   byte_length = 2
}

resource "random_password" "password" {
#  for_each         = { for v in var.users : v.name => v if v.password == null }
  length           = 16
  special          = true
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "_"
}

data "local_file" "setup-sh" {
  filename = "./templates/setup.sh.tpl"
}  

data "local_file" "nginx_vs_default_conf" {
  filename = "./templates/nginx_vs_default.conf.tpl"
}  

locals {
  user = "ubuntu"
  VS_PASS = "${random_password.password.result}"
  user_home_fold = "/home/${local.user}"
  scripts_fold = "${local.user_home_fold}/"
  ssh_key_pub = "C:\\Users\\ivan\\.ssh\\id_rsa.pub"
  ssh_key_prv = "C:\\Users\\ivan\\.ssh\\id_rsa"
  prefix = "jump-host"
}

module "iam_accounts" {
  source = "git::https://github.com/terraform-yacloud-modules/terraform-yandex-iam.git//modules/iam-account?ref=v1.0.0"

  name = "${local.prefix}-sa-${random_id.unique_name.hex}"
  folder_roles = [
    "editor"
#    "container-registry.images.puller",
#    "k8s.clusters.agent",
#    "k8s.tunnelClusters.agent",
#    "load-balancer.admin",
#    "logging.writer",
#    "vpc.privateAdmin",
#    "vpc.publicAdmin",
#    "vpc.user",
  ]
  cloud_roles              = []
  enable_static_access_key = false
  enable_api_key           = false
  enable_account_key       = false

}


module "network" {
  source = "git::https://github.com/terraform-yacloud-modules/terraform-yandex-vpc.git?ref=v1.0.0"
  folder_id = data.yandex_client_config.client.folder_id
  blank_name = "${local.prefix}-net-${random_id.unique_name.hex}"
  labels = {
    repo = "terraform-yacloud-modules/terraform-yandex-vpc"
  }
  azs = ["ru-central1-a", "ru-central1-b", "ru-central1-d"]
  private_subnets = [["10.1.10.0/24"], ["10.1.20.0/24"], ["10.1.30.0/24"]]
  create_vpc         = true
  create_nat_gateway = true
}

module "yandex_compute_instance" {
  source = "../../"
  folder_id = data.yandex_client_config.client.folder_id
  name = "${local.prefix}-${random_id.unique_name.hex}"
  zone       = "ru-central1-a"
  subnet_id  = module.network.private_subnets_ids[0]
  enable_nat = true
  create_pip = true

  hostname = "${local.prefix}-${random_id.unique_name.hex}"
  generate_ssh_key = false
  ssh_user         = local.user
  ssh_pubkey       = local.ssh_key_pub
  service_account_id = module.iam_accounts.id
  boot_disk_initialize_params = {size = "30"}
  image_family = "toolbox"

}

module "instance_secret" {
  source = "git::https://github.com/terraform-yacloud-modules/terraform-yandex-lockbox.git?ref=v1.0.0"

  name = "${local.prefix}-secret-${random_id.unique_name.hex}"

  entries =  {
    "VS_PASS" : local.VS_PASS
  }
  deletion_protection = false
}

resource "yandex_vpc_default_security_group" "default-sg" {
  description = "description for default security group"
  network_id  = "${module.network.vpc_id}"

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  egress {
    protocol       = "ANY"
    description    = "Pass to all"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port      = 65535
  }
}

resource "null_resource" "provision" {
  depends_on = [module.yandex_compute_instance]

  provisioner "file" {
    content     = templatefile(data.local_file.nginx_vs_default_conf.filename, {public_ip = module.yandex_compute_instance.instance_public_ip})
#    destination = "/tmp/nginx_default.conf"
    destination = "${local.scripts_fold}/nginx_default.conf"
    connection {
      type        = "ssh"
      user        = local.user
      private_key = "${file(local.ssh_key_prv)}"
      host        = module.yandex_compute_instance.instance_public_ip
    }
  }

  provisioner "file" {
    content = templatefile(data.local_file.setup-sh.filename, {public_ip = module.yandex_compute_instance.instance_public_ip, VS_PASS = local.VS_PASS})
    destination = "${local.scripts_fold}/setup.sh"
    connection {
      type        = "ssh"
      user        = local.user
      private_key = "${file(local.ssh_key_prv)}"
      host        = module.yandex_compute_instance.instance_public_ip
    }
  }
  provisioner "remote-exec" {
    inline = [
      "bash ${local.scripts_fold}/setup.sh"
    ]
    connection {
      type        = "ssh"
      user        = local.user
      private_key = "${file(local.ssh_key_prv)}"
      host        = module.yandex_compute_instance.instance_public_ip
    }
  }
}