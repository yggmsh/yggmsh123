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

###############################################################################################################

# 用户等待输入
readp() { read -p "$(yellow "$1")" $2; }

###############################################################################################################

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

###############################################################################################################

# 设置各种变量     sbfiles 里面存储了两个文件位置,是配置文件    sbnh 存储了是mihomo 的版本信息
#                 vsid 存储了linux版本的前面     op 存储了完整的版本号
export sbfiles="/etc/ys/config.yaml"
export sbnh=$(/etc/ys/ys -v 2>/dev/null | awk '/Mihomo Meta/{print $1, $2, $3}')
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)

###############################################################################################################

# 如果系统是arch,就显示信息不支持,并退出脚本
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
    red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

###############################################################################################################

# 显示当前正在运行的 Linux 内核版本
version=$(uname -r | cut -d "-" -f1)

###############################################################################################################

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

###############################################################################################################

# 检测安装的bbr拥堵算法   bbr 存储了是什么的bbr版本
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
    bbr=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
    bbr="Openvz版bbr-plus"
else
    bbr="Openvz/Lxc"
fi

###############################################################################################################

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

# 获取当前服务器的公网 IPv4 和 IPv6 地址  v4 变量记录v4 ip  v6变量记录v6 ip
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
    else
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
        v4v6
        vps_ipv4="$v4"
        vps_ipv6="$v6"
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

# 核心逻辑部分，根据网络环境（特别是 IPv4 或纯 IPv6）进行配置，并处理 Warp 的状态。
# 纯v6机器 endip 变量存储ip ipv 变量存储prefer_ipv6 或prefer_ipv4
v6() {
    v4orv6() { # 判断当前 VPS 是纯 IPv6 还是同时支持 IPv4 和 IPv6，并设置相应的 DNS 和目标 IP 地址。
        if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
            echo
            red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            yellow "检测到 纯IPV6 VPS，添加DNS64"
            echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" >/etc/resolv.conf
            endip=2606:4700:d0::a29f:c101
            ipv=prefer_ipv6
        else
            endip=162.159.192.1
            ipv=prefer_ipv4
        fi
    }
    warpcheck # 检查当前服务器是否正在使用 Cloudflare Warp 服务。  wgcfv6 变量 wgcfv4 变量  两个变量里是否存储 on 或 plus
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
        v4orv6 # 判断当前 VPS 是纯 IPv6 还是同时支持 IPv4 和 IPv6，并设置相应的 DNS 和目标 IP 地址。
    else
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
        v4orv6
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
    fi
}

###############################################################################################################

# 用于关闭防火墙的操作方法
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

###############################################################################################################
# 重启mihomo函数               修改完了
mihomo_chongqi() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service ys restart
    else
        systemctl enable ys
        systemctl start ys
        systemctl restart ys
    fi
}
# 重启mihomo函数               修改完了     ^^^^^
###############################################################################################################

# 询问是否开放防火墙
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

###############################################################################################################
# 获取版本号函数,在进入菜单时候,显示    修改完了
lapre() {
    # 获取 mihomo 测试版 版本号
    precore=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases | grep '"name":' | sed -n '5p' | sed 's/\.gz",//' | awk -F'-' '{print $NF}')
    # 获取 mihomo 正式版 版本号
    latcore=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases | grep '"tag_name":' | sed -n '2p' | awk -F'"' '{print $(NF-1)}')
    # 获取当前安装的版本号
    inscore=$(/etc/ys/ys -v 2>/dev/null | awk '/Mihomo Meta/{print $1, $2, $3}')
}
###############################################################################################################
# 获取 mihomo 测试版版本号
v1test=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases | grep '"name":' | sed -n '5p' | sed 's/\.gz",//' | awk -F'-' '{print $NF}')
# 获取 mihomo 正式版版本号
v2version=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases | grep '"tag_name":' | sed -n '2p' | awk -F'"' '{print $(NF-1)}')
#
# 获取 mihomo 版本号的网站
# https://api.github.com/repos/MetaCubeX/mihomo/releases/

# https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-compatible-alpha-${v1test}.gz
# https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-alpha-${v1test}.gz
# https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-alpha-${v1test}.gz
# https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-alpha-${v1test}.gz

# # 正式版本地址
# https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-compatible-${v2version}.gz
# https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-${v2version}.gz
# https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-${v2version}.gz
# https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-${v2version}.gz
###############################################################################################################

# 开始选择 mihomo 安装 正式版 或 测试版
mihomo_setup() { # 配置完成
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    yellow "1：使用 mihomo 正式版内核 (回车默认)"
    yellow "2：使用 mihomo 测试版内核"
    readp "请选择【1-2】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ]; then
        case $(uname -m) in
        armv7l) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-${v2version}.gz ;;
        aarch64) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-${v2version}.gz ;;
        x86_64) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-compatible-${v2version}.gz ;;
        i386 | i686) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/${v2version}/mihomo-linux-${cpu}-${v2version}.gz ;;
        *) red "目前脚本不支持$(uname -m)架构" && exit ;;
        esac
    else
        case $(uname -m) in
        armv7l) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-alpha-${v1test}.gz ;;
        aarch64) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-alpha-${v1test}.gz ;;
        x86_64) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-compatible-alpha-${v1test}.gz ;;
        i386 | i686) curl -L -o /etc/ys/ys.gz -# --retry 2 https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-${cpu}-alpha-${v1test}.gz ;;
        *) red "目前脚本不支持$(uname -m)架构" && exit ;;
        esac
    fi
    if [[ -f '/etc/ys/ys.gz' ]]; then
        gzip -d /etc/ys/ys.gz
        if [[ -f '/etc/ys/ys' ]]; then
            chown root:root /etc/ys/ys
            chmod +x /etc/ys/ys
            blue "成功安装 mihomo 内核版本：$(/etc/ys/ys -v 2>/dev/null | awk '/Mihomo Meta/{print $1, $2, $3}')"
        else
            red "下载 mihomo 内核不完整，安装失败，请再运行安装一次" && exit
        fi
    else
        red "下载 mihomo 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit
    fi
}

###############################################################################################################
#
#
mihomo_cert_private() {
    ymzs() {
        ym_vl_re=www.yahoo.com
        echo "$ym_vl_re" >/etc/ys/vless/server-name.txt
        echo
        blue "Vless-reality的SNI域名默认为 www.yahoo.com"
        ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
        certificatec_vmess_ws='/root/ygkkkca/cert.crt'
        certificatep_vmess_ws='/root/ygkkkca/private.key'
        certificatec_hy2='/root/ygkkkca/cert.crt'
        certificatep_hy2='/root/ygkkkca/private.key'
        certificatec_tuic='/root/ygkkkca/cert.crt'
        certificatep_tuic='/root/ygkkkca/private.key'
        certificatec_anytls='/root/ygkkkca/private.key'
        certificatep_anytls='/root/ygkkkca/private.key'
    }

    zqzs() {
        ym_vl_re=www.yahoo.com
        echo "$ym_vl_re" >/etc/ys/vless/server-name.txt
        echo
        blue "Vless-reality的SNI域名默认为 www.yahoo.com"
        blue "Vmess-ws将关闭TLS，Hysteria-2、Tuic-v5将使用bing自签证书，并关闭SNI证书验证"
        ym_vm_ws=www.bing.com
        certificatec_vmess_ws='/etc/ys/me/cert.pem'
        certificatep_vmess_ws='/etc/ys/me/private.key'
        certificatec_hy2='/etc/ys/me/cert.pem'
        certificatep_hy2='/etc/ys/me/private.key'
        certificatec_tuic='/etc/ys/me/cert.pem'
        certificatep_tuic='/etc/ys/me/private.key'
        certificatec_anytls='/etc/ys/me/cert.pem'
        certificatep_anytls='/etc/ys/me/private.key'
    }

    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "二、生成并设置相关证书"
    echo
    blue "自动生成bing自签证书中……" && sleep 2
    openssl ecparam -genkey -name prime256v1 -out /etc/ys/me/private.key
    openssl req -new -x509 -days 36500 -key /etc/ys/me/private.key -out /etc/ys/me/cert.pem -subj "/CN=www.bing.com"
    echo
    if [[ -f /etc/ys/me/cert.pem ]]; then
        blue "生成bing自签证书成功"
    else
        red "生成bing自签证书失败" && exit
    fi
    echo
    echo "$hostname" >/etc/ys/info/hostname.log
    if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
        yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名证书：$(cat /root/ygkkkca/ca.log) "
        green "是否使用 $(cat /root/ygkkkca/ca.log) 域名证书？"
        yellow "1：否！使用自签的证书 (回车默认)"
        yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名证书"
        readp "请选择【1-2】：" menu
        if [ -z "$menu" ] || [ "$menu" = "1" ]; then
            zqzs # 自签证书
        else
            ymzs # acme证书
        fi
    else
        green "如果你有解析完成的域名，是否申请一个Acme域名证书？"
        yellow "1：否！继续使用自签的证书 (回车默认)"
        yellow "2：是！使用Acme-yg脚本申请Acme证书 (支持常规80端口模式与Dns API模式)"
        readp "请选择【1-2】：" menu
        if [ -z "$menu" ] || [ "$menu" = "1" ]; then
            zqzs # 自签证书
        else
            bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
            if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key && ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
                red "Acme证书申请失败，继续使用自签证书"
                zqzs # 自签证书
            else
                ymzs # acme证书
            fi
        fi
    fi
}

###############################################################################################################

# mihomo 自动配置端口,与手动配置端口的主函数
mihomo_port_auto() { # 配置完成
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "三、设置各个协议端口"
    yellow "1：自动生成每个协议的随机端口 (10000-65535范围内)，回车默认"
    yellow "2：自定义每个协议端口"
    readp "请输入【1-2】：" port
    if [ -z "$port" ] || [ "$port" = "1" ]; then
        ports=()
        for i in {1..6}; do
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
        port_vm_ws=${ports[0]}
        port_vl_re=${ports[1]}
        port_hy2=${ports[2]}
        port_tu=${ports[3]}
        port_any=${prots[4]}
        socks5port=${ports[5]}
        if [[ $tlsyn == "true" ]]; then
            numbers=("2053" "2083" "2087" "2096" "8443")
        else
            numbers=("8080" "8880" "2052" "2082" "2086" "2095")
        fi
        port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
        until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]; do
            if [[ $tlsyn == "true" ]]; then
                numbers=("2053" "2083" "2087" "2096" "8443")
            else
                numbers=("8080" "8880" "2052" "2082" "2086" "2095")
            fi
            port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
        done
        echo
        blue "根据Vmess-ws协议是否启用TLS，随机指定支持CDN优选IP的标准端口：$port_vm_ws"
        # 把 mihomo 生成的端口,写入mihomo_array.txt
        mihomo_array=()
        for i in {1..6}; do
            mihomo_array+=("${ports[$i]}")
        done
        if [ -f "/etc/mita/config.json" ] && [ -f "/etc/ys/mieru" ] && [ -f "/root/mieru_array.txt" ]; then
            READ_ARRAY_FILE="/root/mieru_array.txt"
            read_array_mihomo # 读取 mieru 的端口信息
            for item1 in "${mieru_array[@]}"; do
                # 遍历第二个数组的每个元素
                for item2 in "${mihomo_array[@]}"; do
                    # 比较元素是否相同
                    if [[ "$item1" == "$item2" ]]; then
                        mihomo_port_auto # 返回本函数
                    fi
                done
            done
        fi
        WRITE_ARRAY_FILT="/root/mihomo_array.txt"
        write_array_mihomo # 写入mihomo函数
    else
        vlport && vmport && hy2port && hy2ports && tu5port && tu5ports && anytlsport && socks5port
        mihomo_array=("$port_vl_re" "$port_vm_ws" "$port_hy2" "$port_tu" "$port_any" "$port_socks5" "$hy2_array")
        if [ -f "/etc/mita/config.json" ] && [ -f "/etc/ys/mieru/mieru.txt" ] && [ -f "/root/mieru_array.txt" ]; then
            READ_ARRAY_FILE="/root/mieru_array.txt"
            read_array_mihomo # 读取 mieru 的端口信息
            for item1 in "${mieru_array[@]}"; do
                # 遍历第二个数组的每个元素
                for item2 in "${mihomo_array[@]}"; do
                    # 比较元素是否相同
                    if [[ "$item1" == "$item2" ]]; then
                        mihomo_port_auto # 返回本函数
                    fi
                done
            done
        fi
        WRITE_ARRAY_FILT="/root/mihomo_array.txt"
        write_array_mihomo # 写入mihomo函数
    fi
    echo
    blue "各协议端口确认如下"
    blue "Vless-reality端口：$port_vl_re"
    blue "Hysteria-2端口：$port_hy2"
    blue "Hysteria-2多端口：$hy2_ports"
    blue "Tuic-v5端口：$port_tu"
    blue "Anytls端口：$port_any"
    blue "socks5端口：$socks5port"

    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "四、自动生成各个协议统一的uuid (密码)"
    uuid=$(uuidgen)
    blue "已确认uuid (密码)：${uuid}"
    blue "已确认Vmess的path路径：${uuid}-vm"
    echo "$uuid" >/etc/ys/vless/uuid.txt
    echo "$uuid" >/etc/ys/vmess/uuid.txt
    echo "${uuid}-vm" >/etc/ys/vmess/path.txt
}

