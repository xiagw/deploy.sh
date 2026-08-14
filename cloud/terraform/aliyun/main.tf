terraform {
  required_version = ">= 1.3.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = ">= 1.180.0"
    }
  }
}

# 凭据优先用 access_key / secret_key 变量（terraform.tfvars），
# 也可用环境变量 ALICLOUD_ACCESS_KEY / ALICLOUD_SECRET_KEY。
provider "alicloud" {
  region     = var.region
  access_key = var.access_key != "" ? var.access_key : null
  secret_key = var.secret_key != "" ? var.secret_key : null
}

resource "alicloud_instance" "this" {
  count = var.instance_count

  instance_name              = "${var.instance_name}-${count.index + 1}"
  instance_type              = var.instance_type
  image_id                   = var.image_id
  vswitch_id                 = var.subnet_id
  security_groups            = var.security_group_ids
  availability_zone          = var.availability_zone != "" ? var.availability_zone : null
  instance_charge_type       = "PostPaid"
  system_disk_category       = var.system_disk_type != "" ? var.system_disk_type : "cloud_essd"
  system_disk_size           = var.system_disk_size
  password                   = var.key_name == "" && var.password != "" ? var.password : null
  key_name                   = var.key_name != "" ? var.key_name : null
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = var.internet_max_bandwidth_out
  tags                       = var.tags

  lifecycle {
    precondition {
      condition     = var.image_id != "" && var.instance_type != "" && var.subnet_id != ""
      error_message = "必须设置 image_id、instance_type、subnet_id。"
    }
    precondition {
      condition     = var.password != "" || var.key_name != ""
      error_message = "password 与 key_name 至少设置一个。"
    }
  }
}
