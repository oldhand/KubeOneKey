# Kubernetes (K8s) 离线自动化部署工具 (Ansible)

## 📖 项目简介

这是一个基于 **Ansible** 的全自动化部署工具，专为在 **Linux** 环境下离线部署 **Kubernetes v1.29** 集群而设计。

该项目不仅支持标准的 K8s 集群部署，还深度集成了 **Kube-OVN** 网络插件、**HAProxy + Keepalived** 高可用架构，以及 **NVIDIA GPU** 和 **Huawei Ascend NPU** 的异构算力支持（通过 HAMI 实现 vGPU 调度）。


### ✨ 核心特性

* **完全离线部署**：内置所有依赖包（RPM/Deb）、容器镜像和二进制文件，无需外网。
* **高可用架构 (HA)**：自动检测节点数量，当主节点 ≥ 3 时，自动配置 HAProxy + Keepalived VIP。
* **异构算力支持**：
   * 自动检测并配置 NVIDIA GPU 驱动及插件。
   * 自动检测并配置 Huawei Ascend (昇腾) NPU 驱动及插件。
   * 集成 **HAMI** (Heterogeneous AI Computing Virtualization Middleware) 实现算力虚拟化与调度。
* **网络增强**：默认集成 **Kube-OVN**，提供企业级容器网络能力（子网隔离、固定 IP、QoS 等）。
* **多系统适配**：同一套脚本支持 CentOS 7.9、Ubuntu 22.04 及 openEuler 22.03 (ARM)。



## 💻 支持的操作系统
- **CentOS 7.9 (x86_64)**（已验证）
- **CentOS 7.7 (x86_64)**（已验证）
- **Ubuntu 22.04 LTS (x86_64)**（已验证）
- **openEuler 22.03 LTS (arm)**（已验证）
- 其他Linux发行版（如CentOS等）可能需要适当调整剧本以适配包管理和系统配置。

## 核心结构
### 核心配置文件
- `ansible.cfg`：Ansible配置文件，定义Ansible运行参数。
- `hosts.ini`：主机清单，声明集群节点角色及属性（如主节点、工作节点、负载均衡节点等）。
- `install_k8s.yml`：主部署剧本，按顺序调用各角色执行部署任务。

### 角色（roles）目录
- `cluster`：负责Kubernetes集群核心操作，包括安装kubeadm、kubelet、kubectl，初始化集群，添加主节点和工作节点，安装Helm工具及Calico网络插件等。
- `docker`：部署容器运行时环境，包括安装Docker、配置cri-dockerd（Kubernetes与Docker的适配组件），以及设置cgroup驱动、镜像仓库加速等。
- `init`：系统环境初始化，涵盖检查操作系统版本、配置yum源、安装基础依赖、设置NTP时间同步、禁用SELinux、关闭防火墙、禁用Swap等前置操作。


### 其他文件
- 各类安装包：如`docker-25.0.0.tgz`、`helm-v3.15.0-linux-amd64.tar.gz`、`cri-dockerd-0.3.4.amd64.tgz`等。
- 部署脚本：`install.sh`（简化部署命令的封装脚本）。
- 说明文档：`readme.md`（仓库介绍）。


## 主要功能
1. **环境准备**：通过`init`角色标准化系统环境，确保满足Kubernetes部署的前置条件（如内核参数、依赖库等）。
2. **容器运行时部署**：通过`docker`角色安装Docker及cri-dockerd，配置与Kubernetes兼容的运行时环境。


## 部署步骤

### 前提条件
1. 准备Ansible控制节点，确保能通过SSH无密码访问所有目标节点（`hosts.ini`中定义的节点）。
2. 确保`hosts.ini`中配置的IP地址、角色参数（如`is_master`、`is_init`、`lb_master`等）与实际环境一致。
3. 确保`roles/init/vars/main.yml`中配置的IP地址、主机名称与实际环境一致。
4. 确保`roles/cluster/vars/main.yml`中配置的集群配置与实际环境一致。

