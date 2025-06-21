#!/bin/bash
export LANG=en_US.UTF-8
###############################################################################################################
# 定义颜色与
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
white() { echo -e "\033[37m\033[01m$1\033[0m"; }
readp(){ read -p "$(yellow "$1")" $2;}

# 检测vps root模式  release变量为linux系统发行版的名称
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit

if [[ -f /etc/redhat-release ]]; then
    release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
else
    red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

# 如果系统是arch,就显示信息不支持,并退出脚本
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
    red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

# 显示当前正在运行的 Linux 内核版本
version=$(uname -r | cut -d "-" -f1)

# 判断vps是什么类型的机器      vi 变量存储了检测到的虚拟化类型（如 kvm, docker, lxc, vmware 等）
# 如果是物理机,virt-what 可能无输出或空
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)

###############################################################################################################

# 检测当前系统的 CPU 架构    cpu 变量存储了linux系统的架构
case $(uname -m) in
armv7l) cpu=armv7 ;;
aarch64) cpu=arm64 ;;
x86_64) cpu=amd64 ;;
i386 | i686) cpu="386" ;;
*) red "目前脚本不支持$(uname -m)架构" && exit ;;
esac

# 检测vps主机名称  hostname 存储了vps的主机名
hostname=$(hostname)

###############################################################################################################

# 不同系统安装脚本依赖文件
if [ ! -f sbyg_update ]; then   # ① 检查标记文件
    green "首次安装mihomo脚本必要的依赖……" # ② 提示信息

    if [[ x"${release}" == x"alpine" ]]; then # ③ 如果是 Alpine Linux
        # Alpine 特定的包管理操作 (apk)
        apk update
        apk add wget curl tar jq tzdata openssl expect git socat iproute2 iptables grep coreutils util-linux dcron
        apk add virt-what
        apk add qrencode
    else # ④ 如果不是 Alpine Linux (可能是 Debian/Ubuntu, CentOS, Fedora 等)

        if [[ $release = Centos && ${vsid} =~ 8 ]]; then # ⑤ 如果是 CentOS 8
            # CentOS 8 特定的仓库配置 (替换为阿里云镜像)
            cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/
            curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
            sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
            sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
            yum clean all && yum makecache
            cd
        fi

        # ⑥ 根据包管理器类型安装通用依赖
        if [ -x "$(command -v apt-get)" ]; then # 如果是 Debian/Ubuntu
            apt update -y
            apt install jq cron socat iptables-persistent coreutils util-linux -y
        elif [ -x "$(command -v yum)" ]; then # 如果是 CentOS/RHEL (老版本)
            yum update -y && yum install epel-release -y
            yum install jq socat coreutils util-linux -y
        elif [ -x "$(command -v dnf)" ]; then # 如果是 Fedora/CentOS 8+
            dnf update -y
            dnf install jq socat coreutils util-linux -y
        fi

        # ⑦ 为 CentOS/RHEL/Fedora 系统安装并启用 cronie 和 iptables 服务
        if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
            if [ -x "$(command -v yum)" ]; then
                yum install -y cronie iptables-services
            elif [ -x "$(command -v dnf)" ]; then
                dnf install -y cronie iptables-services
            fi
            systemctl enable iptables >/dev/null 2>&1
            systemctl start iptables >/dev/null 2>&1
        fi

        # ⑧ 如果是物理机（或未检测到虚拟化类型）安装特定包
        if [[ -z $vi ]]; then
            apt install iputils-ping iproute2 systemctl -y # 这里只有 apt 命令，可能逻辑不完整
        fi

        # ⑨ 检查并安装核心工具包
        packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
        inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
        for i in "${!packages[@]}"; do
            package="${packages[$i]}"
            inspackage="${inspackages[$i]}"
            if ! command -v "$package" &>/dev/null; then # 检查命令是否存在
                if [ -x "$(command -v apt-get)" ]; then  # Debian/Ubuntu
                    apt-get install -y "$inspackage"
                elif [ -x "$(command -v yum)" ]; then # CentOS/RHEL
                    yum install -y "$inspackage"
                elif [ -x "$(command -v dnf)" ]; then # Fedora/CentOS 8+
                    dnf install -y "$inspackage"
                fi
            fi
        done
    fi
    touch sbyg_update # ⑩ 创建标记文件
