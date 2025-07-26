#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
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
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
# 如果系统是arch,就显示信息不支持,并退出脚本
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
    red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

version=$(uname -r | cut -d "-" -f1)

# 判断vps是什么类型的机器      vi 变量存储了检测到的虚拟化类型（如 kvm, docker, lxc, vmware 等）
# 如果是物理机,virt-what 可能无输出或空
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)

# 检测当前系统的 CPU 架构    cpu 变量存储了linux系统的架构
case $(uname -m) in
armv7l) cpu=armv7 ;;
aarch64) cpu=arm64 ;;
x86_64) cpu=amd64 ;;
i386 | i686) cpu="386" ;;
*) red "目前脚本不支持$(uname -m)架构" && exit ;;
esac

# 检测安装的bbr拥堵算法   bbr 存储了是什么的bbr版本
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
    bbr=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
    bbr="Openvz版bbr-plus"
else
    bbr="Openvz/Lxc"
fi

# 检测vps主机名称  hostname 存储了vps的主机名
hostname=$(hostname)
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
if [[ $vi = openvz ]]; then
  TUN=$(cat /dev/net/tun 2>&1)
  if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
    red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
    cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
    TUN=$(cat /dev/net/tun 2>&1)
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
      green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
    else
      echo '#!/bin/bash' >/root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >>/root/tun.sh && chmod +x /root/tun.sh
      grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >>/etc/crontab
      green "TUN守护功能已启动"
    fi
  fi
fi
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

# 开放防火墙
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

v4v6() {
    v4=$(curl -s4m5 icanhazip.com -k)
    v6=$(curl -s6m5 icanhazip.com -k)
}