### 1. 准备仓库
将仓库克隆到Ansible控制节点，并进入仓库目录：
```bash
git clone <仓库地址> 
cd <仓库目录>
```



### 2\. 配置主机清单 (`hosts.ini`) [重要]

`hosts.ini` 定义了集群的拓扑结构。请根据您的环境修改 IP 和变量。

#### 变量说明

* `is_master=1`: 标记为主节点 (Control Plane)。
* `is_worker=1`: 标记为工作节点。
* `is_init=1`: **仅限一个**主节点设置，用于执行集群初始化命令。
* **高可用相关 (仅当主节点数量 ≥ 3 时生效)**:
   * `is_lb=1`: 安装 HAProxy 和 Keepalived。
   * `lb_keepalived=MASTER`: 标记为 VIP 的主抢占节点 (仅限 1 个)。
   * `lb_keepalived=BACKUP`: 标记为 VIP 的备用节点 (仅限 1 个)。
   * `lb_ingress=1`: 该节点将作为 HAProxy 转发 Ingress 流量 (80/443) 的后端目标。

#### 配置示例：3 Master 高可用集群

```ini
[k8s]
# --- Master 01: 初始化节点 + Keepalived Master ---
192.168.0.101 is_master=1 is_worker=1 is_init=1 is_lb=1 lb_keepalived=MASTER lb_ingress=1

# --- Master 02: Keepalived Backup ---
192.168.0.102 is_master=1 is_worker=1 is_lb=1 lb_keepalived=BACKUP lb_ingress=1

# --- Master 03: 普通主节点 ---
192.168.0.103 is_master=1 is_worker=1 is_lb=1 lb_ingress=1

# --- Worker 节点 (含 GPU/NPU 自动检测) ---
192.168.0.104 is_worker=1
192.168.0.105 is_worker=1
```

### 3\. 全局变量配置 (`roles/init/vars/main.yml`)

修改此文件以适配您的网络环境。

```yaml
# --- 高可用 VIP 配置 ---
# 虚拟 IP，用于 API Server 高可用，必须与节点在同一网段且未被占用
keepalived_vip: 192.168.0.88 

# 绑定 VIP 的网卡名称 (所有 LB 节点网卡名需一致，如 ens33, eth0)
nic_name: "ens33"

# --- 基础服务 ---
ntp_server: 192.168.0.139       # 时间同步服务器
dns_server:                     # 上游 DNS
  - 114.114.114.114
  - 8.8.8.8

# --- 节点信息 (用于写入 /etc/hosts) ---
k8s_master:
  - { ip: "192.168.0.101", hostname: "kube01" }
  - { ip: "192.168.0.102", hostname: "kube02" }
  - { ip: "192.168.0.103", hostname: "kube03" }
```

### 4\. 集群网络配置 (`roles/cluster/vars/main.yml`)

通常保持默认即可，除非与现有网络冲突。

```yaml
k8s_version_release: v1.29.3
pod_cidr: 192.169.0.0/16        # Pod 网络 CIDR
service_cidr: 172.23.0.0/17     # Service 网络 CIDR
control_plane_endpoint: "192.168.0.139:6443" # 单节点填真实IP，高可用模式下脚本会自动覆盖为 VIP
```

### 3. 安装前脚本准备
#### 步骤1：安装net-tools、glic、python3、git等基础依赖
```bash
chmod +x first.sh
./first.sh 
```
#### 步骤2：若您的节点使用DHCP分配IP地址，建议先将其转换为静态IP
```bash
chmod +x dhcp_to_static.sh
./dhcp_to_static.sh  
```

#### 步骤3：获取您的本地IP，自动修改必需的配置文件
```bash
chmod +x update_ip.sh
./update_ip.sh 
```

### 3. 执行部署
#### 方式1：直接运行Ansible剧本
```bash
ansible-playbook -i hosts.ini install_k8s.yml -k
```

#### 方式2：通过部署脚本运行（自动预处理环境）
```bash
chmod +x install.sh
./install.sh  # 会自动禁用Swap、关闭防火墙等，并执行部署剧本
```