###############################################################################################################

# 各个端口配置函数
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

# 各个协议的手动设置端口函数
vlport() {
    readp "\n设置Vless-reality端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_vl_re=$port
    echo "$port_vl_re" >/etc/ys/vless/port_vl_re.txt
}
vmport() {
    readp "\n设置Vmess-ws端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_vm_ws=$port
    echo "$port_vm_ws" >/etc/ys/vmess/port_vm_ws.txt
}
hy2port() {
    readp "\n设置Hysteria2主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_hy2=$port
    echo "$port_hy2" >/etc/ys/hysteria2/port_hy2.txt
}
hy2ports() {
    blue "设置Hysteria2多端口 格式为[10000-10010],如果不输入直接回车,则随机产生一个"
    blue "10000-65525之间的随机端口,并在这个端口连续往后增加10个端口"
    readp "设置Hysteria2多端口实例[10000-10010] (回车跳过为10000-65525之间的随机端口)" port
    chooseport
    # 如果 port小于65525 并且 不是一个 xxxx数-yyyy数 则执行 num1=$port  num2=$port+10   ports_mieru="$num1-$num2"
    # 判断如果是这个形式的数 xxxx数-yyyy数 则执行pors_mieru=$port 否则返回mieruports
    PORT_RANGE_REGEX="^[0-9]+-[0-9]+$"
    # 第一部分判断：port小于65525 并且 不是一个 xxxx数-yyyy数
    if [[ "$port" -lt 65525 && ! "$port" =~ $PORT_RANGE_REGEX ]]; then
        echo "port ($port) 小于 65525 并且不是 'xxxx数-yyyy数' 格式"
        num1=$port
        num2=$((port + 10)) # 使用 $((...)) 进行算术运
        hy2_array=()
        #hy2_array+=$num1
        for xport in $(seq "$num1" "$num2"); do
            # 加入if语句判断端口是否被占用,占用就执行else mieruports
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                hy2ports
            fi
            hy2_array+=($xport)
        done
        hy2_ports="$num1-$num2"
        hy2_port=$(cat /etc/ys/hysteria2/port_hy2.txt 2>/dev/null)
        xxxx=$hy2_ports
        ports_hy2="${xxxx//-/:}"
        $(iptables -t nat -A PREROUTING -p udp --dport $ports_hy2 -j DNAT --to-destination :$hy2_port)
        $(ip6tables -t nat -A PREROUTING -p udp --dport $ports_hy2 -j DNAT --to-destination :$hy2_port)
        $(netfilter-persistent save)
        echo "$hy2_ports" >/etc/ys/hysteria2/hy2_ports.txt
    # 第二部分判断：如果是这个形式的数 xxxx数-yyyy数
    elif [[ "$port" =~ $PORT_RANGE_REGEX ]]; then
        echo "port ($port) 是 'xxxx数-yyyy数' 格式"
        ports_x="$port"
        hy2_array=()
        IFS='-' read -r start_num end_num <<<"$ports_x"
        for xport in $(seq "$start_num" "$end_num"); do
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                hy2ports
            fi
            hy2_array+=($xport)
            #还要加入写入txt文本来保存数组,用来mihomo读取这个数组,来判断是否被定义过了的端
        done
        hy2_ports=$ports_x
        hy2_port=$(cat /etc/ys/hysteria2/port_hy2.txt 2>/dev/null)
        xxxx=$hy2_ports
        ports_hy2="${xxxx//-/:}"
        $(iptables -t nat -A PREROUTING -p udp --dport $ports_hy2 -j DNAT --to-destination :$hy2_port)
        $(ip6tables -t nat -A PREROUTING -p udp --dport $ports_hy2 -j DNAT --to-destination :$hy2_port)
        $(netfilter-persistent save)
        echo "$hy2_ports" >/etc/ys/hysteria2/hy2_ports.txt
        # 其他情况
    else
        hy2ports
    fi
}
tu5port() {
    readp "\n设置Tuic5主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_tu=$port
    echo "$port_tu" >/etc/ys/tuic5/port_tu.txt
}
tu5ports() {
    blue "设置Tuic5多端口 格式为[10000-10010],如果不输入直接回车,则随机产生一个~"
    blue "10000-65525之间的随机端口,并在这个端口连续往后增加10个端口"
    readp "设置Tuic5多端口实例[10000-10010] (回车跳过为10000-65525之间的随机端口)" port
    chooseport
    PORT_RANGE_REGEX="^[0-9]+-[0-9]+$"
    # 第一部分判断：port小于65525 并且 不是一个 xxxx数-yyyy数
    if [[ "$port" -lt 65525 && ! "$port" =~ $PORT_RANGE_REGEX ]]; then
        echo "port ($port) 小于 65525 并且不是 'xxxx数-yyyy数' 格式"
        num1=$port
        num2=$((port + 10)) # 使用 $((...)) 进行算术运
        tuic5_array=()
        #hy2_array+=$num1
        for xport in $(seq "$num1" "$num2"); do
            # 加入if语句判断端口是否被占用,占用就执行else mieruports
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                tu5ports
            fi
            tuic5_array+=($xport)
        done
        tu_ports="$num1-$num2"
        echo "$tu_ports" >/etc/ys/tuic5/tu_ports.txt
        port_tu=$(cat /etc/ys/tuic5/port_tu.txt 2>/dev/null)
        tutu=$tu_ports
        ports_tu="${tutu//-/:}"
        $(iptables -t nat -A PREROUTING -p udp --dport $ports_tu -j DNAT --to-destination :$port_tu)
        $(ip6tables -t nat -A PREROUTING -p udp --dport $ports_tu -j DNAT --to-destination :$port_tu)
        $(netfilter-persistent save)
    # 第二部分判断：如果是这个形式的数 xxxx数-yyyy数
    elif [[ "$port" =~ $PORT_RANGE_REGEX ]]; then
        echo "port ($port) 是 'xxxx数-yyyy数' 格式"
        ports_x="$port"
        tuic5_array=()
        IFS='-' read -r start_num end_num <<<"$ports_x"
        for xport in $(seq "$start_num" "$end_num"); do
            if ! tcp_port "$xport" || ! udp_port "$xport"; then
                tu5ports
            fi
            tuic5_array+=($xport)
            #还要加入写入txt文本来保存数组,用来mihomo读取这个数组,来判断是否被定义过了的端
        done
        tu_ports=$ports_x
        echo "$tu_ports" >/etc/ys/tuic5/tu_ports.txt
        port_tu=$(cat /etc/ys/tuic5/port_tu.txt 2>/dev/null)
        tutu=$tu_ports
        ports_tu="${tutu//-/:}"
        $(iptables -t nat -A PREROUTING -p udp --dport $ports_tu -j DNAT --to-destination :$port_tu)
        $(ip6tables -t nat -A PREROUTING -p udp --dport $ports_tu -j DNAT --to-destination :$port_tu)
        $(netfilter-persistent save)
    # 其他情况
    else
        tu5ports
    fi
}

anytlsport() {
    readp "\n设置Anytls主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    port_any=$port
    echo "$port_any" >/etc/ys/anytls/port_any.txt
}
socks5port() {
    readp "\n设置socks5主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    portsocks5=$port
    echo "$socks5port" >/etc/ys/socks5/port_scoks5.txt
    echo "12345" > /etc/ys/socks5_in.txt
}

name_password() {
    readp "\n设置全脚本的用户名：" name
    all_name=$name
    readp "设置全脚本的密码：" password
    all_password=$password
    echo "$all_name" >/etc/ys/info/all_name.txt
    echo "$all_password" >/etc/ys/info/all_password.txt
}

read_array_mihomo() { # 读取变量 READ_ARRAY_FILE="/root/mieru_array.txt"
    # 检查文件是否存在
    if [[ ! -f "$READ_ARRAY_FILE" ]]; then
        echo "错误：文件 $READ_ARRAY_FILE 不存在。退出 read_array() 函数。"
        return 1 # 返回非零状态码表示失败
    fi

    # 使用 mapfile (或 readarray) 将文件内容读取到 mihomo_array 数组中
    # -t 选项去除每行的换行符
    mapfile -t mieru_array <"$READ_ARRAY_FILE"

    echo "已从 $READ_ARRAY_FILE 读取数据到 mieru_array 数组。"
    return 0 # 返回零状态码表示成功
}

write_array_mihomo() {                  # 写入变量 WRITE_ARRAY_FILT="/root/mihomo_array.txt"
    local arr_name="${1:-mihomo_array}" # 默认为 mihomo_array
    local arr_ref                       # 声明一个nameref变量

    # 使用nameref来间接引用数组 (Bash 4.3+ 支持)
    if declare -n arr_ref="$arr_name" 2>/dev/null; then
        # 确保文件可写。如果文件不存在，追加写入会创建文件。
        if [[ -f "$WRITE_ARRAY_FILT" && ! -w "$WRITE_ARRAY_FILT" ]]; then
            chmod 777 $WRITE_ARRAY_FILT
        fi

        # 遍历数组并追加写入文件
        for item in "${arr_ref[@]}"; do
            echo "$item" >>"$WRITE_ARRAY_FILT" # 使用 >> 进行追加写入
        done

        echo "已将 ${arr_name} 数组内容追加写入 $WRITE_ARRAY_FILT。"
        return 0
    else
        echo "错误：数组 '${arr_name}' 不存在或不是有效的数组名。"
        return 1
    fi
}

# 获取warp 密钥,ipv6 等值
warpwg() {
    warpcode() {
        reg() {
            keypair=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout)
            private_key=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]' | xxd -r -p | base64)
            public_key=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]' | xxd -r -p | base64)
            curl -X POST 'https://api.cloudflareclient.com/v0a2158/reg' -sL --tlsv1.3 \
                -H 'CF-Client-Version: a-7.21-0721' -H 'Content-Type: application/json' \
                -d \
                '{
