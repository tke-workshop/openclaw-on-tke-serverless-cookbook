# ==================== 数据源 ====================

# 查询当前账号的 UID，用于资源命名去重
data "tencentcloud_user_info" "current" {}

locals {
  # 截取 UID 后 6 位作为后缀，避免多用户资源名冲突
  uid_suffix = substr(data.tencentcloud_user_info.current.owner_uin, -6, 6)
}

# ==================== 网络资源 ====================

resource "tencentcloud_vpc" "cookbook" {
  name       = "${var.cluster_name}-vpc-${local.uid_suffix}"
  cidr_block = var.vpc_cidr
  tags       = var.tags
}

resource "tencentcloud_subnet" "cookbook" {
  name              = "${var.cluster_name}-subnet-gz6-${local.uid_suffix}"
  vpc_id            = tencentcloud_vpc.cookbook.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone
  tags              = var.tags
}

resource "tencentcloud_subnet" "cookbook_gz7" {
  name              = "${var.cluster_name}-subnet-gz7-${local.uid_suffix}"
  vpc_id            = tencentcloud_vpc.cookbook.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-guangzhou-7"
  tags              = var.tags
}

# ==================== 安全组 — 控制面 ====================
# 用于 apiserver 公网端点（CLB），放通 443 用于 kubectl 访问

resource "tencentcloud_security_group" "control_plane" {
  name        = "${var.cluster_name}-sg-control-plane-${local.uid_suffix}"
  description = "TKE 控制面安全组：apiserver 公网访问"
  tags        = var.tags
}

resource "tencentcloud_security_group_rule_set" "control_plane" {
  security_group_id = tencentcloud_security_group.control_plane.id

  # --- 入站规则 ---

  ingress {
    action      = "ACCEPT"
    cidr_block  = var.vpc_cidr
    protocol    = "ALL"
    port        = "ALL"
    description = "Allow VPC internal traffic"
  }

  ingress {
    action      = "ACCEPT"
    cidr_block  = var.service_cidr
    protocol    = "ALL"
    port        = "ALL"
    description = "Allow Service CIDR traffic"
  }

  ingress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "TCP"
    port        = "443"
    description = "Allow HTTPS for kubectl/API access"
  }

  ingress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "ICMP"
    port        = "ALL"
    description = "Allow ICMP for diagnostics"
  }

  # --- 出站规则 ---

  egress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "ALL"
    port        = "ALL"
    description = "Allow all outbound traffic"
  }
}

# ==================== 安全组 — 工作负载 ====================
# 用于超级节点池（Pod 容器），仅开放必要端口

resource "tencentcloud_security_group" "workload" {
  name        = "${var.cluster_name}-sg-workload-${local.uid_suffix}"
  description = "OpenClaw 容器工作负载安全组：仅开放 cookbook 服务端口"
  tags        = var.tags
}

resource "tencentcloud_security_group_rule_set" "workload" {
  security_group_id = tencentcloud_security_group.workload.id

  # --- 入站规则 ---

  ingress {
    action      = "ACCEPT"
    cidr_block  = var.vpc_cidr
    protocol    = "ALL"
    port        = "ALL"
    description = "Allow VPC internal traffic (Pod 间通信、健康检查)"
  }

  ingress {
    action      = "ACCEPT"
    cidr_block  = var.service_cidr
    protocol    = "ALL"
    port        = "ALL"
    description = "Allow Service CIDR traffic"
  }

  ingress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "TCP"
    port        = tostring(var.cookbook_service_port)
    description = "Allow cookbook service port"
  }

  # --- 出站规则 ---

  egress {
    action      = "ACCEPT"
    cidr_block  = "0.0.0.0/0"
    protocol    = "ALL"
    port        = "ALL"
    description = "Allow all outbound traffic (LLM API access)"
  }
}

# ==================== CAM 服务角色（TKE IPAMD） ====================
# VPC-CNI 网络模式要求 IPAMDofTKE_QCSRole 服务角色存在并关联策略
# 该角色授权 TKE IPAMD 访问 VPC 弹性网卡、CVM 信息查询、Tag 管理等

# 先查询角色是否已存在（可能在控制台手动授权过）
data "tencentcloud_cam_roles" "ipamd_existing" {
  name = "IPAMDofTKE_QCSRole"
}

