#!/bin/bash
# 用于更新配置中的IP地址为当前活动网卡IP

# 确保以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行此脚本 (sudo $0)"
    exit 1
fi


# 检测网络接口（默认使用第一个活动接口）
INTERFACE=$(ip -br link show | awk '$1 !~ "lo" && $2 ~ "UP" {print $1; exit}')
if [ -z "$INTERFACE" ]; then
    echo "未找到活动的网络接口，请检查网络连接"
    exit 1
fi

echo "检测到活动网络接口: $INTERFACE"

# 获取当前IP地址（修复换行符问题）
NEW_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 | tr -d '\n')
if [ -z "$NEW_IP" ]; then
    echo "无法获取当前IP地址"
    exit 1
fi

echo "当前IP地址: $NEW_IP"

# 查找旧IP地址 - 从hosts.ini中提取
if [ -f "hosts.ini" ]; then
    OLD_IP=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' hosts.ini | head -n 1 | tr -d '\n')
    if [ -z "$OLD_IP" ]; then
        echo "未在hosts.ini中找到旧IP地址，可能是首次配置"
        exit 0
    fi
else
    echo "未找到hosts.ini文件"
    exit 1
fi

echo "检测到旧IP地址: $OLD_IP"

# 如果新旧IP相同，则无需修改
if [ "$OLD_IP" = "$NEW_IP" ]; then
    echo "IP地址未发生变化，无需更新"
    exit 0
fi

# 确认是否执行替换
read -p "是否将所有 '$OLD_IP' 替换为 '$NEW_IP'? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "脚本已取消"
    exit 1
fi

# 定义需要替换的文件和目录
FILES=(
    "hosts.ini"
    "roles/init/vars/main.yml"
    "roles/cluster/vars/main.yml"
)

DIRS=(
    "roles/cluster/tasks"
    "roles/init/tasks"
    "roles/docker/tasks"
)

# 替换文件中的IP地址
replace_ip() {
    local file=$1
    if [ -f "$file" ]; then
        echo "更新文件: $file"
        # 直接替换IP地址，不创建备份
        sed -i "s/$OLD_IP/$NEW_IP/g" "$file"
    fi
}

# 处理单独文件
for file in "${FILES[@]}"; do
    replace_ip "$file"
done

# 处理目录中的所有文件
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "更新目录: $dir"
        find "$dir" -type f -exec sed -i "s/$OLD_IP/$NEW_IP/g" {} \;
    fi
done

echo "IP地址更新完成: $OLD_IP -> $NEW_IP"

echo "开始更新网卡名称的配置"


# 定义需要更新的配置文件路径
CONFIG_FILES=(
    "roles/init/vars/main.yml"       # 包含 nic_name
)

# 检查文件是否存在
for file in "${CONFIG_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "错误：配置文件 $file 不存在"
        exit 1
    fi
done

# 更新 nic_name（在 init/vars/main.yml 中）
echo "更新 roles/init/vars/main.yml 中的 nic_name 为 $INTERFACE"
sed -i "s/^nic_name: .*/nic_name: \"$INTERFACE\"/" roles/init/vars/main.yml

echo "网卡名称更新完成"
