provider "hcloud" {
  token = var.HCLOUD_TOKEN
}

data "hcloud_network" "kubernetes" {
  name = "kubenet"
}

resource "hcloud_server" "kubernetes_master" {
  name = "${var.kubernetes_prefix}-master"
  image = var.kubernetes_image
  location = var.location
  server_type = var.kubernetes_master_server_type
  user_data = file("templates/cloud-init-master.tpl")
  ssh_keys = [var.ssh_key_name]
}

resource "hcloud_server_network" "kubernetes_master" {
  server_id = hcloud_server.kubernetes_master.id
  network_id = data.hcloud_network.kubernetes.id
  ip = var.kubernetes_master_internal_ip
}

