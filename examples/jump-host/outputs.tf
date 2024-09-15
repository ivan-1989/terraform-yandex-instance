#output "instance_private_ip" {
#  value = module.yandex_compute_instance.instance_private_ip
#}
#
output "public_ip" {
  value = module.yandex_compute_instance.instance_public_ip
}

output "VS_URL" {
  value = "https://code.${module.yandex_compute_instance.instance_public_ip}.sslip.io"

}

output "VS_PASS" {
  value = local.VS_PASS
}

