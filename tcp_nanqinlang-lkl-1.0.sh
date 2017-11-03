#!/bin/bash
Green_font="\033[32m" && Yellow_font="\033[33m" && Red_font="\033[31m" && Font_suffix="\033[0m"
Info="${Green_font}[Info]${Font_suffix}"
Error="${Red_font}[Error]${Font_suffix}"
reboot="${Yellow_font}reboot${Font_suffix}"
echo -e "${Green_font}
#================================================
# Project: tcp_nanqinlang
# Description: tcp bbr enhancement via lkl
# Version: 1.0.0
# Author: nanqinlang
# Blog:   https://sometimesnaive.org
# Github: https://github.com/nanqinlang
#================================================${Font_suffix}"

check_system(){
	cat /etc/issue | grep -q -E -i "debian" && release="debian"
	sys_ver=`grep -oE  "[0-9.]+" /etc/issue`
	bit=`uname -m`
	[[ "${release}" != "debian" ]] && echo -e "${Error} only support Debian !" && exit 1
	[[ "${sys_ver}" < "8" ]] && echo -e "${Error} only support Debian 8+ !" && exit 1
	[[ "${bit}" != "x86_64" ]] && echo -e "${Error} only support 64 bit" && exit 1
}

check_root(){
	[[ "`id -u`" != "0" ]] && echo -e "${Error} must be root user" && exit 1
}

check_ovz(){
	apt-get update && apt-get install -y virt-what
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

config-haproxy(){
	echo -e "${Info} 输入你想加速的端口号(默认 8080-9090):"
	read -p "(输入单个端口号或端口段，例如：443 或 8000-9000):" port
	[[ -z "${port}" ]] && port=8080-9090

echo -e "global

defaults
log global
mode tcp
option dontlognull
timeout connect 5000
timeout client 10000
timeout server 10000

frontend proxy-in
bind *:${port}
default_backend proxy-out

backend proxy-out
server server1 10.0.0.1 maxconn 20480\c" > haproxy.cfg
}

config-redirect(){
echo -e "ip tuntap add lkl-tap mode tap
ip addr add 10.0.0.1/24 dev lkl-tap
ip link set lkl-tap up
sysctl -w net.ipv4.ip_forward=1
iptables -P FORWARD ACCEPT
iptables -t nat -A POSTROUTING -o venet0 -j MASQUERADE
iptables -t nat -A PREROUTING -i venet0 -p tcp --dport ${port} -j DNAT --to-destination 10.0.0.2
nohup /home/tcp_nanqinlang/load.sh &\c" > running.sh
}

install(){
	check_system
	check_root
	check_ovz
	check_ldd
	directory

    #haproxy config
	apt-get install -y bc haproxy
    [[ ! -f haproxy.cfg ]] && config-haproxy
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
    [[ ! -f running.sh ]] && config-redirect
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
	ping=`ping 10.0.0.2 -c 3 | grep ttl`
	if [[ ! -z "${ping}" ]]; then
	echo -e "${Info} tcp_nanqinlang is running"
	else echo -e "${Error} tcp_nanqinlang not running, please check !"
	fi
}

uninstall(){
	check_system
	check_root
	killall haproxy && apt-get remove -y haproxy
	rm -rf /home/tcp_nanqinlang
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