"key":"'${public_key}'",
"tos":"'$(date +"%Y-%m-%dT%H:%M:%S.000Z")'"
}' |
                python3 -m json.tool | sed "/\"account_type\"/i\         \"private_key\": \"$private_key\","
        }
        reserved() {
            reserved_str=$(echo "$warp_info" | grep 'client_id' | cut -d\" -f4)
            reserved_hex=$(echo "$reserved_str" | base64 -d | xxd -p)
            reserved_dec=$(echo "$reserved_hex" | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "["$1", "$2", "$3"]"}')
            echo -e "{\n    \"reserved_dec\": $reserved_dec,"
            echo -e "    \"reserved_hex\": \"0x$reserved_hex\","
            echo -e "    \"reserved_str\": \"$reserved_str\"\n}"
        }
        result() {
            echo "$warp_reserved" | grep -P "reserved" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/:\[/: \[/g' | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\)/\1, \2, \3/' | sed 's/^"/    "/g' | sed 's/"$/",/g'
            echo "$warp_info" | grep -P "(private_key|public_key|\"v4\": \"172.16.0.2\"|\"v6\": \"2)" | sed "s/ //g" | sed 's/:"/: "/g' | sed 's/^"/    "/g'
            echo "}"
        }
        warp_info=$(reg)
        warp_reserved=$(reserved)
        result
    }
    output=$(warpcode)
    if ! echo "$output" 2>/dev/null | grep -w "private_key" >/dev/null; then
        v6=2606:4700:110:860e:738f:b37:f15:d38d
        pvk=g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4=
        res=[33,217,129]
    else
        pvk=$(echo "$output" | sed -n 4p | awk '{print $2}' | tr -d ' "' | sed 's/.$//')
        v6=$(echo "$output" | sed -n 7p | awk '{print $2}' | tr -d ' "')
        res=$(echo "$output" | sed -n 1p | awk -F":" '{print $NF}' | tr -d ' ' | sed 's/.$//')
    fi
    blue "Private_key私钥：$pvk"
    blue "IPV6地址：$v6"
    blue "reserved值：$res"
}

###############################################################################################################

# 各个协议配置文件
ys_vmess_ws_tls() {
    cat <<YAML_BLOCK
- name: vmess-sb-inbound
  type: vmess
  port: ${port_vm_ws} # 支持使用ports格式，例如200,302 or 200,204,401-429,501-503
  listen: 0.0.0.0
  # rule: sub-rule-name1 # 默认使用 rules，如果未找到 sub-rule 则直接使用 rules
  # proxy: proxy # 如果不为空则直接将该入站流量交由指定 proxy 处理 (当 proxy 不为空时，这里的 proxy 名称必须合法，否则会出错)
  users:
    - username: $all_name
      uuid: "${uuid}"
      alterId: 0
  ws-path: "/${uuid}-vm" # 如果不为空则开启 websocket 传输层
  # grpc-service-name: "GunService" # 如果不为空则开启 grpc 传输层
  # 下面两项如果填写则开启 tls（需要同时填写）
  certificate: $certificatec_vmess_ws
  private-key: $certificatep_vmess_ws
  # 如果填写reality-config则开启reality（注意不可与certificate和private-key同时填写）
  # reality-config:
  #   dest: test.com:443
  #   private-key: jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0 # 可由 mihomo generate reality-keypair 命令生成
  #   short-id:
  #     - 0123456789abcdef
  #   server-names:
  #     - test.com
YAML_BLOCK
}

###############################################################################################################

# 创建 mihomo 服务端配置文件
mihomo_config() {
    cat >/etc/ys/config.yaml <<EOF
mixed-port: $socks5port    # 混合代理端口 (同时支持 HTTP 和 SOCKS5)
authentication:   # 认证设置，仅作用于 HTTP/SOCKS 代理端口
  - "$all_name:$all_password"
allow-lan: false    # 如果你只允许本机访问，这里通常设置为 false，虽然 bind-address 已经做了限制
bind-address: "127.0.0.1" # **修改为 127.0.0.1**
# ipv6: true
listeners:

- name: hy2-sb
  type: hysteria2
  port: $port_hy2
  listen: 0.0.0.0
  users:
    $all_name: $all_password
  # up: 1000
  # down: 1000
  ignore-client-bandwidth: true
  masquerade: ""
  alpn:
  - h3
  certificate: $certificatec_hy2
  private-key: $certificatep_hy2

- name: tuic5-sb
  type: tuic
  port: $port_tu
  listen: 0.0.0.0
  users:
    $all_name: $all_password
  certificate: $certificatec_tuic
  private-key: $certificatep_tuic
  congestion-controller: bbr
  max-idle-time: 15000
  authentication-timeout: 1000
  alpn:
    - h3
  max-udp-relay-packet-size: 1500

- name: vless-sb
  type: vless
  port: ${port_vl_re}
  listen: 0.0.0.0
  users:
    - username: $all_name
      uuid: "${uuid}"
      flow: xtls-rprx-vision
  reality-config:
    dest: $ym_vl_re:443
    private-key: $private_key
    short-id:
      - $short_id
    server-names:
      - $ym_vl_re

- name: anytls-sb
  type: anytls
  port: $port_any
  listen: 0.0.0.0
  users:
    $all_name: $all_password
  certificate: $certificatec_anytls
  private-key: $certificatep_anytls
  padding-scheme: |
   stop=8
   0=30-30
   1=100-400
   2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000
   3=9-9,500-1000
   4=500-1000
   5=500-1000
   6=500-1000
   7=500-1000

proxies:
- name: "MyWireGuard"
  type: wireguard
  server: $endip
  port: 2408
  private-key: "$pvk"
  public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
  ip: "172.16.0.2/32"
  ipv6: "$v6/128"
  dns:
    - 8.8.8.8
    - 8.8.4.4
    - 2001:4860:4860::8888
    - 2001:4860:4860::8844
  udp: true

# - name: "socks-out"
#   type: socks5
#   server: 127.0.0.1
#   port: 12345
#   # username: username
#   # password: password
#   # tls: true
#   # fingerprint: xxxx
#   # skip-cert-verify: true
#   udp: true
#   ip-version: ipv6

proxy-groups:
- name: "WireGuard_Group"
  type: select
  proxies:
    - MyWireGuard
      
rules:
  - DOMAIN-SUFFIX,openai.com,WireGuard_Group
  - DOMAIN-SUFFIX,chat.openai.com,WireGuard_Group

EOF
}

###############################################################################################################

# 写入开机启动配置文件
mihomo_kaiji() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo '#!/sbin/openrc-run
description="ys service"
command="/etc/ys/ys"
command_args="run -c /etc/ys/config.yaml"
command_background=true
pidfile="/var/run/ys.pid"' >/etc/init.d/ys
        chmod +x /etc/init.d/ys
        rc-update add ys default
        rc-service ys start
    else
        cat >/etc/systemd/system/ys.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/ys/ys -d /etc/ys
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ys >/dev/null 2>&1
        systemctl start ys
        systemctl restart ys
    fi
}

###############################################################################################################
# 检查 mihomo 配置文件是否存在的 函数      修改完了
sbactive() {
    if [[ ! -f /etc/ys/config.yaml ]]; then
        red "未正常启动mihomo，请卸载重装或者选择10查看运行日志反馈" && exit
    fi
}
# 检查 mihomo 配置文件是否存在的 函数      修改完了   ^^^^^^^^^
###############################################################################################################

# 生成快捷方式
mihomo_gengxin() {
    rm -rf /usr/bin/mihomo
    curl -L -o /usr/bin/mihomo -# --retry 2 --insecure https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys.sh
    chmod +x /usr/bin/mihomo
}

###############################################################################################################

# 凌晨1点重启 mihomo 定时任务
mihomo_dingshi() {
    mihomo_shanchu_dingshi
    crontab -l >/tmp/crontab.tmp
    echo "0 1 * * * systemctl restart ys;rc-service sy restart" >>/tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp
}
# 删除 mihomo 定时任务
mihomo_shanchu_dingshi() {
    crontab -l >/tmp/crontab.tmp
    sed -i '/ys/d' /tmp/crontab.tmp
    sed -i '/sbargopid/d' /tmp/crontab.tmp
    sed -i '/sbargoympid/d' /tmp/crontab.tmp
    sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp
}

###############################################################################################################

# 检测当前 VPS 的 IP 地址类型（IPv4、IPv6 或双栈），并根据检测结果以及用户的选择，设置用于后续配置的 DNS 服务器和服务器 IP 地址。 它还检查 Mihomo 的运行状态。
ipuuid() {
    if [[ x"${release}" == x"alpine" ]]; then
        status_cmd="rc-service ys status"
        status_pattern="started"
    else
        status_cmd="systemctl status ys"
        status_pattern="active"
    fi
    if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/ys/config.yaml' ]]; then
        v4v6
        if [[ -n $v4 && -n $v6 ]]; then
            green "双栈VPS需要选择IP配置输出，一般情况下nat vps建议选择IPV6"
            yellow "1：使用IPV4配置输出 (回车默认) "
            yellow "2：使用IPV6配置输出"
            readp "请选择【1-2】：" menu
            if [ -z "$menu" ] || [ "$menu" = "1" ]; then
                sbdnsip='tls://8.8.8.8/dns-query'
                echo "$sbdnsip" >/etc/ys/info/sbdnsip.log
                server_ip="$v4"
                echo "$server_ip" >/etc/ys/info/server_ip.log
                server_ipcl="$v4"
                echo "$server_ipcl" >/etc/ys/info/server_ipcl.log
            else
                sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
                echo "$sbdnsip" >/etc/ys/info/sbdnsip.log
                server_ip="[$v6]"
                echo "$server_ip" >/etc/ys/info/server_ip.log
                server_ipcl="$v6"
                echo "$server_ipcl" >/etc/ys/info/server_ipcl.log
            fi
        else
            yellow "VPS并不是双栈VPS，不支持IP配置输出的切换"
            serip=$(curl -s4m5 icanhazip.com -k || curl -s6m5 icanhazip.com -k)
            if [[ "$serip" =~ : ]]; then
                sbdnsip='tls://[2001:4860:4860::8888]/dns-query'
                echo "$sbdnsip" >/etc/ys/info/sbdnsip.log
                server_ip="[$serip]"
                echo "$server_ip" >/etc/ys/info/server_ip.log
                server_ipcl="$serip"
                echo "$server_ipcl" >/etc/ys/info/server_ipcl.log
            else
                sbdnsip='tls://8.8.8.8/dns-query'
                echo "$sbdnsip" >/etc/ys/info/sbdnsip.log
                server_ip="$serip"
                echo "$server_ip" >/etc/ys/info/server_ip.log
                server_ipcl="$serip"
                echo "$server_ipcl" >/etc/ys/info/server_ipcl.log
            fi
        fi
    else
        red "mihomo服务未运行" && exit
    fi
}
# 管理并确保 Cloudflare WARP 服务的运行，并在必要时刷新或重新配置其网络参数。 它会根据 WARP 的当前状态来决定执行初始化或重启流程
wgcfgo() {
    warpcheck
    if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
        ipuuid
    else
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
        ipuuid
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        systemctl restart warp-go >/dev/null 2>&1
        systemctl enable warp-go >/dev/null 2>&1
        systemctl start warp-go >/dev/null 2>&1
    fi
}
###############################################################################################################
# 检查 arogid 信息  信息是需要安装argo  修改完了
argopid() {
    ym=$(cat /etc/ys/info/sbargoympid.log 2>/dev/null)
    ls=$(cat /etc/ys/info/sbargopid.log 2>/dev/null)
}
# 检查 arogid 信息  信息是需要安装argo  修改完了
###############################################################################################################

# vless reality vision 客户端配置信息
resvless() {
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
    echo "$vl_link" >/etc/ys/vless/vl_reality.txt
    red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$vl_link${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/vless/vl_reality.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

# vmess ws 或 vmess ws tls  或 arog 节点
resvmess() {
    if [[ "$tls" = "false" ]]; then
        argopid
        if [[ -n $(ps -e | grep -w $ls 2>/dev/null) ]]; then
            echo
            white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            red "🚀【 vmess-ws(tls)+Argo 】临时节点信息如下(可选择3-8-3，自定义CDN优选地址)：" && sleep 2
            echo
            echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
            echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0)${plain}"
            echo
            echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
            echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","type":"none","v":"2"}' | base64 -w 0) >/etc/ys/info/vm_ws_argols.txt
            qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/vmess/vm_ws_argols.txt)"
        fi
        if [[ -n $(ps -e | grep -w $ym 2>/dev/null) ]]; then
            argogd=$(cat /etc/ys/info/sbargoym.log 2>/dev/null)
            echo
            white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            red "🚀【 vmess-ws(tls)+Argo 】固定节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
            echo
            echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
            echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0)${plain}"
            echo
            echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
            echo 'vmess://'$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"8443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","type":"none","v":"2"}' | base64 -w 0) >/etc/ys/info/vm_ws_argogd.txt
            qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/vmess/vm_ws_argogd.txt)"
        fi
        echo
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        red "🚀【 vmess-ws 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
        echo
        echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
        echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)${plain}"
        echo
        echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
        echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0) >/etc/ys/info/vm_ws.txt
        qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/vmess/vm_ws.txt)"
    else
        echo
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        red "🚀【 vmess-ws-tls 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
        echo
        echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
        echo -e "${yellow}vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0)${plain}"
        echo
        echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
        echo 'vmess://'$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","type":"none","v":"2"}' | base64 -w 0) >/etc/ys/info/vm_ws_tls.txt
        qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/vmess/vm_ws_tls.txt)"
    fi
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

