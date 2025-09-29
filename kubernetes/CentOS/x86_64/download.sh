#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要以root权限运行，请使用sudo执行"
    exit 1
fi

cp -fr ./k8s.repo /etc/yum.repos.d/

sudo yumdownloader --resolve --destdir=$PWD/ \
  kubeadm-1.29.15-150500.1.1.x86_64 \
  kubelet-1.29.15-150500.1.1.x86_64 \
  kubectl-1.29.15-150500.1.1.x86_64 \
  cri-tools-1.29.0-150500.1.1.x86_64 \
  conntrack-tools.x86_64.0.1.4.4-7.el7.rpm \
  libnetfilter_cthelper-1.0.0-11.el7.rpm \
  libnetfilter_cttimeout-1.0.0-7.el7.rpm \
  libnetfilter_queue-1.0.2-2.el7_2.rpm