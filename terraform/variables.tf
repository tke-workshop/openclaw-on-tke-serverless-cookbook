# ==================== 区域配置 ====================

variable "region" {
  description = "腾讯云区域"
  type        = string
  default     = "ap-guangzhou"
}

variable "availability_zone" {
  description = "可用区"
  type        = string
  default     = "ap-guangzhou-6"
}

# ==================== 网络配置 ====================

variable "vpc_cidr" {
  description = "VPC CIDR 地址段"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "子网 CIDR 地址段"
  type        = string
  default     = "10.0.1.0/24"
}

variable "service_cidr" {
  description = "集群 Service CIDR"
  type        = string
  default     = "172.19.128.0/17"
}

# ==================== 集群配置 ====================

variable "cluster_name" {
  description = "TKE 集群名称"
  type        = string
  default     = "openclaw-cookbook"
}

variable "cluster_version" {
  description = "Kubernetes 版本"
  type        = string
  default     = "1.34.1"
}

# ==================== 安全组配置 ====================

variable "cookbook_service_port" {
  description = "Cookbook 服务端口（安全组入站放行）"
  type        = number
  default     = 31234
}

# ==================== 标签 ====================

variable "tags" {
  description = "所有资源的公共标签"
  type        = map(string)
  default = {
    "oc-project"    = "openclaw-cookbook"
    "oc-managed-by" = "terraform"
    "oc-env"        = "quickstart"
  }
}