warpcheck() {
    wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

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

# 判断端口是否被占用
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
# 输入端口
vless_xtls_relity_port() {
    #
    readp "\n设置Vless-reality端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    vless_xtls_relity_port=$port
    echo "$vless_xtls_relity_port" >/usr/local/etc/xray/vless_xtls_relity_port.txt
}
xhttp_tcp_reality_port(){
    #
    readp "\n设置xhttp tcp reality端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    xhttp_tcp_reality_port=$port
    echo "$xhttp_tcp_reality_port" >/usr/local/etc/xray/xhttp_tcp_reality_port.txt
}
xhttp_tcp_tls_port(){
    # 
    readp "\n设置xhttp tcp tls端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    xhttp_tcp_tls_port=$port
    echo "$xhttp_tcp_tls_port" >/usr/local/etc/xray/xhttp_tcp_tls_port.txt
}
xhttp_udp_tls_port(){
    # 
    readp "\n设置xhttp udp tls端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    xhttp_udp_tls_port=$port
    echo "$xhttp_udp_tls_port" >/usr/local/etc/xray/xhttp_udp_tls_port.txt    
}
xhttp_huiyuan_cf_port(){
    # 
    readp "\n设置xhttp cf回源 端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    xhttp_huiyuan_cf_port=$port
    echo "$xhttp_huiyuan_cf_port" >/usr/local/etc/xray/xhttp_huiyuan_cf_port.txt    
}
socks5_port(){
    readp "\n设置socks5_port主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    socks5_port=$port
    if [ -d "/etc/hysteria/" ]; then
    echo "$socks5_port" >/etc/hysteria/socks5_port.txt
    fi
    if [ -d "/usr/local/etc/xray/" ]; then
    echo "$socks5_port" >/usr/local/etc/xray/socks5_port.txt
    fi
}

hysteria2_port(){
    readp "\n设置Hysteria2主端口[1-65535] (回车跳过为10000-65535之间的随机端口)：" port
    chooseport
    hysteria2_port=$port
    echo "$hysteria2_port" >/etc/hysteria/hysteria2_port.txt
}
# 输入url
relity_url(){
    readp "写入偷取证书的域名:" xray_reality_url    # 写入url地址
    if [ -z "${reality_url}" ]; then
        reality_url="www.yahoo.com"
    fi
    echo "$reality_url" >/usr/local/etc/xray/reality_url.txt
}

acme_url(){
    readp "请入输入解析过的二级域名:" acme_url
    cd /root/
    wget -O -  https://get.acme.sh | sh
    . .bashrc
    acme.sh --upgrade --auto-upgrade
    acme.sh --set-default-ca --server letsencrypt
    acme.sh --issue -d $acme_url -w /usr/local/etc/xray/ --keylength ec-256 --force
    acme.sh --install-cert -d $acme_url --ecc --fullchain-file /usr/local/etc/xray/cert.crt --key-file /usr/local/etc/xray/private.key
    chmod +r /usr/local/etc/xray/cert.crt
    chmod +r /usr/local/etc/xray/private.key
    echo "$acme_url" >/usr/local/etc/xray/acme_url.txt
}

acme_auto_xuqi() {
cat >/usr/local/etc/xray/auto-xuqi.sh <<EOF
#!/bin/bash
/root/.acme.sh/acme.sh --install-cert -d xuexi.yggmsh.edu.kg --ecc --fullchain-file /usr/local/etc/xray/cert.crt --key-file /usr/local/etc/xray/private.key

chmod +r /usr/local/etc/xray/cert.crt

chmod +r /usr/local/etc/xray/private.key

sudo systemctl restart xray
EOF
    crontab -l >/tmp/crontab.tmp
    echo "30 1 2 * *   bash /usr/local/etc/xray/auto-xuqi.sh" >>/tmp/crontab.tmp
    crontab /tmp/crontab.tmp
    rm /tmp/crontab.tmp
}
# 安装xray
xray_hy2_setup(){
    xitong_name=$(whoami)
    if [ "$xitong_name" != "root" ]; then
        sudo -i
        echo "进入root模式"
    fi
    vps_ip
    echo $vps_ipv4 >/usr/local/etc/xray/vps_ipv4.txt
    echo $vps_ipv6 >/usr/local/etc/xray/vps_ipv6.txt
    openyn      #询问是否开放端口
    # 官方安装脚本
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    bash <(curl -fsSL https://get.hy2.sh/)
    xray_uudi=$(xray uuid)
    echo "$xray_uudi" >/usr/local/etc/xray/xray_uudi.txt
    xray_reality=$(xray x25519)
    private_key=$(echo "$xray_reality" | grep "Private key: " | awk '{print $NF}')
    public_key=$(echo "$xray_reality" | grep "Public key: " | awk '{print $NF}')
    echo "$private_key" >/usr/local/etc/xray/private_key.txt
    echo "$public_key" >/usr/local/etc/xray/public_key.txt
    xray_shortIds=$(openssl rand -hex 8)
    echo "$xray_shortIds" >/usr/local/etc/xray/xray_shortIds.txt
    $(chmod 777 /etc/hysteria/)
    $(openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key)
    $(openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=www.bing.com")
    $(chmod 777 /etc/hysteria/cert.crt)
    $(chmod 777 /etc/hysteria/private.key)
    $(chmod 777 /etc/hysteria/config.yaml)
    if [ ! -f "/usr/local/etc/xray/cert.crt" ] || [ ! -f "/usr/local/etc/xray/private.key" ]; then
    acme_url                    # 注册域名
    fi
    acme_auto_xuqi              # acme证书自动续期 每月2号自动续期
    vless_xtls_relity_port && xhttp_tcp_reality_port && xhttp_tcp_tls_port && xhttp_udp_tls_port && xhttp_huiyuan_cf_port && hysteria2_port && socks5_port              # 写入端口
    relity_url
    readp "设置密码:" all_password
    echo "$all_password" >/etc/hysteria/all_password.txt
    warpwg                      # 注册wireguard信息
    write_config                # 写入配置文件
    xray_hy2_link                  # 显示配置链接
    $(systemctl restart xray)   # 重启xray
    
}
# 读取全部配置信息
read_info(){
    vps_ipv4=$(cat /usr/local/etc/xray/vps_ipv4.txt 2>/dev/null)
    vps_ipv6=$(cat /usr/local/etc/xray/vps_ipv6.txt 2>/dev/null)

    if [ -d "/usr/local/etc/xray/" ]; then
        # vless reality
        xray_uudi=$(cat /usr/local/etc/xray/xray_uudi.txt 2>/dev/null)
        private_key=$(cat /usr/local/etc/xray/private_key.txt 2>/dev/null)
        public_key=$(cat /usr/local/etc/xray/public_key.txt 2>/dev/null)
        xray_shortIds=$(cat /usr/local/etc/xray/xray_shortIds.txt 2>/dev/null)
        reality_url=$(cat /usr/local/etc/xray/reality_url.txt 2>/dev/null)
        vless_xtls_relity_port=$(cat /usr/local/etc/xray/vless_xtls_relity_port.txt 2>/dev/null)
        # xhttp tcp reality
        xhttp_tcp_reality_port=$(cat /usr/local/etc/xray/xhttp_tcp_reality_port.txt 2>/dev/null)

        xhttp_tcp_tls_port=$(cat /usr/local/etc/xray/xhttp_tcp_tls_port.txt 2>/dev/null)

        xhttp_udp_tls_port=$(cat /usr/local/etc/xray/xhttp_udp_tls_port.txt 2>/dev/null)

        xhttp_huiyuan_cf_port=$(cat /usr/local/etc/xray/xhttp_huiyuan_cf_port.txt 2>/dev/null)

        xhttp_tcp_reality_port=$(cat /usr/local/etc/xray/xhttp_tcp_reality_port.txt 2>/dev/null)
        # socks 
        socks5_port=$(cat /usr/local/etc/xray/socks5_port.txt 2>/dev/null)
        #acme_url
        acme_url=$(cat /usr/local/etc/xray/acme_url.txt 2>/dev/null)
    fi
    if [ -d "/etc/hysteria/" ]; then
        all_password=$(cat /etc/hysteria/all_password.txt 2>/dev/null)
        hysteria2_port=$(cat /etc/hysteria/hysteria2_port.txt 2>/dev/null)
        socks5_port=$(cat /etc/hysteria/socks5_port.txt 2>/dev/null)
        
    fi
}
# 写入xray配置文件
write_config(){
    if [ -f "/usr/local/etc/xray/config.json" ]; then
        chmod 777 /usr/local/etc/xray/config.json
    fi
    read_info
cat >/usr/local/etc/xray/config.json <<EOF 
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
    {
        "tag": "vless-xtls-reality",
        "listen": "0.0.0.0",
        "port": $vless_xtls_relity_port,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": "xtls-rprx-vision"
        }
        ],
        "decryption": "none"
        },
        "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
        "dest": "$xray_reality_url:443",
        "serverNames": [
        "$xray_reality_url"
        ],
        "privateKey": "$private_key",
        "shortIds": [
        "$xray_shortIds"
        ]
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "xhttp-tcp-reality",
        "listen": "0.0.0.0",
        "port": $xhttp_tcp_reality_port,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": ""
        }
        ],
        "decryption": "none",
        "fallbacks": []
        },
        "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
        "show": false,
        "fingerprint": "chrome",
        "dest": "$xray_reality_url:443",
        "xver": 0,
        "serverNames": [
        "$xray_reality_url"
        ],
        "privateKey": "$private_key",
        "publicKey": "$public_key",
        "minClientVer": "",
        "maxClientVer": "",
        "maxTimeDiff": 0,
        "shortIds": [
        "$xray_shortIds"
        ]
        },
        "xhttpSettings": {
        "path": "/xuexi",
        "host": "",
        "headers": {},
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": "1000000",
        "noSSEHeader": false,
        "xPaddingBytes": "100-1000",
        "mode": "auto"
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "xhttp-tcp-tls-zhilian",
        "listen": "0.0.0.0",
        "port": $xhttp_tcp_tls_port,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": ""
        }
        ],
        "decryption": "none",
        "fallbacks": []
        },
        "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
        "serverName": "$acme_url",
        "rejectUnknownSni": false,
        "minVersion": "1.2",
        "maxVersion": "1.3",
        "cipherSuites": "",
        "certificates": [
        {
        "ocspStapling": 3600,
        "certificateFile": "/usr/local/etc/xray/cert.crt",
        "keyFile": "/usr/local/etc/xray/private.key"
        }
        ],
        "alpn": [
        "h2",
        "http/1.1"
        ],
        "settings": [
        {
        "allowInsecure": false,
        "fingerprint": "",
        "serverName": ""
        }
        ]
        },
        "xhttpSettings": {
        "path": "/xuexi",
        "host": "",
        "headers": {},
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": "1000000",
        "noSSEHeader": false,
        "xPaddingBytes": "100-1000",
        "mode": "auto"
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "xhttp-udp-tls",
        "listen": "0.0.0.0",
        "port": $xhttp_udp_tls_port,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": ""
        }
        ],
        "decryption": "none",
        "fallbacks": []
        },
        "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
        "serverName": "$acme_url",
        "rejectUnknownSni": false,
        "minVersion": "1.2",
        "maxVersion": "1.3",
        "cipherSuites": "",
        "certificates": [
        {
        "ocspStapling": 3600,
        "certificateFile": "/usr/local/etc/xray/cert.crt",
        "keyFile": "/usr/local/etc/xray/private.key"
        }
        ],
        "alpn": [
        "h3"
        ],
        "settings": [
        {
        "allowInsecure": false,
        "fingerprint": "",
        "serverName": ""
        }
        ]
        },
        "xhttpSettings": {
        "path": "/xuexi",
        "host": "",
        "headers": {},
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": "1000000",
        "noSSEHeader": false,
        "xPaddingBytes": "100-1000",
        "mode": "auto"
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "xhttp-huiyuan-tcp/udp-cdn-80-443",
        "listen": "0.0.0.0",
        "port": $xhttp_huiyuan_cf_port,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": ""
        }
        ],
        "decryption": "none",
        "fallbacks": []
        },
        "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
        "path": "/xuexi",
        "host": "",
        "headers": {},
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": "1000000",
        "noSSEHeader": false,
        "xPaddingBytes": "100-1000",
        "mode": "auto"
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "xhttp-tcp-tls-cdn",
        "listen": "0.0.0.0",
        "port": 8443,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": ""
        }
        ],
        "decryption": "none",
        "fallbacks": []
        },
        "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
        "serverName": "$acme_url",
        "rejectUnknownSni": false,
        "minVersion": "1.2",
        "maxVersion": "1.3",
        "cipherSuites": "",
        "certificates": [
        {
        "ocspStapling": 3600,
        "certificateFile": "/usr/local/etc/xray/cert.crt",
        "keyFile": "/usr/local/etc/xray/private.key"
        }
        ],
        "alpn": [
        "h2",
        "http/1.1"
        ],
        "settings": [
        {
        "allowInsecure": false,
        "fingerprint": "",
        "serverName": ""
        }
        ]
        },
        "xhttpSettings": {
        "path": "/xuexi",
        "host": "$acme_url",
        "headers": {},
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": "1000000",
        "noSSEHeader": false,
        "xPaddingBytes": "100-1000",
        "mode": "auto"
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "xhttp-80-tcp-cdn",
        "listen": "0.0.0.0",
        "port": 8880,
        "protocol": "vless",
        "settings": {
        "clients": [
        {
        "id": "$xray_uudi",
        "flow": ""
        }
        ],
        "decryption": "none",
        "fallbacks": []
        },
        "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
        "path": "/xuexi",
        "host": "$acme_url",
        "headers": {},
        "scMaxBufferedPosts": 30,
        "scMaxEachPostBytes": "1000000",
        "noSSEHeader": false,
        "xPaddingBytes": "100-1000",
        "mode": "auto"
        }
        },
        "sniffing": {
        "enabled": true,
        "destOverride": [
        "http",
        "tls",
        "quic"
        ]
        }
        },
        {
        "tag": "socks-hy2-lai",
        "port": $socks5_port,
        "protocol": "socks",
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1",
        "userLevel": 0
        }   
    ],
    "outbounds": [
        {
        "protocol": "freedom",
        "tag": "direct"
        },
        {
        "protocol": "wireguard",
        "settings": {
        "secretKey": "$pvk",
        "address": [
        "172.16.0.2/32",
        "${v6}/128"
        ],
        "peers": [
        {
        "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        "allowedIPs": [
        "0.0.0.0/0",
        "::/0"
        ],
        "endpoint": "$endip:2408"
        }
        ],
        "reserved": [$res],
        "mtu": 1280
        },
        "tag": "wireguard-out"
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
            "type": "field",
            "domains": [
            "openai.com",
            "chat.openai.com",
            "auth0.openai.com",
            "cdn.openai.com",
            "api.openai.com",
            "auth0.com"
            ],
            "outboundTag": "wireguard-out",
            "inboundTag": ["socks-hy2-lai"]
            },
            {
            "type": "field",
            "ip": [
            "geoip:private"
            ],
            "outboundTag": "direct"
            }
        ]
    }
}
EOF
cat >/etc/hysteria/config.yaml <<EOF
listen: :$hysteria2_port
tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key

