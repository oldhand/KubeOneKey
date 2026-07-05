#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 权限运行（sudo）"
    exit 1
fi

echo "=== 步骤 1: 获取 Kubernetes 主节点 IP ==="

# 1. 尝试通过 kubectl 获取 master/control-plane IP
MASTER_IP=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
if [ -z "$MASTER_IP" ]; then
    MASTER_IP=$(kubectl get nodes --selector='node-role.kubernetes.io/master' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
fi

if [ -z "$MASTER_IP" ]; then
    echo "错误：无法获取 Kubernetes 主节点 IP"
    exit 1
fi

echo "成功获取到主节点 IP: $MASTER_IP"

echo "=== 步骤 2: 校验并修改 /etc/docker/daemon.json ==="

DAEMON_JSON="/etc/docker/daemon.json"
TMP_JSON="/etc/docker/daemon.json.tmp"

# 1. 如果文件不存在，初始化一个空的 JSON 对象
if [ ! -f "$DAEMON_JSON" ] || [ ! -s "$DAEMON_JSON" ]; then
    echo "提示：$DAEMON_JSON 不存在，将自动创建。"
    mkdir -p "$(dirname "$DAEMON_JSON")"
    echo "{}" > "$DAEMON_JSON"
fi

# 2. 提取当前已有的 insecure-registries 列表项
# 将换行符去掉，方便提取中括号中的内容
CONTENT_ONE_LINE=$(tr -d '\n' < "$DAEMON_JSON")
ITEMS_STR=$(echo "$CONTENT_ONE_LINE" | sed -n 's/.*"insecure-registries"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')

EXISTING_ITEMS=()
if [ -n "$ITEMS_STR" ]; then
    # 将逗号分割为换行，并去除引号与首尾空格
    while IFS= read -r item || [ -n "$item" ]; do
        item=$(echo "$item" | tr -d '"' | xargs)
        if [ -n "$item" ]; then
            EXISTING_ITEMS+=("$item")
        fi
    done <<< "$(echo "$ITEMS_STR" | tr ',' '\n')"
fi

# 3. 检查待添加的项目是否已存在
TARGET_IP="${MASTER_IP}:30100"
TARGET_HARBOR="harbor.harbor.svc.cluster.local"

ADD_IP=1
ADD_HARBOR=1

for ext in "${EXISTING_ITEMS[@]}"; do
    if [ "$ext" = "$TARGET_IP" ]; then
        ADD_IP=0
    fi
    if [ "$ext" = "$TARGET_HARBOR" ]; then
        ADD_HARBOR=0
    fi
done

CHANGED=0

if [ $ADD_IP -eq 1 ]; then
    EXISTING_ITEMS+=("$TARGET_IP")
    echo "[+] 将添加主节点配置: $TARGET_IP"
    CHANGED=1
else
    echo "[~] 主节点配置已存在: $TARGET_IP"
fi

if [ $ADD_HARBOR -eq 1 ]; then
    EXISTING_ITEMS+=("$TARGET_HARBOR")
    echo "[+] 将添加 Harbor 配置: $TARGET_HARBOR"
    CHANGED=1
else
    echo "[~] Harbor 配置已存在: $TARGET_HARBOR"
fi

# 4. 如果有变化，重建整个数组并写入文件
if [ $CHANGED -eq 1 ]; then
    # 拼接新的数组内容，不留多余的逗号
    NEW_ARRAY_STR=""
    for item in "${EXISTING_ITEMS[@]}"; do
        if [ -n "$NEW_ARRAY_STR" ]; then
            NEW_ARRAY_STR="${NEW_ARRAY_STR}, \"$item\""
        else
            NEW_ARRAY_STR="\"$item\""
        fi
    done

    # 判断 "insecure-registries" 在原 JSON 中是否存在
    if grep -q '"insecure-registries"' "$DAEMON_JSON"; then
        # 如果存在，使用 awk 安全替换中括号里的内容，支持多行和单行数组
        awk -v new_arr="$NEW_ARRAY_STR" '
        BEGIN { inside=0; replaced=0 }
        /"insecure-registries"[[:space:]]*:[[:space:]]*\[/ {
            print "  \"insecure-registries\": [" new_arr "],";
            inside=1;
            replaced=1;
            if (/\]/) { inside=0 }
            next
        }
        inside {
            if (/\]/) { inside=0 }
            next
        }
        { print }
        ' "$DAEMON_JSON" > "$TMP_JSON" && mv "$TMP_JSON" "$DAEMON_JSON"
    else
        # 如果不存在，判断原文件是否为空的对象 {}
        CLEANED_ORIG=$(tr -d '[:space:]' < "$DAEMON_JSON")
        if [ "$CLEANED_ORIG" = "{}" ]; then
            echo -e "{\n  \"insecure-registries\": [$NEW_ARRAY_STR]\n}" > "$DAEMON_JSON"
        else
            # 如果是其他 JSON 对象，在第一个 { 后面插入新的属性
            awk -v new_arr="$NEW_ARRAY_STR" '
            NR==1 {
                sub("{", "{\n  \"insecure-registries\": [" new_arr "],")
            }
            { print }
            ' "$DAEMON_JSON" > "$TMP_JSON" && mv "$TMP_JSON" "$DAEMON_JSON"
        fi
    fi
    echo "✅ 成功更新 /etc/docker/daemon.json"
else
    echo "✅ 配置已是最新，无需修改。"
fi

echo "=== 检查与更新完成 ==="
