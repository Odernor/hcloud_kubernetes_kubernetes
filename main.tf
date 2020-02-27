provider "hcloud" {
  token = var.HCLOUD_TOKEN
}

data "hcloud_network" "kubernetes" {
  name = "kubenet"
}

data "hcloud_floating_ip" "kubernetes" {
  name = "kubernetes-loadbalancer"
}

data "template_file" "cloud_init_master" {
  template = file("templates/cloud-init-master.tpl")

  vars = {
    floating_ip = data.hcloud_floating_ip.kubernetes.ip_address
  }
}

output "bla" {
  value = data.template_file.cloud_init_master.rendered
}

resource "hcloud_server" "kubernetes_master" {
  name = "${var.kubernetes_prefix}-master"
  image = var.kubernetes_image
  location = var.location
  server_type = var.kubernetes_master_server_type
  user_data = data.template_file.cloud_init_master.rendered
  ssh_keys = [var.ssh_key_name]
}

resource "hcloud_server_network" "kubernetes_master" {
  server_id = hcloud_server.kubernetes_master.id
  network_id = data.hcloud_network.kubernetes.id
  ip = var.kubernetes_master_internal_ip
}
