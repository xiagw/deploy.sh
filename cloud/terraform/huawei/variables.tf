variable "region" {
  description = "华为云地域"
  type        = string
  default     = "cn-north-1"
}

variable "access_key" {
  description = "华为云 AK，留空复用本机 huaweicloud configure / 环境变量"
  type        = string
  sensitive   = true
  default     = ""
}

variable "secret_key" {
  description = "华为云 SK，留空复用本机 huaweicloud configure / 环境变量"
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
  description = "实例规格（flavor_id），如 c7.large.2"
  type        = string
  default     = ""
}

variable "image_id" {
  description = "系统镜像 ID（当前地域可用），如 xxxx-xxxx"
  type        = string
  default     = ""
}

variable "availability_zone" {
  description = "可用区，留空由系统分配"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "子网 ID（network uuid）"
  type        = string
  default     = ""
}

variable "security_group_ids" {
  description = "安全组 ID 列表"
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "SSH 密钥对名称（key_pair），与 password 二选一"
  type        = string
  default     = ""
}

variable "password" {
  description = "登录密码（admin_pass），与 key_name 二选一"
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
  description = "系统盘类型，留空默认 GPSSD"
  type        = string
  default     = ""
}

variable "tags" {
  description = "实例标签"
  type        = map(string)
  default = {
    CreatedBy = "terraform"
  }
}