locals {
  ipamd_role_exists = length(data.tencentcloud_cam_roles.ipamd_existing.role_list) > 0
}

# 仅在角色不存在时创建
resource "tencentcloud_cam_role" "ipamd" {
  count         = local.ipamd_role_exists ? 0 : 1
  name          = "IPAMDofTKE_QCSRole"
  console_login = false
  description   = "腾讯云容器服务(TKE)IPAMD操作权限，含查询CVM信息、增删查VPC弹性网卡、弹性网卡标签管理等。"

  document = jsonencode({
    version = "2.0"
    statement = [
      {
        action = "name/sts:AssumeRole"
        effect = "allow"
        principal = {
          service = ["ccs.qcloud.com"]
        }
      }
    ]
  })

  tags = var.tags
}

# 查询预设策略 QcloudAccessForIPAMDofTKERole 的 policy_id
data "tencentcloud_cam_policies" "ipamd" {
  name = "QcloudAccessForIPAMDofTKERole"
}

# 仅在新创建角色时绑定策略（已有角色通常已绑定）
resource "tencentcloud_cam_role_policy_attachment" "ipamd" {
  count     = local.ipamd_role_exists ? 0 : 1
  role_id   = tencentcloud_cam_role.ipamd[0].id
  policy_id = data.tencentcloud_cam_policies.ipamd.policy_list[0].policy_id
}

# ==================== CAM 服务角色（TKE） ====================
# TKE 服务角色 TKE_QCSRole 用于容器服务访问 CVM、CLB、CBS 等云资源
# 超级节点 Pod 绑定 EIP 需要此角色拥有 EIP 操作权限

# 先查询角色是否已存在（可能在控制台手动授权过）
data "tencentcloud_cam_roles" "tke_existing" {
  name = "TKE_QCSRole"
}

locals {
  tke_role_exists = length(data.tencentcloud_cam_roles.tke_existing.role_list) > 0
}

# 仅在角色不存在时创建
resource "tencentcloud_cam_role" "tke" {
  count         = local.tke_role_exists ? 0 : 1
  name          = "TKE_QCSRole"
  console_login = false
  description   = "腾讯云容器服务(TKE)对云资源的访问权限，含 CVM、CLB、CBS、EIP 等资源操作。"

  document = jsonencode({
    version = "2.0"
    statement = [
      {
        action = "name/sts:AssumeRole"
        effect = "allow"
        principal = {
          service = ["ccs.qcloud.com"]
        }
      }
    ]
  })

  tags = var.tags
}

# 查询预设策略 QcloudAccessForTKERole 的 policy_id
data "tencentcloud_cam_policies" "tke" {
  name = "QcloudAccessForTKERole"
}

# 仅在新创建角色时绑定预设策略
resource "tencentcloud_cam_role_policy_attachment" "tke" {
  count     = local.tke_role_exists ? 0 : 1
  role_id   = tencentcloud_cam_role.tke[0].id
  policy_id = data.tencentcloud_cam_policies.tke.policy_list[0].policy_id
}

# 自定义策略：授予 TKE 服务角色 EIP 操作权限（超级节点 Pod 绑定 EIP 所需）
# 包含 EIP 管理 + Tag 读取（EIP 分配时需查询集群标签）
resource "tencentcloud_cam_policy" "tke_eip" {
  name        = "TKEAccessForEIP-${local.uid_suffix}"
  description = "允许 TKE 服务角色为超级节点 Pod 分配和管理弹性公网 IP (EIP)，含标签查询权限"

  document = jsonencode({
    version = "2.0"
    statement = [
      {
        effect = "allow"
        action = [
          "name/cvm:AllocateAddresses",
          "name/cvm:AssociateAddress",
          "name/cvm:DescribeAddresses",
          "name/cvm:DisassociateAddress",
          "name/cvm:ReleaseAddresses",
          "name/cvm:DescribeAddressQuota",
          "name/cvm:ModifyAddressAttribute",
        ]
        resource = ["*"]
      },
      {
        effect = "allow"
        action = [
          "name/tag:GetResources",
          "name/tag:GetResourceTags",
          "name/tag:DescribeResourcesByTags",
          "name/tag:GetTagKeys",
          "name/tag:GetTagValues",
        ]
        resource = ["*"]
      }
    ]
  })
}

