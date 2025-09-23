# openEuler系统上的Kubernetes自动化部署工具

## 仓库简介
该仓库是一个基于Ansible的自动化部署工具，专为在openEuler 22.03 LTS系统上部署Kubernetes（k8s）1.29版本集群设计。通过预设的角色和任务流程，可实现集群环境的快速搭建，提高部署效率和一致性。


## 核心结构
### 核心配置文件
- `ansible.cfg`：Ansible配置文件，定义Ansible运行参数。
- `hosts.ini`：主机清单，声明集群节点角色及属性（如主节点、工作节点、负载均衡节点等）。
- `install_k8s.yml`：主部署剧本，按顺序调用各角色执行部署任务。

### 角色（roles）目录
- `cluster`：负责Kubernetes集群核心操作，包括安装kubeadm、kubelet、kubectl，初始化集群，添加主节点和工作节点，安装Helm工具及Calico网络插件等。
- `docker`：部署容器运行时环境，包括安装Docker、配置cri-dockerd（Kubernetes与Docker的适配组件），以及设置cgroup驱动、镜像仓库加速等。
- `init`：系统环境初始化，涵盖检查操作系统版本、配置yum源、安装基础依赖、设置NTP时间同步、禁用SELinux、关闭防火墙、禁用Swap等前置操作。
- `lb`：配置负载均衡，通过安装haproxy和keepalived，实现Kubernetes API Server的流量转发和VIP（虚拟IP）高可用。
- `test`：包含测试任务，用于部署过程中的验证。

### 其他文件
- 各类安装包：如`docker-25.0.0.tgz`、`helm-v3.15.0-linux-amd64.tar.gz`、`cri-dockerd-0.3.4.amd64.tgz`等。
- 仓库配置文件：`openEuler.repo`等yum源配置。
- 部署脚本：`install.sh`（简化部署命令的封装脚本）。
- 说明文档：`readme.md`（仓库介绍）、`install.md`（部署步骤）。


## 主要功能
1. **环境准备**：通过`init`角色标准化系统环境，确保满足Kubernetes部署的前置条件（如内核参数、依赖库等）。
2. **容器运行时部署**：通过`docker`角色安装Docker及cri-dockerd，配置与Kubernetes兼容的运行时环境。


## 部署步骤

### 前提条件
1. 目标主机需为**openEuler 22.03 LTS**系统（通过`init`角色自动验证）。
2. 准备Ansible控制节点，确保能通过SSH无密码访问所有目标节点（`hosts.ini`中定义的节点）。
3. 确保`hosts.ini`中配置的IP地址、角色参数（如`is_master`、`is_init`、`lb_master`等）与实际环境一致。


### 1. 准备仓库
将仓库克隆到Ansible控制节点，并进入仓库目录：
```bash
git clone <仓库地址> 
cd <仓库目录>
```


### 2. 配置主机清单（`hosts.ini`）
编辑`hosts.ini`文件，定义集群节点角色：
- `[k8s]`：Kubernetes集群节点，包含：
  - 主节点（`is_master=1`），其中`is_init=1`的节点为初始化节点（第一个主节点）。
  - 工作节点（`is_worker=1`）。
- `[lb]`：负载均衡节点，`lb_master=1`为MASTER角色，`lb_master=0`为BACKUP角色，通过keepalived实现VIP高可用。
- `[test]`：可选测试节点（用于执行测试任务）。

示例配置：
```ini
[k8s]
192.168.0.106 is_master=1 is_worker=1 is_init=1  # 初始化节点（主节点+工作节点）
192.168.0.116 is_master=1 is_worker=1            # 其他主节点

[lb]
192.168.0.106 lb_master=1  # 负载均衡主节点
192.168.0.116 lb_master=0  # 负载均衡备用节点
```

### 3. 安装前脚本准备
#### 步骤1：安装net-tools、glic、python3、git等基础依赖
```bash
chmod +x install_package.sh
./install_package.sh 
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


### 4. 部署流程说明
1**系统环境初始化（`[k8s]`节点）**：
  - 检查操作系统版本、配置yum源、安装基础依赖（`init`角色任务）。
  - 禁用SELinux、防火墙、Swap，配置NTP时间同步、主机DNS和IPVS规则。
  - 修复openEuler系统特定问题（如sysctl配置、tmp.mount屏蔽）。

2. **容器运行时部署（`[k8s]`节点）**：
  - 安装Docker（从本地tgz包）及cri-dockerd（`docker`角色任务）。
  - 配置cgroup驱动（与kubelet一致）、镜像仓库加速等（`docker/02_configure_docker.yml`）。


### 5. 验证部署结果
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

4. **`export_k8s_images.sh`**
    - 功能：导出Kubernetes集群所需的镜像，用于离线环境部署。
    - 主要操作：
        - 批量导出指定的Kubernetes组件镜像（如kube-apiserver、kube-controller-manager等）
        - 将镜像保存为`.tar`文件（命名格式：`镜像名-版本.tar`）
        - 输出导出结果（成功/失败信息）
    - 使用说明：脚本内包含需导出的镜像列表，可根据需求修改后执行

### **核心优势**
1. **全自动化部署**  
   从环境初始化到集群启动的全流程通过Ansible剧本自动执行，用户仅需配置`hosts.ini`并运行部署命令，大幅减少手动操作和人为错误。

2. **深度适配openEuler**  
   针对openEuler系统的特性优化（如系统bug修复、包管理适配），相比通用部署工具（如kubeadm）更稳定可靠。

3. **高可用架构集成**  
   内置haproxy+keepalived实现控制平面高可用，无需额外手动配置，降低集群部署门槛。

4. **版本可控与兼容性保障**  
   明确指定Kubernetes 1.29、Docker 25.0.0等组件版本，通过变量文件（如`roles/cluster/vars/main.yml`）统一管理，避免版本混乱导致的兼容性问题。

5. **离线部署支持**  
   内置所有依赖安装包和仓库配置，可在无外部网络的环境中部署，适合内网或隔离环境使用。

6. **可扩展性与可配置性**  
   通过角色变量（如Pod/Service CIDR、VIP地址）支持集群参数自定义，满足不同网络环境和业务需求。

7. **完整的校验与修复机制**  
   部署过程中包含系统版本校验、组件安装校验、配置文件检查等步骤，出现问题时可通过日志（如`/tmp/kubeadm-init.log`）快速定位。


## 注意事项
1. **参数调整**：
  - 集群参数（如Pod/Service CIDR、Kubernetes版本）可修改`roles/cluster/vars/main.yml`。
  - 负载均衡的VIP（默认`192.168.0.106`）和节点IP在`roles/lb/vars/main.yml`中定义，需与实际网络匹配。

2. **依赖检查**：
  - 部署前确保`docker-25.0.0.tgz`、`cri-dockerd-0.3.4.amd64.tgz`等安装包已放置在仓库根目录（`docker`角色会校验文件存在性）。

3. **问题排查**：
  - 部署错误可查看Ansible输出日志，或目标节点上的临时日志（如`/tmp/kubeadm-init.log`）。
  - 若节点加入失败，检查网络连通性、VIP配置及`hosts.ini`参数是否正确。