# OpenClaw Cookbook — Terraform 一键创建 TKE 体验集群

通过 Terraform 一键创建带超级节点池的 TKE 集群，用于体验 OpenClaw Cookbook。

## 前置要求

1. **Terraform** >= 1.5.0（[安装指南](https://developer.hashicorp.com/terraform/install)）
2. **腾讯云 API 密钥**（[获取地址](https://console.cloud.tencent.com/cam/capi)）
3. **kubectl**（[安装指南](https://kubernetes.io/docs/tasks/tools/)）

## 快速开始

### 1. 配置凭证

```bash
export TENCENTCLOUD_SECRET_ID=AKIDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export TENCENTCLOUD_SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> ⚠️ **安全提示**: 不要将凭证硬编码到任何文件中，也不要提交到版本控制。

### 2. 初始化并创建集群

```bash
cd terraform
terraform init
terraform apply
```

Terraform 会自动创建以下资源：
- VPC + 子网
- 安全组（入站仅放行 cookbook 服务端口和 ICMP）
- NAT 网关 + EIP + 路由表（Pod 公网出口）
- TKE 集群（托管模式，VPC-CNI 网络）
- 超级节点池（安全组已绑定，Pod 自动继承）

整个过程约需 5-10 分钟。

### 3. 获取 kubeconfig 并连接集群

```bash
terraform output -raw kubeconfig > ~/.kube/config-openclaw
export KUBECONFIG=~/.kube/config-openclaw
kubectl get nodes
```

### 4. 体验完成后销毁资源

```bash
cd terraform
terraform destroy
```

> ⚠️ **重要**: 体验完成后务必执行 `terraform destroy`，否则云资源会持续产生费用。

集群就绪后，回到 [项目主 README](../README.md) 继续部署 OpenClaw。

## 自定义配置

复制示例文件并按需修改：

```bash
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars 中的变量值
```

### 可配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `region` | `ap-guangzhou` | 腾讯云区域 |
| `availability_zone` | `ap-guangzhou-6` | 可用区 |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR 地址段 |
| `subnet_cidr` | `10.0.1.0/24` | 子网 CIDR |
| `service_cidr` | `172.19.128.0/17` | 集群 Service CIDR |
| `cluster_name` | `openclaw-cookbook` | 集群名称前缀 |
| `cluster_version` | `1.34.1` | Kubernetes 版本 |
| `nat_bandwidth_out` | `100` | NAT 网关 EIP 出带宽上限 (Mbps) |
| `nat_max_concurrent` | `1000000` | NAT 网关最大并发连接数 |
| `nat_eip_charge_type` | `TRAFFIC_POSTPAID_BY_HOUR` | NAT 网关 EIP 计费方式 |
| `cookbook_service_port` | `31234` | Cookbook 服务端口 |
| `tags` | `project=openclaw-cookbook` | 资源标签 |

## 创建的资源与费用预估

| 资源 | 规格 | 预估费用 |
|------|------|---------|
| TKE 托管集群 | 标准托管 | 集群管理免费 |
| 超级节点池 | 按 Pod 实际用量计费 | 按需（无 Pod 则不计费） |
| NAT 网关 | 标准型 | ~0.5 元/小时 |
| EIP（NAT 网关出口） | 按流量计费 | 按实际流量 |
| VPC + 子网 | 标准配置 | 免费 |
| 安全组 | 标准配置 | 免费 |

> 超级节点池无 CVM 实例，仅按 Pod 实际使用的 CPU/内存资源计费，不部署 Pod 时不产生费用。
> NAT 网关创建后即开始计费，体验完成后请及时销毁。

## 架构说明

```
Terraform 创建
┌──────────────────────────────┐
│  VPC + Subnet                │
│  Security Group              │
│  NAT Gateway + EIP + Route   │──── kubeconfig ──→ kubectl get nodes ✓
│  TKE Cluster                 │
│  Serverless Pool             │
└──────────────────────────────┘
     terraform apply
     terraform destroy
```

Terraform 只负责基础设施（集群 + 网络），应用部署见 [项目主 README](../README.md)。
