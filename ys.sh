#!/bin/bash
export LANG=en_US.UTF-8 #声明编码格式
#颜色定义
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
#颜色定义
#用户输入 和默认输入内容
readp() {
    local prompt_text="$1"
    local var_name="$2"
    local default_val="${3:-}"
    local user_input # 用于临时存储用户的输入

    local current_prompt_with_default
    if [ -n "$default_val" ]; then
        current_prompt_with_default="$(yellow "$prompt_text (回车默认: $default_val)")"
    else
        current_prompt_with_default="$(yellow "$prompt_text")"
    fi

    # 不使用 -i 选项，让用户直接输入
    read -r -p "$current_prompt_with_default: " user_input

    # 如果用户没有输入（直接按回车），则使用默认值
    if [ -z "$user_input" ]; then
        eval "$var_name=\"\$default_val\"" # 将默认值赋给目标变量
    else
        eval "$var_name=\"\$user_input\"" # 将用户输入赋给目标变量
    fi
}

jianche-system() { #检测root模式与linux发行版系统是否支持

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
}

jianche-system-gujia() { #这行命令检测系统构架,看是不是支持
    if [[ $(echo "$op" | grep -i -E "arch") ]]; then
        red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
    fi
    version=$(uname -r | cut -d "-" -f1)
    [[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
    case $(uname -m) in
    armv7l) cpu=armv7 ;;
    aarch64) cpu=arm64 ;;
    x86_64) cpu=amd64 ;;
    *) red "目前脚本不支持$(uname -m)架构" && exit ;;
    esac
}

jianche-bbr() { #检测bbr
    if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
        bbr=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
    elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
        bbr="Openvz版bbr-plus"
    else
        bbr="Openvz/Lxc"
    fi
}

bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "当前VPS的架构为 $vi，不支持开启原版BBR加速" && sleep 2 && exit 
else
green "点击任意键，即可开启BBR加速，ctrl+c退出"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}

acme(){
bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
}

cfwarp(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}

