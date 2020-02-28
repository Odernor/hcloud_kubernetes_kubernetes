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
    kubernetes_version = var.kubernetes_version
    kubernetes_master_ip = var.kubernetes_master_internal_ip
    kubernetes_token = var.kubernetes_token
    hcloud_token = var.HCLOUD_TOKEN
    network_id = data.hcloud_network.kubernetes.id
  }
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

data "template_file" "cloud_init_node" {
  template = file("templates/cloud-init-node.tpl")

  vars = {
    floating_ip = data.hcloud_floating_ip.kubernetes.ip_address
    kubernetes_master_ip = var.kubernetes_master_internal_ip
    kubernetes_token = var.kubernetes_token
  }
}

resource "hcloud_server" "kubernetes_node" {
  name = "${var.kubernetes_prefix}-node-${count.index + 1}"
  count = var.kubernetes_node_count
  image = var.kubernetes_image
  location = var.location
  server_type = var.kubernetes_node_server_type
  user_data = data.template_file.cloud_init_node.rendered
  ssh_keys = [var.ssh_key_name]
}

resource "hcloud_server_network" "kubernetes_node" {
  count = var.kubernetes_node_count
  server_id = element(hcloud_server.kubernetes_node.*.id, count.index)
  network_id = data.hcloud_network.kubernetes.id
}
