#!/bin/bash
set -e

# 下载目录（直接匹配你的离线安装脚本）
OUT_DIR="./Ubuntu/amd64"
mkdir -p ${OUT_DIR}

# 你需要的核心包
PKGS="
ansible
apt-rdepends
apt-transport-https
bash-completion
binutils
ca-certificates
chrony
curl
dpkg-dev
ethtool
git
dpkg-dev
ipset
ipvsadm
ipython3
libdpkg-perl
make
net-tools
nvidia-container-runtime
nvidia-container-toolkit
openssh-server
openvswitch-switch
python3
python3-dev
python3-pip
sshpass
telnet
wget
zlib1g-dev
"

# 【核心】下载所有包 + 完整依赖（官方最稳方法）
apt update
apt install -y apt-rdepends

for pkg in ${PKGS}; do
	  echo "==== 下载 $pkg 及所有依赖 ===="
	    # 递归获取所有真实依赖
	      DEPS=$(apt-rdepends $pkg | grep -v "^ " | grep -v -E "(debconf-2.0|perlapi|virtual|libc-bin|dpkg|libssl-doc)")
	        for d in $DEPS; do
			    apt-get download $d 2>/dev/null || true
			      done
		      done

		      # 移动所有包到目标目录
		      mv *.deb ${OUT_DIR}/

		      echo -e "\n✅ 下载完成！所有包都在：$OUT_DIR"
		      ls ${OUT_DIR} | wc -l