# hysteria2 节点信息
reshy2() {
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    #hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&mport=$hyps&sni=$hy2_name#hy2-$hostname"
    hy2_link="hysteria2://$all_password@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&sni=$hy2_name#hy2-$hostname"
    echo "$hy2_link" >/etc/ys/hysteria2/hy2.txt
    red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$hy2_link${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/hysteria2/hy2.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

# tuic5 节点信息
restu5() {
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    tuic5_link="tuic://$uuid:$all_password@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins#tu5-$hostname"
    echo "$tuic5_link" >/etc/ys/tuic5/tuic5.txt
    red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$tuic5_link${plain}"
    echo
    echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/tuic5/tuic5.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

# anytls 节点信息
resanytls() {
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    anytls_link="anytls://$all_password@$cl_any_ip:$port_any/?insecure=1#anytls-$hostname"
    echo "$anytls_link" >/etc/ys/anytls/anytls.txt
    red "🚀【 anytls 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    echo -e "${yellow}$anytls_link${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/anytls/anytls.txt)"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    echo "nekobox分享链接我不会,就手动选择mieru插件,手动填写吧"
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo "服务器:$address_ip"
    echo "服务器端口:$mita_port"
    echo "协议:TCP"
    echo "用户名:$all_name"
    echo "密码:$all_password"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}

###############################################################################################################
# 函数是用来给 节点信息的各个变量赋值的,用来判断 自签证书还是 acme证书等  修改完了
result_vl_vm_hy_tu() {
    if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
        ym=$(bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
        echo $ym >/root/ygkkkca/ca.log #  把acme 申请的域名写入 ca.log  中
    fi
    rm -rf /etc/ys/vmess/vm_ws_argo.txt /etc/ys/vmess/vm_ws.txt /etc/ys/vmess/vm_ws_tls.txt # 删除vmess ws vmess ws tls vmess ws argo
    sbdnsip=$(cat /etc/ys/info/sbdnsip.log)                                                 # sbdnsip 存储  dns tls://8.8.8.8/dns-query
    server_ip=$(cat /etc/ys/info/server_ip.log)                                             # server_ip 存储  vps的物理ip
    server_ipcl=$(cat /etc/ys/info/server_ipcl.log)                                         # server_ipcl 存储 ip
    hostname=$(cat /etc/ys/info/hostname.log)

    # hysteria2 link需要的配置信息  完成
    #    "hysteria2://$all_password@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=$ins_hy2&sni=$hy2_name#hy2-$hostname"
    hy2_name=www.bing.com
    sb_hy2_ip=$server_ip                                          # link ip地址
    cl_hy2_ip=$server_ipcl                                        # 客户端配置文件ip
    all_password=$(cat /etc/ys/info/all_password.txt 2>/dev/null) # 密码
    hy2_port=$(cat /etc/ys/hysteria2/port_hy2.txt 2>/dev/null)    # 端口
    hy2_ports=$(cat /etc/ys/hysteria2/hy2_ports.txt 2>/dev/null)  # 多端口
    ins_hy2=1

    # tuic5 需要的配置信息  完成
    #    "tuic://$uuid:$all_password@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&allow_insecure=$ins#tu5-$hostname"
    tu5_name=www.bing.com
    sb_tu5_ip=$server_ip
    cl_tu5_ip=$server_ipcl
    tu5_port=$(cat /etc/ys/tuic5/port_tu.txt 2>/dev/null)
    port_tu=$(cat /etc/ys/tuic5/port_tu.txt 2>/dev/null)
    ins=1

    # vless 需要的配置信息  完成
    #    vl_link="vless://$uuid@$server_ip:$vl_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname"
    uuid=$(cat /etc/ys/vless/uuid.txt 2>/dev/null)               # 读取uuid
    vl_port=$(cat /etc/ys/vless/port_vl_re.txt 2>/dev/null)      # 读取端口
    vl_name=$(cat /etc/ys/vless/server-name.txt 2>/dev/null)     # 读取 www.yahoo.com
    $private_key$(cat /etc/ys/vless/private_key.txt 2>/dev/null) # 读取服务端private_key值
    public_key=$(cat /etc/ys/vless/public_key.txt 2>/dev/null)   # 读取客户端public_key值
    short_id=$(cat /etc/ys/vless/short_id.txt 2>/dev/null)       # 读取 short-id

    # anytls 需要的配置信息
    "anytls://$all_password@$cl_any_ip:$port_any/?insecure=1#anytls-$hostname"
    cl_any_ip=$server_ip
    port_any=(cat /etc/ys/anytls/port_any.txt)
    ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)

    # vmess 需要的配置信息
    vmadd_local=$server_ipcl
    vmadd_are_local=$server_ip
    argo=$(cat /etc/ys/info/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    ws_path=$(cat /etc/ys/vmess/path.txt 2>/dev/null) # 得到path
    vm_port=$(cat /etc/ys/vmess/port_vm_ws.txt 2>/dev/null)
    vm_name=$(cat /root/ygkkkca/ca.log 2>/dev/null)

}

###############################################################################################################
# 显示节点信息  修改完了
mihomo_read_link() {
    rm -rf /etc/ys/jhdy.txt /etc/ys/vless/vl_reality.txt /etc/ys/vmess/vm_ws_argols.txt /etc/ys/vmess/vm_ws_argogd.txt /etc/ys/vmess/vm_ws.txt /etc/ys/vmess/vm_ws_tls.txt /etc/ys/hysteria2/hy2.txt /etc/ys/tuic5/tuic5.txt /etc/ys/anytls/anytls.txt
    result_vl_vm_hy_tu && reshy2 && restu5 && resvless && resanytls # 读取配置信息  hy2link  tu5link vlesslink anytlslink
    cat /etc/ys/vless/vl_reality.txt 2>/dev/null >>/etc/ys/jhdy.txt
    if [ -f '/etc/ys/vmess/vm_ws_argols.txt' ]; then
        cat /etc/ys/vmess/vm_ws_argols.txt 2>/dev/null >>/etc/ys/jhdy.txt
    fi
    if [ -f '/etc/ys/vmess/vm_ws_argogd.txt' ]; then
        cat /etc/ys/vmess/vm_ws_argogd.txt 2>/dev/null >>/etc/ys/jhdy.txt
    fi
    if [ -f '/etc/ys/vmess/vm_ws_argogd.txt' ]; then
        cat /etc/ys/vmess/vm_ws.txt 2>/dev/null >>/etc/ys/jhdy.txt
    fi
    if [ -f '/etc/ys/vmess/vm_ws_argogd.txt' ]; then
        cat /etc/ys/vmess/vm_ws_tls.txt 2>/dev/null >>/etc/ys/jhdy.txt
    fi
    cat /etc/ys/hysteria2/hy2.txt 2>/dev/null >>/etc/ys/jhdy.txt
    cat /etc/ys/tuic5/tuic5.txt 2>/dev/null >>/etc/ys/jhdy.txt
    cat /etc/ys/anytls/anytls.txt 2>/dev/null >>/etc/ys/jhdy.txt
    baseurl=$(base64 -w 0 </etc/ys/jhdy.txt 2>/dev/null)
    v2sub=$(cat /etc/ys/jhdy.txt 2>/dev/null)
    echo "$v2sub" >/etc/ys/jh_sub.txt
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀【 四合一聚合订阅 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、Karing】"
    echo -e "${yellow}$baseurl${plain}"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    mihomo_client # 创建 sing-box 客户端与 mihomo 客户端配置文件
}
# 显示节点信息  修改完了
###############################################################################################################
# 创建 sing-box 客户端与 mihomo 客户端配置文件      修改完了
mihomo_client() {
    argopid # 检查 arogid 信息
    cat >/etc/ys/sing_box_client.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "external_ui_download_url": "",
      "external_ui_download_detour": "",
      "secret": "",
      "default_mode": "Rule"
       },
      "cache_file": {
            "enabled": true,
            "path": "cache.db",
            "store_fakeip": true
        }
    },
    "dns": {
        "servers": [
            {
                "tag": "proxydns",
                "address": "$sbdnsip",
                "detour": "select"
            },
            {
                "tag": "localdns",
                "address": "h3://223.5.5.5/dns-query",
                "detour": "direct"
            },
            {
                "tag": "dns_fakeip",
                "address": "fakeip"
            }
        ],
        "rules": [
            {
                "outbound": "any",
                "server": "localdns",
                "disable_cache": true
            },
            {
                "clash_mode": "Global",
                "server": "proxydns"
            },
            {
                "clash_mode": "Direct",
                "server": "localdns"
            },
            {
                "rule_set": "geosite-cn",
                "server": "localdns"
            },
            {
                 "rule_set": "geosite-geolocation-!cn",
                 "server": "proxydns"
            },
             {
                "rule_set": "geosite-geolocation-!cn",         
                "query_type": [
                    "A",
                    "AAAA"
                ],
                "server": "dns_fakeip"
            }
          ],
           "fakeip": {
           "enabled": true,
           "inet4_range": "198.18.0.0/15",
           "inet6_range": "fc00::/18"
         },
          "independent_cache": true,
          "final": "proxydns"
        },
      "inbounds": [
    {
      "type": "tun",
     "tag": "tun-in",
	  "address": [
      "172.19.0.1/30",
	  "fd00::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "sniff": true,
      "sniff_override_destination": true,
      "domain_strategy": "prefer_ipv4"
    }
  ],
  "outbounds": [
    {
      "tag": "select",
      "type": "selector",
      "default": "auto",
      "outbounds": [
        "auto",
        "hy2-$hostname",
        "tuic5-$hostname",
        "vless-$hostname",
        "anytls-$hostname"
      ]
    },
    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$cl_hy2_ip",
        "server_port": $hy2_port,
        "password": "$all_password",
        "tls": {
            "enabled": true,
            "server_name": "$hy2_name",
            "insecure": $hy2_ins,
            "alpn": [
                "h3"
            ]
        }
    },
        {
            "type":"tuic",
            "tag": "tuic5-$hostname",
            "server": "$cl_tu5_ip",
            "server_port": $tu5_port,
            "uuid": "$uuid",
            "password": "$all_password",
            "congestion_control": "bbr",
            "udp_relay_mode": "native",
            "udp_over_stream": false,
            "zero_rtt_handshake": false,
            "heartbeat": "10s",
            "tls":{
                "enabled": true,
                "server_name": "$tu5_name",
                "insecure": $tu5_ins,
                "alpn": [
                    "h3"
                ]
            }
        },
     {
      "type": "vless",
      "tag": "vless-$hostname",
      "server": "$server_ipcl",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "packet_encoding": "xudp",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
        {
        "type": "anytls",
        "tag": "anytls-$hostname",

        "server": "$cl_any_ip",
        "server_port": $port_any,
        "password": "$all_password",
        "idle_session_check_interval": "30s",
        "idle_session_timeout": "30s",
        "min_idle_session": 5,
        "tls": {
            "enabled": true,
            "server_name": "www.bing.com",
            "insecure": true,
            "utls": {
            "enabled": true,
            "fingerprint": "edge" 
            }
            "alpn": ["h2", "http/1.1"]
        }
    },
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
        "hy2-$hostname",
        "tuic5-$hostname",
        "vless-$hostname",
        "anytls-$hostname"
      ],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50,
      "interrupt_exist_connections": false
    }
  ],
  "route": {
      "rule_set": [
            {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-!cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/geolocation-cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            },
            {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs",
                "download_detour": "select",
                "update_interval": "1d"
            }
        ],
    "auto_detect_interface": true,
    "final": "select",
    "rules": [
      {
      "inbound": "tun-in",
      "action": "sniff"
      },
      {
      "protocol": "dns",
      "action": "hijack-dns"
      },
      {
      "port": 443,
      "network": "udp",
      "action": "reject"
      },
      {
        "clash_mode": "Direct",
        "outbound": "direct"
      },
      {
        "clash_mode": "Global",
        "outbound": "select"
      },
      {
        "rule_set": "geoip-cn",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-cn",
        "outbound": "direct"
      },
      {
      "ip_is_private": true,
      "outbound": "direct"
      },
      {
        "rule_set": "geosite-geolocation-!cn",
        "outbound": "select"
      }
    ]
  },
    "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m",
    "detour": "direct"
  }
}
EOF

    cat >/etc/ys/clash_meta_client.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
global-client-fingerprint: chrome
dns:
  enable: false
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver: 
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:

