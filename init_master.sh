#!/bin/bash
#
#下载必要镜像
cat >kubeadm_pull.sh <<EOF
for i in \`kubeadm config images list\`; do 
  imageName=\${i#k8s.gcr.io}
  docker pull gcr.azk8s.cn/google_containers/\$imageName
  docker tag gcr.azk8s.cn/google_containers/\$imageName k8s.gcr.io/\$imageName
  docker rmi gcr.azk8s.cn/google_containers/\$imageName
done;
EOF
chmod +x ./kubeadm_pull.sh
./kubeadm_pull.sh

cat >kubeadm.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: $1
controlPlaneEndpoint: "192.168.3.200:6443"
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.244.0.0/16"
  dnsDomain: "cluster.local"
---
# 开启 IPVS 模式
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
featureGates:
  SupportIPVSProxyMode: true
mode: ipvs

EOF

# kubeadm init
# 根据您服务器网速的情况，您需要等候 3 - 10 分钟  
kubeadm init --config kubeadm.yaml --ignore-preflight-errors=Swap

# 配置 kubectl	
rm -rf /root/.kube/
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# 安装 flannel 网络插件
curl -O https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f  kube-flannel.yml
kubectl get pod -n kube-system
kubectl get node