# 将 EIP 策略绑定到 TKE_QCSRole（无论角色是新建还是已有）
resource "tencentcloud_cam_role_policy_attachment" "tke_eip" {
  role_id   = local.tke_role_exists ? data.tencentcloud_cam_roles.tke_existing.role_list[0].role_id : tencentcloud_cam_role.tke[0].id
  policy_id = tencentcloud_cam_policy.tke_eip.id
}

# 将 EIP 策略同时绑定到 IPAMDofTKE_QCSRole（IPAMD 负责 Pod 网络资源分配，包括 EIP）
resource "tencentcloud_cam_role_policy_attachment" "ipamd_eip" {
  role_id   = local.ipamd_role_exists ? data.tencentcloud_cam_roles.ipamd_existing.role_list[0].role_id : tencentcloud_cam_role.ipamd[0].id
  policy_id = tencentcloud_cam_policy.tke_eip.id
}

# ==================== TKE 集群 ====================

resource "tencentcloud_kubernetes_cluster" "cookbook" {
  vpc_id                  = tencentcloud_vpc.cookbook.id
  cluster_cidr            = ""
  cluster_name            = "${var.cluster_name}-${local.uid_suffix}"
  cluster_version         = var.cluster_version
  cluster_deploy_type     = "MANAGED_CLUSTER"
  service_cidr            = var.service_cidr
  cluster_max_pod_num     = 64
  cluster_max_service_num = 32768
  cluster_os              = "tlinux3.2x86_64"
  network_type            = "VPC-CNI"
  vpc_cni_type            = "tke-route-eni"
  eni_subnet_ids          = [tencentcloud_subnet.cookbook.id, tencentcloud_subnet.cookbook_gz7.id]
  is_non_static_ip_mode   = true
  deletion_protection     = false
  cluster_ipvs            = false

  # 注意：不在此处设置 cluster_internet = true
  # 无 worker 节点的集群创建时不支持直接开启公网访问
  # 改为通过 tencentcloud_kubernetes_cluster_endpoint 在节点池就绪后开启

  tags = var.tags

  # 确保 IPAMD 服务角色及策略就绪后再创建 VPC-CNI 模式集群
  # 同时确保 TKE_QCSRole 及 EIP 策略就绪，以支持 Pod 绑定 EIP
  depends_on = [
    tencentcloud_cam_role_policy_attachment.ipamd,
    tencentcloud_cam_role_policy_attachment.tke_eip,
    tencentcloud_cam_role_policy_attachment.ipamd_eip,
  ]
}

# ==================== 超级节点池（Serverless Node Pool） ====================

# 广州6区超级节点池
resource "tencentcloud_kubernetes_serverless_node_pool" "cookbook" {
  cluster_id = tencentcloud_kubernetes_cluster.cookbook.id
  name       = "${var.cluster_name}-serverless-pool-gz6"

  serverless_nodes {
    display_name = "cookbook-virtual-node-gz6"
    subnet_id    = tencentcloud_subnet.cookbook.id
  }

  security_group_ids = [tencentcloud_security_group.workload.id]

  labels = {
    "node-pool" = "serverless"
    "project"   = "openclaw-cookbook"
    "zone"      = "gz6"
  }
}

# 广州7区超级节点池
resource "tencentcloud_kubernetes_serverless_node_pool" "cookbook_gz7" {
  cluster_id = tencentcloud_kubernetes_cluster.cookbook.id
  name       = "${var.cluster_name}-serverless-pool-gz7"

  serverless_nodes {
    display_name = "cookbook-virtual-node-gz7"
    subnet_id    = tencentcloud_subnet.cookbook_gz7.id
  }

  security_group_ids = [tencentcloud_security_group.workload.id]

  labels = {
    "node-pool" = "serverless"
    "project"   = "openclaw-cookbook"
    "zone"      = "gz7"
  }
}

# ==================== 集群公网访问端点 ====================
# 必须在超级节点池创建完成后才能开启公网访问

resource "tencentcloud_kubernetes_cluster_endpoint" "cookbook" {
  cluster_id                      = tencentcloud_kubernetes_cluster.cookbook.id
  cluster_internet                = true
  cluster_internet_security_group = tencentcloud_security_group.control_plane.id

  depends_on = [
    tencentcloud_kubernetes_serverless_node_pool.cookbook,
    tencentcloud_kubernetes_serverless_node_pool.cookbook_gz7,
  ]
}