- name: hysteria2-$hostname                            
  type: hysteria2                                      
  server: $cl_hy2_ip                               
  #port: $hy2_port 
  ports: $hy2_ports,$hy2_port                               
  password: $all_password
  sni: $hy2_name  
  alpn:                                 # 支持的应用层协议协商列表，按优先顺序排列。
    - h3                               
  skip-cert-verify: $hy2_ins            # 跳过证书验证，仅适用于使用 tls 的协议
  fast-open: true
  #fingerprint: xxxx         # 证书指纹，仅适用于使用 tls 的协议，可使用
  #ca: "./my.ca"
  #ca-str: "xyz"
  ###quic-go特殊配置项，不要随意修改除非你知道你在干什么###
  # initial-stream-receive-window： 8388608
  # max-stream-receive-window： 8388608
  # initial-connection-receive-window： 20971520
  # max-connection-receive-window： 20971520

- name: tuic5-$hostname                            
  server: $cl_tu5_ip                      
  port: $tu5_port                                    
  type: tuic
  uuid: $uuid       
  password: $all_password   
  alpn: [h3]
  disable-sni: true
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: $tu5_name                                
  skip-cert-verify: $tu5_ins

- name: vless-reality-vision-$hostname               
  type: vless
  server: $server_ipcl                           
  port: $vl_port                                
  uuid: $uuid   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $vl_name                 
  reality-opts: 
    public-key: $public_key    
    short-id: $short_id                    
  client-fingerprint: chrome                  

- name: anytls-$hostname
  type: anytls
  server: $cl_any_ip
  port: $port_any
  password: "$all_password"
  client-fingerprint: edge
  udp: true
  idle-session-check-interval: 30
  idle-session-timeout: 30
  min-idle-session: 0
  sni: "www.bing.com"
  alpn:
    - h2
    - http/1.1
  skip-cert-verify: true

proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:                              
    - hysteria2-$hostname
    - tuic5-$hostname
    - vless-reality-vision-$hostname
    - anytls-$hostname

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:                             
    - hysteria2-$hostname
    - tuic5-$hostname
    - vless-reality-vision-$hostname 
    - anytls-$hostname
    
- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡                                         
    - 自动选择
    - DIRECT
    - hysteria2-$hostname    
    - tuic5-$hostname
    - vless-reality-vision-$hostname 
    - anytls-$hostname

rules:
  - DOMAIN-SUFFIX,googleapis.cn,🚀 节点选择
  - DOMAIN-SUFFIX,xn--ngstr-lra8j.com,🚀 节点选择
  - DOMAIN-SUFFIX,xn--ngstr-cn-8za9o.com,🚀 节点选择

  - GEOIP,CN,DIRECT
  - GEOIP,LAN,DIRECT
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT

  - IP-CIDR,224.0.0.0/3,REJECT
  - IP-CIDR,ff00::/8,REJECT

  - MATCH,🌍选择代理节点
EOF
}

###############################################################################################################

mihomo_reality() { # vless-reality-key short_id
    blue "Vless-reality相关key与id将自动生成……"
    key_pair=$(/etc/ys/ys generate reality-keypair)                           # 修改完mihomo配置
    private_key=$(echo "$key_pair" | grep "PrivateKey: " | awk '{print $NF}') # 修改完mihomo配置
    public_key=$(echo "$key_pair" | grep "PublicKey: " | awk '{print $NF}')   # 修改完mihomo配置
    echo "$public_key" >/etc/ys/public.key                                    # 修改完mihomo配置
    short_id=$(openssl rand -hex 8)                                           # 修改完mihomo配置
    echo "$private_key" >/etc/ys/vless/private_key.txt
    echo "$public_key" >/etc/ys/vless/public_key.txt
    echo "$short_id" >/etc/ys/vless/short_id.txt

}

