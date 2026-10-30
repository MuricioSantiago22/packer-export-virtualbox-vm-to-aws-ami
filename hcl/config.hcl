packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "ssh_username" {
  type = string
}

variable "ssh_password" {
  type      = string
  sensitive = true
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "s3_bucket_name" {
  type    = string
  default = "packer-vm-import-mauricio-2026"
}

source "virtualbox-ovf" "vm1" {
  source_path      = "../export/vm1.ova"
  format           = "ova"
  vm_name          = "vm1-packer"
  headless         = true
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "20m"
  vboxmanage       = [["modifyvm", "{{.Name}}", "--nic1", "nat"]]
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
}

build {
  sources = ["source.virtualbox-ovf.vm1"]

  provisioner "shell" {
    script          = "../scripts/install-nginx.sh"
    execute_command = "echo '${var.ssh_password}' | sudo -S -E bash '{{ .Path }}'"
  }

  post-processor "amazon-import" {
    region         = var.region
    s3_bucket_name = var.s3_bucket_name
    format         = "ova"
    boot_mode      = "legacy-bios"
    license_type   = "BYOL"
    ami_name       = "vm1-nginx-hcl"
    tags = {
      Name = "vm1-nginx-hcl"
    }
  }
}