### 4 验证部署结果
在任意主节点（`is_master=1`）执行以下命令，确认集群状态：
```bash
# 查看节点状态（所有节点应处于Ready状态）
kubectl get nodes

# 查看系统组件状态（所有Pod应处于Running状态）
kubectl get pods -A
```


## 脚本文件说明
以下是仓库中所有`.sh`脚本的功能说明：

1. **`install.sh`**
    - 功能：部署流程封装脚本，自动化执行环境预处理及部署任务。
    - 主要操作：
        - 禁用Swap分区并注释`/etc/fstab`中的Swap配置
        - 关闭并禁用firewalld防火墙
        - 临时关闭SELinux并配置永久关闭（需重启生效）
        - 调用Ansible剧本执行集群部署（`ansible-playbook -i hosts.ini install_k8s.yml`）
    - 使用方式：`chmod +x install.sh && ./install.sh`

2. **`dhcp_to_static.sh`**
    - 功能：将openEuler 22.03 LTS系统的DHCP网络配置转换为静态IP配置。
    - 主要操作：
        - 自动检测活动网络接口及当前DHCP分配的IP、子网掩码、网关和DNS
        - 计算子网掩码（从CIDR转换）并备份原有网络配置
        - 修改网络接口配置文件（`/etc/sysconfig/network-scripts/ifcfg-<接口名>`）
        - 重启网络服务使配置生效
    - 使用方式：`sudo ./dhcp_to_static.sh`（需root权限执行）

3. **`kube_clear.sh`**
    - 功能：清理Kubernetes集群残留数据，用于重置集群环境。
    - 主要操作：
        - 执行`kubeadm reset --force`重置集群配置
        - 删除kubelet工作目录（`/var/lib/kubelet`）和etcd数据目录（`/var/lib/etcd`）
        - 清理Kubernetes配置文件（`/etc/kubernetes`和`~/.kube/config`）
        - 停止并删除Kubernetes相关容器及镜像
    - 使用方式：`./kube_clear.sh`

   
## 注意事项
1. **参数调整**：
  - 集群参数（如Pod/Service CIDR、Kubernetes版本）可修改`roles/cluster/vars/main.yml`。 

2. **依赖检查**：
  - 部署前确保`docker-25.0.0.tgz`、`cri-dockerd-0.3.4.amd64.tgz`等安装包已放置在仓库根目录（`docker`角色会校验文件存在性）。

3. **问题排查**：
  - 部署错误可查看Ansible输出日志，或目标节点上的临时日志（如`/tmp/kubeadm-init.log`）。
  - 若节点加入失败，检查网络连通性、VIP配置及`hosts.ini`参数是否正确。


## 🔧 常见问题与维护

### 如何重置集群？

如果部署失败或需要重新部署，请运行根目录下的清理脚本。该脚本会重置 kubeadm、清理 CNI 网络残留和 etcd 数据。

```bash
./kube_clear.sh
```

### 高可用是如何工作的？

1.  **判定逻辑**：Ansible 任务 `20_check_lb.yml` 会计算 `master_node_count`。若数量 **\>= 3**，则触发 LB 安装。
2.  **流量路径**：
* 客户端 (kubectl/Worker) -\> **VIP (192.168.0.88)** -\> **Keepalived (Master)** -\> **HAProxy (本机)** -\> **API Servers (101, 102, 103)**。
3.  **配置检查**：
* HAProxy 配置模板：`roles/init/templates/haproxy-cfg.j2`
* Keepalived 配置模板：`roles/init/templates/keepalived-conf.j2` (使用单播 Unicast 模式，适应云环境)。

### 算力调度 (HAMI)

项目默认集成了 HAMI (v2.6.1)。它通过 Webhook 拦截 Pod 创建请求，实现 vGPU 切分和显存隔离。

* 配置文件：`roles/hami/files/hami.yaml`
* 查看状态：`kubectl get pods -n kube-system -l app.kubernetes.io/component=hami-scheduler`

-----