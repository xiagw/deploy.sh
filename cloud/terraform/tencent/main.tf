terraform {
  required_version = ">= 1.3.0"

  required_providers {
    tencentcloud = {
      source  = "tencentcloudstack/tencentcloud"
      version = ">= 1.60.0"
    }
  }
}

# 凭据可用 secret_id / secret_key 变量，或环境变量 TENCENTCLOUD_SECRET_ID / TENCENTCLOUD_SECRET_KEY。
provider "tencentcloud" {
  region     = var.region
  secret_id  = var.secret_id != "" ? var.secret_id : null
  secret_key = var.secret_key != "" ? var.secret_key : null
}

resource "tencentcloud_instance" "this" {
  count = var.instance_count

  instance_name              = "${var.instance_name}-${count.index + 1}"
  instance_type              = var.instance_type
  image_id                   = var.image_id
  availability_zone          = var.availability_zone
  vpc_id                     = var.vpc_id
  subnet_id                  = var.subnet_id
  orderly_security_groups    = var.security_group_ids
  instance_charge_type       = "POSTPAID_BY_HOUR"
  system_disk_type           = var.system_disk_type != "" ? var.system_disk_type : "CLOUD_SSD"
  system_disk_size           = var.system_disk_size
  password                   = length(var.key_ids) == 0 && var.password != "" ? var.password : null
  key_ids                    = var.key_ids
  allocate_public_ip         = var.internet_max_bandwidth_out > 0
  internet_charge_type       = var.internet_max_bandwidth_out > 0 ? "TRAFFIC_POSTPAID_BY_HOUR" : null
  internet_max_bandwidth_out = var.internet_max_bandwidth_out
  tags                       = var.tags

  lifecycle {
    precondition {
      condition     = var.image_id != "" && var.instance_type != "" && var.availability_zone != "" && var.vpc_id != "" && var.subnet_id != ""
      error_message = "必须设置 image_id、instance_type、availability_zone、vpc_id、subnet_id。"
    }
    precondition {
      condition     = var.password != "" || length(var.key_ids) > 0
      error_message = "password 与 key_ids 至少设置一个。"
    }
  }
}