auth:
  type: password
  password: $all_password
ignoreClientBandwidth: false

outbounds:
  - name: socks5_out
    type: socks5
    socks5:
      addr: "127.0.0.1:$socks5_port"

  - name: direct_out
    type: direct

acl:
  inline:
    - socks5_out(DOMAIN-SUFFIX:openai.com)
    - socks5_out(DOMAIN-SUFFIX:chatgpt.com)
    - direct_out(all)
EOF
}

xray_hy2_link(){
    read_info       # 读取配置信息
    link_vless_xtls_relity() {
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_vless_xtls_relity="vless://$xray_uudi@$vps_ipv4:$vless_xtls_relity_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$xray_reality_url&fp=chrome&pbk=$public_key&sid=$xray_shortIds&type=tcp#vless_xtls_relity-$hostname"
    echo "$link_vless_xtls_relity" >/usr/local/etc/xray/link_vless_xtls_relity.txt
    red "🚀【 vless_xtls_relity 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_vless_xtls_relity${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_vless_xtls_relity.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_tcp_reality(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_tcp_reality="vless://$xray_uudi@$vps_ipv4:$xhttp_tcp_reality_port?mode=auto&path=%2Fxuexi&security=reality&encryption=none&pbk=$public_key&fp=chrome&type=xhttp&sni=$xray_reality_url&sid=$xray_shortIds#xhttp_tcp_reality-$hostname"
    echo "$link_xhttp_tcp_reality" >/usr/local/etc/xray/link_xhttp_tcp_reality.txt
    red "🚀【 xhttp_tcp_reality 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_tcp_reality${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_tcp_reality.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_tcp_tls(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_tcp_tls="vless://$xray_uudi@$acme_url:$xhttp_tcp_tls_port?mode=auto&path=%2Fxuexi&security=tls&alpn=h2%2Chttp%2F1.1&encryption=none&type=xhttp#xhttp_tcp_tls-$hostname"
    echo "$link_xhttp_tcp_tls" >/usr/local/etc/xray/link_xhttp_tcp_tls.txt
    red "🚀【 xhttp_tcp_tls 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_tcp_tls${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_tcp_tls.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_udp_tls(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_udp_tls="vless://$xray_uudi@$acme_url:$xhttp_udp_tls_port?mode=auto&path=%2Fxuexi&security=tls&alpn=h3&encryption=none&type=xhttp#xhttp-udp-tls-$hostname"
    echo "$link_xhttp_udp_tls" >/usr/local/etc/xray/link_xhttp_udp_tls.txt
    red "🚀【 xhttp_udp_tls 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_udp_tls${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_udp_tls.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_huiyuan_cf_80(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_huiyuan_cf_80="vless://$xray_uudi@172.64.90.8:8880?encryption=none&host=beishong.yggmsh.edu.kg&mode=auto&path=%2Fxuexi&security=none&type=xhttp#xhttp_huiyuan_cf_80-$hostname"
    echo "$link_xhttp_huiyuan_cf_80" >/usr/local/etc/xray/link_xhttp_huiyuan_cf_80.txt
    red "🚀【 xhttp_huiyuan_cf_80 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_huiyuan_cf_80${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_huiyuan_cf_80.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_huiyuan_cf_443(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_huiyuan_cf_443="vless://$xray_uudi@172.64.90.8:443?mode=auto&path=%2Fxuexi&security=tls&encryption=none&host=beishong.yggmsh.edu.kg&type=xhttp#xhttp_huiyuan_cf_443-$hostname"
    echo "$link_xhttp_huiyuan_cf_443" >/usr/local/etc/xray/link_xhttp_huiyuan_cf_443.txt
    red "🚀【 xhttp_huiyuan_cf_443 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_huiyuan_cf_443${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_huiyuan_cf_443.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_tcp_cdn_80(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_tcp_cdn_80="vless://$xray_uudi@172.67.134.88:8880?encryption=none&host=$acme_url&mode=auto&path=%2Fxuexi&security=none&type=xhttp#xhttp_tcp_cdn_80-$hostname"
    echo "$link_xhttp_tcp_cdn_80" >/usr/local/etc/xray/link_xhttp_tcp_cdn_80.txt
    red "🚀【 xhttp_tcp_cdn_80 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_tcp_cdn_80${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_tcp_cdn_80.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    link_xhttp_udp_tls_cdn_443(){
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_xhttp_udp_tls_cdn_443="vless://$xray_uudi@172.64.90.8:8443?mode=auto&path=%2Fxuexi&security=tls&alpn=h3&encryption=none&host=$acme_url&type=xhttp&sni=$acme_url#xhttp_udp_tls_cdn_443-$hostname"
    echo "$link_xhttp_udp_tls_cdn_443" >/usr/local/etc/xray/link_xhttp_udp_tls_cdn_443.txt
    red "🚀【 xhttp_udp_tls_cdn_443 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_xhttp_udp_tls_cdn_443${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/link_xhttp_udp_tls_cdn_443.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"        
    }
    # hysteria2 节点信息
    link_hysteria2() {
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    link_hysteria2="hysteria2://$all_password@$vps_ipv4:$hysteria2_port?security=tls&alpn=h3&insecure=1&sni=www.bing.com#hy2-$hostname"
    echo "$link_hysteria2" >/etc/hysteria/link_hysteria2.txt
    red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$link_hysteria2${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/hysteria/link_hysteria2.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    }
    if [ -d "/etc/hysteria/" ]; then    
    link_hysteria2            # 显示hy2链接
    fi
    if [ -d "/usr/local/etc/xray/" ]; then
    link_xhttp_tcp_reality
    link_vless_xtls_relity
    link_xhttp_tcp_tls
    link_xhttp_udp_tls
    link_xhttp_huiyuan_cf_80
    link_xhttp_huiyuan_cf_443
    link_xhttp_tcp_cdn_80
    link_xhttp_udp_tls_cdn_443
    fi
    rm -rf /usr/local/etc/xray/jhdy.txt
    rm -rf /usr/local/etc/xray/sing_box_client.json
    rm -rf /usr/local/etc/xray/clash_meta_client.yaml
    sing_box_clash_meta         # sing-box订阅 与 clash_meta订阅
    cat /etc/hysteria/link_hysteria2.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_tcp_reality.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_vless_xtls_relity.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_tcp_tls.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_udp_tls.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_huiyuan_cf_80.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_huiyuan_cf_443.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_tcp_cdn_80.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    cat /usr/local/etc/xray/link_xhttp_udp_tls_cdn_443.txt 2>/dev/null >>/usr/local/etc/xray/jhdy.txt
    baseurl=$(base64 -w 0 </usr/local/etc/xray/jhdy.txt 2>/dev/null)
    v2sub=$(cat /usr/local/etc/xray/jhdy.txt 2>/dev/null)
    echo "$v2sub" >/usr/local/etc/xray/jh_sub.txt
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀【 四合一聚合订阅 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、Karing】"
    echo -e "${yellow}$baseurl${plain}"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    if [ -f "/usr/local/etc/xray/good_gitlab.yes" ]; then
        gitlabsubgo     # 同步gitlab
        clsbshow        # 显示gitlab的link
    fi
}
# sing-box订阅 与 clash_meta订阅
sing_box_clash_meta(){
read_info
cat >/usr/local/etc/xray/sing_box_client.json <<EOF
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
        "server": "8.8.8.8",
        "type": "tls",
        "detour": "select"
        },
        {
        "tag": "localdns",
        "server": "223.5.5.5",
        "type": "h3",
        "detour": "direct"
        },
      {
        "type": "fakeip",
        "tag": "fakeip",
        "inet4_range": "198.18.0.0/15",
        "inet6_range": "fc00::/18"
      }
        ],
    "rules": [
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
        "server": "fakeip"
      }
    ],
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
        "vless-xtls-reality-$hostname"
      ]
    },
    {
        "type": "hysteria2",
        "tag": "hy2-$hostname",
        "server": "$vps_ipv4",
        "server_port": $hysteria2_port,
        "password": "$all_password",
        "tls": {
            "enabled": true,
            "server_name": "www.bing.com",
            "insecure": false,
            "alpn": [
                "h3"
            ]
        }
    },
     {
      "type": "vless",
      "tag": "vless-xtls-reality-$hostname",
      "server": "$vps_ipv4",
      "server_port": $vless_xtls_relity_port,
      "uuid": "$xray_uudi",
      "packet_encoding": "xudp",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$reality_url",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
      "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$xray_shortIds"
        }
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
        "vless-xtls-reality-$hostname"
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
    "default_domain_resolver": "proxydns",
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
cat >/usr/local/etc/xray/clash_meta_client.yaml <<EOF
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
  server: $vps_ipv4                          
  port: $hysteria2_port                              
  password: $all_password
  sni: www.bing.com
  alpn:
    - h3                               
  skip-cert-verify: false
  fast-open: true

