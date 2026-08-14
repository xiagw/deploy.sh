output "instance_ids" {
  description = "创建的实例 ID"
  value       = alicloud_instance.this[*].id
}

output "instance_names" {
  description = "创建的实例名称"
  value       = alicloud_instance.this[*].instance_name
}

output "private_ips" {
  description = "实例内网 IP"
  value       = alicloud_instance.this[*].private_ip
}

output "public_ips" {
  description = "实例公网 IP"
  value       = alicloud_instance.this[*].public_ip
}
