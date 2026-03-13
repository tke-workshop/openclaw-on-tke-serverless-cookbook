# Terraform 和 Provider 版本约束

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    tencentcloud = {
      source  = "tencentcloudstack/tencentcloud"
      version = "~> 1.81"
    }
  }
}

provider "tencentcloud" {
  region = var.region
  # 凭证通过环境变量传入：
  #   export TENCENTCLOUD_SECRET_ID=xxx
  #   export TENCENTCLOUD_SECRET_KEY=xxx
}