- name: vless-reality-vision-$hostname               
  type: vless
  server: $vps_ipv4
  port: $vless_xtls_relity_port                                
  uuid: $xray_uudi   
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: $reality_url                 
  reality-opts: 
    public-key: $public_key
    short-id: $xray_shortIds                  
  client-fingerprint: chrome

proxy-groups
    
- name: 🌍选择代理节点
  type: select
  proxies:                                      
    - 自动选择
    - DIRECT
    - hysteria2-$hostname
    - vless-reality-vision-$hostname

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:                             
    - hysteria2-$hostname
    - vless-reality-vision-$hostname

rules:
  - DOMAIN-SUFFIX,googleapis.cn,🌍选择代理节点
  - DOMAIN-SUFFIX,xn--ngstr-lra8j.com,🌍选择代理节点
  - DOMAIN-SUFFIX,xn--ngstr-cn-8za9o.com,🌍选择代理节点

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


# 卸载xray
xray_del(){
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
}
# 卸载hy2
hysteria2_del(){
    bash <(curl -fsSL https://get.hy2.sh/) --remove
}
# 更新xray
xray_up(){
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
    $(systemctl restart xray)   # 重启xray
}
# 更新hy2
hysteria2_up(){
    bash <(curl -fsSL https://get.hy2.sh/)
    $(systemctl restart hysteria-server.service)
}
# 更新脚本
bash_up() {
    xray_hy2_kuaijie # 更新菜单
    curl -sL https://raw.githubusercontent.com/yggmsh/yggmsh123/main/xray_hy2_v | awk -F "更新内容" '{print $1}' | head -n 1 >/root/v
    green " xray-hy2 安装脚本升级成功" && sleep 5 && xray-hy2
}
# 生成快捷方式
xray_hy2_kuaijie() {
    $(rm -rf /usr/bin/xray-hy2)
    curl -L -o /usr/bin/xray-hy2 -# --retry 2 --insecure https://raw.githubusercontent.com/yggmsh/yggmsh123/main/xray-hy2.sh
    chmod +x /usr/bin/xray-hy2
}
# 查看xray运行状态
xray_zhuangtai(){
    green "1.查看xray服务是否启动,按ctrl+c结束运行"
    green "2.查看xray启动详细信息,按ctrl+c结束运行"
    green "3.重启xray服务"
    green "0.返回主菜单"
    readp "请选择【0-3】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ]; then
        systemctl status xray
    elif [ -z "$menu" ] || [ "$menu" = "2" ]; then    
        journalctl --no-pager -e -u xray
    elif [ -z "$menu" ] || [ "$menu" = "3" ]; then
        systemctl restart xray
        xray_zhuangtai
    else
        xray-hy2
    fi
}
# 查看和ysteria2运行状态
hy2_zhuangtai(){
    green "1.查看hy2服务是否启动,按ctrl+c结束运行"
    green "2.查看hy2启动详细信息,按ctrl+c结束运行"
    green "3.重启hy2服务"
    green "0.返回主菜单"
    readp "请选择【0-3】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ]; then
        systemctl status hysteria-server.service
    elif [ -z "$menu" ] || [ "$menu" = "2" ]; then    
        journalctl --no-pager -e -u hysteria-server.service
    elif [ -z "$menu" ] || [ "$menu" = "3" ]; then
        systemctl restart hysteria-server.service
        hy2_zhuangtai
    else
        xray-hy2
    fi
}
# 开启bbr
bbr_jiaoben() {
    if [[ $vi =~ lxc|openvz ]]; then
        yellow "当前VPS的架构为 $vi，不支持开启原版BBR加速" && sleep 2 && exit
    else
        green "点击任意键，即可开启BBR加速，ctrl+c退出"
        bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
    fi
}
# 安装cf-warp
cfwarp() {
    #bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
    bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}
# 设置gitlab功能
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
            rm -rf /usr/local/etc/xray/gitlab_ml_ml
        else
            gitlab_ml=":${gitlabml}"
            git_sk="${gitlabml}"
            echo "${gitlab_ml}" >/usr/local/etc/xray/gitlab_ml_ml
        fi
        echo "$token" >/usr/local/etc/xray/gitlabtoken.txt
        rm -rf /usr/local/etc/xray/.git
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
            cat >/usr/local/etc/xray/gitpush.sh <<EOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for 'https://$(cat /usr/local/etc/xray/gitlabtoken.txt 2>/dev/null)@gitlab.com':"
send "$(cat /usr/local/etc/xray/gitlabtoken.txt 2>/dev/null)\r"
interact
EOF
            chmod +x gitpush.sh
            ./gitpush.sh "git push -f origin main${gitlab_ml}" cat /usr/local/etc/xray/gitlabtoken.txt >/dev/null 2>&1
            echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sing_box_client.json/raw?ref=${git_sk}&private_token=${token}" >/usr/local/etc/xray/sing_box_gitlab.txt
            echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clash_meta_client.yaml/raw?ref=${git_sk}&private_token=${token}" >/usr/local/etc/xray/clash_meta_gitlab.txt
            echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh_sub.txt/raw?ref=${git_sk}&private_token=${token}" >/usr/local/etc/xray/jh_sub_gitlab.txt
            clsbshow # gitlab更新节点显示
            echo "订阅成功" >/usr/local/etc/xray/good_gitlab.yes
        else
            yellow "设置Gitlab订阅链接失败，请反馈"
        fi
        cd
    else
        gitlab_menu # 返回菜单
    fi
}
# 显示gitlab订阅的信息link
clsbshow() {

    green "当前Sing-box节点已更新并推送"
    green "Sing-box订阅链接如下："
    blue "$(cat /usr/local/etc/xray/sing_box_gitlab.txt 2>/dev/null)"
    echo
    green "Sing-box订阅链接二维码如下："
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/sing_box_gitlab.txt 2>/dev/null)"
    echo
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    green "当前mihomo节点配置已更新并推送"
    green "mihomo订阅链接如下："
    blue "$(cat /usr/local/etc/xray/clash_meta_gitlab.txt 2>/dev/null)"
    echo
    green "mihomo订阅链接二维码如下："
    qrencode -o - -t ANSIUTF8 "$(cat /usr/local/etc/xray/clash_meta_gitlab.txt 2>/dev/null)"
    echo
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    green "当前聚合订阅节点配置已更新并推送"
    green "订阅链接如下："
    blue "$(cat /usr/local/etc/xray/jh_sub_gitlab.txt 2>/dev/null)"
    echo
    yellow "可以在网页上输入订阅链接查看配置内容，如果无配置内容，请自检Gitlab相关设置并重置"
    echo
}
# 同步推送gitlab
gitlabsubgo() {
    cd /usr/local/etc/xray/
    if [[ $(ls -a | grep '^\.git$') ]]; then
        if [ -f /usr/local/etc/xray/gitlab_ml_ml ]; then
            gitlab_ml=$(cat /usr/local/etc/xray/gitlab_ml_ml)
        fi
        git rm --cached sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
        git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
        git add sing_box_client.json clash_meta_client.yaml jh_sub.txt >/dev/null 2>&1
        git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
        chmod +x gitpush.sh
        ./gitpush.sh "git push -f origin main${gitlab_ml}" cat /usr/local/etc/xray/gitlabtoken.txt >/dev/null 2>&1
        clsbshow # gitlab更新节点显示
    else
        yellow "未设置Gitlab订阅链接"
    fi
    cd
}
# gitlab菜单
gitlab_menu(){
    green "1.设置Gitlab订阅"
    green "2.同步Gitlab订阅"
    green "0.返回主菜单"
    readp "请选择【0-2】：" menu
    if [ -z "$menu" ] || [ "$menu" = "1" ]; then
        gitlabsub           # 设置Gitlab订阅
    elif [ -z "$menu" ] || [ "$menu" = "2" ]; then
        gitlabsubgo         # 同步Gitlab订阅 
    else
        xray-hy2
    fi
}

