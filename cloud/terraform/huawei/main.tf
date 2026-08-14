terraform {
  required_version = ">= 1.3.0"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.60.0"
    }
  }
}

# 凭据优先复用本机 huaweicloud configure（~/.huaweicloud/credentials），
# 也可用 access_key / secret_key 变量或环境变量注入。
provider "huaweicloud" {
  region     = var.region
  access_key = var.access_key != "" ? var.access_key : null
  secret_key = var.secret_key != "" ? var.secret_key : null
}

resource "huaweicloud_compute_instance" "this" {
  count = var.instance_count

  name               = "${var.instance_name}-${count.index + 1}"
  image_id           = var.image_id
  flavor_id          = var.instance_type
  availability_zone  = var.availability_zone != "" ? var.availability_zone : null
  security_group_ids = var.security_group_ids
  admin_pass         = var.key_name == "" && var.password != "" ? var.password : null
  key_pair           = var.key_name != "" ? var.key_name : null
  system_disk_size   = var.system_disk_size
  system_disk_type   = var.system_disk_type != "" ? var.system_disk_type : "GPSSD"
  tags               = var.tags

  network {
    uuid = var.subnet_id
  }

  lifecycle {
    precondition {
      condition     = var.image_id != "" && var.instance_type != "" && var.subnet_id != ""
      error_message = "必须设置 image_id、instance_type、subnet_id。"
    }
    precondition {
      condition     = var.password != "" || var.key_name != ""
      error_message = "admin_pass 与 key_pair 至少设置一个。"
    }
  }
}