fi

###############################################################################################################

# 用来处理 OpenVZ 虚拟化环境下 TUN 模块的支持问题
if [[ $vi = openvz ]]; then      # ① 检查是否为 OpenVZ 虚拟化环境
    TUN=$(cat /dev/net/tun 2>&1) # ② 尝试读取 TUN 设备状态
    # ③ 检查 TUN 设备是否处于错误状态
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
        red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4                                # ④ 提示未开启 TUN 并尝试添加
        cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun # ⑤ 创建 TUN 设备文件
        TUN=$(cat /dev/net/tun 2>&1)                                         # ⑥ 再次检查 TUN 设备状态
        # ⑦ 再次检查 TUN 设备是否仍处于错误状态
        if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
            green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit # ⑧ 失败则提示并退出
        else
            echo '#!/bin/bash' >/root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >>/root/tun.sh && chmod +x /root/tun.sh # ⑨ 创建 TUN 守护脚本
            grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >>/etc/crontab       # ⑩ 添加到 Crontab 实现开机自启
            green "TUN守护功能已启动"                                                                                                                                      # ⑪ 提示守护功能启动
        fi
    fi
fi

###############################################################################################################
# 询问是否开放防火墙函数
openyn() {
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    readp "是否开放端口，关闭防火墙？\n1、是，执行 (回车默认)\n2、否，跳过！自行处理\n请选择【1-2】：" action
    if [[ -z $action ]] || [[ "$action" = "1" ]]; then
        close
    elif [[ "$action" = "2" ]]; then
        echo
    else
        red "输入错误,请重新选择" && openyn
    fi
}

# 开放防火墙函数
close() {
    systemctl stop firewalld.service >/dev/null 2>&1
    systemctl disable firewalld.service >/dev/null 2>&1
    setenforce 0 >/dev/null 2>&1
    ufw disable >/dev/null 2>&1
    iptables -P INPUT ACCEPT >/dev/null 2>&1
    iptables -P FORWARD ACCEPT >/dev/null 2>&1
    iptables -P OUTPUT ACCEPT >/dev/null 2>&1
    iptables -t mangle -F >/dev/null 2>&1
    iptables -F >/dev/null 2>&1
    iptables -X >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    if [[ -n $(apachectl -v 2>/dev/null) ]]; then
        systemctl stop httpd.service >/dev/null 2>&1
        systemctl disable httpd.service >/dev/null 2>&1
        service apache2 stop >/dev/null 2>&1
        systemctl disable apache2 >/dev/null 2>&1
    fi
    sleep 1
    green "执行开放端口，关闭防火墙完毕"
}

