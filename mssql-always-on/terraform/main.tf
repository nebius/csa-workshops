 
 terraform {
   required_providers {
     yandex = {
       source = "yandex-cloud/yandex"
     }
   }
   required_version = ">= 0.13"
 }
  
 provider "yandex" {
   endpoint         = "api.cloudil.com:443"
   token = "<ENTER_OAUTH_TOKEN>"
   cloud_id  = "<ENTER_CLOUD_ID>"
   folder_id = "<ENTER_FOLDER_ID>"
   zone      = "il1-b"
 }

 variable "image-id" {
     type = string
 }

 
variable "folder-id" {
     type = string
 }

variable "zone" {
     type = string
 }

variable "zone-a" {
     type = string
 }

variable "zone-b" {
     type = string
 }

variable "zone-c" {
     type = string
 }

variable "region_id" {
     type = string
}

variable "platform_id" {
     type = string
}

variable "vm-ya-ad-internal-ipv4" {
     type = string
}

variable "vm-ya-mssql1-internal-ipv4" {
     type = string
}

variable "vm-ya-mssql2-internal-ipv4" {
     type = string
}

variable "vm-ya-mssql3-internal-ipv4" {
     type = string
}


variable ps1-scripts {
  type = map(string)
}

locals {  
    ps1-scripts-vars= var.ps1-scripts  
 }  

/*creating VPC network with subnets*/
resource "yandex_vpc_network" "ya-network" {
    name = "ya-network"
}

resource "yandex_vpc_subnet" "ya-sqlserver-rc1a" {
  name       = "ya-sqlserver-rc1a"
  zone       = var.zone-a
  network_id = "${yandex_vpc_network.ya-network.id}"
  v4_cidr_blocks = ["192.168.1.0/28"]
}

resource "yandex_vpc_subnet" "ya-sqlserver-rc1b" {
  name       = "ya-sqlserver-rc1b"
  zone       = var.zone-b
  network_id = "${yandex_vpc_network.ya-network.id}"
  v4_cidr_blocks = ["192.168.1.16/28"]
}

resource "yandex_vpc_subnet" "ya-sqlserver-rc1c" {
  name       = "ya-sqlserver-rc1c"
  zone       = var.zone-c
  network_id = "${yandex_vpc_network.ya-network.id}"
  v4_cidr_blocks = ["192.168.1.32/28"]
}

resource "yandex_vpc_subnet" "ya-ilb-rc1a" {
  name       = "ya-ilb-rc1a"
  zone       = var.zone-a
  network_id = "${yandex_vpc_network.ya-network.id}"
  v4_cidr_blocks = ["192.168.1.48/28"]
}

resource "yandex_vpc_subnet" "ya-ad-rc1a" {
  name       = "ya-ad-rc1a"
  zone       = var.zone-a
  network_id = "${yandex_vpc_network.ya-network.id}"
  v4_cidr_blocks = ["10.0.0.0/28"]
}

/*creating Network Load Balancer Target Group*/
resource "yandex_lb_target_group" "ya-tg" {
  name      = "ya-tg"
  region_id = var.region_id

  target {
    subnet_id = "${yandex_vpc_subnet.ya-sqlserver-rc1a.id}"
    address   = var.vm-ya-mssql1-internal-ipv4
  }

  target {
    subnet_id = "${yandex_vpc_subnet.ya-sqlserver-rc1b.id}"
    address   = var.vm-ya-mssql2-internal-ipv4
  }

  target {
    subnet_id = "${yandex_vpc_subnet.ya-sqlserver-rc1c.id}"
    address   = var.vm-ya-mssql3-internal-ipv4
  }
}

/*creating Network Load Balancer*/
resource "yandex_lb_network_load_balancer" "ya-loadbalancer" {
  name = "ya-loadbalancer"
  type = "internal"
  listener {
    name = "ya-listener"
    port = 1433
    target_port = 14333
    protocol = "tcp"
    internal_address_spec {
      ip_version = "ipv4"
      subnet_id = yandex_vpc_subnet.ya-ilb-rc1a.id
    }
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.ya-tg.id}"

    healthcheck {
      name = "listener"
      tcp_options {
        port = 59999
      }
    }
  }
}


