#cloud-config


write_files:
  - content: |
      auto eth0:1
      iface eth0:1 inet static
        address ${floating_ip}
        netmask 32
    path: /etc/network/interfaces.d/60-floating-ip.cfg
  - content: |
      [Service]
      Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external"
    path: /etc/systemd/system/kubelet.service.d/20-hetzner-cloud.conf
  - content: |
      [Service]
      ExecStart=
      ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --exec-opt native.cgroupdriver=systemd
    path: /etc/systemd/system/docker.service.d/00-cgroup-systemd.conf
  - content: |
      # Allow IP forwarding for kubernetes
      net.bridge.bridge-nf-call-iptables = 1
      net.ipv4.ip_forward = 1
    path: /etc/sysctl.d/10-kubernetes.conf
  - content: |
      #!/bin/bash

      /sbin/ifup eth0:1

      export KUBECONFIG=/etc/kubernetes/admin.conf

      cat <<EOF | kubectl apply -f -
      apiVersion: v1
      kind: Secret
      metadata:
        name: hcloud
        namespace: kube-system
      stringData:
        token: "${hcloud_token}"
        network: "${network_id}"
      ---
      apiVersion: v1
      kind: Secret
      metadata:
        name: hcloud-csi
        namespace: kube-system
      stringData:
        token: "${hcloud_token}"
      EOF

      kubectl apply -f https://raw.githubusercontent.com/hetznercloud/hcloud-cloud-controller-manager/master/deploy/v1.5.1-networks.yaml
      kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
      kubectl apply -f https://raw.githubusercontent.com/kubernetes/csi-api/master/pkg/crd/manifests/csidriver.yaml
      kubectl apply -f https://raw.githubusercontent.com/kubernetes/csi-api/master/pkg/crd/manifests/csinodeinfo.yaml
      kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/master/deploy/kubernetes/hcloud-csi.yml

      kubectl -n kube-system patch daemonset kube-flannel-ds-amd64 --type json -p '[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'
      kubectl -n kube-system patch deployment coredns --type json -p '[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'
      
      cd /tmp
      wget "https://get.helm.sh/helm-v3.1.1-linux-amd64.tar.gz"
      tar -zvxf helm-v3.1.1-linux-amd64.tar.gz 
      cp linux-amd64/helm /usr/local/bin/

      helm repo add stable https://kubernetes-charts.storage.googleapis.com/
      helm repo update

      kubectl create namespace metallb
      helm install metallb --namespace metallb stable/metallb

      cat <<EOF |kubectl apply -f-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        namespace: metallb
        name: metallb-config
      data:
        config: |
          address-pools:
          - name: default
            protocol: layer2
            addresses:
            - ${floating_ip}/32
      EOF

      kubectl create namespace fip-controller
      kubectl apply -f https://raw.githubusercontent.com/cbeneke/hcloud-fip-controller/master/deploy/rbac.yaml
      kubectl apply -f https://raw.githubusercontent.com/cbeneke/hcloud-fip-controller/master/deploy/deployment.yaml

      cat <<EOF | kubectl apply -f -
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: fip-controller-config
        namespace: fip-controller
      data:
        config.json: |
          {
            "hcloud_floating_ips": [ "${floating_ip}" ]
          }
      ---
      apiVersion: v1
      kind: Secret
      metadata:
        name: fip-controller-secrets
        namespace: fip-controller
      stringData:
        HCLOUD_API_TOKEN: ${hcloud_token}
      EOF
      
    path: /run/kubernetes_init.sh
      
apt:
  sources:
    docker.list:
      source: deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
    kubernetes.list:
      source: deb http://packages.cloud.google.com/apt/ kubernetes-xenial main
      keyid: 54A647F9048D5688D7DA2ABE6A030B21BA07F4FB


packages:
  - docker-ce
  - kubeadm
  - kubectl
  - kubelet

runcmd:
  - systemctl daemon-reload
  - kubeadm init --token ${kubernetes_token} --token-ttl 1h --pod-network-cidr=10.244.0.0/16 --kubernetes-version=${kubernetes_version} --ignore-preflight-errors=NumCPU --apiserver-cert-extra-sans=${kubernetes_master_ip}
  - sh /run/kubernetes_init.sh


