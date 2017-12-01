#!/bin/bash
Green_font="\033[32m" && Yellow_font="\033[33m" && Red_font="\033[31m" && Font_suffix="\033[0m"
Info="${Green_font}[Info]${Font_suffix}"
Error="${Red_font}[Error]${Font_suffix}"
echo -e "${Green_font}
#================================================
# Project: tcp_nanqinlang
# Description: lkl centos branch
# Version: 1.0.0
# Author: nanqinlang
# Blog:   https://sometimesnaive.org
# Github: https://github.com/nanqinlang
#================================================${Font_suffix}"

check_system(){
	[[ -z "`cat /etc/redhat-release | grep -E -i "CentOS"`" ]] && echo -e "${Error} only support CentOS !" && exit 1
	[[ "`uname -m`" != "x86_64" ]] && echo -e "${Error} only support 64 bit" && exit 1
}

check_root(){
	[[ "`id -u`" != "0" ]] && echo -e "${Error} must be root user" && exit 1
}

check_ovz(){
	yum update && yum install -y virt-what
	virt=`virt-what`
	[[ "${virt}" != "openvz" ]] && echo -e "${Error} only support OpenVZ !" && exit 1
}

check_ldd(){
    ldd=`ldd --version | grep ldd | awk '{print $NF}'`
    [[ "${ldd}" < "2.14" ]] && echo -e "${Error} ldd version < 2.14, not support" && exit 1
}

directory(){
	[[ ! -d /home/tcp_nanqinlang ]] && mkdir -p /home/tcp_nanqinlang
	cd /home/tcp_nanqinlang
}

config(){
	echo -e "${Info} 你想加速单个端口（例如 443）还是端口段(例如 8080-9090) ？\n1.单个端口\n2.端口段"
	read -p "(输入数字以选择):" choose
	while [[ ! "${choose}" =~ ^[1-2]$ ]]
	do
		echo -e "${Error} 无效输入"
		echo -e "${Info} 请重新选择" && read -p "输入数字以选择:" choose
	done

	if [[ "${choose}" == "1" ]]; then
		 echo -e "${Info} 输入你想加速的端口"
		 read -p "(输入单个端口号，例如：443，默认使用 443):" port1
		 [[ -z "${port1}" ]] && port1=443
		 config-haproxy-1
		 config-redirect-1
	else
		 echo -e "${Info} 输入端口段的第一个端口号"
		 read -p "(例如端口段为 8080-9090，则此处输入 8080，默认使用 8080):" port1
		 [[ -z "${port1}" ]] && port1=8080
		 echo -e "${Info} 输入端口段的第二个端口号"
		 read -p "(例如端口段为 8080-9090，则此处输入 9090，默认使用 9090):" port2
		 [[ -z "${port2}" ]] && port2=9090
		 config-haproxy-2
		 config-redirect-2
	fi
}

config-haproxy-1(){
echo -e "global

defaults
log global
mode tcp
option dontlognull
timeout connect 5000
timeout client 10000
timeout server 10000

frontend proxy-in
bind *:${port1}
default_backend proxy-out

backend proxy-out
server server1 10.0.0.1 maxconn 20480\c" > haproxy.cfg
}

config-haproxy-2(){
echo -e "global

defaults
log global
mode tcp
option dontlognull
timeout connect 5000
timeout client 10000
timeout server 10000

frontend proxy-in
bind *:${port1}-${port2}
default_backend proxy-out

backend proxy-out
server server1 10.0.0.1 maxconn 20480\c" > haproxy.cfg
}

config-redirect-1(){
echo -e "ip tuntap add lkl-tap mode tap
ip addr add 10.0.0.1/24 dev lkl-tap
ip link set lkl-tap up
sysctl -w net.ipv4.ip_forward=1
iptables -P FORWARD ACCEPT
iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
iptables -t nat -A PREROUTING -i venet0 -p tcp --dport ${port1} -j DNAT --to-destination 10.0.0.2
nohup /home/tcp_nanqinlang/load.sh &\c" > running.sh
}

config-redirect-2(){
echo -e "ip tuntap add lkl-tap mode tap
ip addr add 10.0.0.1/24 dev lkl-tap
ip link set lkl-tap up
sysctl -w net.ipv4.ip_forward=1
iptables -P FORWARD ACCEPT
iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
iptables -t nat -A PREROUTING -i venet0 -p tcp --dport ${port1}:${port2} -j DNAT --to-destination 10.0.0.2
nohup /home/tcp_nanqinlang/load.sh &\c" > running.sh
}

install(){
	check_system
	check_root
	check_ovz
	check_ldd
	directory
	config

    #haproxy config
	yum install -y iptables bc haproxy
    [[ ! -f haproxy.cfg ]] && echo -e "${Error} not found haproxy config, please check !" && exit 1
	chmod 7777 haproxy.cfg

	#download lkl
    [[ ! -f tcp_nanqinlang.so ]] && wget https://raw.githubusercontent.com/nanqinlang-tcp/tcp_nanqinlang/lkl/mod/tcp_nanqinlang.so
	[[ ! -f tcp_nanqinlang.so ]] && echo -e "${Error} download lkl failed, please check !" && exit 1
	chmod 7777 tcp_nanqinlang.so

    #load lkl
    [[ ! -f load.sh ]] && wget https://raw.githubusercontent.com/nanqinlang-tcp/tcp_nanqinlang/lkl/sh/load.sh
    [[ ! -f load.sh ]] && echo -e "${Error} download file failed, please check !" && exit 1
	chmod 7777 load.sh

    #apply redirect
    [[ ! -f running.sh ]] && echo -e "${Error} not found redirect config, please check !" && exit 1
	chmod 7777 running.sh

    #self start
    sed -i 's/exit 0/ /ig' /etc/rc.local
	echo -e "\n/home/tcp_nanqinlang/running.sh\c" >> /etc/rc.local

	#run
	bash running.sh
	status
}

status(){
	pingstatus=`ping 10.0.0.2 -c 3 | grep ttl`
	if [[ ! -z "${pingstatus}" ]]; then
		echo -e "${Info} tcp_nanqinlang is running"
		else echo -e "${Error} tcp_nanqinlang not running, please check !"
	fi
}

uninstall(){
	check_system
	check_root
	killall haproxy && yum remove -y haproxy
	rm -rf /home/tcp_nanqinlang
	#iptables -F
	sed -i '/\/home\/tcp_nanqinlang\/running.sh/d' /etc/rc.local
	echo -e "${Info} please remember ${reboot} to stop tcp_nanqinlang"
}




echo -e "${Info} 选择你要使用的功能: "
echo -e "1.安装 lkl\n2.检查 lkl 运行状态\n3.卸载 lkl"
read -p "输入数字以选择:" function

while [[ ! "${function}" =~ ^[1-3]$ ]]
	do
		echo -e "${Error} 无效输入"
		echo -e "${Info} 请重新选择" && read -p "输入数字以选择:" function
	done

if [[ "${function}" == "1" ]]; then
	install
elif [[ "${function}" == "2" ]]; then
	status
else
	uninstall
fi