echo "bash <(wget -qO- https://raw.githubusercontent.com/yggmsh/yggmsh123/main/xray-hy2.sh)"
echo ""
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. xray与hy2官方联合脚本" 
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 2. 升级最新xray正式版"
green " 3. 升级最新hy2正式版"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 4. 更新xray与hy2联合脚本"
white "----------------------------------------------------------------------------------"
green " 5. 显示xray与hy2配置link信息"
green " 6. Gitlab订阅设置与推送"
white "----------------------------------------------------------------------------------"
green " 7. 查看xray运行状态"
green " 8. 查看hysteria2运行状态"
white "----------------------------------------------------------------------------------" 
green " 9. 一键BBR+加速"
white "----------------------------------------------------------------------------------"
green "10. 管理 Warp 查看Netflix/ChatGPT解锁情况"
green "11. 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】没弄明白,还不能用"
white "----------------------------------------------------------------------------------"
white "----------------------------------------------------------------------------------"
white "----------------------------------------------------------------------------------"
white "----------------------------------------------------------------------------------"
green "20. 删除xray脚本"
green "30. 删除hysteria2脚本"
green " 0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "快捷启动为:xray-hy2"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "VPS状态如下："
echo -e "系统:$blue$op$plain  \c"
echo -e "内核:$blue$version$plain  \c"
echo -e "处理器:$blue$cpu$plain  \c"
echo -e "虚拟化:$blue$vi$plain  \c"
echo -e "BBR算法:$blue$bbr$plain"
vps_ip # 获取本地vps的真实ip
echo -e "本地IPV4地址：${blue}${vps_ipv4}$plain    本地IPV6地址：${blue}${vps_ipv6}$plain"

