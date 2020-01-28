#!/bin/bash
#
# 在 master 节点和 worker 节点都要执行
# 关闭 防火墙
downfire(){
systemctl status firewalld >/dev/null
if [[ $? -eq 0 ]];then
	systemctl stop firewalld && systemctl disable firewalld
fi
}
# 关闭 SeLinux
downselinux(){
echo $(getenforce)|grep '^Disabled$' >/dev/null
if [[ $? -ne 0 ]];then
	setenforce 0
	sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
fi
}
# 关闭 swap
#swapoff -a
#yes | cp /etc/fstab /etc/fstab_bak
#cat /etc/fstab_bak |grep -v swap > /etc/fstab

# 时间同步
chrony(){
chronyc -v >/dev/null
if [[ $? -ne 0 ]];then
	yum -y install chrony >dev/null
	mv /etc/chrony.conf{,.bak}
cat > /etc/chrony.conf <<EOF
server ntp1.aliyun.com
server time1.aliyun.com
stratumweight 0
driftfile /var/lib/chrony/drift
rtcsync
logdir /var/log/chrony
EOF
	systemctl start chronyd.service && systemctl enable chronyd.service
	echo"install chrony success !"
fi
}
# 三台主机分别修改hostname
#hostnamectl set-hostname node1
#hostnamectl set-hostname node2

# 配置主机映射（自己修改为自己实际的）
##127.0.0.1 localhost localhost.localdomain localhost4 localhost4.localdomain4
#::1 localhost localhost.localdomain localhost6 localhost6.localdomain6
#192.168.3.200 master
#192.168.3.201 node1
#192.168.3.202 node2
#EOF
set_kenrel(){
# 调整内核参数，对于K8S
if [[ ! -f /etc/sysctl.d/kubernetes.conf ]];then
cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.tcp_tw_recycle=0
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nv_conntrack_max=2310720
EOF
	sysctl -f /etc/sysctl.d/kubernetes.conf >dev/null
fi

# 配置资源限制
cat /etc/security/limits.conf|grep 'soft nofile 65536'
if [[ $? -ne 0 ]];then
cat  >> /etc/security/limits.conf << EOF
* - nofile 1800000
* soft nproc 65536
* hard nproc 65536
* soft nofile 65536
* hard nofile 65536
EOF
fi

ipvsadm -v >/dev/null
if [[ $? -ne 0 ]];then
	yum -y install ipset* ipvsadm >dev/null
	modprobe br_netfilter
cat > /etc/sysconfig/modules/ipvs.modules <<EOF
#!/bin/bash 
modprobe -- ip_vs 
modprobe -- ip_vs_rr 
modprobe -- ip_vs_wrr 
modprobe -- ip_vs_sh 
modprobe -- nf_conntrack_ipv4 
EOF
chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack_ipv4
fi
}
# 安装 docker
install_docker(){
# 卸载旧版本
yum remove -y docker \
docker-client \
docker-client-latest \
docker-common \
docker-latest \
docker-latest-logrotate \
docker-logrotate \
docker-selinux \
docker-engine-selinux \
docker-engine

# 设置 yum repository
yum install -y epel-release yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

# 安装并启动 docker
yum install -y docker-ce >/dev/null
# 设置 docker 镜像，提高 docker 镜像下载速度和稳定性
cat > /etc/docker/daemon.json <<EOF 
{
    "registry-mirrors":["https://vr37c7hn.mirror.aliyuncs.com"],
    "exec-opts":["native.cgroupdriver=systemd"],
    "log-driver":"json-file",
    "log-opts":{
        "max-size":"100m"
    }
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload && systemctl restart docker && systemctl enable docker
echo "install docker success!"
}
# 配置K8S的yum源
install_k8s(){
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
       http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

# 卸载旧版本
yum remove -y kubelet kubeadm kubectl >/dev/null
# 安装kubelet、kubeadm、kubectl
yum install -y kubelet-${1} kubeadm-${1} kubectl-${1} >/dev/null
# 启动 kubelet
systemctl enable kubelet && systemctl start kubelet
echo "KUBELET_EXTRA_ARGS=--fail-swap-on=false" >/etc/sysconfig/kubelet
echo "install k8s success"
}
downfire
downselinux
chrony
set_kenrel
install_docker
install_k8s