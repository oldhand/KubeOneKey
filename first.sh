#!/bin/bash

# 检查是否为 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 权限运行（sudo）"
    exit 1
fi

# --------------------------
# 1. 系统与架构识别
# --------------------------
os_name=$(grep NAME /etc/os-release | head -n1 | cut -d= -f2 | sed 's/"//g' | cut -d' ' -f1)
if [ -z "$os_name" ]; then
    echo "错误：无法识别操作系统"
    exit 1
fi

cpu_arch=$(uname -m)
# Ubuntu 架构映射（x86_64 → amd64，与 deb 包匹配）
if [ "$os_name" = "Ubuntu" ] && [ "$cpu_arch" = "x86_64" ]; then
    cpu_arch="amd64"
fi

echo "操作系统: $os_name"
echo "CPU架构: $cpu_arch"


# --------------------------
# 2. 复制本地包到目标目录（确保离线包可用）
# --------------------------
src_pkg_dir="./packages/$os_name/$cpu_arch"  # 脚本同级目录的离线包源
dest_pkg_dir="/home/packages"  # 最终私有源目录

# 检查源包目录是否存在
if [ ! -d "$src_pkg_dir" ]; then
    echo "错误：离线包源目录不存在 - $src_pkg_dir"
    exit 1
fi

# 创建并复制包到目标目录（覆盖旧文件，确保最新）
mkdir -p "$dest_pkg_dir" || { echo "错误：创建目标目录失败"; exit 1; }
cp -rf "$src_pkg_dir"/* "$dest_pkg_dir/" || { echo "错误：复制包失败"; exit 1; }
chmod -R 755 "$dest_pkg_dir"  # 确保包管理工具可访问
echo "离线包已同步到私有目录：$dest_pkg_dir"


# --------------------------
# 3. 离线安装私有源工具（createrepo/dpkg-dev）
# --------------------------
if [ "$os_name" = "CentOS" ]; then
    # RPM 系：离线安装 createrepo 及其依赖（包已在 dest_pkg_dir 中）
    echo "离线安装 createrepo 工具..."
    rpm -ivh "$dest_pkg_dir"/deltarpm-3.6-3.el7.x86_64.rpm --force --nodeps
    rpm -ivh "$dest_pkg_dir"/python-deltarpm-3.6-3.el7.x86_64.rpm --force --nodeps
    rpm -ivh "$dest_pkg_dir"/createrepo-0.9.9-28.el7.noarch.rpm --force --nodeps
elif [ "$os_name" = "openEuler" ]; then
     echo "离线安装 createrepo 工具..."
     rpm -ivh "$dest_pkg_dir"/drpm-0.5.0-2.oe2203.aarch64.rpm --force --nodeps
     rpm -ivh "$dest_pkg_dir"/createrepo_c-0.17.6-1.oe2203.aarch64.rpm --force --nodeps
elif [ "$os_name" = "Ubuntu" ]; then
    # DEB 系：离线安装 dpkg-dev 及其依赖（包已在 dest_pkg_dir 中）
    echo "离线安装 dpkg-dev 工具..."
    # 安装目录下所有 DEB 包（包含 dpkg-dev 及依赖）
    sudo dpkg -i "$dest_pkg_dir"/dpkg-dev_1.21.1ubuntu2.3_all.deb
else
    echo "错误：不支持的操作系统 - $os_name"
    exit 1
fi


# --------------------------
# 4. 创建离线私有源（无网络依赖）
# --------------------------
if [ "$os_name" = "openEuler" ] || [ "$os_name" = "CentOS" ]; then
    # RPM 系：生成 yum 源元数据
    echo "生成离线 yum 私有源..."
    rm -f "$dest_pkg_dir"/repodata/ 2>/dev/null
    createrepo "$dest_pkg_dir" || { echo "错误：生成 yum 源元数据失败"; exit 1; }

    # 配置本地 yum 源
    repo_file="/etc/yum.repos.d/ansible-local.repo"
    cat > "$repo_file" <<EOF
[ansible-local]
name=Offline Ansible Repo
baseurl=file://$dest_pkg_dir
enabled=1
gpgcheck=0
priority=1
EOF

    # 清理缓存（离线环境无需联网更新）
    yum clean all >/dev/null 2>&1

elif [ "$os_name" = "Ubuntu" ]; then
    # DEB 系：生成 apt 源索引
    echo "生成离线 apt 私有源..."
    rm -fr "$dest_pkg_dir"/Packages* 2>/dev/null
    cd "$dest_pkg_dir" || exit 1
    dpkg-scanpackages . /dev/null | gzip -c > Packages.gz || {
        echo "错误：生成 apt 源索引失败"
        exit 1
    }
    cd - >/dev/null 2>&1

    # 配置本地 apt 源
    list_file="/etc/apt/sources.list.d/ansible-local.list"
    cat > "$list_file" <<EOF
deb [trusted=yes] file://$dest_pkg_dir ./
EOF

    # 离线更新缓存（不联网，仅加载本地源）
    apt update -o Dir::Etc::sourcelist="sources.list.d/ansible-local.list" \
               -o Dir::Etc::sourceparts="-" \
               -o APT::Get::List-Cleanup="0" >/dev/null 2>&1 || {
        echo "警告：apt 缓存更新跳过网络源（正常离线行为）"
    }
fi


# --------------------------
# 5. 离线安装 ansible（仅用本地源）
# --------------------------
echo "从离线私有源安装 ansible..."
if [ "$os_name" = "CentOS" ]; then
    yum install -y git unzip  --disablerepo=* --enablerepo=ansible-local
    yum install -y ansible --disablerepo=* --enablerepo=ansible-local
elif [ "$os_name" = "openEuler" ]; then
    yum install -y python3-libselinux --disablerepo=* --enablerepo=ansible-local
    yum install -y ansible --disablerepo=* --enablerepo=ansible-local
else
    apt install -y ansible -o Dir::Etc::sourcelist="sources.list.d/ansible-local.list" -o Dir::Etc::sourceparts="-"
fi

# 验证安装结果
if command -v ansible &>/dev/null; then
    echo "ansible 离线安装成功！版本：$(ansible --version | head -n1)"
else
    echo "错误：ansible 安装失败（检查私有源是否包含完整依赖）"
    exit 1
fi



if [ "$os_name" = "CentOS" ]; then
    rpm -e ansible-2.9.27-1.el7.noarch
    pip3 install $(pwd)/pip/$os_name/pip-21.3.1-py3-none-any.whl
    pip3 install --no-index --find-links=$(pwd)/pip/$os_name ansible
    ln -s /usr/local/bin/ansible /usr/bin/ansible-playbook
    ln -s /usr/local/bin/ansible /usr/bin/ansible-galaxy
    ln -s /usr/local/bin/ansible /usr/bin/ansible
    ansible-galaxy collection install $(pwd)/kubernetes/kubernetes-core-6.1.0.tar.gz --force
    pip3 install --no-index --find-links=$(pwd)/pip/$os_name kubernetes PyYAML
else
  ansible-galaxy collection install $(pwd)/kubernetes/kubernetes-core-6.1.0.tar.gz --force
  pip3 install --no-index --find-links=$(pwd)/pip/$os_name kubernetes PyYAML
fi
