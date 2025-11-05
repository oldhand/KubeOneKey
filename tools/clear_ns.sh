#!/bin/bash
set -eo pipefail

# 目标命名空间
NAMESPACE="kube-mlops"

# 检查命名空间是否存在
echo "===== 检查命名空间 $NAMESPACE 状态 ====="
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "命名空间 $NAMESPACE 不存在，无需清理，脚本退出。"
  exit 0
fi

# 步骤1：清理工作负载控制器（按顺序：Deployment -> StatefulSet -> DaemonSet -> ReplicaSet -> Job）
# 这些控制器会管理Pod，先删除它们避免Pod被重建
echo -e "\n===== 第一步：清理工作负载控制器 ====="
WORKLOAD_TYPES=(
  "Deployment"
  "StatefulSet"
  "DaemonSet"
  "ReplicaSet"
  "Job"
)

for workload in "${WORKLOAD_TYPES[@]}"; do
  # 检查该类型是否有资源
  if kubectl get "$workload" -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q .; then
    echo "删除 $workload 资源..."
    # 强制删除该类型下所有资源
    kubectl delete "$workload" -n "$NAMESPACE" --all --force --grace-period=0 --ignore-not-found || true
    # 等待2秒，确保控制器停止重建Pod
    sleep 2
  else
    echo "没有 $workload 资源，跳过..."
  fi
done

# 步骤2：清理Pod（控制器已删除，此时Pod不会再重建）
echo -e "\n===== 第二步：清理Pod ====="
if kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q .; then
  echo "删除所有Pod..."
  # 强制删除所有Pod（包括Terminating状态的）
  kubectl delete pods -n "$NAMESPACE" --all --force --grace-period=0 --ignore-not-found || true
  # 等待3秒，确保Pod彻底终止
  sleep 3
else
  echo "没有Pod资源，跳过..."
fi

# 步骤3：清理其他命名空间级资源（排除已处理的类型）
echo -e "\n===== 第三步：清理其他资源 ====="
# 获取所有命名空间级资源类型
ALL_RESOURCES=$(kubectl api-resources --namespaced=true -o name)
# 已处理的资源类型（转换为小写复数形式，匹配api-resources输出）
PROCESSED_RESOURCES=(
  "deployments"
  "statefulsets"
  "daemonsets"
  "replicasets"
  "jobs"
  "pods"
)

# 过滤出未处理的资源类型
OTHER_RESOURCES=$(comm -23 \
  <(echo "$ALL_RESOURCES" | sort) \
  <(printf "%s\n" "${PROCESSED_RESOURCES[@]}" | sort) \
)

for resource in $OTHER_RESOURCES; do
  # 检查该资源类型是否有实例
  if kubectl get "$resource" -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q .; then
    echo "删除资源类型：$resource..."
    kubectl delete "$resource" -n "$NAMESPACE" --all --force --grace-period=0 --ignore-not-found || true
  fi
done

# 步骤4：删除命名空间
echo -e "\n===== 第四步：删除命名空间 $NAMESPACE ====="
kubectl delete namespace "$NAMESPACE" --ignore-not-found

# 处理命名空间卡在Terminating状态的情况
echo -e "\n===== 检查命名空间是否残留 ====="
if kubectl get namespace "$NAMESPACE" 2>/dev/null | grep -q "Terminating"; then
  echo "命名空间 $NAMESPACE 处于Terminating状态，强制清理..."
  # 移除finalizers阻塞
  kubectl get namespace "$NAMESPACE" -o json > "/tmp/${NAMESPACE}-ns.json"
  sed -i '/"finalizers": \[.*\],/d' "/tmp/${NAMESPACE}-ns.json"
  kubectl replace --raw "/api/v1/namespaces/${NAMESPACE}/finalize" -f "/tmp/${NAMESPACE}-ns.json"
  rm -f "/tmp/${NAMESPACE}-ns.json"
fi

# 最终验证
echo -e "\n===== 清理结果验证 ====="
if kubectl get namespace "$NAMESPACE" 2>/dev/null; then
  echo "警告：命名空间 $NAMESPACE 仍未删除，请手动检查。"
else
  echo "成功删除命名空间 $NAMESPACE 及所有资源！"
fi
