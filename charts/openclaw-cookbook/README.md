# OpenClaw Cookbook — Helm Chart

在 TKE Serverless 上部署 OpenClaw Gateway。

## 前置条件: 创建 TKE 集群

部署 cookbook 前，需要一个带超级节点池的 TKE 集群。你可以：

### 方式一：Terraform 一键创建（推荐）

如果你还没有 TKE 集群，可以使用项目自带的 Terraform 配置一键创建：

```bash
# 配置腾讯云凭证
export TENCENTCLOUD_SECRET_ID=AKIDxxxxxxxx
export TENCENTCLOUD_SECRET_KEY=xxxxxxxx

# 一键创建集群（约 5-10 分钟）
cd terraform
terraform init && terraform apply

# 获取 kubeconfig
terraform output -raw kubeconfig > ~/.kube/config-openclaw
export KUBECONFIG=~/.kube/config-openclaw
```

详细说明见 [Terraform README](../../terraform/README.md)。

### 方式二：手动创建

在 [腾讯云 TKE 控制台](https://console.cloud.tencent.com/tke2) 手动创建集群，确保：
- 集群类型为标准集群 + 超级节点池
- 网络模式为 VPC-CNI
- 已获取 kubeconfig 并配置好 kubectl

---

## 部署步骤

```bash
# 1. 创建 namespace（已有则跳过）
kubectl create namespace openclaw

# 2. 创建镜像仓库凭证（已有则跳过）
kubectl create secret docker-registry ccr-registry \
  --docker-server=ccr.ccs.tencentyun.com \
  --docker-username=<用户名> \
  --docker-password=<密码> \
  -n openclaw

# 3. 创建 API Key Secret（已有则跳过）
# 支持任意 LLM API Key，按需配置
kubectl create secret generic openclaw-secrets \
  --from-literal=OPENROUTER_API_KEY=sk-or-v1-xxx \
  --from-literal=OPENAI_API_KEY=sk-xxx \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-xxx \
  -n openclaw

# 4. 部署（引用已有 Secret）
helm install cookbook ./charts/openclaw-cookbook/ \
  --namespace openclaw \
  --set secrets.existingSecret=openclaw-secrets

# 5. 等待就绪
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=cookbook \
  -n openclaw --timeout=180s

# 6. 通过 port-forward 访问 Gateway Control UI
kubectl port-forward -n openclaw svc/cookbook-openclaw-cookbook-public 20000:20000
# 然后在浏览器中打开 http://localhost:20000
```

> **为什么用 port-forward？** OpenClaw Gateway 的 Control UI 默认仅允许 `localhost` origin 连接，
> 不支持通配符放通。使用 `port-forward` 是最简单安全的访问方式，无需额外配置 origin 白名单、
> HTTPS 证书或设备配对。
>
> 如需通过公网直接访问，可设置 `--set service.type=LoadBalancer`，并参考
> [OpenClaw 文档](https://docs.openclaw.ai) 配置 `gateway.controlUi.allowedOrigins`。

## 部署 Profile

| Profile | 文件 | 说明 |
|---------|------|------|
| **标准模式（默认推荐）** | `values.yaml` | Istio 服务治理 + 出站白名单 + 熔断保护 |
| **最简模式** | `values-minimal.yaml` | 仅基础工作负载 + 安全加固，适合个人体验 |

### 标准模式部署（默认推荐）

只需一条命令，Istio 控制面会通过 pre-install hook 自动安装：

```bash
helm install cookbook ./charts/openclaw-cookbook/ \
  --namespace openclaw --create-namespace \
  --set secrets.existingSecret=openclaw-secrets
```

> **自动安装流程**：Chart 通过 Helm pre-install hook 在主资源部署前，自动将 istio-base + istiod 安装到 `istio-system` namespace，并给目标 namespace 打上 `istio-injection=enabled` 标签。

### 最简模式部署（个人体验）

```bash
helm install cookbook ./charts/openclaw-cookbook/ \
  -f ./charts/openclaw-cookbook/values-minimal.yaml \
  --namespace openclaw \
  --set secrets.existingSecret=openclaw-secrets
```

#### 集群已有 Istio？

如果集群中已有 Istio 控制面，跳过自动安装即可：

```bash
helm install cookbook ./charts/openclaw-cookbook/ \
  --namespace openclaw --create-namespace \
  --set secrets.existingSecret=openclaw-secrets \
  --set istio.install.enabled=false
```

## 第二层: 治理能力

### Istio 服务治理

| 参数 | 默认值 | 作用 |
|------|--------|------|
| `istio.enabled` | `false` | 启用 Istio 治理（sidecar 注入标签 + CRD 策略渲染） |
| `istio.install.enabled` | `false` | 通过 hook 自动安装 Istio 控制面到 istio-system |
| `istio.install.version` | `1.24.6` | Istio Chart 版本 |
| `istio.install.uninstallOnDelete` | `false` | helm uninstall 时是否同时卸载 Istio |
| `istio.install.meshConfig.*` | — | istiod meshConfig 配置 |
| `istio.install.pilot.resources.*` | — | istiod 资源限制 |

> **渲染逻辑**: 当 `istio.install.enabled=true` 时，模板信任 pre-install hook 已安装 CRD，直接渲染策略资源。当 `istio.install.enabled=false` 时，模板通过 `.Capabilities.APIVersions.Has` 检测集群是否已有 Istio CRD，CRD 不存在则跳过渲染，避免安装失败。

### Istio 安装控制矩阵

| `istio.enabled` | `istio.install.enabled` | 效果 |
|:---:|:---:|:---|
| `false` | `false` | 纯应用部署，无 Istio 相关资源 |
| `true` | `false` | 仅渲染 Istio CRD 策略（需集群已有 Istio） |
| `true` | `true` | **推荐**: 自动安装 Istio + 渲染 CRD 策略 |
| `false` | `true` | 安装 Istio 控制面但不渲染策略（调试场景） |

### 出站网络策略

当 `istio.enabled=true` + `egressPolicy.enabled=true` + 集群已有 Istio CRD 时，渲染以下资源：

- **ServiceEntry**: 为 `egressPolicy.allowlist` 中的每个域名注册白名单
- **Sidecar CRD**: 限制 Envoy 只能看到 `istio-system` 和当前 namespace 的服务
- **DestinationRule**: 为每个白名单域名配置连接池和熔断保护

## 升级 / 卸载

```bash
# 升级（如更新镜像版本）
helm upgrade cookbook ./charts/openclaw-cookbook/ \
  --namespace openclaw \
  --set secrets.existingSecret=openclaw-secrets \
  --set image.tag=v2026.3.11

# 卸载应用（Istio 控制面默认保留）
helm uninstall cookbook -n openclaw

# 卸载应用并同时卸载 Istio（需事先设置 uninstallOnDelete=true）
# 或手动卸载：
helm uninstall istiod -n istio-system
helm uninstall istio-base -n istio-system
kubectl delete namespace istio-system

# 清理 PVC（卸载后不会自动删除）
kubectl delete pvc -n openclaw -l app.kubernetes.io/instance=cookbook
```

## 主要配置项

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `secrets.existingSecret` | `""` | 引用已有 Secret（推荐） |
| `secrets.env` | `{}` | API Key 环境变量（支持任意 Key） |
| `secrets.placeholders` | 见下方 | 配置文件占位符映射 |
| `image.tag` | `latest` | 镜像版本 |
| `gateway.port` | `20000` | Gateway 监听端口 |
| `eip.enabled` | `false` | Pod 绑定公网 EIP |
| `imageCache.enabled` | `false` | TKE 自动镜像缓存 |
| `dataPersistence.enabled` | `false` | 容器数据盘保留 |
| `service.type` | `ClusterIP` | Service 类型（可改为 `LoadBalancer` 公网暴露） |
| `storage.size` | `10Gi` | PVC 容量 |
| `resources.limits.cpu` | `2` | CPU 上限 |
| `resources.limits.memory` | `2Gi` | 内存上限 |
| `istio.enabled` | `false` | 启用 Istio 治理 |
| `istio.install.enabled` | `false` | 自动安装 Istio 控制面 |
| `istio.install.version` | `1.24.6` | Istio 版本 |
| `istio.install.uninstallOnDelete` | `false` | 卸载时是否清理 Istio |
| `egressPolicy.enabled` | `false` | 出站白名单策略 |
| `egressPolicy.allowlist` | `[]` | 白名单域名列表 |

### API Key 配置

支持任意 LLM API Key，通过 `secrets.env` 配置：

```yaml
secrets:
  existingSecret: ""  # 或引用已存在的 Secret
  env:
    OPENROUTER_API_KEY: "sk-or-v1-xxx"
    OPENAI_API_KEY: "sk-xxx"
    ANTHROPIC_API_KEY: "sk-ant-xxx"
    # 可添加任意其他 API Key
  placeholders:
    # 配置文件中的占位符映射（用于 sed 替换 openclaw.json）
    OPENROUTER_API_KEY: "__OPENROUTER_API_KEY__"
    OPENAI_API_KEY: "__OPENAI_API_KEY__"
    ANTHROPIC_API_KEY: "__ANTHROPIC_API_KEY__"
```

**推荐方式**：使用 `existingSecret` 引用已存在的 Secret，避免在 values 中硬编码敏感信息：

```bash
# 先创建 Secret
kubectl create secret generic my-secrets \
  --from-literal=OPENROUTER_API_KEY=sk-or-v1-xxx \
  --from-literal=OPENAI_API_KEY=sk-xxx \
  -n openclaw

# 部署时引用
helm install cookbook ./charts/openclaw-cookbook/ \
  --set secrets.existingSecret=my-secrets \
  -n openclaw
```

完整参数见 [values.yaml](values.yaml)（标准模式）或 [values-minimal.yaml](values-minimal.yaml)（最简模式）。