# 主菜单1项 安装 mihomo 一键脚本    修改完了
mihomo_run() {
    if [ -f "/etc/ys/config.yaml" ] && [ -f "/etc/ys/ys" ]; then
        red "已安装mihomo服务，无法再次安装" && exit
    fi
    mkdir -p /etc/ys
    chmod 777 /etc/ys
    mkdir -p /etc/ys/info
    chmod 777 /etc/ys/info
    mkdir -p /etc/ys/me/
    chmod 777 /etc/ys/me/
    mkdir -p /etc/ys/vless
    chmod 777 /etc/ys/vless
    mkdir -p /etc/ys/vmess
    chmod 777 /etc/ys/vmess
    mkdir -p /etc/ys/Hysteria2
    chmod 777 /etc/ys/Hysteria2
    mkdir -p /etc/ys/tuic5
    chmod 777 /etc/ys/tuic5
    mkdir -p /etc/ys/Anytls
    chmod 777 /etc/ys/Anytls
    mkdir -p /etc/ys/socks5
    chmod 777 /etc/ys/socks5
    echo "12345" > /etc/ys/socks5_in.txt
    v6                  # 核心逻辑部分，根据网络环境（特别是 IPv4 或纯 IPv6）进行配置，并处理 Warp 的状态。
    openyn              # 询问是否开放防火墙
    mihomo_setup        # 选择 mihomo 安装 正式版 或 测试版
    mihomo_cert_private # 自签证书与各个产生的变量
    mihomo_port_auto    # 配置协议端口
    mihomo_reality      #  vless-reality-key short_id
    if [[ ! -f '/etc/ys/info/all_name.txt' || ! -f '/etc/ys/info/all_password.txt' ]]; then
        name_password
    fi # 账户 密码
    echo
    wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
    wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    
    green "五、自动生成warp-wireguard出站账户" && sleep 2
    warpwg        # 获取 warp 密钥,ipv6 等值
    mihomo_config # 创建 mihomo 服务端配置文件
    mihomo_kaiji  # 写入开机启动配置文件
    sbactive      # 检查 mihomo 配置文件是否存在
    curl -sL https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys-v | awk -F "更新内容" '{print $1}' | head -n 1 >/etc/ys/v
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    mihomo_gengxin && blue " mihomo 脚本安装成功，脚本快捷方式：mihomo" && mihomo_dingshi # mihomo_gengxin 生成 mihomo 快捷方式  mihomo_dingshi 凌晨1点重启 mihomo 定时任务
    echo
    wgcfgo           # 管理并确保 Cloudflare WARP 服务的运行，并在必要时刷新或重新配置其网络参数。 它会根据 WARP 的当前状态来决定执行初始化或重启流程
    mihomo_read_link # 显示节点信息
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    blue "Clash-Meta/Sing-box客户端配置及私有订阅链接，请选择9查看"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
}
# 主菜单1项 安装 mihomo 一键脚本    修改完了
###############################################################################################################
# 主菜单2项  卸载mihomo 系统
unins() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service ys stop
        rc-update del ys default
        rm /etc/init.d/ys -f
    else
        systemctl stop ys >/dev/null 2>&1
        systemctl disable ys >/dev/null 2>&1
        rm -f /etc/systemd/system/ys.service
    fi
    kill -15 $(cat /etc/ys/info/sbargopid.log 2>/dev/null) >/dev/null 2>&1
    kill -15 $(cat /etc/ys/info/sbargoympid.log 2>/dev/null) >/dev/null 2>&1
    kill -15 $(cat /etc/ys/info/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
    rm -rf /etc/ys sbyg_update /usr/bin/mihomo /root/geoip.db /root/geosite.db /root/warpapi /root/warpip
    mihomo_shanchu_dingshi # 删除 mihomo 定时任务
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    service iptables save >/dev/null 2>&1
    green "mihomo卸载完成！"
    blue "欢迎继续使用mihomo脚本：bash <(curl -Ls https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys.sh)"
    echo
}
###############################################################################################################
# 主菜单3项  变更配置 【双证书TLS/UUID路径/Argo/IP优先/TG通知/Warp/订阅/CDN优选】
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# 3菜单第1项  更换Reality域名伪装地址,修改服务端服务端,修改客户端配置,快捷链接
menu_3() {
    echo
    echo "这里是重新设置各个协议的配置"
    yellow "1:重新设置hysteria2协议"
    yellow "2:重新设置Tuic5协议"
    yellow "3:重新设置vless reality协议"
    yellow "4:重新设置Anytls协议"
    yellow "0:返回上级菜单"
    readp "选择你要修改的协议:" menu
    if [ $menu == 1 ]; then
        echo "设置Hysteria2各种参数"
        yellow "1:设置Hysteria2单端口"
        yellow "2:设置Hysteria2多端口"
        yellow "3:设置Hysteria2使用的证书"
        yellow "4:设置Hysteria2使用udp模式还是bbr模式"
        yellow "5:设置Hysteria2用户名密码"
        yellow "0:返回上级菜单"
        readp "选择你要修改的:" menu
        if [ $menu == 1 ]; then
            oldhy2port=$(cat /etc/ys/hysteria2/port_hy2.txt 2>/dev/null)
            echo "旧的 hysteria2 的端口是:$oldhy2port"
            echo "$oldhy2port" >/etc/ys/hysteria2/oldhy2port.txt
            echo "设置新的 hysteria2 端口"
            hy2port # 新的端口  $port_hy2"
            newhy2port=$(cat /etc/ys/hysteria2/port_hy2.txt 2>/dev/null)
            sed -i 's/'"$oldhy2port"'/'"$newhy2port"'/g' /etc/ys/config.yaml
            # 客户端文件替换
            sed -i 's/'"$oldhy2port"'/'"$newhy2port"'/g' /etc/ys/clash_meta_client.yaml
            sed -i 's/'"$oldhy2port"'/'"$newhy2port"'/g' /etc/ys/sing_box_client.json
            $(netfilter-persistent save)
            # 添加重启ys语句
            mihomo_chongqi
            # 添加客户端配置与快捷方式
            allports
            mihomo_read_link
            # 返回菜单3
            readp "输入1返回菜单:/ns输入2退出脚本:" numm
            if [ "$numm" == "1" ]; then
                menu_3_1
            fi
        elif [$menu == 2]; then
            oldhy2ports=$(cat /etc/ys/hysteria2/oldhy2pord.txt 2>/dev/null)
            echo "旧的 hysteria2 多端口是:$oldhy2ports"
            oldhy2port=$(/etc/ys/hysteria2/oldhy2port.txt 2>/dev/null)
            echo "旧的上一个 hysteria2 单端口为:$oldhy2port"
            newhy2port=$(cat /etc/ys/hysteria2/port_hy2.txt 2>/dev/null)
            echo "新的 hysteria2 单端口是:$newhy2port"
            xxxx=$oldhy2ports
            ports_hy2_old="${xxxx//-/:}"
            # 删除旧的绑定端口,,10000:11000,9999
            $(iptables -t nat -D PREROUTING -p udp --dport $ports_hy2_old -j DNAT --to-destination :$oldhy2port)
            $(ip6tables -t nat -D PREROUTING -p udp --dport $ports_hy2_old -j DNAT --to-destination :$oldhy2port)
            $(netfilter-persistent save)
            # 删除旧的多端口
            echo "设置新hysteria2的多端口"
            hy2ports # 设置多端口函数     "$hy2_ports"
            newhy2ports=$(cat /etc/ys/hysteria2/hy2_ports.txt 2>/dev/null)
            sed -i 's/'"$oldhy2port"'/'"$newhy2ports"'/g' /etc/ys/config.yaml
            # 客户端文件替换
            sed -i 's/'"$oldhy2ports"'/'"$newhy2ports"'/g' /etc/ys/clash_meta_client.yaml
            sed -i 's/'"$oldhy2ports"'/'"$newhy2ports"'/g' /etc/ys/sing_box_client.json
            # 添加重启ys语句
            mihomo_chongqi
            # 添加客户端配置与快捷方式
            allports
            mihomo_read_link
            # 返回菜单3
            readp "输入1返回菜单:/ns输入2退出脚本:" numm
            if [ "$numm" == "1" ]; then
                menu_3_1
            fi
        elif [ "$menu" == "3" ]; then
		echo "还没写"
        elif [ "$menu" == "4" ]; then
		echo "还没写"
        elif [ "$menu" == "5" ]; then
		echo "还没写"
        elif [ "$menu" == "0" ]; then
            menu_3_1 #返回上级菜单
        else
		mihomo
        fi
    elif [ $menu == 2 ]; then
        echo "重新设置Tuic5协议"

    elif [ $menu == 3 ]; then
        echo "重新设置vless reality协议"
        yellow "1:从新设置其他伪装域名"
        yellow "2:从新设置其他uuid"
        yellow "3:从新设置端口"
        yellow "4:从新设置key"
        yellow "5:从新设置16进制码"
        yellow "0:"
        readp "选择你要修改的:" menu
        if [ $menu == 1 ]; then
            # 设置域名
            old_server_name=$(cat /etc/ys/vless/server-name.txt 2>/dev/null)
            # 定义你想要设置的新域名
            echo "你的旧域名是:$old_server_name"
            readp "设置你要更换的Reality域名伪装地址:" wangzi
            echo "$wangzi" >/etc/ys/vless/server-name.txt
            # 服务端文件替换
            sed -i 's/'"$old_server_name"'/'"$wangzi"'/g' /etc/ys/config.yaml
            # 客户端文件替换
            sed -i 's/'"$old_server_name"'/'"$wangzi"'/g' /etc/ys/clash_meta_client.yaml
            sed -i 's/'"$old_server_name"'/'"$wangzi"'/g' /etc/ys/sing_box_client.json
            # 添加重启ys语句
            mihomo_chongqi
            # 添加客户端配置与快捷方式
            allports
            mihomo_read_link
            # 设置域名
            # 返回菜单3
            readp "输入1返回菜单:/ns输入2退出脚本:" numm
            if [ "$numm" == "1" ]; then
                menu_3_1
            fi
        elif [$menu == 2]; then
            # 设置uuid
            echo
            olduuid=$(cat /etc/ys/vless/uuid.txt 2>/dev/null)
            green "旧的全协议的uuid:$olduuid"
            echo
            readp "输入uuid，必须是uuid格式，不懂就回车(重置并随机生成uuid)：" menu
            if [ -z "$menu" ]; then # 回车就为空 就生成新的uuid
                newuuid=$(uuidgen)
            else
                newuuid=$menu
            fi
            # 服务端文件替换
            sed -i 's/'"$olduuid"'/'"$newuuid"'/g' /etc/ys/config.yaml # 所有旧的,替换新的
            # 客户端文件替换
            sed -i 's/'"$olduuid"'/'"$newuuid"'/g' /etc/ys/clash_meta_client.yaml
            sed -i 's/'"$olduuid"'/'"$newuuid"'/g' /etc/ys/sing_box_client.json
            echo "$newuuid" >/etc/ys/vless/uuid.txt
            mihomo_chongqi # 重启mihomo
            mihomo_read_link
            blue "已确认uuid (密码)：${uuid}"
            # 设置uuid
            # 返回菜单3
            readp "输入1返回菜单:/ns输入2退出脚本:" numm
            if [ "$numm" == "1" ]; then
                menu_3_1
            fi
        elif [ $menu == 3 ]; then
            oldvless=$(cat /etc/ys/vless/port_vl_re.txt 2>/dev/null)
            echo "旧的vless 端口:$oldvless"
            vlport
            newvless=$(cat /etc.ys/vless/port_vl_re.txt 2>/dev/null)
            sed -i 's/'"$oldvless"'/'"$newvless"'/g' /etc/ys/config.yaml
            # 客户端文件替换
            sed -i 's/'"$oldvless"'/'"$newvless"'/g' /etc/ys/clash_meta_client.yaml
            sed -i 's/'"$oldvless"'/'"$newvless"'/g' /etc/ys/sing_box_client.json
            # 添加重启ys语句
            mihomo_chongqi
            # 添加客户端配置与快捷方式
            allports
            mihomo_read_link
            # 设置域名
            # 返回菜单3
            readp "输入1返回菜单:/ns输入2退出脚本:" numm
            if [ "$numm" == "1" ]; then
                menu_3_1
            fi
        elif [ $menu == 4 ]; then
            echo "从新设置vless reality key"
        elif [ $menu == 5 ]; then
            echo "从新设置vless reality 16进制码"
        elif [ $menu == 0 ]; then
            menu_3_1 #返回上级菜单
        else
            echo "输入错误,请从新输入" && menu_3_1
        fi
    elif [ $menu == 4 ]; then
        echo "重新设置Anytls协议"

    elif [ $menu == 0 ]; then
        mihomo #返回主菜单
    else
        echo "输入错误,请从新输入" && menu_3_1
    fi
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
menu_8(){
    echo "1.节点推送到Telegram"
    echo "2.节点同步到Gitlab"
    echo "0.返回到主菜单"
    readp "请选择菜单:" menu
    if [ $menu == 1 ]; then
        tgsbshow
    elif [ $menu == 2 ]; then
        gitlabsub
    else
        mihomo
    fi
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# 8菜单  设置Telegram推送节点通知
tgsbshow() { # telegram 推送设置
    echo
    yellow "1：重置/设置Telegram机器人的Token、用户ID"
    yellow "0：返回上层"
    readp "请选择【0-1】：" menu
    if [ "$menu" = "1" ]; then
        rm -rf /etc/ys/sbtg.sh
        readp "输入Telegram机器人Token: " token
        telegram_token=$token
        readp "输入Telegram机器人用户ID: " userid
        telegram_id=$userid
        echo '#!/bin/bash
export LANG=en_US.UTF-8

total_lines=$(wc -l < /etc/ys/clash_meta_client.yaml)
half=$((total_lines / 2))
head -n $half /etc/ys/clash_meta_client.yaml > /etc/ys/clash_meta_client1.txt
tail -n +$((half + 1)) /etc/ys/clash_meta_client.yaml > /etc/ys/clash_meta_client2.txt

total_lines=$(wc -l < /etc/ys/sing_box_client.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/ys/sing_box_client.json > /etc/ys/sing_box_client1.txt
tail -n +$((quarter + 1)) /etc/ys/sing_box_client.json | head -n $quarter > /etc/ys/sing_box_client2.txt
tail -n +$((2 * quarter + 1)) /etc/ys/sing_box_client.json | head -n $quarter > /etc/ys/sing_box_client3.txt
tail -n +$((3 * quarter + 1)) /etc/ys/sing_box_client.json > /etc/ys/sing_box_client4.txt

m1=$(cat /etc/ys/vless/vl_reality.txt 2>/dev/null)
m2=$(cat /etc/ys/vm_ws.txt 2>/dev/null)
m3=$(cat /etc/ys/vm_ws_argols.txt 2>/dev/null)
m3_5=$(cat /etc/ys/vm_ws_argogd.txt 2>/dev/null)
m4=$(cat /etc/ys/vm_ws_tls.txt 2>/dev/null)
m5=$(cat /etc/ys/hysteria2/hy2.txt 2>/dev/null)
m6=$(cat /etc/ys/tuic5/tuic5.txt 2>/dev/null)
m7=$(cat /etc/ys/sing_box_client1.txt 2>/dev/null)
m7_5=$(cat /etc/ys/sing_box_client2.txt 2>/dev/null)
m7_5_5=$(cat /etc/ys/sing_box_client3.txt 2>/dev/null)
m7_5_5_5=$(cat /etc/ys/sing_box_client4.txt 2>/dev/null)
m8=$(cat /etc/ys/clash_meta_client1.txt 2>/dev/null)
m8_5=$(cat /etc/ys/clash_meta_client2.txt 2>/dev/null)
m9=$(cat /etc/ys/sing_box_gitlab.txt 2>/dev/null)
m10=$(cat /etc/ys/clash_meta_gitlab.txt 2>/dev/null)
m11=$(cat /etc/ys/jh_sub.txt 2>/dev/null)
m12=$(cat /etc/ys/anytls/anytls.txt 2>/dev/null)
message_text_m1=$(echo "$m1")
message_text_m2=$(echo "$m2")
message_text_m3=$(echo "$m3")
message_text_m3_5=$(echo "$m3_5")
message_text_m4=$(echo "$m4")
message_text_m5=$(echo "$m5")
message_text_m6=$(echo "$m6")
message_text_m7=$(echo "$m7")
message_text_m7_5=$(echo "$m7_5")
message_text_m7_5_5=$(echo "$m7_5_5")
message_text_m7_5_5_5=$(echo "$m7_5_5_5")
message_text_m8=$(echo "$m8")
message_text_m8_5=$(echo "$m8_5")
message_text_m9=$(echo "$m9")
message_text_m10=$(echo "$m10")
message_text_m11=$(echo "$m11")
message_text_m12=$(echo "$m12")
MODE=HTML
URL="https://api.telegram.org/bottelegram_token/sendMessage"
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vless-reality-vision 分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m1}")
if [[ -f /etc/ys/vm_ws.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws 分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -f /etc/ys/vm_ws_argols.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+Argo临时域名分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/ys/vm_ws_argogd.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws(tls)+Argo固定域名分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3_5}")
fi
if [[ -f /etc/ys/vm_ws_tls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Vmess-ws-tls 分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m4}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Hysteria-2 分享链接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Tuic-v5 分享链接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m6}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Anytls 分享链接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m12}")
if [[ -f /etc/ys/sing_box_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 订阅链接 】：支持SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m9}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 配置文件(4段) 】：支持SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m7_5_5_5}")
fi

if [[ -f /etc/ys/clash_meta_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 订阅链接 】：支持Clash-meta相关客户端 "$'"'"'\n\n'"'"'"${message_text_m10}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 配置文件(2段) 】：支持Clash-meta相关客户端 "$'"'"'\n\n'"'"'"${message_text_m8}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m8_5}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 四合一协议聚合订阅链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m11}")

if [ $? == 124 ];then
echo TG_api请求超时,请检查网络是否重启完成并是否能够访问TG
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "TG推送成功";
else
echo "TG推送失败，请检查TG机器人Token和ID";
fi
' >/etc/ys/sbtg.sh
        sed -i "s/telegram_token/$telegram_token/g" /etc/ys/sbtg.sh
        sed -i "s/telegram_id/$telegram_id/g" /etc/ys/sbtg.sh
        green "设置完成！请确保TG机器人已处于激活状态！"
        tgnotice # telegram 推送文件
    else
        menu_8 # 返回菜单3
    fi
}
# telegram 推送文件
tgnotice() {
    if [[ -f /etc/ys/sbtg.sh ]]; then
        green "请稍等5秒，TG机器人准备推送……"
        mihomo_read_link >/dev/null 2>&1 # 显示节点信息
        bash /etc/ys/sbtg.sh
    else
        yellow "未设置TG通知功能"
    fi
    exit
}
# 8菜单 设置Telegram推送节点通知    ^^^^^
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# 8菜单  设置Gitlab订阅分享链接"
gitlabsub() {
    echo
    green "请确保Gitlab官网上已建立项目，已开启推送功能，已获取访问令牌"
    yellow "1：重置/设置Gitlab订阅链接"
    yellow "0：返回上层"
    readp "请选择【0-1】：" menu
    if [ "$menu" = "1" ]; then
        cd /etc/ys
        readp "输入登录邮箱: " email
        readp "输入访问令牌: " token
        readp "输入用户名: " userid
        readp "输入项目名: " project
        echo
        green "多台VPS共用一个令牌及项目名，可创建多个分支订阅链接"
        green "回车跳过表示不新建，仅使用主分支main订阅链接(首台VPS建议回车跳过)"
        readp "新建分支名称: " gitlabml
        echo
        if [[ -z "$gitlabml" ]]; then
            gitlab_ml=''
            git_sk=main
            rm -rf /etc/ys/gitlab_ml_ml
        else
            gitlab_ml=":${gitlabml}"
            git_sk="${gitlabml}"
            echo "${gitlab_ml}" >/etc/ys/gitlab_ml_ml
        fi
        echo "$token" >/etc/ys/gitlabtoken.txt
        rm -rf /etc/ys/.git
        git init >/dev/null 2>&1
        git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
        git config --global user.email "${email}" >/dev/null 2>&1
        git config --global user.name "${userid}" >/dev/null 2>&1
        git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
        branches=$(git branch)
        if [[ $branches == *master* ]]; then
            git branch -m master main >/dev/null 2>&1
        fi
        git remote add origin https://${token}@gitlab.com/${userid}/${project}.git >/dev/null 2>&1
        if [[ $(ls -a | grep '^\.git$') ]]; then
            cat >/etc/ys/gitpush.sh <<EOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for 'https://$(cat /etc/ys/gitlabtoken.txt 2>/dev/null)@gitlab.com':"
send "$(cat /etc/ys/gitlabtoken.txt 2>/dev/null)\r"
interact
EOF
            chmod +x gitpush.sh
            ./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/ys/gitlabtoken.txt >/dev/null 2>&1
            echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sing_box_client.json/raw?ref=${git_sk}&private_token=${token}" >/etc/ys/sing_box_gitlab.txt
            echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clash_meta_client.yaml/raw?ref=${git_sk}&private_token=${token}" >/etc/ys/clash_meta_gitlab.txt
            echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh_sub.txt/raw?ref=${git_sk}&private_token=${token}" >/etc/ys/jh_sub_gitlab.txt
            clsbshow # gitlab更新节点显示
        else
            yellow "设置Gitlab订阅链接失败，请反馈"
        fi
        cd
    else
        menu_8 # 返回3菜单
    fi
}
# gitlab更新节点显示        修改完了
clsbshow() {
    green "当前Sing-box节点已更新并推送"
    green "Sing-box订阅链接如下："
    blue "$(cat /etc/ys/sing_box_gitlab.txt 2>/dev/null)"
    echo
    green "Sing-box订阅链接二维码如下："
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/sing_box_gitlab.txt 2>/dev/null)"
    echo
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    green "当前mihomo节点配置已更新并推送"
    green "mihomo订阅链接如下："
    blue "$(cat /etc/ys/clash_meta_gitlab.txt 2>/dev/null)"
    echo
    green "mihomo订阅链接二维码如下："
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys/clash_meta_gitlab.txt 2>/dev/null)"
    echo
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    green "当前聚合订阅节点配置已更新并推送"
    green "订阅链接如下："
    blue "$(cat /etc/ys/jh_sub_gitlab.txt 2>/dev/null)"
    echo
    yellow "可以在网页上输入订阅链接查看配置内容，如果无配置内容，请自检Gitlab相关设置并重置"
    echo
}
# 推送gitlab 订阅函数
gitlabsubgo() {
    cd /etc/ys
    if [[ $(ls -a | grep '^\.git$') ]]; then
        if [ -f /etc/ys/gitlab_ml_ml ]; then
            gitlab_ml=$(cat /etc/ys/gitlab_ml_ml)
        fi
        git rm --cached sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
        git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
        git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
        git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
        chmod +x gitpush.sh
        ./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/ys/gitlabtoken.txt >/dev/null 2>&1
        clsbshow # gitlab更新节点显示
    else
        yellow "未设置Gitlab订阅链接"
    fi
    cd
}
# 8菜单  设置Gitlab订阅分享链接"   ^^^^^
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