# 获取 mieru 版本号
mieru_version() {
    mieru_zhengshi=$(curl -s https://api.github.com/repos/enfein/mieru/releases | grep '"tag_name":' | sed -n '1p' | awk -F'"' '{print $(NF-1)}')
    mieru_zhengshi_v=$(curl -s https://api.github.com/repos/enfein/mieru/releases | grep '"tag_name":' | sed -n '1p' | awk -F'"' '{print $(NF-1)}' | sed 's/^v//')
}
# 安装 mita 服务端
mieru_setup() {                          # 编写完毕
    mieru_version                        #获取 mieru 版本号
    if command -v dpkg &>/dev/null; then # 判断系统使用的是不是Debian 系linux
        red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        yellow "是否安装 mieru$mieru_zhengshi 正式版内核 (回车默认 1 )"
        yellow "输入 1 或 回车 安装 mieru "
        readp "输入 2 或其他退出程序返回上级菜单 " menu
        if [ -z "$menu" ] || [ "$menu" = "1" ]; then
            case $(uname -m) in
            aarch64) curl -L -o /root/mita.deb -# --retry 2 https://github.com/enfein/mieru/releases/download/${mieru_zhengshi}/mita_${mieru_zhengshi_v}_${cpu}.deb ;;
            x86_64) curl -L -o /root/mita.deb -# --retry 2 https://github.com/enfein/mieru/releases/download/${mieru_zhengshi}/mita_${mieru_zhengshi_v}_${cpu}.deb ;;
            *) red "目前脚本不支持$(uname -m)架构" && exit ;;
            esac
            cd /root/
            sudo dpkg -i mita.deb
            echo "deb 包安装完成"
        else
            sb
        fi
    elif command -v rpm &>/dev/null; then # 判断系统使用的是不是red 系linux
        red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        yellow "是否安装 mieru$mieru_zhengshi 正式版内核 (回车默认 1 )"
        yellow "输入 1 或 回车 安装 mieru "
        readp "输入 2 或其他退出程序返回上级菜单 " menu
        if [ -z "$menu" ] || [ "$menu" = "1" ]; then
            case $(uname -m) in
            aarch64) curl -L -o /root/mita.rpm -# --retry 2 https://github.com/enfein/mieru/releases/download/${mieru_zhengshi}/mita-${mieru_zhengshi-v}-1.${cpu}.rpm ;;
            x86_64) curl -L -o /root/mita.rpm -# --retry 2 https://github.com/enfein/mieru/releases/download/${mieru_zhengshi}/mita-${mieru_zhengshi-v}-1.${cpu}.rpm ;;
            *) red "目前脚本不支持$(uname -m)架构" && exit ;;
            esac
            cd /root/
            sudo rpm -Uvh --force mita.rpm
            echo "rpm 包安装完成"
        else
            sb
        fi
    else
        curl -fSsLO https://raw.githubusercontent.com/enfein/mieru/refs/heads/main/tools/setup.py
        chmod +x setup.py
        sudo python3 setup.py --lang=zh
    fi
}

# 删除 mieru 函数
mieru_del() {
    if command -v dpkg &>/dev/null; then # 判断系统使用的是不是Debian 系linux
        sudo dpkg -P mita
    elif command -v rpm &>/dev/null; then # 判断系统使用的是不是red 系linux
        name_v1=$(rpm -qa | grep -i mita)
        sudo rpm -e mita
    else
        echo "无法卸载"
    fi
}

# 配置mieru 服务端配置文件
mieru_config() {
    cat >/etc/mita/config.json <<EOF
{
	"portBindings": [
		{
			"portRange": "$ports_mieru",
			"protocol": "$xieyi_duo"
		},
		{
			"port": $port_mieru,
			"protocol": "$xieyi_one"
		}
	],
	"users": [
		{
			"name": "$all_name",
			"password": "$all_password",
            "allowPrivateIP": false,
            "allowLoopbackIP": true
		}
	],
	"loggingLevel": "INFO",
	"mtu": 1400,
    "dns": {
        "dualStack": "PREFER_IPv4"
    },
	"egress": {
		"proxies": [
			{
				"name": "cloudflare",
				"protocol": "SOCKS5_PROXY_PROTOCOL",
				"host": "127.0.0.1",
				"port": $socks5port,
				"socks5Authentication": {
					"user": "$all_name",
					"password": "$all_password"
				}
			}
		],
		"rules": [
			{
				"ipRanges": [
					"*"
				],
				"domainNames": [
					"*"
				],
				"action": "PROXY",
				"proxyName": "cloudflare"
			}
		]
	}
}
EOF
}