echo $vps_ipv4 >/usr/local/etc/xray/vps_ipv4.txt
echo $vps_ipv6 >/usr/local/etc/xray/vps_ipv6.txt
warp_ip # 获取warp的ip
echo -e "WARP IPV4地址：${blue}${warp_ipv4}$plain    WARP IPV6地址：${blue}${warp_ipv6}$plain"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
xray_hy2_kuaijie       #创建快捷方式
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "请输入数字【0-30】:" Input
case "$Input" in  
 1 ) xray_hy2_setup;;                   # xray与hy2官方安装脚本      
 2 ) xray_up;;                          # 升级最新xray正式版
 3 ) hysteria2_up;;                     # 升级最新hy2正式版
 4 ) bash_up;;                          # 更新xray与hy2联合脚本
 5 ) xray_hy2_link;;                    # 显示xray与hy2配置link信息
 6 ) gitlab_menu;;                      # Gitlab订阅设置与推送
 7 ) xray_zhuangtai;;                   # 查看xray运行状态
 8 ) hy2_zhuangtai;;                    # 查看hysteria2运行状态
 9 ) bbr_jiaoben;;                      # 一键BBR+加速
 10) cfwarp;;                           # 管理 Warp 查看Netflix/ChatGPT解锁情况
 11) inssbwpph;;                        # 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】没弄明白,还不能用
 20) xray_del;;                         # 删除xray脚本
 30) hysteria2_del;;                    # 删除hysteria2脚本
 * ) exit 
esac