###############################################################################################################
# 所有端口信息函数          修改完了
allports() {
    vl_port=$(cat /etc/ys/vless/port_vl_re.txt)
    vm_port=$(cat /etc/ys/vmess/port_vm_ws_vps.txt)
    hy2_port=$(cat /etc/ys/hysteria2/port_hy2.txt)
    tu5_port=$(cat /etc/ys/tuic5/port_tu.txt)
    port_any=$(cat /etc/ys/anytls/port_any.txt)
    socks5port=$(cat /etc/ys/socks5/port_scoks5.txt)
    hy2_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$hy2_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
    tu5_ports=$(iptables -t nat -nL --line 2>/dev/null | grep -w "$tu5_port" | awk '{print $8}' | sed 's/dpts://; s/dpt://' | tr '\n' ',' | sed 's/,$//')
    [[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="未添加"
    [[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="未添加"
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

###############################################################################################################
# 主菜单5项  关闭/重启 mihomo       修改完了
mihomo_restart_stop() { # 重启mihomo  关闭mihomo
    if [[ ! -f '/etc/ys/config.yaml' ]]; then
        red "未正常安装mihomo" && exit
    fi
    echo "mihomo 关闭重启菜单"
    echo "0:返回主菜单"
    readp "1：重启\n2：关闭\n请选择：" menu
    if [ "$menu" = "1" ]; then
        mihomo_chongqi # 重启mihomo 函数
        sbactive       # 检查 mihomo 配置文件是否存在的 函数
        green "mihomo服务已重启\n" && sleep 3 && sb
    elif [ "$menu" = "2" ]; then
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service ys stop
        else
            systemctl stop ys
            systemctl disable ys
        fi
        green "mihomo服务已关闭\n" && sleep 3 && sb
    else
        mihomo # 返回本函数
    fi
}
# 主菜单5项  关闭/重启 mihomo       修改完了
###############################################################################################################
# 主菜单6项  更新 mihomo 脚本   修改完了
bash_up() {
    if [[ ! -f '/usr/bin/mihomo' ]]; then
        red "未正常安装mihomo" && exit
    fi
    mihomo_gengxin # 更新菜单
    curl -sL https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys-v | awk -F "更新内容" '{print $1}' | head -n 1 >/etc/ys/v
    green " mihomo 安装脚本升级成功" && sleep 5 && mihomo
}
###############################################################################################################
# 主菜单7 更新/切换/指定 mihomo 内核版本  修改完了
mihomo_up() {
    if [ -f '/etc/ys/config.yaml' ]; then
        mihomo_setup
    fi
}
###############################################################################################################
# 主菜单8 刷新并查看节点 【Clash-Meta/SFA+SFI+SFW三合一配置/订阅链接/推送TG通知】  修改完了
clash_sb_share() {
    sbactive # 检查 mihomo 配置文件是否存在的 函数
    echo
    yellow "1：刷新并查看各协议分享链接、二维码、四合一聚合订阅"
    yellow "2：刷新并查看mihomo、Sing-box客户端SFA/SFI/SFW三合一配置、Gitlab私有订阅链接"
    yellow "3：目前无用,就放了一个mihomo_read_link函数"
    yellow "4：推送最新节点配置信息(选项1+选项2)到Telegram通知"
    yellow "0：返回上层"
    readp "请选择【0-4】：" menu
    if [ "$menu" = "1" ]; then
        mihomo_read_link # 显示节点信息
    elif [ "$menu" = "2" ]; then
        green "请稍等……"
        mihomo_read_link >/dev/null 2>&1 # 显示节点信息
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        red "Gitlab订阅链接如下："
        gitlabsubgo # 推送gitlab 订阅函数
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5 】Clash-Meta配置文件显示如下："
        red "文件目录 /etc/ys/clash_meta_client.yaml ，复制自建以yaml文件格式为准" && sleep 2
        echo
        cat /etc/ys/clash_meta_client.yaml
        echo
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        echo
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        red "🚀【 vless-reality、vmess-ws、Hysteria2、Tuic5 】SFA/SFI/SFW配置文件显示如下："
        red "安卓SFA、苹果SFI，win电脑官方文件包SFW请到甬哥Github项目自行下载，"
        red "文件目录 /etc/ys/sing_box_client.json ，复制自建以json文件格式为准" && sleep 2
        echo
        cat /etc/ys/sing_box_client.json
        echo
        white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        echo
    elif [ "$menu" = "3" ]; then
        green "请稍等……"
        mihomo_read_link >/dev/null 2>&1 # 显示节点信息
    elif [ "$menu" = "4" ]; then
        tgnotice # telegram 推送文件
    else
        sb # 返回主菜单
    fi
}
# 主菜单8 刷新并查看节点 【Clash-Meta/SFA+SFI+SFW三合一配置/订阅链接/推送TG通知】  修改完了
###############################################################################################################
# 主菜单9 查看 mihomo 运行日志  修改完了
mihomo_rizhi() {
    red "退出日志 Ctrl+c"
    if [[ x"${release}" == x"alpine" ]]; then
        yellow "暂不支持alpine查看日志"
    else
        echo "1:查看 mihomo 运行成功"
        echo "2:查看 mihomo 运行日记"
        echo "0:返回菜单"
        readp "选择要查看的菜单:" menu
        if [ $menu == 1 ]; then
            systemctl status ys
        elif [ $menu == 2 ]; then
            journalctl -u ys -o cat -e
        else
            mihomo
        fi
    fi
}
# 主菜单10 查看 mihomo 运行日志  修改完了
###############################################################################################################
# 主菜单10 bbr加速菜单   不需要修改
bbr() {
    if [[ $vi =~ lxc|openvz ]]; then
        yellow "当前VPS的架构为 $vi，不支持开启原版BBR加速" && sleep 2 && exit
    else
        green "点击任意键，即可开启BBR加速，ctrl+c退出"
        bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    fi
}


# 主菜单11 一键原版BBR+FQ加速   不需要修改   ^^^^^
###############################################################################################################
# 主菜单11 管理 Acme 申请域名证书   不需要修改
acme() {
    bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
}
# 主菜单11 管理 Acme 申请域名证书   不需要修改
###############################################################################################################
# 主菜单12 管理 Warp 查看Netflix/ChatGPT解锁情况    不需要修改
cfwarp() {
    #bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
    bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}
# 主菜单12 管理 Warp 查看Netflix/ChatGPT解锁情况    不需要修改
###############################################################################################################

# 主菜单13 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】 待修改
inssbwpph() {
    sbactive # 检查 mihomo 配置文件是否存在的 函数
    ins() {
        if [ ! -e /etc/ys/sbwpph ]; then
            case $(uname -m) in
            aarch64) cpu=arm64 ;;
            x86_64) cpu=amd64 ;;
            esac
            curl -L -o /etc/ys/sbwpph -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sbwpph_$cpu
            chmod +x /etc/ys/sbwpph
        fi
        if [[ -n $(ps -e | grep sbwpph) ]]; then
            kill -15 $(cat /etc/ys/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
        fi
        v4v6
        if [[ -n $v4 ]]; then
            sw46=4
        else
            red "IPV4不存在，确保安装过WARP-IPV4模式"
            sw46=6
        fi
        echo
        readp "设置WARP-plus-Socks5端口（回车跳过端口默认12345）：" port
        if [[ -z $port ]]; then
            port=12345
            until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
                [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
            done
        else
            until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
                [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
            done
        fi        
        oldsocks5_in=$(cat /etc/ys/socks5_in.txt)
        sed -i 's/'"$oldsocks5_in"'/'"$port"'/g' /etc/ys/config.yaml
        echo "$port" > /etc/ys/socks5_in.txt
        mihomo_chongqi # 重启ys
    }
    unins() {
        kill -15 $(cat /etc/ys/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
        rm -rf /etc/ys/sbwpph.log /etc/ys/sbwpphid.log
        crontab -l >/tmp/crontab.tmp
        sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
        crontab /tmp/crontab.tmp
        rm /tmp/crontab.tmp
    }
    echo
    yellow "1：重置启用WARP-plus-Socks5本地Warp代理模式"
    yellow "2：重置启用WARP-plus-Socks5多地区Psiphon代理模式"
    yellow "3：停止WARP-plus-Socks5代理模式"
    yellow "0：返回上层"
    readp "请选择【0-3】：" menu
    if [ "$menu" = "1" ]; then
        ins
        nohup setsid /etc/ys/sbwpph -b 127.0.0.1:$port --gool -$sw46 >/dev/null 2>&1 &
        echo "$!" >/etc/ys/sbwpphid.log
        green "申请IP中……请稍等……" && sleep 20
        resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
        resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
        if [[ -z $resv1 && -z $resv2 ]]; then
            red "WARP-plus-Socks5的IP获取失败" && unins && exit
        else
            echo "/etc/ys/sbwpph -b 127.0.0.1:$port --gool -$sw46 >/dev/null 2>&1" >/etc/ys/sbwpph.log
            crontab -l >/tmp/crontab.tmp
            sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
            echo '@reboot /bin/bash -c "nohup setsid $(cat /etc/ys/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/ys/sbwpphid.log"' >>/tmp/crontab.tmp
            crontab /tmp/crontab.tmp
            rm /tmp/crontab.tmp
            green "WARP-plus-Socks5的IP获取成功，可进行Socks5代理分流"
        fi
    elif [ "$menu" = "2" ]; then
        ins
        echo '
奥地利（AT）
澳大利亚（AU）
比利时（BE）
保加利亚（BG）
加拿大（CA）
瑞士（CH）
捷克 (CZ)
德国（DE）
丹麦（DK）
爱沙尼亚（EE）
西班牙（ES）
芬兰（FI）
法国（FR）
英国（GB）
克罗地亚（HR）
匈牙利 (HU)
爱尔兰（IE）
印度（IN）
意大利 (IT)
日本（JP）
立陶宛（LT）
拉脱维亚（LV）
荷兰（NL）
挪威 (NO)
波兰（PL）
葡萄牙（PT）
罗马尼亚 (RO)
塞尔维亚（RS）
瑞典（SE）
新加坡 (SG)
斯洛伐克（SK）
美国（US）
'
        readp "可选择国家地区（输入末尾两个大写字母，如美国，则输入US）：" guojia
        nohup setsid /etc/ys/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 >/dev/null 2>&1 &
        echo "$!" >/etc/ys/sbwpphid.log
        green "申请IP中……请稍等……" && sleep 20
        resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
        resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
        if [[ -z $resv1 && -z $resv2 ]]; then
            red "WARP-plus-Socks5的IP获取失败，尝试换个国家地区吧" && unins && exit
        else
            echo "/etc/ys/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 >/dev/null 2>&1" >/etc/ys/sbwpph.log
            crontab -l >/tmp/crontab.tmp
            sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
            echo '@reboot /bin/bash -c "nohup setsid $(cat /etc/ys/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/ys/sbwpphid.log"' >>/tmp/crontab.tmp
            crontab /tmp/crontab.tmp
            rm /tmp/crontab.tmp
            green "WARP-plus-Socks5的IP获取成功，可进行Socks5代理分流"
        fi
    elif [ "$menu" = "3" ]; then
        unins && green "已停止WARP-plus-Socks5代理功能"
    else
        mihomo
    fi
}

###############################################################################################################

showprotocol() { # 主界面显示的 信息函数    修改完了
    allports
    echo -e "mihomo 与 mieru 节点关键信息："
    echo -e "🚀【 Vless-reality 】${yellow}端口:$vl_port  Reality域名证书伪装地址：$(cat /etc/ys/vless/server-name.txt)${plain}".
    echo -e "🚀【 anytls 】${yellow}端口:$vl_port  Reality域名证书伪装地址：$(cat /etc/ys/vless/server-name.txt)${plain}"
    echo -e "🚀【 mieru 】${yellow}端口:$vl_port  Reality域名证书伪装地址：$(cat /etc/ys/vless/server-name.txt)${plain}"
    if [[ ! -f "$certificatec_vmess_ws" && ! -f "$certificatep_vmess_ws" ]]; then
        echo -e "🚀【   Vmess-ws    】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
    else
        echo -e "🚀【 Vmess-ws-tls  】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
    fi
    echo -e "🚀【  Hysteria-2   】${yellow}端口:$hy2_port  证书形式:$hy2_zs  转发多端口: $hy2zfport${plain}"
    echo -e "🚀【    Tuic-v5    】${yellow}端口:$tu5_port  证书形式:$tu5_zs  转发多端口: $tu5zfport${plain}"
    echo "------------------------------------------------------------------------------------"
    if [[ -n $(ps -e | grep sbwpph) ]]; then
        s5port=$(cat /etc/ys/sbwpph.log 2>/dev/null | awk '{print $3}' | awk -F":" '{print $NF}')
        s5gj=$(cat /etc/ys/sbwpph.log 2>/dev/null | awk '{print $6}')
        case "$s5gj" in
        AT) showgj="奥地利" ;;
        AU) showgj="澳大利亚" ;;
        BE) showgj="比利时" ;;
        BG) showgj="保加利亚" ;;
        CA) showgj="加拿大" ;;
        CH) showgj="瑞士" ;;
        CZ) showgj="捷克" ;;
        DE) showgj="德国" ;;
        DK) showgj="丹麦" ;;
        EE) showgj="爱沙尼亚" ;;
        ES) showgj="西班牙" ;;
        FI) showgj="芬兰" ;;
        FR) showgj="法国" ;;
        GB) showgj="英国" ;;
        HR) showgj="克罗地亚" ;;
        HU) showgj="匈牙利" ;;
        IE) showgj="爱尔兰" ;;
        IN) showgj="印度" ;;
        IT) showgj="意大利" ;;
        JP) showgj="日本" ;;
        LT) showgj="立陶宛" ;;
        LV) showgj="拉脱维亚" ;;
        NL) showgj="荷兰" ;;
        NO) showgj="挪威" ;;
        PL) showgj="波兰" ;;
        PT) showgj="葡萄牙" ;;
        RO) showgj="罗马尼亚" ;;
        RS) showgj="塞尔维亚" ;;
        SE) showgj="瑞典" ;;
        SG) showgj="新加坡" ;;
        SK) showgj="斯洛伐克" ;;
        US) showgj="美国" ;;
        esac
        grep -q "country" /etc/ys/sbwpph.log 2>/dev/null && s5ms="多地区Psiphon代理模式 (端口:$s5port  国家:$showgj)" || s5ms="本地Warp代理模式 (端口:$s5port)"
        echo -e "WARP-plus-Socks5状态：$yellow已启动 $s5ms$plain"
    else
        echo -e "WARP-plus-Socks5状态：$yellow未启动$plain"
    fi
    echo "------------------------------------------------------------------------------------"
}

