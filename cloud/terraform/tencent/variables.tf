variable "region" {
  description = "腾讯云地域"
  type        = string
  default     = "ap-guangzhou"
}

variable "secret_id" {
  description = "腾讯云 SecretId，留空使用环境变量 TENCENTCLOUD_SECRET_ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "secret_key" {
  description = "腾讯云 SecretKey，留空使用环境变量 TENCENTCLOUD_SECRET_KEY"
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
  default     = "terraform-cvm"
}

variable "instance_type" {
  description = "实例规格，如 S5.LARGE8"
  type        = string
  default     = ""
}

variable "image_id" {
  description = "系统镜像 ID（当前地域可用），如 img-xxxx"
  type        = string
  default     = ""
}

variable "availability_zone" {
  description = "可用区（必填），如 ap-guangzhou-3"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "子网 ID"
  type        = string
  default     = ""
}

variable "security_group_ids" {
  description = "安全组 ID 列表"
  type        = list(string)
  default     = []
}

variable "key_ids" {
  description = "SSH 密钥对 ID 列表（skey-xxx），与 password 二选一"
  type        = list(string)
  default     = []
}

variable "password" {
  description = "登录密码，与 key_ids 二选一"
  type        = string
  sensitive   = true
  default     = ""
}

variable "system_disk_size" {
  description = "系统盘大小（GB）"
  type        = number
  default     = 50
}

variable "system_disk_type" {
  description = "系统盘类型，留空默认 CLOUD_SSD"
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
