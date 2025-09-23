#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以root权限运行，请使用sudo执行"
    exit 1
fi

if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | sed 's/"//g')
    echo "此脚本专为 Ubuntu 22.04 设计，检测到不兼容的操作系统: $OS_NAME"
    exit 1
fi

echo "下载所有的依赖包..."


# 1. 基础网络与系统工具类
echo "正在下载基础网络与系统工具类软件包..."
sudo apt-get download -o Dir::Cache="./" -o Dir::Cache::archives="./" \
    net-tools openssh-client openssh-server openssh-sftp-server sshpass curl wget git git-man tar apt-rdepends dpkg-dev libdpkg-perl libfile-fcntllock-perl lto-disabled-list \
    telnet bash-completion seccomp chrony ipset libipset13 ipvsadm apt-transport-https ca-certificates \
    openvswitch-common openvswitch-switch

# 2. 自动化与虚拟化工具类
echo "正在下载自动化与虚拟化工具类软件包..."
sudo apt-get download -o Dir::Cache="./" -o Dir::Cache::archives="./" \
    ansible python3 python3-pip python3-setuptools python3-wheel python3-apt python3-jinja2 python3-yaml python3-paramiko python3-pkg-resources python3-cryptography libcurl4 liberror-perl \
    ieee-data libapt-pkg-perl python-babel-localedata python3-babel python3-bcrypt python3-distutils python3-dnspython python3-lib2to3 python3-markupsafe python3-netaddr python3-packaging python3-pycryptodome python3-requests-toolbelt \
    python3-sniffio python3-trio ipython3

# 3. 开发工具与编译环境类
echo "正在下载开发工具与编译环境类软件包..."
sudo apt-get download -o Dir::Cache="./" -o Dir::Cache::archives="./" \
  binutils binutils-common binutils-x86-64-linux-gnu javascript-common libasan6 libatomic1 libbinutils libblas3 \
  libc6-dev libcc1-0 libcrypt-dev libctf-nobfd0 libctf0 libexpat1 libexpat1-dev libgcc-11-dev libgcc-s1 libgfortran5 libgomp1 libitm1 libjs-jquery libjs-jquery-ui libjs-sphinxdoc libjs-underscore liblapack3 liblbfgsb0 liblsan0 libnsl-dev libopenblas-dev \
  libopenblas-pthread-dev libopenblas0 libopenblas0-pthread libpython3-dev libpython3.10 libpython3.10-dev libpython3.10-minimal libpython3.10-stdlib libqhull-r8.0 libquadmath0 libstdc++-11-dev libstdc++6 libtirpc-dev libtk8.6 libtsan0 libubsan1 \
  libxsimd-dev linux-libc-dev manpages-dev python-matplotlib-data python3-appdirs python3-async-generator python3-attr python3-backcall python3-beniget python3-brotli python3-bs4 python3-cycler python3-decorator python3-dev python3-fonttools python3-fs \
  python3-gast python3-html5lib python3-ipython python3-jedi python3-kiwisolver python3-lxml python3-lz4 python3-matplotlib python3-matplotlib-inline python3-mpmath python3-numpy python3-outcome python3-parso python3-pickleshare python3-pil.imagetk \
  python3-ply python3-prompt-toolkit python3-pygments python3-pythran python3-scipy python3-sortedcontainers python3-soupsieve python3-sympy python3-tk python3-traitlets python3-ufolib2 python3-unicodedata2 python3-wcwidth python3-webencodings python3.10 \
  python3.10-dev python3.10-minimal rpcsvc-proto tk8.6-blt2.5 unicode-data zlib1g-dev

echo "所有软件包下载完成！"