/*creating VM ya-jump1 - Bastion Host witn NAT*/
 resource "yandex_compute_instance" "ya-jump1" {
  name        = "ya-jump1"
  hostname    = "ya-jump1"
  platform_id = var.platform_id
  zone        = var.zone-a

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = var.image-id
      size = 50
      type = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.ya-ad-rc1a.id
    nat       = true
  }

  metadata = {
    user-data = sensitive(templatefile("${path.module}/setpass.ps1", local.ps1-scripts-vars))
  }
}

/*creating VM ya-ad - Active Directory Server*/
 resource "yandex_compute_instance" "ya-ad" {
  name        = "ya-ad"
  hostname    = "ya-ad"
  platform_id = var.platform_id
  zone        = var.zone-a

  resources {
    cores  = 2
    memory = 6
  }

  boot_disk {
    initialize_params {
      image_id = var.image-id
      size = 50
      type = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.ya-ad-rc1a.id
    ip_address = var.vm-ya-ad-internal-ipv4
    nat       = false
  }

  metadata = {
    user-data = sensitive(templatefile("${path.module}/setpass.ps1", local.ps1-scripts-vars))
  }
}

/*creating VM ya-mssql1 - MSSQL Server 2022 Cluster Noder*/
resource "yandex_compute_disk" "ya-mssql1-db-disk" {
  name       = "ya-mssql1-db-disk"
  type       = "network-ssd"
  zone       = var.zone-a
  size       = 200
}

 resource "yandex_compute_instance" "ya-mssql1" {
  name        = "ya-mssql1"
  hostname    = "ya-mssql1"
  platform_id = var.platform_id
  zone        = var.zone-a

  resources {
    cores  = 4
    memory = 16
  }

  boot_disk {
    initialize_params {
      image_id = var.image-id
      size = 50
      type = "network-ssd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.ya-mssql1-db-disk.id
    mode = "READ_WRITE"
    auto_delete = true
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.ya-sqlserver-rc1a.id
    nat       = true
    ip_address = var.vm-ya-mssql1-internal-ipv4
  }

  metadata = {
   user-data = sensitive(templatefile("${path.module}/setpass.ps1", local.ps1-scripts-vars))
  }
}

/*creating VM ya-mssql2 - MSSQL Server 2022 Cluster Noder*/
resource "yandex_compute_disk" "ya-mssql2-db-disk" {
  name       = "ya-mssql2-db-disk"
  type       = "network-ssd"
  zone       = var.zone-b
  size       = 200
}

 resource "yandex_compute_instance" "ya-mssql2" {
  name        = "ya-mssql2"
  hostname    = "ya-mssql2"
  platform_id = var.platform_id
  zone        = var.zone-b

  resources {
    cores  = 4
    memory = 16
  }

  boot_disk {
    initialize_params {
      image_id = var.image-id
      size = 50
      type = "network-ssd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.ya-mssql2-db-disk.id
    mode = "READ_WRITE"
    auto_delete = true
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.ya-sqlserver-rc1b.id
    nat       = true
    ip_address = var. vm-ya-mssql2-internal-ipv4
  }

  metadata = {
    user-data = sensitive(templatefile("${path.module}/setpass.ps1", local.ps1-scripts-vars))
  }
}

/*creating VM ya-mssql3 - MSSQL Server 2022 Cluster Noder*/
resource "yandex_compute_disk" "ya-mssql3-db-disk" {
  name       = "ya-mssql3-db-disk"
  type       = "network-ssd"
  zone       = var.zone-c
  size       = 200
}

 resource "yandex_compute_instance" "ya-mssql3" {
  name        = "ya-mssql3"
  hostname    = "ya-mssql3"
  platform_id = var.platform_id
  zone        = var.zone-c

  resources {
    cores  = 4
    memory = 16
  }

  boot_disk {
    initialize_params {
      image_id = var.image-id
      size = 50
      type = "network-ssd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.ya-mssql3-db-disk.id
    mode = "READ_WRITE"
    auto_delete = true
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.ya-sqlserver-rc1c.id
    nat       = true
    ip_address = var. vm-ya-mssql3-internal-ipv4
  }

  metadata = {
    user-data = sensitive(templatefile("${path.module}/setpass.ps1", local.ps1-scripts-vars))
  }
}

