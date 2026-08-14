output "instance_ids" {
  description = "创建的实例 ID"
  value       = huaweicloud_compute_instance.this[*].id
}

output "instance_names" {
  description = "创建的实例名称"
  value       = huaweicloud_compute_instance.this[*].name
}

output "private_ips" {
  description = "实例内网 IP"
  value       = huaweicloud_compute_instance.this[*].access_ip_v4
}