# 检查tcp端口是否被占用                 编写完了
tcp_port() {
    [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$1") ]]
}
# 检查udp端口是否被占用
udp_port() {
    [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$1") ]]
}


chooseport() { #  回车生成一个端口,并检查端口是否被占用
    if [[ -z $port ]]; then
        port=$(shuf -i 10000-65535 -n 1)
        until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
            [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
        done
    else
        until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
            [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
        done
    fi
    blue "确认的端口：$port" && sleep 2
}

# 输入用户名密码
name_password() {
    readp "\n设置全脚本的用户名：" name
    all_name=$name
    readp "设置全脚本的密码：" password
    all_password=$password
    echo "$all_name" >/etc/mita/all_name.txt
    echo "$all_password" >/etc/mita/all_password.txt
}

# 输入socks5链接的 sing-box 或 mihomo 端口
socks5port() {
    readp "\n设置socks5主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    portsocks5=$port
    echo "$socks5port" >/etc/mita/port_scoks5.txt
}
# 自定义单端口
mieruport() { #配置mieru主端口与协议   已完成
    readp "\n设置mieru主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    # 增加写入txt数据,#还要加入写入txt文本来保存数组,用来mihomo读取这个数组,来判断是否被定义过了的端口
    port_mieru=$prot
    echo "$port_mieru" > /etc/mita/port_mieru.txt
}

# 自定义多端口
mieruports() { 
    blue "设置mieru多端口 格式为[10000-10010],如果不输入直接回车,则随机产生一个"
    blue "10000-65525之间的随机端口,并在这个端口连续往后增加10个端口"
    readp "设置mieru多端口实例[10000-10010] (回车跳过为10000-65525之间的随机端口)" port
    chooseport
    # 如果 port小于65525 并且 不是一个 xxxx数-yyyy数 则执行 num1=$port  num2=$port+10   ports_mieru="$num1-$num2"
    # 判断如果是这个形式的数 xxxx数-yyyy数 则执行pors_mieru=$port 否则返回mieruports
    PORT_RANGE_REGEX="^[0-9]+-[0-9]+$"
    # 第一部分判断：port小于65525 并且 不是一个 xxxx数-yyyy数
    if [[ "$port" -lt 65525 && ! "$port" =~ $PORT_RANGE_REGEX ]]; then
        echo "port ($port) 小于 65525 并且不是 'xxxx数-yyyy数' 格式"
        num1=$port
        num2=$((port + 10)) # 使用 $((...)) 进行算术运
        mieru_array=()
        mieru_array+=$num1
        for xport in $(seq "$num1" "$num2"); do
            # 加入if语句判断端口是否被占用,占用就执行else mieruports
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                mieruports
            fi
        done
        ports_mieru="$num1-$num2"
        echo "$ports_mieru" > /etc/mita/ports_mieru.txt
    # 第二部分判断：如果是这个形式的数 xxxx数-yyyy数
    elif [[ "$port" =~ $PORT_RANGE_REGEX ]]; then
        echo "port ($port) 是 'xxxx数-yyyy数' 格式"
        ports_x="$port"
        mieru_array=()
        IFS='-' read -r start_num end_num <<<"$ports_x"
        for xport in $(seq "$start_num" "$end_num"); do
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                mieruports
            fi
        done
        ports_mieru=$ports_x
        echo "$ports_mieru" > /etc/mita/ports_mieru.txt
    # 其他情况
    else
        mieruports
    fi
}

# 单端口协议
mieru_xieyi_zhu() { 
    readp "设置mieru主端口传输协议[输入 1 为 TCP 输入 2 为 UDP](回车默认TCP)：" protocol
    if [[ -z "$protocol" || "$protocol" == "1" ]]; then
        xieyi_one="TCP"
        echo "$xieyi_one" >/etc/mita/xieyi_one.txt
    elif [[ "$protocol" == "2" ]]; then
        xieyi_one="UDP"
        echo "$xieyi_one" >/etc/mita/xieyi_one.txt
    else
        echo "输入错误,请从新输入"
        mieru_xieyi_zhu
    fi
}

# 多端口协议
mieru_xieyi_duo() { 
    readp "设置meiru主端口传输协议[输入 1 为 TCP 输入 2 为 UDP](回车默认TCP)：" protocols
    if [[ -z "$protocols" || "$protocols" == "1" ]]; then
        xieyi_duo="TCP"
        echo "$xieyi_duo" >/etc/mita/xieyi_duo.txt 
    elif [[ "$protocols" == "2" ]]; then
        xieyi_duo="UDP"
        echo "$xieyi_duo" >/etc/mita/xieyi_duo.txt 
    else
        echo "输入错误,请从新输入"
        mieru_xieyi_duo
    fi
}

# 自动生成端口或手动设置端口的入口
mieru_port_auto() {
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "三、设置各个协议端口"
    yellow "1：自动生成每个协议的随机端口 (10000-65535范围内)，回车默认"
    yellow "2：自定义每个协议端口"
    readp "请输入【1-2】：" port
    if [ -z "$port" ] || [ "$port" = "1" ]; then
        ports=()
        for i in {1..3}; do
            while true; do
                port=$(shuf -i 10000-65535 -n 1)
                if ! [[ " ${ports[@]} " =~ " $port " ]] &&
                    [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] &&
                    [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
                    ports+=($port)
                    break
                fi
            done
        done
        num1=${ports[1]}
        num2=$((num1 + 10))
        mieru_array=()
        mieru_array+=${ports[0]}
        mieru_array+=${ports[2]}
        for xport in $(seq "$num1" "$num2"); do
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                mieru_port_auto
            fi
        done
        port_mieru=${ports[0]}
        echo "$port_mieru" >/etc/mita/port_mieru.txt
        ports_mieru="$num1-$num2"
        echo "$ports_mieru" > /etc/mita/ports_mieru.txt
        socks5port=${ports[2]}
        echo "$socks5port" >/etc/mita/port_scoks5.txt
        xieyi_one="TCP"
        echo "$xieyi_one" > /etc/mita/xieyi_one.txt
        xieyi_duo="UDP"
        echo "$xieyi_duo" > /etc/mita/xieyi_duo.txt
        
    else
        mieruport && mieru_xieyi_zhu && mieruports && mieru_xieyi_duo && socks5port
    fi
    echo
    blue "各协议端口确认如下"
    blue "Mieru主端口：$port_mieru"
    blue "Mieru主端口协议：$xieyi_one"
    blue "Mieru多端口：$ports_mieru"
    blue "Mieru多端口协议：$xieyi_duo"
    blue "Mieru所使用的socks5协议端口："$pocks5port
    # 加入写入/etc/mita/mieru 各个信息
}

# 检查 mieru 是否运行
mieru_jieche() {
    if systemctl is-active --quiet mita; then
        echo "mita 服务端 (mita) 已成功安装并正在运行。"
    elif command -v mita &>/dev/null; then
        echo "mita 服务端 (mita) 命令已找到，但可能服务未启动。"
        echo "您可能需要手动启动服务: sudo systemctl start mita"
    else
        echo "mita 服务端 (mita) 未检测到安装成功。"
        echo "请检查安装日志或手动尝试安装。"
    fi
}
# 读取个配置信息
mieru_read_peizi() { 
    server_ip=$(cat /etc/mita/ipv4.txt 2>/dev/null)
    server_ipv6=$(cat /etc/mita/ipv6.txt 2>/dev/null)
    port_mieru=$(cat /etc/mita/port_mieru.txt 2>/dev/null)
    xieyi_one=$(cat /etc/mita/xieyi_one.txt 2>/dev/null)
    ports_mieru=$(cat /etc/mita/ports_mieru.txt 2>/dev/null)
    xieyi_duo=$(cat /etc/mita/xieyi_duo.txt 2>/dev/null)
    all_name=$(cat /etc/mita/all_name.txt 2>/dev/null)
    all_password=$(cat /etc/mita/all_password.txt 2>/dev/null)
    socks5port=$(cat /etc/mita/port_scoks5.txt 2>/dev/null)
}


#显示 mieru_link 配置信息
mieru_link() {
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    mieru_link2="mierus://$all_name:$all_password@$server_ip?:$port_mieru&port=$port_mieru&mtu=1400&multiplexing=8&profile=mieru-$hostname&protocol=$xieyi_one"
    echo "$mieru_link2" >/etc/mita/mieru.txt
    echo
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo -e "${yellow}$(cat /etc/mita/mieru.txt)${plain}"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "nekobox分享链接我不会,就手动选择mieru插件,手动填写吧"
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo "服务器:$server_ip"
    echo "单端口:$port_mieru"
    echo "单端口协议:$xieyi_one"
    echo "多端口:$ports_mieru"
    echo "多端口协议$xieyi_duo"
    echo "用户名:$all_name"
    echo "密码:$all_password"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    # 预计还要加入 同步到mihomo 客户端配置,与 sing-box 客户端配置
}
mieru_deploy(){
    echo "修改 Meru 协议的配置信息"
    echo "1.单端口修改"
    echo "2.单端口协议修改"
    echo "3.多端口修改"
    echo "4.多端口协议修改"
    echo "5.修改socks5端口"
    echo "6.修改用户名密码"
    echo "0.返回主菜单"
    readp "选择阿拉伯数字修改项:" menu
    if [ $menu == 1 ]; then
        oldport=$(cat /etc/mita/port_mieru.txt 2>/dev/null)
        echo "旧的端口为:$oldport"
        mieruport
        newport_mieru=$(cat /etc/mita/port_mieru.txt 2>/dev/null)
        sed -i 's/'"$oldport"'/'"$newport_mieru"'/g' /etc/mita/config.json
        mita apply config /etc/mita/config.json
        mieru_restart
    elif [ $menu == 2 ]; then
        oldxieyi=$(cat /etc/mita/xieyi_one.txt 2>/dev/null)
        echo "旧的单端口协议为:$oldxieyi"
        mieru_xieyi_zhu
        newxieyi=$(cat /etc/mita/xieyi_one.txt 2>/dev/null)
        sed -i 's/'"$oldxieyi"'/'"$newxieyi"'/g' /etc/mita/config.json
        mita apply config /etc/mita/config.json
        mieru_restart
    elif [ $menu == 3 ]; then
        oldports_=$(cat /etc/mita/ports_mieru.txt 2>/dev/null)
        echo "旧的多端口为:$oldports"
        mieruports
        newports=$(cat /etc/mita/ports_mieru.txt 2>/dev/null)
        sed -i 's/'"$oldports"'/'"$newports"'/g' /etc/mita/config.json
        mita apply config /etc/mita/config.json
        mieru_restart
    elif [ $menu == 4 ]; then
        oldxieyiduo=$(cat /etc/mita/xieyi_duo.txt 2>/dev/null)
        echo "旧的多端口协议为:$oldxieyiduo"
        mieru_xieyi_duo
        newxieyiduo=$(cat /etc/mita/xieyi_duo.txt 2>/dev/null)
        sed -i 's/'"$oldxieyiduo"'/'"$newxieyiduo"'/g' /etc/mita/config.json
        mita apply config /etc/mita/config.json
        mieru_restart
    elif [ $menu == 5 ]; then
        oldsocks5=$(cat /etc/mita/port_scoks5.txt 2>/dev/null)
        echo "旧的 socks5 端口为:$oldsocks5"
        socks5port
        newsocks5=$(cat /etc/mita/port_scoks5.txt 2>/dev/null)
        sed -i 's/'"$oldsocks5"'/'"$newsocks5"'/g' /etc/mita/config.json
        mita apply config /etc/mita/config.json
        mieru_restart
    elif [ $menu == 6 ]; then
        oldname=$(cat /etc/mita/all_name.txt 2>/dev/null)
        oldpassword=$(cat /etc/mita/all_password.txt 2>/dev/null)
        echo "旧的用户名为:$oldname 旧的密码为:$oldpassword"
        name_password
        newname=$(cat /etc/mita/all_name.txt 2>/dev/null)
        newpassword=$(cat /etc/mita/all_password.txt 2>/dev/null)
        sed -i 's/'"$oldname"'/'"$newname"'/g' /etc/mita/config.json
        sed -i 's/'"$oldpassword"'/'"$newpassword"'/g' /etc/mita/config.json
        mita apply config /etc/mita/config.json
        mieru_restart
    else
        mieru    
    fi 
}
mieru_run() {
    openyn          # 询问是否开放防火墙
    mieru_setup     # 安装mieru 服务端
    mieru_port_auto # 设置mieru端口
    vps_ip

    mieru_read_peizi                           # 读取端口等信息
    mieru_config                               # 写入 mieru 服务端配置
    mita apply config /etc/mita/config.json # 配置生效命令
    sleep 2
    mieru_jieche # 检查 mieru 是否运行
    echo
    mieru_link # 显示配置信息
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

v4v6() {
    v4=$(curl -s4m5 icanhazip.com -k)
    v6=$(curl -s6m5 icanhazip.com -k)
}
###############################################################################################################

# 检查当前服务器是否正在使用 Cloudflare Warp 服务。  wgcfv6 变量 wgcfv4 变量  两个变量里是否存储 on 或 plus
warpcheck() {
    wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

###############################################################################################################
vps_ip() {    # 获取本地vps的真实ip
    warpcheck # 检查当前服务器是否正在使用 Cloudflare Warp 服务。  wgcfv6 变量 wgcfv4 变量  两个变量里是否存储 on 或 plus
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
        v4v6
        vps_ipv4="$v4"
        vps_ipv6="$v6"
        echo "$vps_ipv4" > /etc/mita/ipv4.txt
        echo "$vps_ipv6" > /etc/mita/ipv6.txt 
    else
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
        v4v6
        vps_ipv4="$v4"
        vps_ipv6="$v6"
        echo "$vps_ipv4" > /etc/mita/ipv4.txt
        echo "$vps_ipv6" > /etc/mita/ipv6.txt 
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
    fi
}
warp_ip() {
    warpcheck # 检查当前服务器是否正在使用 Cloudflare Warp 服务。

    # 如果当前没有使用 Warp，则尝试启动它
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
        echo "当前未检测到 Cloudflare Warp 服务，尝试启动..."
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
        sleep 5 # 等待Warp服务完全启动并生效

        # 启动后再次检查Warp状态，确保变量已更新
        warpcheck

        # 只要IPv4或IPv6中有一个Warp服务开启，就认为成功
        if [[ $wgcfv4 =~ on|plus || $wgcfv6 =~ on|plus ]]; then
            echo "Cloudflare Warp 服务已成功启动。"
            v4v6 # 获取Warp后的IP
            warp_ipv4="$v4"
            warp_ipv6="$v6"
        fi
    else # 如果Warp已经在使用中
        echo "Cloudflare Warp 服务已在运行中。"
        # 确保Warp服务状态良好，虽然可能多余，但可以作为兜底
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
        sleep 2 # 稍作等待以确保服务稳定

        v4v6 # 获取Warp后的IP
        warp_ipv4="$v4"
        warp_ipv6="$v6"
    fi
}
###############################################################################################################

# 重启mieru
mieru_restart(){
    mita stop
    mita start
}
# 关闭mieru
mieru_stop(){
    mita stop
}
# 升级mieru脚本
mieru_up(){
rm -rf /usr/bin/mieru
curl -L -o /usr/bin/mieru -# --retry 2 --insecure https://raw.githubusercontent.com/yggmsh/yggmsh123/main/mita.sh
chmod +x /usr/bin/mieru
curl -sL https://raw.githubusercontent.com/yggmsh/yggmsh123/main/mita-v | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/mita/v
green "mieru 安装脚本升级成功" && sleep 5 && mieru    
}
#这是脚本的主代码,用来运行脚本菜的的界面
clear
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "mieru 一键脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "脚本快捷方式：mieru"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 一键安装 mieru(完)"
green " 2. 一键删除 mieru(完)"
green " 3. 配置参数(完)"
green " 4. 重启mieru(完)"
green " 5. 关闭mieru(完)"
green " 6. 查看运行状态(完)"
green " 7. 显示配置信息(完)"
green " 8. 更新脚本(完)"
green " 9. 更新mieru(完)"
green " 0. 退出脚本"
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
vps_ip # 获取本地vps的真实ip
echo -e "本地IPV4地址：${blue}${vps_ipv4}$plain    本地IPV6地址：${blue}${vps_ipv6}$plain"
warp_ip # 获取warp的ip
echo -e "WARP IPV4地址：${blue}${warp_ipv4}$plain    WARP IPV6地址：${blue}${warp_ipv6}$plain"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "请输入数字【0-9】:" Input
case "$Input" in
1) mieru_run ;;
2) mieru_del ;;
3) mieru_deploy ;;
4) mieru_restart ;;
5) mieru_stop ;;
6) mieru_jieche ;;
7) mieru_link ;;
8) mieru_up ;;
9) mieru_setup ;;
*) exit ;;
esac