# 检查tcp端口是否被占用                 编写完了
tcp_port() {
    [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$1") ]]
}
# 检查udp端口是否被占用
udp_port() {
    [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$1") ]]
}

#################################################################################################################
#这是脚本的主代码,用来运行脚本菜的的界面
clear
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "${bblue}    █     █   ███   █     █     █   ██    █   █                         "
echo -e "${bblue}   █ █   █ █   █   █ █   █ █   █ █  █ █   █  █ █                        "
echo -e "${bblue}  █   █ █   █  █  █   █ █   █ █   █ █  █  █ █   █                       "
echo -e "${bblue}  █   █ █   █  █  █   █ █   █  █ █  █   █ █  █ █                        "
echo -e "${bblue}  █   ███   █ ███ █   ███   █   █   █    ██   █                         "
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "这是一个参照了勇哥sb脚本,使用了勇哥脚本一些功能函数的 Mihomo 与 mieru 脚本的一键脚本,本~"
white "脚本有各种bug,不建议大家使用,脚本是我为了方便自己使用设计的,再次声明,不建议大家使用呦呦~~"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "本脚本是mihomo的一键脚本,支持下面五种协议,脚本还在改进状态,里面有各种bug,不要使用呦呦呦呦"
white "Vless-reality-vision、Anytls、Hysteria-2、Tuic-v5 (Vmess argo)待研究改四协议共存脚本"
white "安装 mieru 协议 后mihomo客户端支持 mieru 协议,sing-box客户端不支持,所以目前最多支持五~"
white "协议共存,未来如果能研究明白,在加入Vmess argo,可能就是六协议了,哈哈哈哈"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "脚本快捷方式：mihomo"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 一键安装 mihomo (测试)"
green " 2. 删除卸载 mihomo (测试)"
white "----------------------------------------------------------------------------------"
green " 3. mihomo 修改配置菜单(待修改)"
white "----------------------------------------------------------------------------------"
green " 4. 查看 mihomo 运行日志(完)"
green " 5. 关闭/重启 mihomo (完)"
green " 6. 更新脚本(完)"
green " 7. 更新 mihomo 服务端 (完)"
white "----------------------------------------------------------------------------------"
green " 8. 设置同步菜单(完)"
green " 9. 刷新并查看节点 【Clash-Meta/SFA+SFI+SFW三合一配置/订阅链接/推送TG通知】(完)"
white "----------------------------------------------------------------------------------"
green "10. bbr加速菜单(完)"
green "11. 勇哥管理 Acme 申请域名证书(完)"
green "12. 勇哥管理 Warp 查看Netflix/ChatGPT解锁情况(完)"
green "13. 勇哥添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】(待修改)"
white "----------------------------------------------------------------------------------"
green " 0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/ys/v 2>/dev/null) # insV 脚本内核版本号  latestV 是github上版本
latestV=$(curl -sL https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys-v | awk -F "更新内容" '{print $1}' | head -n 1)
# 检查 mihomo脚本是不是最新版
if [ -f /etc/ys/v ]; then
    if [ "$insV" = "$latestV" ]; then
        echo -e "当前 mihomo 脚本最新版：${bblue}${insV}${plain} (已安装)"
    else
        echo -e "当前 mihomo 脚本版本号：${bblue}${insV}${plain}"
        echo -e "检测到最新 mihomo 脚本版本号：${yellow}${latestV}${plain} (可选择7进行更新)"
        echo -e "${yellow}$(curl -sL https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys-v)${plain}"
    fi
else
    echo -e "当前 mihomo 脚本版本号：${bblue}${latestV}${plain}"
    yellow "未安装 mihomo 脚本！请先选择 1 安装"
fi

lapre # 获取版本号函数,在进入菜单时候,显示
if [ -f '/etc/ys/config.yaml' ]; then
    if [[ $inscore =~ ^[0-9.]+$ ]]; then
        if [ "${inscore}" = "${latcore}" ]; then
            echo
            echo -e "当前 mihomo 最新正式版内核：${bblue}${inscore}${plain} (已安装)"
            echo
            echo -e "当前 mihomo 最新测试版内核：${bblue}${precore}${plain} (可切换)"
        else
            echo
            echo -e "当前 mihomo 已安装正式版内核：${bblue}${inscore}${plain}"
            echo -e "检测到最新 mihomo 正式版内核：${yellow}${latcore}${plain} (可选择8进行更新)"
            echo
            echo -e "当前 mihomo 最新测试版内核：${bblue}${precore}${plain} (可切换)"
        fi
    else
        if [ "${inscore}" = "${precore}" ]; then
            echo
            echo -e "当前 mihomo 最新测试版内核：${bblue}${inscore}${plain} (已安装)"
            echo
            echo -e "当前 mihomo 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
        else
            echo
            echo -e "当前 mihomo 已安装测试版内核：${bblue}${inscore}${plain}"
            echo -e "检测到最新 mihomo 测试版内核：${yellow}${precore}${plain} (可选择8进行更新)"
            echo
            echo -e "当前 mihomo 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
        fi
    fi
else
    echo
    echo -e "当前 mihomo 最新正式版内核：${bblue}${latcore}${plain}"
    echo -e "当前 mihomo 最新测试版内核：${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "VPS状态如下："
echo -e "系统:$blue$op$plain  \c"
echo -e "内核:$blue$version$plain  \c"
echo -e "处理器:$blue$cpu$plain  \c"
echo -e "虚拟化:$blue$vi$plain  \c"
echo -e "BBR算法:$blue$bbr$plain"
vps_ip # 获取本地vps的真实ip
echo -e "本地IPV4地址：${blue}${vps_ipv4}$plain    本地IPV6地址：${blue}${vps_ipv6}$plain"
warp_ip # 获取warp的ip
echo -e "WARP IPV4地址：${blue}${warp_ipv4}$plain    WARP IPV6地址：${blue}${warp_ipv6}$plain"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [[ x"${release}" == x"alpine" ]]; then
    status_cmd="rc-service ys status"
    status_pattern="started"
else
    status_cmd="systemctl status ys"
    status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/ys/config.yaml' ]]; then
    echo -e "mihomo状态：$blue运行中$plain"
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/ys/config.yaml' ]]; then
    echo -e "mihomo状态：$yellow未启动，选择10查看日志并反馈，建议切换正式版内核或卸载重装脚本$plain"
else
    echo -e "mihomo状态：$red未安装$plain"
fi
if [ -d "/etc/ys/mieru" ] && [ -f "/etc/mita/config.json" ]; then
    echo -e "mieru服务端:${blue}已安装$plain"
else
    echo -e "mieru服务器:${blue}未安装$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
# 这函数显示tls 开起关闭,多端口显示等信息
if [ -f '/etc/ys/config.yaml' ]; then
    showprotocol # 目前没加入这个函数
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
readp "请输入数字【0-13】:" Input
case "$Input" in
1) mihomo_run ;;          # 一键安装 mihomo 完
2) unins ;;               # 删除卸载 mihomo 完
3) menu_3 ;;              # mihomo 修改配置菜单 完
4) mihomo_rizhi ;;        # 查看 mihomo 运行日志 完
5) mihomo_restart_stop ;; # 关闭/重启 mihomo 完
6) bash_up ;;             # 更新脚本 完
7) mihomo_up ;;           # 更新 mihomo 服务端 完
8) menu_8 ;;              # 设置同步菜单
9) clash_sb_share ;;      # 刷新并查看节点 【Clash-Meta/SFA+SFI+SFW三合一配置/订阅链接/推送TG通知】完
10) bbr ;;                # 勇哥一键原版BBR+FQ加速 完
11) acme ;;               # 勇哥管理 Acme 申请域名证书 完
12) cfwarp ;;             # 勇哥管理 Warp 查看Netflix/ChatGPT解锁情况 完
13) inssbwpph ;;          # 勇哥添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】待修改
*) exit ;;
esac
