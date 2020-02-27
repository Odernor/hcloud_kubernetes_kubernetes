#cloud-config

runcmd:
 - mkdir /opt/data

package_upgrade: true

packages:
 - docker.io
