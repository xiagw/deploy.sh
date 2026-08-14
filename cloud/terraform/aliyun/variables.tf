variable "region" {
  description = "阿里云地域"
  type        = string
  default     = "cn-hangzhou"
}

variable "access_key" {
  description = "阿里云 AccessKeyId，留空使用环境变量 ALICLOUD_ACCESS_KEY"
  type        = string
  sensitive   = true
  default     = ""
}

variable "secret_key" {
  description = "阿里云 AccessKeySecret，留空使用环境变量 ALICLOUD_SECRET_KEY"
  type        = string
  sensitive   = true
  default     = ""
}

variable "instance_count" {
  description = "创建实例数量"
  type        = number
  default     = 1
}

variable "instance_name" {
  description = "实例名称前缀，实际名称追加 -1/-2... 序号"
  type        = string
  default     = "terraform-ecs"
}

variable "instance_type" {
  description = "实例规格，如 ecs.g7.large"
  type        = string
  default     = ""
}

variable "image_id" {
  description = "系统镜像 ID（当前地域可用），如 ubuntu_24_04_x64_*.vhd"
  type        = string
  default     = ""
}

variable "availability_zone" {
  description = "可用区，留空由交换机决定"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "交换机 ID（vswitch_id）"
  type        = string
  default     = ""
}

variable "security_group_ids" {
  description = "安全组 ID 列表"
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "SSH 密钥对名称，与 password 二选一"
  type        = string
  default     = ""
}

variable "password" {
  description = "登录密码（8-30 位，需含大小写字母与数字），与 key_name 二选一"
  type        = string
  sensitive   = true
  default     = ""
}

variable "system_disk_size" {
  description = "系统盘大小（GB）"
  type        = number
  default     = 40
}

variable "system_disk_type" {
  description = "系统盘类型，留空默认 cloud_essd"
  type        = string
  default     = ""
}

variable "internet_max_bandwidth_out" {
  description = "公网出带宽上限（Mbps），0 表示不分配公网 IP"
  type        = number
  default     = 0
}

variable "tags" {
  description = "实例标签"
  type        = map(string)
  default = {
    CreatedBy = "terraform"
  }
}