inssbwpph(){  # 待修改
sbactive
ins(){
if [ ! -e /etc/ys-ygy/sbwpph ]; then
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
esac
curl -L -o /etc/ys-ygy/sbwpph -# --retry 2 --insecure https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sbwpph_$cpu
chmod +x /etc/ys-ygy/sbwpph
fi
if [[ -n $(ps -e | grep sbwpph) ]]; then
kill -15 $(cat /etc/ys-ygy/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
fi
v4v6
if [[ -n $v4 ]]; then
sw46=4
else
red "IPV4不存在，确保安装过WARP-IPV4模式"
sw46=6
fi
echo
readp "设置WARP-plus-Socks5端口（回车跳过端口默认40000）：" port
if [[ -z $port ]]; then
port=40000
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] 
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") && -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义端口:" port
done
fi
s5port=$(sed 's://.*::g' /etc/ys-ygy/sb.json | jq -r '.outbounds[] | select(.type == "socks") | .server_port')
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sed -i "127s/$s5port/$port/g" /etc/ys-ygy/sb10.json
sed -i "150s/$s5port/$port/g" /etc/ys-ygy/sb11.json
rm -rf /etc/ys-ygy/sb.json
cp /etc/ys-ygy/sb${num}.json /etc/ys-ygy/sb.json
restartsb
}
unins(){
kill -15 $(cat /etc/ys-ygy/sbwpphid.log 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/ys-ygy/sbwpph.log /etc/ys-ygy/sbwpphid.log
crontab -l > /tmp/crontab.tmp
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
nohup setsid /etc/ys-ygy/sbwpph -b 127.0.0.1:$port --gool -$sw46 >/dev/null 2>&1 & echo "$!" > /etc/ys-ygy/sbwpphid.log
green "申请IP中……请稍等……" && sleep 20
resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP获取失败" && unins && exit
else
echo "/etc/ys-ygy/sbwpph -b 127.0.0.1:$port --gool -$sw46 >/dev/null 2>&1" > /etc/ys-ygy/sbwpph.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot /bin/bash -c "nohup setsid $(cat /etc/ys-ygy/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/ys-ygy/sbwpphid.log"' >> /tmp/crontab.tmp
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
nohup setsid /etc/ys-ygy/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 >/dev/null 2>&1 & echo "$!" > /etc/ys-ygy/sbwpphid.log
green "申请IP中……请稍等……" && sleep 20
resv1=$(curl -s --socks5 localhost:$port icanhazip.com)
resv2=$(curl -sx socks5h://localhost:$port icanhazip.com)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP获取失败，尝试换个国家地区吧" && unins && exit
else
echo "/etc/ys-ygy/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 >/dev/null 2>&1" > /etc/ys-ygy/sbwpph.log
crontab -l > /tmp/crontab.tmp
sed -i '/sbwpphid.log/d' /tmp/crontab.tmp
echo '@reboot /bin/bash -c "nohup setsid $(cat /etc/ys-ygy/sbwpph.log 2>/dev/null) & pid=\$! && echo \$pid > /etc/ys-ygy/sbwpphid.log"' >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
green "WARP-plus-Socks5的IP获取成功，可进行Socks5代理分流"
fi
elif [ "$menu" = "3" ]; then
unins && green "已停止WARP-plus-Socks5代理功能"
else
sb
fi
}

gongju-install() { #检测安装脚本所需要的工具,并安装各种工具
    if [ ! -f sbyg_update ]; then
        green "首次安装脚本必要的依赖……"
        if [[ x"${release}" == x"alpine" ]]; then
            apk update
            apk add wget curl tar jq tzdata openssl expect git socat iproute2 iptables grep coreutils util-linux dcron
            apk add virt-what
            apk add qrencode
        else
            if [[ $release = Centos && ${vsid} =~ 8 ]]; then
                cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/
                curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
                sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
                sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
                yum clean all && yum makecache
                cd
            fi
            if [ -x "$(command -v apt-get)" ]; then
                apt update -y
                apt install jq cron socat iptables-persistent coreutils util-linux -y
            elif [ -x "$(command -v yum)" ]; then
                yum update -y && yum install epel-release -y
                yum install jq socat coreutils util-linux -y
            elif [ -x "$(command -v dnf)" ]; then
                dnf update -y
                dnf install jq socat coreutils util-linux -y
            fi
            if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
                if [ -x "$(command -v yum)" ]; then
                    yum install -y cronie iptables-services
                elif [ -x "$(command -v dnf)" ]; then
                    dnf install -y cronie iptables-services
                fi
                systemctl enable iptables >/dev/null 2>&1
                systemctl start iptables >/dev/null 2>&1
            fi
            if [[ -z $vi ]]; then
                apt install iputils-ping iproute2 systemctl -y
            fi

            packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
            inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
            for i in "${!packages[@]}"; do
                package="${packages[$i]}"
                inspackage="${inspackages[$i]}"
                if ! command -v "$package" &>/dev/null; then
                    if [ -x "$(command -v apt-get)" ]; then
                        apt-get install -y "$inspackage"
                    elif [ -x "$(command -v yum)" ]; then
                        yum install -y "$inspackage"
                    elif [ -x "$(command -v dnf)" ]; then
                        dnf install -y "$inspackage"
                    fi
                fi
            done
        fi
        touch sbyg_update # 标记创建一个名为 sbyg_update 的空文件。这个文件的存在将作为下次脚本启动时跳过依赖安装步骤的标记。
    fi
}

jianche-openvz() { # 检查并尝试为 OpenVZ 虚拟化环境启用 TUN/TAP 支持。
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
}

warpwg() {  #获取wireguard 的信息
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

changewg() {     #带修改
  [[ "$sbnh" == "1.10" ]] && num=10 || num=11
  if [[ "$sbnh" == "1.10" ]]; then
    wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .local_address[1] | split("/")[0]')
    wgprkey=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .private_key')
    wgres=$(sed -n '165s/.*\[\(.*\)\].*/\1/p' /etc/s-box/sb.json)
    wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server')
    wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.outbounds[] | select(.type == "wireguard") | .server_port')
  else
    wgipv6=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .address[1] | split("/")[0]')
    wgprkey=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .private_key')
    wgres=$(sed -n '125s/.*\[\(.*\)\].*/\1/p' /etc/s-box/sb.json)
    wgip=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .peers[].address')
    wgpo=$(sed 's://.*::g' /etc/s-box/sb.json | jq -r '.endpoints[] | .peers[].port')
  fi
  echo
  green "当前warp-wireguard可更换的参数如下："
  green "Private_key私钥：$wgprkey"
  green "IPV6地址：$wgipv6"
  green "Reserved值：$wgres"
  green "对端IP：$wgip:$wgpo"
  echo
  yellow "1：更换warp-wireguard账户"
  yellow "2：自动优选warp-wireguard对端IP"
  yellow "0：返回上层"
  readp "请选择【0-2】：" menu
  if [ "$menu" = "1" ]; then
    green "最新随机生成普通warp-wireguard账户如下"
    warpwg
    echo
    readp "输入自定义Private_key：" menu
    sed -i "163s#$wgprkey#$menu#g" /etc/s-box/sb10.json
    sed -i "115s#$wgprkey#$menu#g" /etc/s-box/sb11.json
    readp "输入自定义IPV6地址：" menu
    sed -i "161s/$wgipv6/$menu/g" /etc/s-box/sb10.json
    sed -i "113s/$wgipv6/$menu/g" /etc/s-box/sb11.json
    readp "输入自定义Reserved值 (格式：数字,数字,数字)，如无值则回车跳过：" menu
    if [ -z "$menu" ]; then
      menu=0,0,0
    fi
    sed -i "165s/$wgres/$menu/g" /etc/s-box/sb10.json
    sed -i "125s/$wgres/$menu/g" /etc/s-box/sb11.json
    rm -rf /etc/s-box/sb.json
    cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
    restartsb
    green "设置结束"
    green "可以先在选项5-1或5-2使用完整域名分流：cloudflare.com"
    green "然后使用任意节点打开网页https://cloudflare.com/cdn-cgi/trace，查看当前WARP账户类型"
  elif [ "$menu" = "2" ]; then
    green "请稍等……更新中……"
    if [ -z $(curl -s4m5 icanhazip.com -k) ]; then
      curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n2\n") | bash endip.sh >/dev/null 2>&1
      nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
      nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F "]" '{print $2}' | tr -d ':')
    else
      curl -sSL https://gitlab.com/rwkgyg/CFwarp/raw/main/point/endip.sh -o endip.sh && chmod +x endip.sh && (echo -e "1\n1\n") | bash endip.sh >/dev/null 2>&1
      nwgip=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $1}')
      nwgpo=$(awk -F, 'NR==2 {print $1}' /root/result.csv 2>/dev/null | awk -F: '{print $2}')
    fi
    a=$(cat /root/result.csv 2>/dev/null | awk -F, '$3!="timeout ms" {print} ' | sed -n '2p' | awk -F ',' '{print $2}')
    if [[ -z $a || $a = "100.00%" ]]; then
      if [[ -z $(curl -s4m5 icanhazip.com -k) ]]; then
        nwgip=2606:4700:d0::a29f:c001
        nwgpo=2408
      else
        nwgip=162.159.192.1
        nwgpo=2408
      fi
    fi
    sed -i "157s#$wgip#$nwgip#g" /etc/s-box/sb10.json
    sed -i "158s#$wgpo#$nwgpo#g" /etc/s-box/sb10.json
    sed -i "118s#$wgip#$nwgip#g" /etc/s-box/sb11.json
    sed -i "119s#$wgpo#$nwgpo#g" /etc/s-box/sb11.json
    rm -rf /etc/s-box/sb.json
    cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
    restartsb
    rm -rf /root/result.csv /root/endip.sh
    echo
    green "优选完毕，当前使用的对端IP：$nwgip:$nwgpo"
  else
    changeserv
  fi
}
select_network_ip() { # 检测vps的所有ip,并确认vps的主IP 变量为*** address_ip  ***
    local v4=""
    local v6=""
    local -A LOCAL_IPV4_IPS_INFO
    local -A LOCAL_IPV6_IPS_INFO
    local IPV4_COUNT=0
    local IPV6_COUNT=0
    local DEFAULT_INTERFACES=("eth0" "ens33" "enp0s3" "eno1")
    local DEFAULT_IPV4_ACCESS_IP=""
    local DEFAULT_IPV6_ACCESS_IP=""
    local LOCAL_IPV4_TEMP_FILE=$(mktemp)
    local LOCAL_IPV6_TEMP_FILE=$(mktemp)

    # 确保函数退出时清理临时文件
    trap "rm -f \"$LOCAL_IPV4_TEMP_FILE\" \"$LOCAL_IPV6_TEMP_FILE\"" EXIT

    # 获取公网 IPv4 和 IPv6 地址的内部函数
    v4v6_inner() {
        v4=$(curl -s4m5 icanhazip.com -k)
        v6=$(curl -s6m5 icanhazip.com -k)
    }

    # 用于检测特定IP地址是否能访问公网的内部辅助函数
    check_public_access_inner() {
        local ip_to_check=$1
        local ip_version=$2
        local public_dns=""

        if [ "$ip_version" -eq 4 ]; then
            public_dns="8.8.8.8"
            if timeout 2 ping -c 1 -W 2 -4 -I "$ip_to_check" "$public_dns" &>/dev/null; then
                echo "是"
            else
                echo "否"
            fi
        elif [ "$ip_version" -eq 6 ]; then
            public_dns="2001:4860:4860::8888"
            if timeout 2 ping -c 1 -W 2 -6 -I "$ip_to_check" "$public_dns" &>/dev/null; then
                echo "是"
            else
                echo "否"
            fi
        else
            echo "未知"
        fi
    }

    # 用于获取IP地址ping延迟的内部辅助函数
    get_ping_latency_inner() {
        local ip_to_ping=$1
        local ip_version=$2
        local public_dns=""
        local ping_output=""
        local latency=""

        if [ "$ip_version" -eq 4 ]; then
            public_dns="8.8.8.8"
            ping_output=$(timeout 2 ping -c 1 -W 1 -4 -I "$ip_to_ping" "$public_dns" 2>/dev/null)
        elif [ "$ip_version" -eq 6 ]; then
            public_dns="2001:4860:4860::8888"
            ping_output=$(timeout 2 ping -c 1 -W 1 -6 -I "$ip_to_ping" "$public_dns" 2>/dev/null)
        fi

        if [ -n "$ping_output" ]; then
            latency=$(echo "$ping_output" | awk -F'/' '/rtt min\/avg\/max/{print $5}' | cut -d'.' -f1) # 提取平均延迟并取整
            echo "${latency:-9999}"                                                                    # 如果延迟为空，给一个大值
        else
            echo "9999" # 无法ping通或超时，给一个非常大的延迟值
        fi
    }

    echo "=== Linux 系统 IP 地址检测 ==="
    echo ""

    # 调用函数获取公网 IP 地址
    v4v6_inner

    echo "--- 本地 IP 地址检测 ---"

    # 使用 'ip' 命令获取本地 IP 地址 (推荐)
    if command -v ip &>/dev/null; then
        echo "通过 'ip address show' 获取 IP 地址:"

        # 获取所有 IPv4 地址，并检测其公网可访问性
        echo "IPv4 地址:"
        ip -o -4 addr show | while read -r _ interface _ ip_addr_cidr _; do
            local ip_addr=$(echo "$ip_addr_cidr" | cut -d'/' -f1)
            local access=$(check_public_access_inner "$ip_addr" 4)
            echo "  接口: $interface, 地址: $ip_addr, 公网可访问: **$access**"
            echo "$ip_addr,$access" >>"$LOCAL_IPV4_TEMP_FILE" # 将 IP 和可访问性写入临时文件

            # 检查是否是默认网卡且可访问公网
            for default_iface in "${DEFAULT_INTERFACES[@]}"; do
                if [[ "$interface" == *"$default_iface"* && "$access" == "是" ]]; then
                    DEFAULT_IPV4_ACCESS_IP="$ip_addr"
                    break
                fi
            done
        done
        if [ ! -s "$LOCAL_IPV4_TEMP_FILE" ]; then # 检查文件是否为空
            echo "未找到本地 IPv4 地址。"
        fi

        echo ""
        # 获取所有 IPv6 地址，并检测其公网可访问性
        echo "IPv6 地址:"
        ip -o -6 addr show | while read -r _ interface _ ip_addr_cidr _; do
            local ip_addr=$(echo "$ip_addr_cidr" | cut -d'/' -f1)
            # 过滤掉 link-local 地址 (fe80::/10)
            if [[ "$ip_addr" != fe80:* ]]; then
                local access=$(check_public_access_inner "$ip_addr" 6)
                echo "  接口: $interface, 地址: $ip_addr, 公网可访问: **$access**"
                echo "$ip_addr,$access" >>"$LOCAL_IPV6_TEMP_FILE" # 将 IP 和可访问性写入临时文件

                # 检查是否是默认网卡且可访问公网
                for default_iface in "${DEFAULT_INTERFACES[@]}"; do
                    if [[ "$interface" == *"$default_iface"* && "$access" == "是" ]]; then
                        DEFAULT_IPV6_ACCESS_IP="$ip_addr"
                        break
                    fi
                done
            fi
        done
        if [ ! -s "$LOCAL_IPV6_TEMP_FILE" ]; then
            echo "未找到本地 IPv6 地址。"
        fi
    else
        echo "警告: 'ip' 命令未找到。请确保 iproute2 包已安装。"
        echo "尝试使用 'ifconfig' 获取 IP 地址 (如果可用)..."
        if command -v ifconfig &>/dev/null; then
            echo "通过 'ifconfig' 获取 IP 地址:"
            echo "IPv4 地址:"
            ifconfig | awk '/inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}/ {print $2, $1}' | while read -r ip_addr interface; do
                local access=$(check_public_access_inner "$ip_addr" 4)
                echo "  接口: $interface, 地址: $ip_addr, 公网可访问: **$access**"
                echo "$ip_addr,$access" >>"$LOCAL_IPV4_TEMP_FILE"
                for default_iface in "${DEFAULT_INTERFACES[@]}"; do
                    if [[ "$interface" == *"$default_iface"* && "$access" == "是" ]]; then
                        DEFAULT_IPV4_ACCESS_IP="$ip_addr"
                        break
                    fi
                done
            done
            if [ ! -s "$LOCAL_IPV4_TEMP_FILE" ]; then
                echo "未找到本地 IPv4 地址。"
            fi

            echo ""
            echo "IPv6 地址:"
            ifconfig | awk '/inet6 / {print $2, $1}' | while read -r ip_addr interface; do
                if [[ "$ip_addr" != fe80:* ]]; then # 过滤link-local
                    local access=$(check_public_access_inner "$ip_addr" 6)
                    echo "  接口: $interface, 地址: $ip_addr, 公网可访问: **$access**"
                    echo "$ip_addr,$access" >>"$LOCAL_IPV6_TEMP_FILE"
                    for default_iface in "${DEFAULT_INTERFACES[@]}"; do
                        if [[ "$interface" == *"$default_iface"* && "$access" == "是" ]]; then
                            DEFAULT_IPV6_ACCESS_IP="$ip_addr"
                            break
                        fi
                    done
                fi
            done
            if [ ! -s "$LOCAL_IPV6_TEMP_FILE" ]; then
                echo "未找到本地 IPv6 地址。"
            fi
        else
            echo "警告: 'ifconfig' 命令也未找到。无法获取本地 IP 地址。"
        fi
    fi

    echo "---"

    echo "--- 公网 IP 地址检测 (通过外部服务) ---"
    echo "尝试获取当前系统出口公网 IP 地址 (通过 ifconfig.me / icanhazip.com)"

    local PUBLIC_IPV4_ACCESSIBLE="否"
    local PUBLIC_IPV6_ACCESSIBLE="否"

    if [ -n "$v4" ]; then
        echo "出口公网 IPv4 地址: **$v4**"
        if ping -c 1 -W 2 -4 8.8.8.8 &>/dev/null; then
            echo "  可访问外部网络: **是**"
            PUBLIC_IPV4_ACCESSIBLE="是"
        else
            echo "  可访问外部网络: 否 (可能是防火墙或网络问题)"
        fi
    else
        echo "无法获取出口公网 IPv4 地址。"
    fi

    echo ""

    if [ -n "$v6" ]; then
        echo "出口公网 IPv6 地址: **$v6**"
        if ping -c 1 -W 2 -6 2001:4860:4860::8888 &>/dev/null; then
            echo "  可访问外部网络: **是**"
            PUBLIC_IPV6_ACCESSIBLE="是"
        else
            echo "  可访问外部网络: 否 (可能是防火墙或网络问题)"
        fi
    else
        echo "无法获取出口公网 IPv6 地址。"
    fi

    echo ""
    echo "=== IP 地址选择 ==="

    local IPV4_CHOICES_DISPLAY=()
    local IPV6_CHOICES_DISPLAY=()
    local -A IPV4_MAP # 存储序号到实际IP的映射
    local -A IPV6_MAP # 存储序号到实际IP的映射

    # 从临时文件读取并整理可供选择的 IPv4 地址
    local current_idx=0
    while IFS=',' read -r ip_addr access; do
        current_idx=$((current_idx + 1))
        IPV4_CHOICES_DISPLAY+=("$current_idx. 本地 IPv4 ($ip_addr) - 公网可访问: $access")
        IPV4_MAP["$current_idx"]="$ip_addr"
    done <"$LOCAL_IPV4_TEMP_FILE"

    if [ "$PUBLIC_IPV4_ACCESSIBLE" == "是" ]; then
        current_idx=$((current_idx + 1))
        IPV4_CHOICES_DISPLAY+=("$current_idx. 出口公网 IPv4 ($v4) - 公网可访问: 是")
        IPV4_MAP["$current_idx"]="$v4"
    fi

    # 从临时文件读取并整理可供选择的 IPv6 地址
    current_idx=0 # 重置索引
    while IFS=',' read -r ip_addr access; do
        current_idx=$((current_idx + 1))
        IPV6_CHOICES_DISPLAY+=("$current_idx. 本地 IPv6 ($ip_addr) - 公网可访问: $access")
        IPV6_MAP["$current_idx"]="$ip_addr"
    done <"$LOCAL_IPV6_TEMP_FILE"

    if [ "$PUBLIC_IPV6_ACCESSIBLE" == "是" ]; then
        current_idx=$((current_idx + 1))
        IPV6_CHOICES_DISPLAY+=("$current_idx. 出口公网 IPv6 ($v6) - 公网可访问: 是")
        IPV6_MAP["$current_idx"]="$v6"
    fi

    if [ ${#IPV4_CHOICES_DISPLAY[@]} -eq 0 ] && [ ${#IPV6_CHOICES_DISPLAY[@]} -eq 0 ]; then
        echo "没有可用的 IP 地址进行选择。"
        return 1
    fi

    echo "请选择要使用的 IP 地址类型:"
    echo "1. IPv4"
    echo "2. IPv6"
    echo "(直接回车将默认选择 IPv4 地址)" # 新增提示

    # 提示默认网卡可上公网的 IP
    if [ -n "$DEFAULT_IPV4_ACCESS_IP" ]; then
        echo "提示: 您的默认网卡 IPv4 (例如: ${DEFAULT_INTERFACES[*]}) 可访问公网的 IP 是: **$DEFAULT_IPV4_ACCESS_IP**"
    fi
    if [ -n "$DEFAULT_IPV6_ACCESS_IP" ]; then
        echo "提示: 您的默认网卡 IPv6 (例如: ${DEFAULT_INTERFACES[*]}) 可访问公网的 IP 是: **$DEFAULT_IPV6_ACCESS_IP**"
    fi

    read -p "请输入选项 (1/2): " ip_type_choice

    local selected_ip=""
    local selected_ip_version=""

    # 自动选择最快 IP 的内部函数
    auto_select_fastest_ip_inner() {
        local ip_type=$1
        local choices_map
        local public_access_ips=()
        local best_ip=""
        local min_latency=99999 # 初始一个很大的延迟值

        if [ "$ip_type" == "IPv4" ]; then
            choices_map=("${!IPV4_MAP[@]}") # 获取所有键 (序号)
            local display_array=("${IPV4_CHOICES_DISPLAY[@]}")
            local ip_version_num=4
        else # IPv6
            choices_map=("${!IPV6_MAP[@]}")
            local display_array=("${IPV6_CHOICES_DISPLAY[@]}")
            local ip_version_num=6
        fi

        # 筛选出可访问公网的 IP
        for idx_key in "${choices_map[@]}"; do
            local current_ip=""
            if [ "$ip_type" == "IPv4" ]; then
                current_ip="${IPV4_MAP[$idx_key]}"
            else
                current_ip="${IPV6_MAP[$idx_key]}"
            fi

            # 检查显示文本中是否包含 "公网可访问: 是"
            local display_text="${display_array[$((idx_key - 1))]}"
            if [[ "$display_text" == *"公网可访问: 是"* ]]; then
                public_access_ips+=("$current_ip")
            fi
        done

        if [ ${#public_access_ips[@]} -eq 0 ]; then
            echo "警告: 没有可访问公网的 ${ip_type} 地址可供自动选择。"
            return 1
        fi

        echo "正在检测可访问公网的 ${ip_type} 地址的延迟..."
        for ip_candidate in "${public_access_ips[@]}"; do
            local latency=$(get_ping_latency_inner "$ip_candidate" "$ip_version_num")
            echo "  IP: $ip_candidate, 延迟: ${latency}ms"
            if ((latency < min_latency)); then
                min_latency=$latency
                best_ip="$ip_candidate"
            fi
        done

        if [ -z "$best_ip" ] || [ "$min_latency" -eq 99999 ]; then
            echo "警告: 无法自动选择最快可访问公网的 ${ip_type} 地址。"
            return 1
        fi
        echo "自动选择的最快 ${ip_type} 地址是: **$best_ip** (延迟: ${min_latency}ms)"
        selected_ip="$best_ip"
        selected_ip_version="$ip_type"
        return 0
    }

    # 核心修改：增加默认回车选择IPv4的逻辑
    if [ -z "$ip_type_choice" ]; then # 如果用户直接回车
        echo "未选择IP类型，默认选择速度最快的IPv4地址..."
        ip_type_choice="1" # 强制设置为IPv4选择
    fi

    case $ip_type_choice in
    1)
        if [ ${#IPV4_CHOICES_DISPLAY[@]} -eq 0 ]; then
            echo "没有可用的 IPv4 地址。"
            return 1
        fi
        echo ""
        echo "可用的 IPv4 地址列表 (请选择一个序号，或直接回车自动选择速度最快的可公网访问 IP):"
        for choice_line in "${IPV4_CHOICES_DISPLAY[@]}"; do
            echo "$choice_line"
        done

        read -p "请选择一个 IPv4 地址的序号: " ipv4_index
        if [ -z "$ipv4_index" ]; then # 用户直接回车
            echo "自动选择最快 IPv4 地址..."
            auto_select_fastest_ip_inner "IPv4" || return 1 # 如果自动选择失败，则退出函数
        elif [[ "$ipv4_index" =~ ^[0-9]+$ ]] && [ "$ipv4_index" -gt 0 ] && [ "$ipv4_index" -le ${#IPV4_CHOICES_DISPLAY[@]} ]; then
            selected_ip="${IPV4_MAP[$ipv4_index]}" # 从映射中获取实际IP
            selected_ip_version="IPv4"
            echo "你选择了 IPv4 地址: $selected_ip"
        else
            echo "无效的选项。"
            return 1
        fi
        ;;
    2)
        if [ ${#IPV6_CHOICES_DISPLAY[@]} -eq 0 ]; then
            echo "没有可用的 IPv6 地址。"
            return 1
        fi
        echo ""
        echo "可用的 IPv6 地址列表 (请选择一个序号，或直接回车自动选择速度最快的可公网访问 IP):"
        for choice_line in "${IPV6_CHOICES_DISPLAY[@]}"; do
            echo "$choice_line"
        done

        read -p "请选择一个 IPv6 地址的序号: " ipv6_index
        if [ -z "$ipv6_index" ]; then # 用户直接回车
            echo "自动选择最快 IPv6 地址..."
            auto_select_fastest_ip_inner "IPv6" || return 1 # 如果自动选择失败，则退出函数
        elif [[ "$ipv6_index" =~ ^[0-9]+$ ]] && [ "$ipv6_index" -gt 0 ] && [ "$ipv6_index" -le ${#IPV6_CHOICES_DISPLAY[@]} ]; then
            selected_ip="${IPV6_MAP[$ipv6_index]}" # 从映射中获取实际IP
            selected_ip_version="IPv6"
            echo "你选择了 IPv6 地址: $selected_ip"
        else
            echo "无效的选项。"
            return 1
        fi
        ;;
    *)
        echo "无效的选项。请选择 1 或 2。"
        return 1
        ;;
    esac

    # 根据选择的IP地址类型，将其赋值给对应的全局变量
    # 注意：这里赋值给全局变量，而不是 local 变量
    if [ "$selected_ip_version" == "IPv4" ]; then
        ipv4_inter="$selected_ip"
        ipv6_inter="" # 确保另一个变量为空
        address_ip=$ipv4_inter
        echo "ipv4_inter 变量已设置为: **$ipv4_inter**"
    elif [ "$selected_ip_version" == "IPv6" ]; then
        ipv6_inter="$selected_ip"
        ipv4_inter="" # 确保另一个变量为空
        address_ip=$ipv6_inter
        echo "ipv6_inter 变量已设置为: **$ipv6_inter**"
    fi

    echo ""
    echo "=== 检测与选择完成 ==="
    echo "后续操作将使用 IP: $address_ip"
}

check_service_status() { # 检查程序服务是否成功运行
    SERVICE_NAME=$1
    echo "--- 检查 $SERVICE_NAME 服务 ---"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "$SERVICE_NAME 正在运行 (active)."
        return 0
    elif systemctl is-failed --quiet "$SERVICE_NAME"; then
        echo "$SERVICE_NAME 状态为失败 (failed)。请检查日志以获取更多信息。"
        systemctl status "$SERVICE_NAME" --no-pager
        return 1
    else
        echo "$SERVICE_NAME 未运行 (inactive/dead)。"
        systemctl status "$SERVICE_NAME" --no-pager
        return 1
    fi
}

detection() {                             # 检测mihomo与mita程序是否运行成功
    check_service_status "ys-ygy.service" # 通过check_service_status函数检测mita是否运行成功
    echo ""                               # 空行分隔
    check_service_status "mita"           # 通过check_service_status函数检测mita是否运行成功
}

ys-link-quan() { # 安装程序运行完显示的导入链接和二维码
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    hy2_link="hysteria2://$hy2_password@$address_ip:$hy2_port/?mport=$hy2_port%2C$hy2_ports&insecure=1&sni=wwww.bing.com&alpn=h3#$ys_hy2_name"
    echo "$hy2_link" >/etc/ys-ygy/txt/hy2.txt
    red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    echo -e "${yellow}$hy2_link${plain}"
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/txt/hy2.txt)"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    anytls_link="anytls://$anytls_password@$address_ip:$anytls_port/?insecure=1#$ys_anytls_name"
    echo "$anytls_link" >/etc/ys-ygy/txt/anytls.txt
    red "🚀【 anytls 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    echo -e "${yellow}$anytls_link${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/txt/anytls.txt)"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    echo "nekobox分享链接我不会,就手动选择mieru插件,手动填写吧"
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo "服务器:$address_ip"
    echo "服务器端口:$mita_port"
    echo "协议:TCP"
    echo "用户名:$mita_name"
    echo "密码:$mita_password"
    echo "$address_ip" > /etc/ys-ygy/txt/address_ip.txt
    echo "$mita_port" > /etc/ys-ygy/txt/mita_port.txt
    echo "$mita_name" > /etc/ys-ygy/txt/mita_name.txt
    echo "$mita_password" > /etc/ys-ygy/txt/mita_password.txt
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    mieru_link2="mierus://$mita_name:$mita_password@$address_ip:$mita_port?mtu=1400&profile=$mieru_name&protocol=TCP"
    echo "$mieru_link2" >/etc/ys-ygy/txt/mieru-exclave.txt
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【虎兕husi、Exclave】"
    echo -e "${yellow}$(cat /etc/ys-ygy/txt/mieru-exclave.txt)${plain}"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    vl_link="vless://$vless_reality_vision_uuid@$address_ip:$vless_reality_vision_port/?type=tcp$encryption=none&flow=xtls-rprx-vision&sni=$vless_reality_vision_url&fp=edge&security=reality&pbk=$vless_reality_vision_Public_Key&sid=$ys_short_id&packetEncoding=xudp#$ys_vless_reality_vision_name"
    echo "$vl_link" >/etc/ys-ygy/txt/ys-vless-reality-vision.txt
    red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    echo -e "${yellow}$vl_link${plain}"
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/txt/ys-vless-reality-vision.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    if [ -f "/etc/ys-ygy/jhdy.txt" ]; then
    rm "/etc/ys-ygy/jhdy.txt"
    fi
    cat /etc/ys-ygy/txt/hy2.txt 2>/dev/null >>/etc/ys-ygy/jh_sub.txt
    cat /etc/ys-ygy/txt/anytls.txt 2>/dev/null >>/etc/ys-ygy/jh_sub.txt
    cat /etc/ys-ygy/txt/ys-vless-reality-vision.txt 2>/dev/null >>/etc/ys-ygy/jh_sub.txt
    cat /etc/ys-ygy/txt/mieru-exclave.txt 2>/dev/null >>/etc/ys-ygy/jh_sub.txt

}

################################### 菜单选择显示配置的函数 ################################
ys-check() {
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    echo -e "${yellow}$(cat /etc/ys-ygy/txt/hy2.txt)${plain}"
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/txt/hy2.txt)"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    red "🚀【 anytls 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    echo -e "${yellow}$(cat /etc/ys-ygy/txt/anytls.txt)${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/txt/anytls.txt)"
    echo
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    echo -e "${yellow}$(cat /etc/ys-ygy/txt/ys-vless-reality-vision.txt)${plain}"
    echo
    echo "二维码【v2rayn、v2rayng、nekobox、虎兕husi、Exclave、小火箭shadowrocket】"
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/txt/ys-vless-reality-vision.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo
    echo "分享链接【虎兕husi、Exclave】"
    echo -e "${yellow}$(cat /etc/ys-ygy/txt/mieru-exclave.txt)${plain}"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "nekobox分享链接我不会,就手动选择mieru插件,手动填写吧"
    red "🚀【 mieru 】节点信息如下：" && sleep 2
    echo "服务器:$(cat /etc/ys-ygy/txt/address_ip.txt)"
    echo "服务器端口:$(cat /etc/ys-ygy/txt/mita_port.txt)"
    echo "协议:TCP"
    echo "用户名:$(cat /etc/ys-ygy/txt/mita_name.txt)"
    echo "密码:$(cat /etc/ys-ygy/txt/mita_password.txt)"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    gitlabsubgo
    
}
################################### 菜单选择显示配置的函数 ################################

close() { # close() 函数是一个 Shell 脚本函数，旨在禁用各种防火墙服务并开放 Linux 系统上的所有端口。
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

openyn() { #执行脚本时候,确认是否关闭防火墙的交互脚本
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

open_ports_net()(
    xxxx=$hy2_ports
    ports_hy2="${xxxx//-/:}"
    $(iptables -t nat -A PREROUTING -p udp --dport $ports_hy2 -j DNAT --to-destination :$hy2_port)
    $(ip6tables -t nat -A PREROUTING -p udp --dport $ports_hy2 -j DNAT --to-destination :$hy2_port)
    $(netfilter-persistent save)
)

################################### 菜单选择gitlab建立同步的函数 ################################
tgsbshow(){
echo
yellow "1：重置/设置Telegram机器人的Token、用户ID"
yellow "0：返回上层"
readp "请选择【0-1】：" menu
if [ "$menu" = "1" ]; then
rm -rf /etc/ys-ygy/sbtg.sh
readp "输入Telegram机器人Token: " token
telegram_token=$token
readp "输入Telegram机器人用户ID: " userid
telegram_id=$userid
echo '#!/bin/bash
export LANG=en_US.UTF-8

total_lines=$(wc -l < /etc/ys-ygy/ys-client.yaml)
half=$((total_lines / 2))
head -n $half /etc/ys-ygy/ys-client.yaml > /etc/ys-ygy/ys-client.yaml1.txt
tail -n +$((half + 1)) /etc/ys-ygy/ys-client.yaml > /etc/ys-ygy/ys-client.yaml2.txt

total_lines=$(wc -l < /etc/ys-ygy/sb-client.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/ys-ygy/sb-client.json > /etc/ys-ygy/sb-client.json1.txt
tail -n +$((quarter + 1)) /etc/ys-ygy/sb-client.json | head -n $quarter > /etc/ys-ygy/sb-client.json2.txt
tail -n +$((2 * quarter + 1)) /etc/ys-ygy/sb-client.json | head -n $quarter > /etc/ys-ygy/sb-client.json3.txt
tail -n +$((3 * quarter + 1)) /etc/ys-ygy/sb-client.json > /etc/ys-ygy/sb-client.json4.txt

m1=$(cat /etc/ys-ygy/hy2.txt 2>/dev/null)
m2=$(cat /etc/ys-ygy/anytls.txt 2>/dev/null)
m3=$(cat /etc/ys-ygy/ys-vless-reality-vision.txt 2>/dev/null)
m4=$(cat /etc/ys-ygy/mieru-exclave.txt 2>/dev/null)
m5=$(cat /etc/ys-ygy/sb-client.json1.txt 2>/dev/null)
m5_5=$(cat /etc/ys-ygy/sb-client.json2.txt 2>/dev/null)
m5_5_5=$(cat /etc/ys-ygy/sb-client.json3.txt 2>/dev/null)
m5_5_5_5=$(cat /etc/ys-ygy/sb-client.json4.txt 2>/dev/null)
m6=$(cat /etc/ys-ygy/ys-client.yaml1.txt 2>/dev/null)
m6_5=$(cat /etc/ys-ygy/ys-client.yaml2.txt 2>/dev/null)
m7=$(cat /etc/ys-ygy/sb-client_gitlab.txt 2>/dev/null)
m8=$(cat /etc/ys-ygy/ys-client_gitlab.txt 2>/dev/null)
m9=$(cat /etc/ys-ygy/jh_sub.txt 2>/dev/null)
message_text_m1=$(echo "$m1")
message_text_m2=$(echo "$m2")
message_text_m3=$(echo "$m3")
message_text_m4=$(echo "$m4")
message_text_m5=$(echo "$m5")
message_text_m5_5=$(echo "$m5_5")
message_text_m5_5_5=$(echo "$m5_5_5")
message_text_m5_5_5_5=$(echo "$m5_5_5_5")
message_text_m6=$(echo "$m6")
message_text_m6_5=$(echo "$m6_5")
message_text_m7=$(echo "$m7")
message_text_m8=$(echo "$m8")
message_text_m9=$(echo "$m9")
MODE=HTML
URL="https://api.telegram.org/bottelegram_token/sendMessage"
if [[ -f /etc/ys-ygy/hy2.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 hy2 分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m1}")
fi
if [[ -f /etc/ys-ygy/anytls.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 anytls 分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m2}")
fi
if [[ -f /etc/ys-ygy/ys-vless-reality-vision.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 vless-reality-vision 分享链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m3}")
fi
if [[ -f /etc/ys-ygy/mieru-exclave.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 mieru 分享链接 】：支持nekobox "$'"'"'\n\n'"'"'"${message_text_m4}")
fi

if [[ -f /etc/ys-ygy/sb-client_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 订阅链接 】：支持SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m7}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Sing-box 配置文件(4段) 】：支持SFA、SFW、SFI "$'"'"'\n\n'"'"'"${message_text_m5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m5_5_5}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m5_5_5_5}")
fi

if [[ -f /etc/ys-ygy/ys-client_gitlab.txt ]]; then
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 订阅链接 】：支持Clash-meta相关客户端 "$'"'"'\n\n'"'"'"${message_text_m8}")
else
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 Clash-meta 配置文件(2段) 】：支持Clash-meta相关客户端 "$'"'"'\n\n'"'"'"${message_text_m6}")
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=${message_text_m6_5}")
fi
res=$(timeout 20s curl -s -X POST $URL -d chat_id=telegram_id  -d parse_mode=${MODE} --data-urlencode "text=🚀【 四合一协议聚合订阅链接 】：支持v2rayng、nekobox "$'"'"'\n\n'"'"'"${message_text_m9}")

if [ $? == 124 ];then
echo TG_api请求超时,请检查网络是否重启完成并是否能够访问TG
fi
resSuccess=$(echo "$res" | jq -r ".ok")
if [[ $resSuccess = "true" ]]; then
echo "TG推送成功";
else
echo "TG推送失败，请检查TG机器人Token和ID";
fi
' > /etc/ys-ygy/sbtg.sh
sed -i "s/telegram_token/$telegram_token/g" /etc/ys-ygy/sbtg.sh
sed -i "s/telegram_id/$telegram_id/g" /etc/ys-ygy/sbtg.sh
green "设置完成！请确保TG机器人已处于激活状态！"
tgnotice
else
setup_gitlab
fi
}

tgnotice(){
if [[ -f /etc/ys-ygy/sbtg.sh ]]; then
green "请稍等5秒，TG机器人准备推送……"
sbshare > /dev/null 2>&1
bash /etc/ys-ygy/sbtg.sh
else
yellow "未设置TG通知功能"
fi
exit
}

##gitlab建立订阅链接
gitlabsub() {
    echo
    green "请确保Gitlab官网上已建立项目，已开启推送功能，已获取访问令牌"
    yellow "1：重置/设置Gitlab订阅链接"
    yellow "0：返回上层"
    readp "请选择【0-1】：" menu
    if [ "$menu" = "1" ]; then
        cd /etc/ys-ygy
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
            rm -rf /etc/ys-ygy/gitlab_ml_ml
        else
            gitlab_ml=":${gitlabml}"
            git_sk="${gitlabml}"
            echo "${gitlab_ml}" >/etc/ys-ygy/gitlab_ml_ml
        fi
        echo "$token" >/etc/ys-ygy/gitlabtoken.txt
        rm -rf /etc/ys-ygy/.git
        git init >/dev/null 2>&1
        git add sb-client.json ys-client.yaml jh_sub.txt >/dev/null 2>&1
        git config --global user.email "${email}" >/dev/null 2>&1
        git config --global user.name "${userid}" >/dev/null 2>&1
        git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
        branches=$(git branch)
        if [[ $branches == *master* ]]; then
            git branch -m master main >/dev/null 2>&1
        fi
        git remote add origin https://${token}@gitlab.com/${userid}/${project}.git >/dev/null 2>&1
        if [[ $(ls -a | grep '^\.git$') ]]; then
            cat >/etc/ys-ygy/gitpush.sh <<EOF
#!/usr/bin/expect
spawn bash -c "git push -f origin main${gitlab_ml}"
expect "Password for 'https://$(cat /etc/ys-ygy/gitlabtoken.txt 2>/dev/null)@gitlab.com':"
send "$(cat /etc/ys-ygy/gitlabtoken.txt 2>/dev/null)\r"
interact
EOF
chmod +x gitpush.sh
./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/ys-ygy/gitlabtoken.txt >/dev/null 2>&1
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sb-client.json/raw?ref=${git_sk}&private_token=${token}" >/etc/ys-ygy/sb-client_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/ys-client.yaml/raw?ref=${git_sk}&private_token=${token}" >/etc/ys-ygy/ys-client_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh_sub.txt/raw?ref=${git_sk}&private_token=${token}" >/etc/ys-ygy/jh_sub_gitlab.txt
clsbshow
        else
            yellow "设置Gitlab订阅链接失败，请反馈"
        fi
        cd
        else
        setup_gitlab
        fi
}

gitlabsubgo() {
    cd /etc/ys-ygy
    if [[ $(ls -a | grep '^\.git$') ]]; then
        if [ -f /etc/ys-ygy/gitlab_ml_ml ]; then
            gitlab_ml=$(cat /etc/ys-ygy/gitlab_ml_ml)
        fi
        git rm --cached sb-client.json ys-client.yaml jh_sub.txt >/dev/null 2>&1
        git commit -m "commit_rm_$(date +"%F %T")" >/dev/null 2>&1
        git add sb-client.json ys-client.yaml jh_sub.txt >/dev/null 2>&1
        git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
        chmod +x gitpush.sh
        ./gitpush.sh "git push -f origin main${gitlab_ml}" cat /etc/ys-ygy/gitlabtoken.txt >/dev/null 2>&1
        clsbshow
    else
        yellow "未设置Gitlab订阅链接"
    fi
    cd
}
################################### 菜单选择gitlab建立同步的函数 ################################

################################### 菜单选择gitlab推送同步的函数 ################################
clsbshow() {
    green "当前Sing-box节点已更新并推送"
    green "Sing-box订阅链接如下："
    blue "$(cat /etc/ys-ygy/sb-client_gitlab.txt 2>/dev/null)"
    echo
    green "Sing-box订阅链接二维码如下："
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/sb-client_gitlab.txt 2>/dev/null)"
    echo
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    green "当前mihomo节点配置已更新并推送"
    green "mihomo订阅链接如下："
    blue "$(cat /etc/ys-ygy/ys-client_gitlab.txt 2>/dev/null)"
    echo
    green "mihomo订阅链接二维码如下："
    qrencode -o - -t ANSIUTF8 "$(cat /etc/ys-ygy/ys-client_gitlab.txt 2>/dev/null)"
    echo
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    green "当前聚合订阅节点配置已更新并推送"
    green "订阅链接如下："
    blue "$(cat /etc/ys-ygy/jh_sub_gitlab.txt 2>/dev/null)"
    echo
    yellow "可以在网页上输入订阅链接查看配置内容，如果无配置内容，请自检Gitlab相关设置并重置"
    echo
}

##gitlab建立订阅链接
################################### 菜单选择gitlab推送同步的函数 ################################
##############################ys-ygy-install################ mihomo安装程序   ####################################################

ys-ygy-install() { # 安装mihomo的函数
    # --- 配置区 ---
    # GitHub 仓库信息
    OWNER="MetaCubeX"
    REPO="mihomo"

    # 自动检测当前系统的操作系统类型
    case "$(uname -s)" in
    Linux*) TARGET_TYPE="linux" ;;
    Darwin*) TARGET_TYPE="darwin" ;;
    CYGWIN* | MINGW32* | MSYS*) TARGET_TYPE="windows" ;; # 适用于 Git Bash
    *)
        echo "警告: 无法识别的操作系统类型，默认使用 linux。"
        TARGET_TYPE="linux"
        ;;
    esac

    # 自动检测当前系统的 CPU 架构
    case "$(uname -m)" in
    x86_64) TARGET_ARCH="amd64" ;;
    aarch64) TARGET_ARCH="arm64" ;;
    armv7l) TARGET_ARCH="arm32v7" ;; # 注意：mihomo可能使用arm32v7
    i386 | i686) TARGET_ARCH="386" ;;
    *)
        echo "警告: 无法识别的CPU架构，默认使用 amd64。"
        TARGET_ARCH="amd64"
        ;;
    esac

    # 文件的通用后缀（例如 'compatible'）
    # 如果你不需要兼容性版本，或者你的文件名中没有这个后缀，请改为 ""
    COMMON_FILE_SUFFIX="compatible"

    # 文件的压缩格式扩展名
    TARGET_EXTENSION="gz" # 通常是 "gz" 或 "tar.gz"

    # --- 脚本开始 ---

    echo "--- 正在检测 Mihomo 发布版本 ---"
    echo "目标操作系统: ${TARGET_TYPE}"
    echo "目标CPU架构: ${TARGET_ARCH}"
    echo "文件通用后缀: ${COMMON_FILE_SUFFIX:-无}" # 如果 COMMON_FILE_SUFFIX 为空，显示“无”
    echo "文件扩展名: ${TARGET_EXTENSION}"
    echo "-----------------------------------"

    # 检查依赖工具
    if ! command -v curl &>/dev/null; then
        echo "错误: 'curl' 未安装。请先安装 curl。"
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "错误: 'jq' 未安装。请先安装 jq (用于解析 JSON)。"
        echo "  Debian/Ubuntu: sudo apt update && sudo apt install jq"
        echo "  CentOS/RHEL: sudo yum install epel-release && sudo yum install jq"
        exit 1
    fi

    # 获取所有发布版本的 JSON 数据
    ALL_RELEASES_INFO=$(curl -sL "https://api.github.com/repos/${OWNER}/${REPO}/releases")

    if [[ -z "$ALL_RELEASES_INFO" ]]; then
        echo "错误: 无法从 GitHub API 获取发布信息。请检查网络连接或仓库详情。"
        exit 1
    fi

    # --- 查找最新正式版 ---
    echo "--- 查找最新正式版 ---"
    STABLE_RELEASE_TAG=$(echo "${ALL_RELEASES_INFO}" |
        jq -r '.[] | select(.prerelease == false) | .tag_name' | head -n 1)

    STABLE_DOWNLOAD_URL=""
    STABLE_FILENAME=""

    if [[ -n "$STABLE_RELEASE_TAG" ]]; then
        echo "  找到最新正式版标签: ${STABLE_RELEASE_TAG}"
        CLEAN_STABLE_VERSION="${STABLE_RELEASE_TAG#v}" # 移除 'v' 前缀，用于文件名

        # 构造正式版预期的文件名包含部分 (注意: 正式版文件名中有 'v')
        EXPECTED_STABLE_FILENAME_PART="${TARGET_TYPE}-${TARGET_ARCH}"
        if [[ -n "$COMMON_FILE_SUFFIX" ]]; then
            EXPECTED_STABLE_FILENAME_PART+="-${COMMON_FILE_SUFFIX}"
        fi
        EXPECTED_STABLE_FILENAME_PART+="-v${CLEAN_STABLE_VERSION}" # 正式版文件名有 'v'

        # 从最新正式版的 assets 中查找精确匹配的文件
        STABLE_DOWNLOAD_URL=$(echo "${ALL_RELEASES_INFO}" |
            jq -r --arg tag "$STABLE_RELEASE_TAG" \
                --arg part "$EXPECTED_STABLE_FILENAME_PART" \
                --arg ext "$TARGET_EXTENSION" \
                '.[] | select(.tag_name == $tag) | .assets[] |
																		           select(.name | contains("mihomo-" + $part) and endswith("." + $ext)) | .browser_download_url' | head -n 1)

        # 如果带 COMMON_FILE_SUFFIX 的精确匹配未找到，尝试不带后缀的“标准”正式版
        if [[ -z "$STABLE_DOWNLOAD_URL" && -n "$COMMON_FILE_SUFFIX" ]]; then
            echo "  警告: 未找到带后缀 '${COMMON_FILE_SUFFIX}' 的正式版精确文件名，尝试查找标准版..."
            EXPECTED_STABLE_FILENAME_PART_NO_SUFFIX="${TARGET_TYPE}-${TARGET_ARCH}-v${CLEAN_STABLE_VERSION}" # 不带后缀的模式
            STABLE_DOWNLOAD_URL=$(echo "${ALL_RELEASES_INFO}" |
                jq -r --arg tag "$STABLE_RELEASE_TAG" \
                    --arg part "$EXPECTED_STABLE_FILENAME_PART_NO_SUFFIX" \
                    --arg ext "$TARGET_EXTENSION" \
                    '.[] | select(.tag_name == $tag) | .assets[] |
																																                  select(.name | contains("mihomo-" + $part) and (contains("compatible") | not) and (contains("go") | not) and endswith("." + $ext)) | .browser_download_url' | head -n 1)
        fi

        if [[ -n "$STABLE_DOWNLOAD_URL" ]]; then
            STABLE_FILENAME=$(basename "${STABLE_DOWNLOAD_URL}")
            echo "  正式版下载链接: ${STABLE_DOWNLOAD_URL}"
            echo "  正式版文件名: ${STABLE_FILENAME}"
        else
            echo "  未找到适合 ${TARGET_TYPE}-${TARGET_ARCH} 的正式版下载 URL。"
        fi
    else
        echo "未找到任何正式版发布。"
    fi

    # --- 查找最新测试版 ---
    echo "--- 查找最新测试版 ---"
    TEST_RELEASE_TAG=$(echo "${ALL_RELEASES_INFO}" |
        jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)

    TEST_DOWNLOAD_URL=""
    TEST_FILENAME=""

    if [[ -n "$TEST_RELEASE_TAG" ]]; then
        echo "  找到最新测试版标签: ${TEST_RELEASE_TAG}"
        # 测试版文件名中不直接包含 tag_name，而是包含 'alpha' 和 commit hash。
        # 所以我们根据通用部分和 'alpha' 字符串来匹配
        EXPECTED_TEST_FILENAME_PART="${TARGET_TYPE}-${TARGET_ARCH}"
        if [[ -n "$COMMON_FILE_SUFFIX" ]]; then
            EXPECTED_TEST_FILENAME_PART+="-${COMMON_FILE_SUFFIX}"
        fi
        EXPECTED_TEST_FILENAME_PART+="-alpha" # 测试版文件名有 'alpha' 后缀

        # 从最新测试版的 assets 中查找精确匹配的文件
        TEST_DOWNLOAD_URL=$(echo "${ALL_RELEASES_INFO}" |
            jq -r --arg tag "$TEST_RELEASE_TAG" \
                --arg part "$EXPECTED_TEST_FILENAME_PART" \
                --arg ext "$TARGET_EXTENSION" \
                '.[] | select(.tag_name == $tag) | .assets[] |
																		           select(.name | contains("mihomo-" + $part) and endswith("." + $ext)) | .browser_download_url' | head -n 1)

        # 如果带 COMMON_FILE_SUFFIX 的精确匹配未找到，尝试不带后缀的“标准”测试版
        if [[ -z "$TEST_DOWNLOAD_URL" && -n "$COMMON_FILE_SUFFIX" ]]; then
            echo "  警告: 未找到带后缀 '${COMMON_FILE_SUFFIX}' 的测试版精确文件名，尝试查找标准版..."
            EXPECTED_TEST_FILENAME_PART_NO_SUFFIX="${TARGET_TYPE}-${TARGET_ARCH}-alpha" # 不带后缀的模式
            TEST_DOWNLOAD_URL=$(echo "${ALL_RELEASES_INFO}" |
                jq -r --arg tag "$TEST_RELEASE_TAG" \
                    --arg part "$EXPECTED_TEST_FILENAME_PART_NO_SUFFIX" \
                    --arg ext "$TARGET_EXTENSION" \
                    '.[] | select(.tag_name == $tag) | .assets[] |
																																                  select(.name | contains("mihomo-" + $part) and (contains("compatible") | not) and (contains("go") | not) and endswith("." + $ext)) | .browser_download_url' | head -n 1)
        fi

        if [[ -n "$TEST_DOWNLOAD_URL" ]]; then
            TEST_FILENAME=$(basename "${TEST_DOWNLOAD_URL}")
            echo "  测试版下载链接: ${TEST_DOWNLOAD_URL}"
            echo "  测试版文件名: ${TEST_FILENAME}"
        else
            echo "  未找到适合 ${TARGET_TYPE}-${TARGET_ARCH} 的测试版下载 URL。"
        fi
    else
        echo "未找到任何测试版发布。"
    fi

    echo "-----------------------------------"
    cd /etc/ys-ygy
    # --- 用户选择和下载 ---
    echo ""
    echo "请选择要下载的版本:"
    echo "1) 最新正式版: ${STABLE_RELEASE_TAG:-N/A} (${STABLE_FILENAME:-未找到})"
    echo "2) 最新测试版: ${TEST_RELEASE_TAG:-N/A} (${TEST_FILENAME:-未找到})"
    echo "3) 退出"

    read -p "请输入你的选择 [1-3]: " choice

    DOWNLOAD_FINAL_URL=""
    FILENAME_TO_DOWNLOAD=""
    VERSION_TO_DOWNLOAD_TAG=""

    case "$choice" in
    1)
        if [[ -n "$STABLE_DOWNLOAD_URL" ]]; then
            DOWNLOAD_FINAL_URL="$STABLE_DOWNLOAD_URL"
            FILENAME_TO_DOWNLOAD="$STABLE_FILENAME"
            VERSION_TO_DOWNLOAD_TAG="$STABLE_RELEASE_TAG"
        else
            echo "正式版下载链接不可用。退出。"
            exit 1
        fi
        ;;
    2)
        if [[ -n "$TEST_DOWNLOAD_URL" ]]; then
            DOWNLOAD_FINAL_URL="$TEST_DOWNLOAD_URL"
            FILENAME_TO_DOWNLOAD="$TEST_FILENAME"
            VERSION_TO_DOWNLOAD_TAG="$TEST_RELEASE_TAG"
        else
            echo "测试版下载链接不可用。退出。"
            exit 1
        fi
        ;;
    3)
        echo "退出脚本。"
        exit 0
        ;;
    *)
        echo "无效选择。退出。"
        exit 1
        ;;
    esac

    echo ""
    echo "--- 开始下载 ---"
    echo "正在下载 ${VERSION_TO_DOWNLOAD_TAG} (${FILENAME_TO_DOWNLOAD})..."
    curl -L -o "${FILENAME_TO_DOWNLOAD}" "${DOWNLOAD_FINAL_URL}"

    if [ $? -eq 0 ]; then
        echo "下载成功: ${FILENAME_TO_DOWNLOAD}"

        # 根据扩展名处理解压
        if [[ "${TARGET_EXTENSION}" == "gz" ]]; then
            echo "--- 解压 .gz 文件 ---"
            # 解压并强制覆盖，同时删除 .gz 源文件
            gunzip -f "${FILENAME_TO_DOWNLOAD}"
            if [ $? -eq 0 ]; then
                echo "解压成功。原始 .gz 文件已移除。"
                # 重命名解压后的文件为通用名 ys-ygy，方便后续使用
                mv "${FILENAME_TO_DOWNLOAD%.gz}" ys-ygy
                chmod +x ys-ygy
                echo "Mihomo 可执行文件已准备就绪: ./ys-ygy"
                echo "版本验证: $(/etc/ys-ygy/ys-ygy -v 2>/dev/null || echo '验证失败。')"
            else
                echo "错误: 解压失败，请手动检查文件。"
                exit 1
            fi
        elif [[ "${TARGET_EXTENSION}" == "tar.gz" ]]; then
            echo "--- 解压 .tar.gz 文件 ---"
            tar -xzf "${FILENAME_TO_DOWNLOAD}"
            if [ $? -eq 0 ]; then
                echo "解压成功。文件已解压。"
                # 尝试移动 mihomo 可执行文件到当前目录
                # 这是一个启发式操作，可能需要根据 tarball 的实际结构进行调整
                if find . -maxdepth 2 -type f -name "mihomo" -print -quit | grep -q .; then
                    find . -maxdepth 2 -type f -name "mihomo" -exec mv {} ./mihomo \;
                    chmod +x mihomo
                    echo "Mihomo 可执行文件已准备就绪: ./mihomo"
                    echo "版本验证: $(/etc/ys-ygy/ys-ygy -v 2>/dev/null || echo '验证失败。')"
                else
                    echo "警告: 无法自动找到 tarball 内的 'mihomo' 可执行文件。"
                    echo "请手动检查解压后的文件。"
                fi
                rm "${FILENAME_TO_DOWNLOAD}" # 删除下载的 tar.gz 文件
            else
                echo "错误: 解压失败，请手动检查文件。"
                exit 1
            fi
        else
            echo "警告: 未知的文件扩展名 '${TARGET_EXTENSION}'。文件已下载但未解压。"
            chmod +x "${FILENAME_TO_DOWNLOAD}" # 尝试赋予可执行权限
        fi
    else
        echo "错误: 文件下载失败。请检查网络连接或下载链接是否有效。"
        exit 1
    fi

    echo "--- mihomo脚本安装完成,准备安装miat脚本---"
}
##############################ys-ygy-install################ mihomo安装程序   ####################################################

########################### mita-install ############################   mita-安装程序  ###########################################
mita-install() {
    # 获取当前系统架构
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

    # 确定 mieru 服务端对应的架构
    if [[ "$ARCH" == "amd64" || "$ARCH" == "x86_64" ]]; then
        MIETU_ARCH_DEB="amd64"
        MIETU_ARCH_RPM="x86_64"
    elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        MIETU_ARCH_DEB="arm64"
        MIETU_ARCH_RPM="aarch64"
    else
        echo "不支持的系统架构: $ARCH"
        exit 1
    fi

    echo "检测到您的系统架构为: $ARCH"

    # 获取最新正式版和测试版的版本号
    get_latest_version() {
        TYPE=$1 # "release" or "pre-release"
        VERSION=$(
            curl -s https://api.github.com/repos/enfein/mieru/releases |
                jq -r "map(select(.prerelease == (\"$TYPE\" == \"pre-release\"))) | .[0].tag_name" |
                sed 's/v//'
        )
        echo "$VERSION"
    }

    LATEST_RELEASE_VERSION=$(get_latest_version "release")
    LATEST_PRERELEASE_VERSION=$(get_latest_version "pre-release")

    echo ""
    echo "MIERU 服务端最新版本信息:"
    echo "1. 最新正式版: $LATEST_RELEASE_VERSION"
    echo "2. 最新测试版: $LATEST_PRERELEASE_VERSION"
    echo "0. 退出程序"
    echo ""

    read -p "请选择要下载的版本 (1, 2, 或 0): " CHOICE

    DOWNLOAD_VERSION=""
    if [[ "$CHOICE" == "1" ]]; then
        DOWNLOAD_VERSION="$LATEST_RELEASE_VERSION"
    elif [[ "$CHOICE" == "2" ]]; then
        DOWNLOAD_VERSION="$LATEST_PRERELEASE_VERSION"
    elif [[ "$CHOICE" == "0" ]]; then
        echo "程序已退出。"
        exit 0
    else
        echo "无效的选择，脚本退出。"
        exit 1
    fi

    if [ -z "$DOWNLOAD_VERSION" ]; then
        echo "无法获取到所选版本的下载信息，请检查网络或稍后重试。"
        exit 1
    fi

    echo "您选择了下载 mieru v${DOWNLOAD_VERSION} 版本。"

    # 确定下载链接和包类型
    DOWNLOAD_URL=""
    PACKAGE_TYPE=""
    if command -v apt &>/dev/null; then
        PACKAGE_TYPE="deb"
        DOWNLOAD_URL="https://github.com/enfein/mieru/releases/download/v${DOWNLOAD_VERSION}/mita_${DOWNLOAD_VERSION}_${MIETU_ARCH_DEB}.deb"
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        PACKAGE_TYPE="rpm"
        # RPM 包的版本号可能略有不同，例如 3.15.0-1
        # 尝试构建常见的 RPM 包名，如果下载失败可以考虑更复杂的逻辑去解析 release name
        DOWNLOAD_URL="https://github.com/enfein/mieru/releases/download/v${DOWNLOAD_VERSION}/mita-${DOWNLOAD_VERSION}-1.${MIETU_ARCH_RPM}.rpm"
    else
        echo "当前系统不支持 deb 或 rpm 包管理器 (apt, dnf, yum)。无法安装。"
        exit 1
    fi

    echo "尝试从以下链接下载: $DOWNLOAD_URL"

    # 下载包
    TEMP_PACKAGE_FILE="/tmp/mita_server.${PACKAGE_TYPE}"
    if ! curl -L -o "$TEMP_PACKAGE_FILE" "$DOWNLOAD_URL"; then
        echo "下载失败，请检查网络连接或下载链接是否正确。"
        rm -f "$TEMP_PACKAGE_FILE"
        exit 1
    fi

    echo "下载完成，开始安装..."

    # 安装包
    if [[ "$PACKAGE_TYPE" == "deb" ]]; then
        if sudo dpkg -i "$TEMP_PACKAGE_FILE"; then
            echo "deb 包安装成功。"
        else
            echo "deb 包安装失败，尝试解决依赖问题..."
            if sudo apt install -f; then
                if sudo dpkg -i "$TEMP_PACKAGE_FILE"; then
                    echo "deb 包安装成功 (依赖已修复)。"
                else
                    echo "deb 包安装失败，即使尝试修复依赖。"
                    rm -f "$TEMP_PACKAGE_FILE"
                    exit 1
                fi
            else
                echo "无法自动修复依赖问题。"
                rm -f "$TEMP_PACKAGE_FILE"
                exit 1
            fi
        fi
    elif [[ "$PACKAGE_TYPE" == "rpm" ]]; then
        if command -v dnf &>/dev/null; then
            if sudo dnf install -y "$TEMP_PACKAGE_FILE"; then
                echo "rpm 包安装成功 (通过 dnf)。"
            else
                echo "rpm 包安装失败 (通过 dnf)。"
                rm -f "$TEMP_PACKAGE_FILE"
                exit 1
            fi
        elif command -v yum &>/dev/null; then
            if sudo yum install -y "$TEMP_PACKAGE_FILE"; then
                echo "rpm 包安装成功 (通过 yum)。"
            else
                echo "rpm 包安装失败 (通过 yum)。"
                rm -f "$TEMP_PACKAGE_FILE"
                exit 1
            fi
        fi
    fi

    # 清理临时文件
    rm -f "$TEMP_PACKAGE_FILE"

    # 检查安装是否成功
    echo "正在检查 mita 服务端是否安装成功..."
    if systemctl is-active --quiet mita; then
        echo "mita 服务端 (mita) 已成功安装并正在运行。"
        echo "安装的版本是: v$DOWNLOAD_VERSION"
    elif command -v mita &>/dev/null; then
        echo "mita 服务端 (mita) 命令已找到，但可能服务未启动。"
        echo "您可能需要手动启动服务: sudo systemctl start mita"
        echo "安装的版本是: v$DOWNLOAD_VERSION"
    else
        echo "mita 服务端 (mita) 未检测到安装成功。"
        echo "请检查安装日志或手动尝试安装。"
    fi
    echo "--- mita 脚本安装完成,准备配置mihomo脚本---"
}

########################### mita-install ############################   mita-安装程序  ###########################################

########################### install_mieru_client_interactive #################### 安装Mieru客户端 ###############################################################
install_mieru_client_interactive() {
    # 局部变量，避免与全局变量冲突
    local INSTALL_DIR="/etc/mieru"
    local BIN_DIR="/usr/local/bin" # 符号链接目录
    local GITHUB_OWNER="enfein"
    local GITHUB_REPO="mieru"
    local MIERU_EXEC_REL_PATH="mieru"

    # 检查是否以root用户运行
    if [ "$EUID" -ne 0 ]; then
        echo "此脚本需要root权限才能运行。请使用sudo执行。"
        return 1 # 函数返回非零表示失败
    fi

    # 检查并安装依赖 (curl, jq)
    install_dependencies() {
        echo "正在检查并安装必要的依赖 (curl, jq)..."
        local deps=("curl" "jq")
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &>/dev/null; then
                echo "$dep 未安装，正在尝试安装..."
                if command -v apt-get &>/dev/null; then
                    sudo apt-get update && sudo apt-get install -y "$dep"
                elif command -v yum &>/dev/null; then
                    sudo yum install -y "$dep"
                elif command -v dnf &>/dev/null; then
                    sudo dnf install -y "$dep"
                else
                    echo "错误: 无法安装 $dep。请手动安装 $dep 后重试。"
                    return 1 # 返回失败
                fi
            fi
        done
        return 0 # 返回成功
    }

    # 从GitHub API获取最新发布信息
    get_mieru_release_info() {
        local release_type=$1 # "latest" 或 "pre_release"
        local releases_json

        echo "DEBUG: 正在尝试从 URL 获取发布信息: https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases" >&2
        releases_json=$(curl -s "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases")

        echo "DEBUG: curl 返回的原始数据如下 (前500字符):" >&2
        echo "${releases_json:0:500}" >&2

        if [ -z "$releases_json" ]; then
            echo "错误: 无法从GitHub获取发布信息。curl 返回空数据。请检查网络或 GITHUB_OWNER/GITHUB_REPO 配置。" >&2
            return 1
        fi

        if ! echo "$releases_json" | jq . &>/dev/null; then
            echo "错误: curl 返回的数据不是有效的JSON格式。这可能是网络问题、API错误响应或URL配置错误。" >&2
            echo "完整的原始数据如下:" >&2
            echo "$releases_json" >&2
            return 1
        fi

        local tag_name=""
        local browser_download_url=""

        if [ "$release_type" == "latest" ]; then
            tag_name=$(echo "$releases_json" | jq -r '
            map(select(.prerelease == false)) |
            sort_by(.published_at) | reverse | .[0].tag_name // empty
            ')
            browser_download_url=$(echo "$releases_json" | jq -r "
            map(select(.prerelease == false)) |
            sort_by(.published_at) | reverse | .[0].assets[]? |
            select(.name | contains(\"linux\") and contains(\"amd64\") and (endswith(\".tar.gz\") or endswith(\".zip\"))).browser_download_url // empty
            ")
        elif [ "$release_type" == "pre_release" ]; then
            tag_name=$(echo "$releases_json" | jq -r '
            map(select(.prerelease == true)) |
            sort_by(.published_at) | reverse | .[0].tag_name // empty
            ')
            browser_download_url=$(echo "$releases_json" | jq -r "
            map(select(.prerelease == true)) |
            sort_by(.published_at) | reverse | .[0].assets[]? |
            select(.name | contains(\"linux\") and contains(\"amd64\") and (endswith(\".tar.gz\") or endswith(\".zip\"))).browser_download_url // empty
            ")
        fi

        if [ -z "$tag_name" ] || [ -z "$browser_download_url" ]; then
            echo "未找到对应的 Mieru $release_type 版本或下载链接。" >&2
            return 1
        fi

        echo "$tag_name;$browser_download_url"
        return 0
    }

    # 安装Mieru客户端
    install_mieru_client() {
        local download_url=$1
        local version=$2
        local filename=$(basename "$download_url")
        local tmp_path="/tmp/$filename"
        local extract_dir=""

        echo "正在安装 Mieru 客户端 $version..."

        # 1. 下载Mieru客户端二进制包
        echo "正在下载: $download_url"
        curl -L -o "$tmp_path" "$download_url"
        if [ $? -ne 0 ]; then
            echo "错误: 下载Mieru客户端失败。请检查URL或网络连接。"
            return 1
        fi

        # 2. 清理旧的安装 (可选，如果需要覆盖安装)
        if [ -d "$INSTALL_DIR" ]; then
            echo "正在清理旧的安装目录: $INSTALL_DIR"
            rm -rf "$INSTALL_DIR"
        fi
        echo "正在创建安装目录: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
        if [ $? -ne 0 ]; then
            echo "错误: 创建安装目录失败。"
            return 1
        fi

        # 3. 解压二进制包到安装目录
        echo "正在解压 $filename 到 $INSTALL_DIR"
        if [[ "$filename" == *.tar.gz ]]; then
            tar -xzf "$tmp_path" -C "$INSTALL_DIR"
        elif [[ "$filename" == *.zip ]]; then
            if ! command -v unzip &>/dev/null; then
                echo "unzip 未安装，正在尝试安装..."
                if command -v apt-get &>/dev/null; then
                    sudo apt-get install -y unzip
                elif command -v yum &>/dev/null; then
                    sudo yum install -y unzip
                elif command -v dnf &>/dev/null; then
                    sudo dnf install -y unzip
                else
                    echo "错误: 无法安装 unzip。请手动安装 unzip。"
                    rm -f "$tmp_path"
                    return 1
                fi
            fi
            unzip -q "$tmp_path" -d "$INSTALL_DIR"
        else
            echo "错误: 不支持的压缩文件格式 ($filename)。"
            rm -f "$tmp_path"
            return 1
        fi

        if [ $? -ne 0 ]; then
            echo "错误: 解压Mieru客户端二进制包失败。请检查文件是否损坏或格式是否正确。"
            rm -f "$tmp_path"
            return 1
        fi

        local mieru_executable=""
        if [ -f "$INSTALL_DIR/$MIERU_EXEC_REL_PATH" ]; then
            mieru_executable="$INSTALL_DIR/$MIERU_EXEC_REL_PATH"
        else
            echo "警告: 未在预设路径 '$INSTALL_DIR/$MIERU_EXEC_REL_PATH' 找到可执行文件。"
            echo "尝试在 '$INSTALL_DIR' 目录下查找 'mieru' 文件..."
            mieru_executable=$(find "$INSTALL_DIR" -maxdepth 2 -type f -name "mieru" -executable | head -n 1)
            if [ -z "$mieru_executable" ]; then
                echo "错误: 未能在安装目录中找到 Mieru 可执行文件。请检查 MIERU_EXEC_REL_PATH 或手动查找。"
                rm -f "$tmp_path"
                return 1
            fi
            echo "找到可执行文件: $mieru_executable"
        fi

        # 4. 赋予可执行权限
        echo "正在赋予Mieru客户端可执行权限: $mieru_executable"
        chmod +x "$mieru_executable"
        if [ $? -ne 0 ]; then
            echo "错误: 赋予可执行权限失败。"
            rm -f "$tmp_path"
            return 1
        fi

        # 5. 创建符号链接到 /usr/local/bin
        echo "正在创建符号链接到 $BIN_DIR..."
        if [ -L "$BIN_DIR/mieru" ]; then
            rm "$BIN_DIR/mieru" # 移除旧的符号链接
        fi
        ln -sf "$mieru_executable" "$BIN_DIR/mieru"
        if [ $? -ne 0 ]; then
            echo "警告: 创建符号链接失败，但这通常不影响核心功能。"
        fi

        # 6. 清理下载的临时文件
        echo "正在清理临时文件..."
        rm -f "$tmp_path"

        echo "Mieru客户端 $version 安装完成！"
        echo "您现在可以通过 'mieru' 命令运行客户端 (如果符号链接创建成功)。"
        echo "Mieru客户端安装在: $INSTALL_DIR"
        echo "可执行文件路径: $mieru_executable"
        echo "请根据Mieru客户端的文档进行配置和使用。"
        return 0
    }

    # 主程序逻辑
    if ! install_dependencies; then
        echo "依赖安装失败，退出。"
        return 1
    fi

    echo "正在搜索 Mieru 客户端的最新版本..."
    local LATEST_RELEASE_INFO=$(get_mieru_release_info "latest")
    local LATEST_RELEASE_STATUS=$? # 捕获get_mieru_release_info的退出状态
    local PRE_RELEASE_INFO=$(get_mieru_release_info "pre_release")
    local PRE_RELEASE_STATUS=$? # 捕获get_mieru_release_info的退出状态

    local LATEST_VERSION=""
    local LATEST_URL=""
    if [ "$LATEST_RELEASE_STATUS" -eq 0 ] && [ -n "$LATEST_RELEASE_INFO" ]; then
        LATEST_VERSION=$(echo "$LATEST_RELEASE_INFO" | cut -d';' -f1)
        LATEST_URL=$(echo "$LATEST_RELEASE_INFO" | cut -d';' -f2)
    fi

    local PRE_VERSION=""
    local PRE_URL=""
    if [ "$PRE_RELEASE_STATUS" -eq 0 ] && [ -n "$PRE_RELEASE_INFO" ]; then
        PRE_VERSION=$(echo "$PRE_RELEASE_INFO" | cut -d';' -f1)
        PRE_URL=$(echo "$PRE_RELEASE_INFO" | cut -d';' -f2)
    fi

    while true; do
        echo ""
        echo "请选择要安装的Mieru客户端版本:"
        if [ -n "$LATEST_VERSION" ]; then
            echo "1) 安装最新正式版 ($LATEST_VERSION)"
        else
            echo "1) 最新正式版信息不可用 (可能未找到或不存在)"
        fi

        if [ -n "$PRE_VERSION" ]; then
            echo "2) 安装最新测试版 ($PRE_VERSION)"
        else
            echo "2) 最新测试版信息不可用 (可能未找到或不存在)"
        fi
        echo "0) 退出"

        read -p "您的选择 (1, 2, 0): " choice

        case "$choice" in
        1)
            if [ -n "$LATEST_URL" ]; then
                install_mieru_client "$LATEST_URL" "$LATEST_VERSION"
                if [ $? -eq 0 ]; then
                    break # 安装成功后退出
                fi
            else
                echo "最新正式版信息不可用，请选择其他选项。"
            fi
            ;;
        2)
            if [ -n "$PRE_URL" ]; then
                install_mieru_client "$PRE_URL" "$PRE_VERSION"
                if [ $? -eq 0 ]; then
                    break # 安装成功后退出
                fi
            else
                echo "最新测试版信息不可用，请选择其他选项。"
            fi
            ;;
        0)
            echo "退出安装程序。"
            return 0 # 退出函数
            ;;
        *)
            echo "无效的选择，请重新输入。"
            ;;
        esac
    done
    return 0 # 函数成功完成
}
#####################################################安装Mieru客户端#########################################################################
zhiqian_zhengshu(){     #设置自签证书
    $(mkdir -p /etc/ys-ygy/shiyou-miyao/)
    $(chmod +x /etc/ys-ygy/shiyou-miyao/)
    $(cd /root)
    $(openssl rand -writerand .rnd)
    $(openssl ecparam -genkey -name prime256v1 -out /etc/ys-ygy/shiyou-miyao/private.key)
    $(openssl req -new -x509 -days 36500 -key /etc/ys-ygy/shiyou-miyao/private.key -out /etc/ys-ygy/shiyou-miyao/cert.crt -subj "/CN=www.bing.com")
    $(chmod 777 /etc/ys-ygy/shiyou-miyao/cert.crt)
    $(chmod 777 /etc/ys-ygy/shiyou-miyao/private.key)
}
##############################输入函数###################################################
##################################################### mihome输入的配置 配置函数 ###########################################################
ys-parameter() { #  mihomo的配置参数
    yellow "选择防火墙是否开放端口$"
    openyn
    yellow " mihomo安装 hysteria2, anytls, vless_reality_vision 三个协议"
    yellow " 并安装 socks5 用于 mieru的mita服务器端通过 socks5 来给mieru节点分流ChatGPT"
    vps_name=$(hostname)
    green "--- 正在配置 Hysteria2 ---"
    readp "请输入 Hysteria2 协议的节点名称" ys_hy2_name "ys_hy2_$vps_name"
    hy2_type=hysteria2
    readp "请输入 Hysteria2 端口" hy2_port "20000"
    readp "请输入 Hysteria2 多端口 " hy2_ports "31000-32000"
    readp "请为 Hysteria2 设置用户名" hy2_name "hy2_name_1"
    readp "请为 Hysteria2 设置密码" hy2_password "password001"

    green "--- 正在配置 Anytls ---"
    readp "请输入 Anytls 协议的节点名称" ys_anytls_name "ys_anytls_$vps_name"
    anytls_type=anytls
    readp "请输入 Anytls 端口" anytls_port "8443"
    readp "请为 Anytls 设置用户名" anytls_name "anytls_name_1"
    readp "请为 Anytls 设置密码" anytls_password "password001"

    green "--- 正在配置 VLESS Reality Vision ---"
    readp "请输入 VLESS Reality Vision 协议的节点名称" ys_vless_reality_vision_name "ys_vless_reality_vision_$vps_name"
    vless_reality_vision_type=vless
    readp "请输入 VLESS Reality Vision 端口" vless_reality_vision_port "26000"
    readp "请输入 vless_reality_vision 的用户名" vless_reality_vision_name "vless_reality_vision_name_1"
    vless_reality_vision_uuid=$(uuidgen)
    green "自动获取 VLESS Reality Vision 的 UUID "
    green "您获取的 uuid 是:$vless_reality_vision_uuid"
    readp "请输入 vless_reality_vision 盗取证书的网站" vless_reality_vision_url "www.yahoo.com"
    ys_reality_keypair=$(/etc/ys-ygy/ys-ygy generate reality-keypair)
    vless_reality_vision_private_key=$(echo "$ys_reality_keypair" | grep "PrivateKey: " | awk '{print $NF}')
    vless_reality_vision_Public_Key=$(echo "$ys_reality_keypair" | grep "PublicKey: " | awk '{print $NF}')
    green "自动获取 vless_reality_vision 的private_key和publickey"
    green "您获取的 privatekey 是:$vless_reality_vision_private_key"
    green "您获取的 publickey 是:$vless_reality_vision_Public_Key"
    ys_short_id=$(openssl rand -hex 8)

    green "--- 正在配置 socks5 节点,目的用来给mieru的节点通过socks5链接mihomo的socks5,利用mihomo的分流来ChatGPT分流 ---"
    readp "请输入 socks5 的端口" socks_port "9369"
    readp "请输入 socks5 的用户名" socks_name "socks_name_1"
    readp "请输入 socks5 的密码" socks_password "password001"
    echo "-------"
    $(mkdir -p /etc/ys-ygy/txt/)
    $(chmod +x /etc/ys-ygy/txt/)
    echo "$ys_hy2_name" > /etc/ys-ygy/txt/ys_hy2_name.txt
    echo "$hy2_port" > /etc/ys-ygy/txt/hy2_port.txt
    echo "$hy2_ports" > /etc/ys-ygy/txt/hy2_ports.txt
    echo "$hy2_name" > /etc/ys-ygy/txt/hy2_name.txt
    echo "$hy2_password" > /etc/ys-ygy/txt/hy2_password.txt
    echo "$ys_anytls_name" > /etc/ys-ygy/txt/ys_anytls_name.txt
    echo "$anytls_port" > /etc/ys-ygy/txt/anytls_port.txt
    echo "$anytls_name" > /etc/ys-ygy/txt/anytls_name.txt
    echo "$anytls_password" > /etc/ys-ygy/txt/anytls_password.txt
    echo "$ys_vless_reality_vision_name" > /etc/ys-ygy/txt/ys_vless_reality_vision_name.txt
    echo "$vless_reality_vision_port" > /etc/ys-ygy/txt/vless_reality_vision_port.txt
    echo "$vless_reality_vision_name" > /etc/ys-ygy/txt/vless_reality_vision_name.txt
    echo "$vless_reality_vision_uuid" > /etc/ys-ygy/txt/vless_reality_vision_uuid.txt
    echo "$vless_reality_vision_url" > /etc/ys-ygy/txt/vless_reality_vision_url.txt
    echo "$vless_reality_vision_private_key" > /etc/ys-ygy/txt/vless_reality_vision_private_key.txt
    echo "$vless_reality_vision_Public_Key" > /etc/ys-ygy/txt/vless_reality_vision_Public_Key.txt
    echo "$ys_short_id" > /etc/ys-ygy/txt/ys_short_id.txt
    echo "$socks_port" > /etc/ys-ygy/txt/socks_port.txt
    echo "$socks_name" > /etc/ys-ygy/txt/socks_name.txt
    echo "$socks_password" > /etc/ys-ygy/txt/socks_password.txt

}
##############################输入函数###################################################
mita-parameter() {
    vps_name=$(hostname)
    green "--- 正在配置 mita 服务端 ---"
    readp "请输入多端口 范围在20000-65534 格式为xxxxx-xxxxxx" mita_ports "38000-39000"
    readp "请输入多端口传输模式 模式为 TCP 或 UDP " mita_protocols "TCP"
    readp "请输入单端口 范围在20000-65534 格式为xxxxx" mita_port "37999"
    readp "请输入单端口传输模式 模式为 TCP 或 UDP " mita_protocol "TCP"
    readp "请输入用户名 " mita_name "mita_$vps_name"
    readp "请输入密码" mita_password "password001"
    mieru_name="mieru_$vps_name"
    echo "$mieru_name" > /etc/ys-ygy/txt/mieru_name.txt
    echo "$mita_ports" > /etc/ys-ygy/txt/mita_ports.txt
    echo "$mita_protocols" > /etc/ys-ygy/txt/mita_protocols.txt
    echo "$mita_port" > /etc/ys-ygy/txt/mita_port.txt
    echo "$mita_protocol" > /etc/ys-ygy/txt/mita_protocol.txt
    echo "$mita_name" > /etc/ys-ygy/txt/mita_name.txt
    echo "$mita_password" > /etc/ys-ygy/txt/mita_password.txt
}
##############################输入函数###################################################

################################每个协议单独的配置#################################################
ys_hysteria2() {
    cat <<YAML_BLOCK
- name: $ys_hy2_name
  type: hysteria2
  port: $hy2_port
  listen: 0.0.0.0
  users:
    $hy2_name: $hy2_password
  up: 1000
  down: 1000
  ignore-client-bandwidth: false
  masquerade: ""
  alpn:
  - h3
  certificate: /etc/ys-ygy/shiyou-miyao/cert.crt
  private-key: /etc/ys-ygy/shiyou-miyao/private.key

YAML_BLOCK
}

ys_anytls() {
    cat <<YAML_BLOCK
- name: $ys_anytls_name
  type: anytls
  port: $anytls_port
  listen: 0.0.0.0
  users:
    $anytls_name: $anytls_password
  certificate: /etc/ys-ygy/shiyou-miyao/cert.crt
  private-key: /etc/ys-ygy/shiyou-miyao/private.key
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
YAML_BLOCK
}

ys_vless_reality_vision() {
    cat <<YAML_BLOCK
- name: $ys_vless_reality_vision_name
  type: vless
  port: $vless_reality_vision_port
  listen: 0.0.0.0
  users:
    - username: $vless_reality_vision_name
      uuid: $vless_reality_vision_uuid
      flow: xtls-rprx-vision
  reality-config:
    dest: $vless_reality_vision_url:443
    private-key: $vless_reality_vision_private_key
    short-id:
      - $ys_short_id
    server-names:
      - $vless_reality_vision_url
YAML_BLOCK
}

ys_socks_mieru() {
    cat <<YAML_BLOCK
- name: socks-in-Mieru
  type: socks
  port: $socks_port
  listen: 127.0.0.1
  udp: true
  users:
    - username: $socks_name
      password: $socks_password
YAML_BLOCK
}
################################每个协议单独的配置#################################################

################################### mihomo服务端配置文件的写入 ################################
# insx 函数：生成最终的 config.yaml
ys-config() {
    cat >/etc/ys-ygy/config.yaml <<EOF
listeners:
$(ys_hysteria2)

$(ys_anytls)

$(ys_vless_reality_vision)

$(ys_socks_mieru)

proxies:
- name: "MyWireGuard"
  type: wireguard
  server: 162.159.192.1
  port: 2408
  private-key: "8N30LVA3XZ5sfRFHjDnfSLfdhDtT/60nh6nQixJ/0Hk="
  public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
  ip: "172.16.0.2/32"
  ipv6: "2606:4700:110:8efd:7e96:4c5e:34d2:4469/128"
  dns:
    - 8.8.8.8
    - 8.8.4.4
    - 2001:4860:4860::8888
    - 2001:4860:4860::8844
  udp: true

proxy-groups:
- name: "WireGuard_Group"
  type: select
  proxies:
    - MyWireGuard
      
rules:
  - DOMAIN-SUFFIX,openai.com,WireGuard_Group
  - DOMAIN-SUFFIX,chat.openai.com,WireGuard_Group

dns:
  enable: true
  listen: 0.0.0.0:53
  ipv6: false

  nameserver:
    - https://223.5.5.5/dns-query
    - tls://8.8.8.8:853

  fallback:
    - tls://1.1.1.1:853
    - 8.8.4.4
EOF
    green "mihomo脚本执行完毕。"
}

################################### mihomo服务端配置文件的写入 ################################

################################### mita服务端配置文件的写入 ################################
mita-config() {
    cat >/etc/mita/config.json <<EOF
{
	"portBindings": [
		{
			"portRange": "$mita_ports",
			"protocol": "$mita_protocols"
		},
		{
			"port": $mita_port,
			"protocol": "$mita_protocol"
		}
	],
	"users": [
		{
			"name": "$mita_name",
			"password": "$mita_password"
		}
	],
	"loggingLevel": "INFO",
	"mtu": 1400,
	"egress": {
		"proxies": [
			{
				"name": "cloudflare",
				"protocol": "SOCKS5_PROXY_PROTOCOL",
				"host": "127.0.0.1",
				"port": $socks_port,
				"socks5Authentication": {
					"user": "$socks_name",
					"password": "$socks_password"
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
    green "mieru的mita服务器脚本执行完毕。"
}
################################### mita服务端配置文件的写入 ################################

################################### mihomo客户端配置文件的写入 ################################
ys-client() {

    cat >/etc/ys-ygy/ys-client.yaml <<EOF
allow-lan: true
global-client-fingerprint: chrome
dns:
  enable: true
  # listen: :53
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
    domain:
      - '+.googleapis.cn'
      - '+.xn--ngstr-lra8j.com'
      - '+.xn--ngstr-cn-8za9o.com'
      - '+.google.com'
      - '+.youtube.com'
      - '+.tiktok.com'
      - '+.instagram.com'
      - '+.twitter.com'

  nameserver-policy:
    "geosite:cn": [223.6.6.6]
    "googleapis.cn": [tls://8.8.4.4:853]
    "xn--ngstr-lra8j.com": [tls://8.8.4.4:853]
    "xn--ngstr-cn-8za9o.com": [tls://8.8.4.4:853]
    "geosite:google": [tls://8.8.4.4:853]
    "geosite:youtube": [tls://8.8.4.4:853]
    "geosite:tiktok": [tls://8.8.4.4:853]

proxies:

- name: "$ys_hy2_name"
  type: hysteria2
  server: $address_ip
  #port: $hy2_port
  ports: $hy2_ports,$hy2_port
  password: $hy2_password
  up: "1000 Mbps"
  down: "1000 Mbps"
  sni: www.bing.com
  skip-cert-verify: true   # 跳过证书验证，仅适用于使用 tls 的协议
  #fingerprint: xxxx         # 证书指纹，仅适用于使用 tls 的协议，可使用
  alpn:                     # 支持的应用层协议协商列表，按优先顺序排列。
    - h3
  #ca: "./my.ca"
  #ca-str: "xyz"
  ###quic-go特殊配置项，不要随意修改除非你知道你在干什么###
  # initial-stream-receive-window： 8388608
  # max-stream-receive-window： 8388608
  # initial-connection-receive-window： 20971520
  # max-connection-receive-window： 20971520

- name: "$ys_vless_reality_vision_name"
  type: vless
  server: $address_ip
  port: $vless_reality_vision_port
  udp: true
  uuid: $vless_reality_vision_uuid
  flow: xtls-rprx-vision
  packet-encoding: xudp
  tls: true
  servername: $vless_reality_vision_url
  alpn:
  - h2
  - http/1.1
  #fingerprint: xxxx
  client-fingerprint: edge
  skip-cert-verify: false
  reality-opts:
    public-key: $vless_reality_vision_Public_Key
    short-id: $ys_short_id
  network: tcp
  #smux:
  #  enabled: false

- name: "$ys_anytls_name"
  type: anytls
  server: $address_ip
  port: $anytls_port
  password: "$anytls_password"
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

- name: "$mieru_name"
  type: mieru
  server: $address_ip
  #port: $mita_port
  port-range: $mita_ports
  transport: TCP
  username: $mita_name
  password: $mita_password
  multiplexing: MULTIPLEXING_OFF

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "$ys_hy2_name"
      - "$ys_anytls_name"
      - "$mieru_name"
      - "$ys_vless_reality_vision_name"
      - "DIRECT"
      - "REJECT"
      - "自动选择"

  - name: 自动选择
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
      - "$ys_hy2_name"
      - "$ys_anytls_name"
      - "$mieru_name"
      - "$ys_vless_reality_vision_name"

rules:
  - DOMAIN-SUFFIX,googleapis.cn,🚀 节点选择
  - DOMAIN-SUFFIX,xn--ngstr-lra8j.com,🚀 节点选择
  - DOMAIN-SUFFIX,xn--ngstr-cn-8za9o.com,🚀 节点选择

  - GEOSITE,google,🚀 节点选择
  - GEOSITE,youtube,🚀 节点选择
  - GEOSITE,tiktok,🚀 节点选择
  - GEOSITE,instagram,🚀 节点选择
  - GEOSITE,twitter,🚀 节点选择
  - GEOSITE,facebook,🚀 节点选择
  - GEOSITE,netflix,🚀 节点选择
  - GEOSITE,telegram,🚀 节点选择
  - GEOSITE,github,🚀 节点选择
  - GEOSITE,microsoft,🚀 节点选择
  - GEOSITE,apple,🚀 节点选择
  - DOMAIN-SUFFIX,wikipedia.org,🚀 节点选择

  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT

  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT

  - IP-CIDR,224.0.0.0/3,REJECT
  - IP-CIDR,ff00::/8,REJECT

  - MATCH,🚀 节点选择
EOF
}

################################### mihomo客户端配置文件的写入 ################################

################################### mieru客户端 配置文件的写入 ################################
mieru-client-config() {
    cat >/etc/mieru/config.json <<EOC
{
    "profiles": [
        {
            "profileName": "default",
            "user": {
                "name": "$mita_name",
                "password": "$mita_password"
            },
            "servers": [
                {
                    "ipAddress": "$address_ip",
                    "domainName": "",
                    "portBindings": [
                        {
                            "portRange": "$mita_ports",
                            "protocol": "$mita_protocols"
                        },
                        {
                            "port": $mita_port,
                            "protocol": "$mita_protocol"
                        }
                    ]
                }
            ],
            "mtu": 1400,
            "multiplexing": {
                "level": "MULTIPLEXING_HIGH"
            }
        }
    ],
    "activeProfile": "default",
    "rpcPort": 8964,
    "socks5Port": 1080,
    "loggingLevel": "INFO",
    "socks5ListenLAN": false,
    "httpProxyPort": 8080,
    "httpProxyListenLAN": false
}
EOC
}
################################### mieru客户端 配置文件的写入 ################################

################################### 开机自动启动 配置文件的写入 ################################

ys-system-auto() {
    cat >/etc/systemd/system/ys-ygy.service <<EOF
[Unit]
Description=Mihomo Proxy Service (ys-ygy)
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
# 由于以 root 运行，CapabilityBoundingSet 和 AmbientCapabilities 通常不需要，
# 但保留它们也无害，因为 root 默认拥有所有权限。
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
# 注意：这里使用 --config 明确指定配置文件路径
ExecStart=/etc/ys-ygy/ys-ygy -d /etc/ys-ygy
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
}

sb-config(){   #sing-box客户端配置文件
new_ports="${hy2_ports/-/:}"
hy2_ports="$new_ports"
cat > /etc/ys-ygy/sb-client.json <<EOF
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
                "address": "tls://8.8.8.8/dns-query",
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
        "$ys_hy2_name",
        "$ys_anytls_name",
        "$ys_vless_reality_vision_name"
      ]
    },
    {
      "type": "vless",
      "tag": "$ys_vless_reality_vision_name",
      "server": "$address_ip",
      "server_port": $vless_reality_vision_port,
      "uuid": "$vless_reality_vision_uuid",
      "packet_encoding": "xudp",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vless_reality_vision_url",
        "utls": {
          "enabled": true,
          "fingerprint": "edge"
        },
      "reality": {
          "enabled": true,
          "public_key": "$vless_reality_vision_Public_Key",
          "short_id": "$ys_short_id"
        }
      }
    },
    {
        "type": "hysteria2",
        "tag": "$ys_hy2_name",
        "server": "$address_ip",
        "server_port": $hy2_port,
        "password": "$hy2_password",
        "up_mbps": 1000,
        "down_mbps": 1000,
        "tls": {
            "enabled": true,
            "server_name": "www.bing.com",
            "insecure": true,
            "alpn": [
                "h3"
            ]
        }
    },
        {
        "type": "anytls",
        "tag": "$ys_anytls_name",

        "server": "$address_ip",
        "server_port": $anytls_port,
        "password": "$anytls_password",
        "idle_session_check_interval": "30s",
        "idle_session_timeout": "30s",
        "min_idle_session": 5,
        "tls": {
            "enabled": true,
            "server_name": "wwww.bing.com",
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
        "$ys_hy2_name",
        "$ys_anytls_name",
        "$ys_vless_reality_vision_name"
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
new_ports="${hy2_ports/:/-}"
hy2_ports="$new_ports"
EOF
}
################################### 开机自动启动 配置文件的写入 ################################

####################################################################
run_ys_mita(){
    $(systemctl daemon-reload)
    $(systemctl enable ys-ygy.service)
    $(systemctl start ys-ygy.service)
    $(systemctl start mita)
    $(mita apply config /etc/mita/config.json)
}
run_ys(){
    $(systemctl daemon-reload)
    $(systemctl enable ys-ygy.service)
    $(systemctl start ys-ygy.service)
    $(systemctl start mita)
    peizi_ys
}
restart_ys(){
    $(systemctl restart ys-ygy.service)
    peizi_ys
}
stop_ys(){                     # 停止运行
    $(systemctl stop ys-ygy.service)
    peizi_ys
}
run_mita(){
    $(systemctl start mita)
    peizi_ys
}

stop_mita(){
    $(systemctl stop mita)
    peizi_ys
}

hy_auto() {
  rm -rf /usr/bin/ys
  curl -L -o /usr/bin/ys -# --retry 2 --insecure https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys.sh
  chmod +x /usr/bin/ys
  cd /root/
}


ipv4_ipv6_switch(){
    select_network_ip
    ys_hy2_name=$(cat /etc/ys-ygy/txt/ys_hy2_name.txt)
    hy2_port=$(cat /etc/ys-ygy/txt/hy2_port.txt)
    hy2_ports=$(cat /etc/ys-ygy/txt/hy2_ports.txt)
    hy2_name=$(cat /etc/ys-ygy/txt/hy2_name.txt)
    hy2_password=$(cat /etc/ys-ygy/txt/hy2_password.txt)
    ys_anytls_name=$(cat /etc/ys-ygy/txt/ys_anytls_name.txt)
    anytls_port=$(cat /etc/ys-ygy/txt/anytls_port.txt)
    anytls_name=$(cat /etc/ys-ygy/txt/anytls_name.txt)
    anytls_password=$(cat /etc/ys-ygy/txt/anytls_password.txt)
    ys_vless_reality_vision_name=$(cat /etc/ys-ygy/txt/ys_vless_reality_vision_name.txt)
    vless_reality_vision_port=$(cat /etc/ys-ygy/txt/vless_reality_vision_port.txt)
    vless_reality_vision_name=$(cat /etc/ys-ygy/txt/vless_reality_vision_name.txt)
    vless_reality_vision_uuid=$(cat /etc/ys-ygy/txt/vless_reality_vision_uuid.txt)
    vless_reality_vision_url=$(cat /etc/ys-ygy/txt/vless_reality_vision_url.txt)
    vless_reality_vision_private_key=$(cat /etc/ys-ygy/txt/vless_reality_vision_private_key.txt)
    vless_reality_vision_Public_Key=$(cat /etc/ys-ygy/txt/vless_reality_vision_Public_Key.txt)
    ys_short_id=$(cat /etc/ys-ygy/txt/ys_short_id.txt)
    socks_port=$(cat /etc/ys-ygy/txt/socks_port.txt)
    socks_name=$(cat /etc/ys-ygy/txt/socks_name.txt)
    socks_password=$(cat /etc/ys-ygy/txt/socks_password.txt)
    mieru_name=$(cat /etc/ys-ygy/txt/mieru_name.txt)
    mita_ports=$(cat /etc/ys-ygy/txt/mita_ports.txt)
    mita_protocols=$(cat /etc/ys-ygy/txt/mita_protocols.txt)
    mita_port=$(cat /etc/ys-ygy/txt/mita_port.txt)
    mita_protocol=$(cat /etc/ys-ygy/txt/mita_protocol.txt)
    mita_name=$(cat /etc/ys-ygy/txt/mita_name.txt)
    mita_password=$(cat /etc/ys-ygy/txt/mita_password.txt)
    ys-config           # 写入/etc/ys-ygy/config.yaml主文件
    mita-config         # 写入/etc/mita/config.json主文件
    ys-client           # 写入/etc/ys-ygy/ys-client.yaml mihomo客户端配置文件,里面包括mieru客户端配置
    sb-config           # 写入/etc/ys-ygy/sb-client.json客户端配置危机
    mieru-client-config # 写入/etc/mieru/config.json mieru客户端配置文件,用来创建配置链接
    run_ys_mita              # 运行ys配置
    detection           #检测mihomo与mita程序是否运行成功,通过调用check_service_status
    ys-link-quan        #快捷链接
}
#__________________________________________________________________________________________
setup_install() {
    zhiqian_zhengshu        #创建自签证书
    select_network_ip #检测vps的所有ip,并确认vps的主IP 变量为*** address_ip  ***
    ys-ygy-install    # 检查网络mihomo最新测试版或正式版,并选择安装
    mita-install      # 检查网络mita最新正式版与测试版,并选择安装
    install_mieru_client_interactive    # 检查网络mieru最新正式版与测试版,并选择安装
    ys-parameter        # 用户输入mihomo服务端的各种参数
    mita-parameter      # 用户输入mita服务端的各种参数
    ys-config           # 写入/etc/ys-ygy/config.yaml主文件
    sb-config           # 写入/etc/ys-ygy/sb-client.json客户端配置危机
    mita-config         # 写入/etc/mita/config.json主文件
    ys-client           # 写入/etc/ys-ygy/ys-client.yaml mihomo客户端配置文件,里面包括mieru客户端配置
    mieru-client-config # 写入/etc/mieru/config.json mieru客户端配置文件,用来创建配置链接
    ys-system-auto      # 写入开机mihomo自动启动配置文件/etc/systemd/system/ys-ygy.service
    open_ports_net      # 多端口配置
    run_ys_mita         # 运行ys配置
    detection           #检测mihomo与mita程序是否运行成功,通过调用check_service_status
    ys-link-quan        #快捷链接
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
peizi_ys() {

    green " 1. 重启ys-ygy"
    green " 2. 停止ys-ygy"
    green " 3. 新启动ys-ygy"
    green " 4. 停止mita"
    green " 5. 新启动mita"
    green " 6. 查看ys-ygy与mata运行状态"
    green " 0. 返回上级菜单"
    readp "请输入数字【0-5】:" Input
    case "$Input" in
    1) restart_ys ;;    #菜单选项,重启ys-ygy
    2) stop_ys ;;       #菜单选项,停止ys-ygy
    3) run_ys ;;       #菜单选项,新启动ys-ygy
    4) stop_mita ;;       #菜单选项,停止ys-ygy
    5) run_mita ;;       #菜单选项,新启动ys-ygy
    6) detection ;;         #菜单选项,查看ys-ygy与mata运行状态
    0) menu_zhu ;;
    esac
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
setup_gitlab() {

    green " 1. gitlab建立订阅链接"
    green " 2. 检查是否设置了gitlab订阅链接"
    green " 3. 打印当前gitlab订阅链接"
    green " 4. 同步到telegram"
    green " 0. 返回上级菜单"
    readp "请输入数字【0-3】:" Input
    case "$Input" in
    1) gitlabsub ;;   #菜单选项,gitlab建立订阅链接
    2) gitlabsubgo ;; #检查是否设置了gitlab订阅链接
    3) clsbshow ;;    #打印当前gitlab订阅链接
    4) tgsbshow ;;    #同步到telegram
    0) menu_zhu ;;
    esac
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##编写菜单目录
menu_zhu() {
    clear
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green "##############################################################################"
    red "#######本脚本为一键安装hysteria2 anstls vless-reality-vision mieru 四协议脚本##### "
    red "本脚本为mihomo与mieru双服务器端脚本,mieru协议通过socks5跳转到mihomo服务端来分流ChatGPT"
    green "##############################################################################"
    white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green " 1. 一键安装 Mihomo协议与mieru协议服务器端"
    green " 2. 查看客户端配置"
    green " 3. 查看服务"
    green " 4. 同步到GitLab与telegram"
    green " 5. 一键原版BBR+FQ加速"
    green " 6. 管理 Acme 申请域名证书"
    green " 7. 管理 Warp 查看Netflix/ChatGPT解锁情况"
    green " 8. 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】"
    green " 9. 双栈VPS切换IPV4/IPV6配置输出"
    white "----------------------------------------------------------------------------------"
    green " 0. 退出脚本"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    readp "请输入数字【0-4】:" Input
    case "$Input" in
    1) setup_install ;; # 一键安装mihomo与mieru服务端脚本
    2) ys-check ;;      # 查看客户端配置
    3) peizi_ys ;;     # 查看服务是否正常运行
    4) setup_gitlab ;;  # 同步到GitLab和telegram
    5) bbr;;     # 一键原版BBR+FQ加速
    6) acme;;
    7) cfwarp;;
    8) inssbwpph;;
    9) ipv4_ipv6_switch;;   #切换ip
    0) exit ;;
    esac
}
curl -L -o /usr/bin/ys -# --retry 2 --insecure https://raw.githubusercontent.com/yggmsh/yggmsh123/main/ys.sh
jianche-system       #检测root模式与linux发行版系统是否支持
jianche-system-gujia #这行命令检测系统构架,看是不是支持
gongju-install       #检测安装脚本所需要的工具,并安装各种工具
hy_auto
jianche-openvz
jianche-bbr  
menu_zhu             #主菜单
##################################################################################
