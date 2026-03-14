# ==================== 集群输出 ====================

output "cluster_id" {
  description = "TKE 集群 ID"
  value       = tencentcloud_kubernetes_cluster.cookbook.id
}

output "cluster_name" {
  description = "TKE 集群名称"
  value       = tencentcloud_kubernetes_cluster.cookbook.cluster_name
}

output "kubeconfig" {
  description = "Kubeconfig 配置（用于 kubectl/helm 连接集群）"
  value       = tencentcloud_kubernetes_cluster_endpoint.cookbook.kube_config
  sensitive   = true
}

# ==================== 网络输出 ====================

output "vpc_id" {
  description = "VPC ID"
  value       = tencentcloud_vpc.cookbook.id
}

output "subnet_id" {
  description = "子网 ID（广州6区）"
  value       = tencentcloud_subnet.cookbook.id
}

output "subnet_id_gz7" {
  description = "子网 ID（广州7区）"
  value       = tencentcloud_subnet.cookbook_gz7.id
}

output "security_group_id_control_plane" {
  description = "控制面安全组 ID（apiserver 公网端点使用，放通 443）"
  value       = tencentcloud_security_group.control_plane.id
}

output "security_group_id_workload" {
  description = "工作负载安全组 ID（超级节点池 / 容器使用，仅开放 cookbook 服务端口）"
  value       = tencentcloud_security_group.workload.id
}

# ==================== 超级节点池输出 ====================

output "serverless_node_pool_id" {
  description = "超级节点池 ID（广州6区）"
  value       = tencentcloud_kubernetes_serverless_node_pool.cookbook.id
}

output "serverless_node_pool_id_gz7" {
  description = "超级节点池 ID（广州7区）"
  value       = tencentcloud_kubernetes_serverless_node_pool.cookbook_gz7.id
}

# ==================== 使用提示 ====================

output "next_steps" {
  description = "集群创建完成后的下一步操作"
  value       = <<-EOT
    ✅ 集群创建完成！下一步操作：

    1. 导出 kubeconfig:
       terraform output -raw kubeconfig > ~/.kube/config-openclaw
       export KUBECONFIG=~/.kube/config-openclaw

    2. 验证集群连接:
       kubectl get nodes

    3. 部署 cookbook（以 OpenAI 为例）:
       cd .. # 确保回到 openclaw-on-tencentcloud-tke-serverless-cookbook 根目录
       helm install cookbook ./charts/openclaw-cookbook/ \
         -f ./charts/openclaw-cookbook/values-minimal.yaml \
         --namespace openclaw --create-namespace \
         --set provider.name=openai \
         --set provider.baseUrl=https://api.openai.com/v1 \
         --set secrets.env.API_KEY=sk-proj-xxx \
         --set provider.defaultModel=gpt-4o \
         --set gateway.authToken=your-gateway-token 
    
    4. 访问 Gateway Control UI（自签名证书，需点击"继续访问"）:
       echo "https://$(kubectl get svc -n openclaw --field-selector spec.type=LoadBalancer -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"

    5. 体验完成后销毁所有资源（避免持续计费）:
       helm uninstall cookbook -n openclaw
       terraform destroy
  EOT
}
