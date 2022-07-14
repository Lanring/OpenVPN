#!/bin/bash
# Revision:1.5.6
# Date:2022/07/14
# Filename:OpenVPN_Auto_Install_with_LDAP.sh
# Author:Lance
# Email:Lance@cnwan.com.cn
# Description:在CentOS7x64系统上安装OpenVPN-v2.4.12+EasyRSA-3.0.8使用用户独立证书+证书密码+用户名密码验证
#=====================================================================================================
function checkOS() {
        if [[ -e /etc/system-release ]]; then
                source /etc/os-release
                if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
                        OS="centos"
                        if [[ ! $VERSION_ID =~ (7|8) ]]; then
                                echo -e "\033[32m   你的CentOS版本不被支持. \033[0m"
                                echo ""
                                echo -e "\033[32m   这个脚本只支持 CentOS 7 和 CentOS 8. \033[0m"
                                echo ""
                                exit 1
                        else
                                yum -y update &> /dev/null && yum -y upgrade &> /dev/null
                                yum install -y wget lrzsz git &> /dev/null
                        fi
                fi
        else
                echo -e "\033[32m   你的系统似乎不是 CentOS 7 或 CentOS 8. \033[0m"
                exit 1
        fi
}
#-----------------------------------------------------------------------------------------------------
function isRoot() {
        if [ "$EUID" -ne 0 ]; then
                return 1
        fi
}
#-----------------------------------------------------------------------------------------------------
function initialCheck() {
        if ! isRoot; then
                echo -e "\033[32m   对不起, 你需要使用root账户运行这个脚本. \033[0m"
                exit 1
        fi
        checkOS
}
#-----------------------------------------------------------------------------------------------------
# Check for root, TUN, OS...
initialCheck
#-----------------------------------------------------------------------------------------------------
function installError() {
        echo ""
        echo -e "\033[32m   安装出错了，清理残留. \033[0m"
        # Get OpenVPN port from the configuration
        PORT=$(grep '^port ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
        PROTOCOL=$(grep '^proto ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
        rm -rf /usr/local/openvpn/
        rm -rf /usr/lib/systemd/system/openvpn.service
        rm -rf /etc/openvpn/
        rm -rf /usr/lib64/openvpn/
        rm -rf /usr/lib64/openvpn-auth-ldap.so
        rm -rf /usr/local/sbin/openvpn
        rm -rf /var/log/openvpn.log
        rm -rf /tmp/v2.4.12.tar.gz
        rm -rf /tmp/openvpn-2.4.12.tar.gz
        rm -rf /tmp/openvpn-2.4.12
        rm -rf /tmp/EasyRSA-3.0.8.tgz
        rm -rf /tmp/EasyRSA-3.0.8
        firewall-cmd --zone=public --remove-port=$PORT/tcp --permanent &> /dev/null
        firewall-cmd --remove-masquerade --permanent &> /dev/null
        firewall-cmd --remove-service=openvpn --permanent &> /dev/null
        firewall-cmd --reload &> /dev/null
        echo ""
        echo -e "\033[32m   完成清理. \033[0m"
}
#=====================================================================================================
function installQuestions() {
        echo ""
        echo -e "\033[32m   欢迎使用 OpenVPN 安装脚本!在安装之前需要回答一些问题. \033[0m"
        echo ""
        echo -e "\033[32m   即使你只使用默认值，也能顺利完成安装. \033[0m"
        echo ""
        echo "你的 OpenVPN 运行在哪个端口上?"
        echo "   1) 默认: 1194"
        echo "   2) 自定义"
        echo "   3) 随机 [49152-65535]"
        until [[ $PORT_CHOICE =~ ^[1-3]$ ]]; do
                read -rp "选择端口 [1-3]: " -e -i 1 PORT_CHOICE
        done
        case $PORT_CHOICE in
        1)
                PORT="1194"
                ;;
        2)
                until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
                        read -rp "请输入自定义端口[1-65535]: " -e -i 1194 PORT
                done
                ;;
        3)
                # Generate random number within private ports range
                PORT=$(shuf -i49152-65535 -n1)
                echo "随机端口号: $PORT"
                ;;
        esac

        echo ""
        echo -e "\033[32m   输入允许VPN用户访问的网段地址.例如允许访问内网192.168.10.0段，则输入192.168.10.0 255.255.255.0 \033[0m"
        echo ""
        read -rp "请输入VPN用户可访问的内网网段: " ROUTE_IP
        echo ""
        echo "OpenVPN 将使用什么协议?"
        echo "   1) UDP"
        echo "   2) TCP"
        until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
                read -rp "协议 [1-2]: " -e -i 2 PROTOCOL_CHOICE
        done
        case $PROTOCOL_CHOICE in
        1)
                PROTOCOL="udp"
                ;;
        2)
                PROTOCOL="tcp"
                ;;
        esac

        echo -e "\033[32m   我们将使用 OpenVPN-v2.4.12 和 EasyRSA-3.0.8 安装包来完成安装. \033[0m"
        echo ""
        echo -e "\033[32m   你的安装包是在本地磁盘(/tmp/)还是直接从官方网站下载? \033[0m"
        echo ""
        echo "   1) 从本地磁盘安装"
        echo "   2) 从官方网站下载安装"
        until [[ $INSTALL_CHOICE =~ ^[1-2]$ ]]; do
                read -rp "从哪里开始安装 [1-2]: " -e -i 1 INSTALL_CHOICE
        done
        case $INSTALL_CHOICE in
        1)
                INSTALL_FROM="localdisk"
                echo -e "\033[32m   请先将 openvpn-2.4.12.tar.gz 和 EasyRSA-3.0.8.tgz 安装包复制到 /tmp/，再运行脚本进行安装. \033[0m"
                ;;
        2)
                INSTALL_FROM="cloud"
                ;;
        esac

        echo ""
        echo -e "\033[32m   所有需要确认的参数都已经确定，接下来将开始安装OpenVPN. \033[0m"
        echo ""
        APPROVE_INSTALL=${APPROVE_INSTALL:-y}
        if [[ $APPROVE_INSTALL =~ n ]]; then
                read -n1 -r -p "按任意键开始安装......"
        fi
}
#-----------------------------------------------------------------------------------------------------
function checkcountry() {
        read -rp "请输入所在国家(如：CN): " -e -i CN COUNTRY
        if [ ! -n "$COUNTRY" ]; then
                checkcountry
        fi
}

function checkprovince() {
        read -rp "请输入所在省份(如：JiangSu): " -e -i JiangSu PROVINCE
        if [ ! -n "$PROVINCE" ]; then
                checkprovince
        fi
}

function checkcity() {
        read -rp "请输入所在城市(如：SuZhou): " -e -i SuZhou CITY
        if [ ! -n "$CITY" ]; then
                checkcity
        fi
}

function checkorg() {
        read -rp "请输入所在组织(如：Company): " -e -i Company ORG
        if [ ! -n "$ORG" ]; then
                checkorg
        fi
}

function checkemail() {
        read -rp "请输入Email地址: " -e -i xxx@126.com EMAIL
        if [ ! -n "$EMAIL" ]; then
                checkemail
        fi
}

function checkiou() {
        read -rp "请输入所在部门(如：IT): " -e -i IT IOU
        if [ ! -n "$IOU" ]; then
                checkiou
        fi
}

function checkcaexpire() {
        read -rp "请输入CA有效期(如：10年则输入3650): " -e -i 3650 CAEXPIRE
        if [ ! -n "$CAEXPIRE" ]; then
                checkcaexpire
        fi
}

function checkcerexpire() {
        read -rp "请输入证书有效期(如：10年则输入3650): " -e -i 3650 CEREXPIRE
        if [ ! -n "$CEREXPIRE" ]; then
                checkcerexpire
        fi
}

#-----------------------------------------------------------------------------------------------------
function CheckLdapURL() {
        read -rp "请输入域控制器的主机名或IP地址(形如：dc01.cnwan.com.cn): " -e LdapURL
        if [ ! -n "$LdapURL" ]; then
                CheckLdapURL
        fi
}

function CheckBindDN() {
        read -rp "请输入用于验证用户的BindDN(形如：CN=openvpn,CN=Users,DC=cnwan,DC=com,DC=cn): " -e BindDNU
        if [ ! -n "$BindDNU" ]; then
                CheckBindDN
        fi
}

function CheckBindDNPW() {
        read -rp "请输入用于验证用户的密码(BindDN用户的密码): " -e BindDNPW
        if [ ! -n "$BindDNPW" ]; then
                CheckBindDNPW
                echo -e "\033[32m   请在域控制器上建立该用户. \033[0m"
        fi
}

function CheckBaseDN() {
        read -rp "请输入域控制器的BaseDN(形如：CN=Users,DC=cnwan,DC=com,DC=cn): " -e BaseDN
        if [ ! -n "$BaseDN" ]; then
                CheckBaseDN
        fi
}

function CheckVPNUsers() {
        read -rp "请输入VPN用户组名称(必须在BaseDN下): " -e VPNUsers
        if [ ! -n "$VPNUsers" ]; then
                CheckVPNUsers
                echo -e "\033[32m   凡是加入到这个组中的用户，均具备VPN权限. \033[0m"
        fi
}

function LdapSetting() {
        Bak_Date=$(date +"%Y%m%d%H%M%S")
        if [[ -e /etc/openvpn/auth/ldap.conf ]]; then
                mv /etc/openvpn/auth/ldap.conf /etc/openvpn/auth/ldap-${Bak_Date}.conf
        fi
        CheckLdapURL
        CheckBindDN
        CheckBindDNPW
        CheckBaseDN
        CheckVPNUsers
        cat > /etc/openvpn/auth/ldap.conf << EOF
<LDAP>
    URL                ldap://$LdapURL:389
    TLSEnable          no
    BindDN             $BindDNU
    Password           $BindDNPW
    Timeout            15
    FollowReferrals    no
</LDAP>
<Authorization>
     BaseDN           "$BaseDN"
     SearchFilter     "(&(sAMAccountName=%u)(memberof=CN=$VPNUsers,$BaseDN))"
     RequireGroup    false
</Authorization>
EOF
}
#-----------------------------------------------------------------------------------------------------
function installOpenVPN() {
        IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
        # Run setup questions first, and set other variables if auto-install
        installQuestions

        # 开放OpenVPN所需的端口、服务
        firewall-cmd --zone=public --add-port=$PORT/tcp --permanent &> /dev/null
        echo ""
        echo -e "\033[32m   完成防火墙开放 OpenVPN 服务所需的端口. \033[0m"
        firewall-cmd --zone=public --add-port=123/tcp --permanent &> /dev/null
        echo ""
        echo -e "\033[32m   完成防火墙开放时间服务所需的端口. \033[0m"
        firewall-cmd --add-masquerade --permanent &> /dev/null
        firewall-cmd --add-service=openvpn --permanent &> /dev/null
        firewall-cmd --add-service=ntp --permanent &> /dev/null
        echo ""
        echo -e "\033[32m   完成防火墙开放所需的所有服务端口. \033[0m"
        firewall-cmd --reload &> /dev/null
        echo ""
        echo -e "\033[32m   完成重新载入防火墙配置. \033[0m"
        firewall-cmd --zone=public --list-all
        sleep 3

        # 设置内核转发
        grep 'net.ipv4.ip_forward = 1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
        echo ""
        echo -e "\033[32m   完成开启内核转发. \033[0m"

        # 设置时间同步
        rm -rf /etc/localtime
        ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        timedatectl set-local-rtc 0
        echo ""
        echo -e "\033[32m   完成系统时区配置. \033[0m"
        yum install -y ntp crontabs &> /dev/null
        sed -i 's/server 0.centos.pool.ntp.org iburst/#server 0.centos.pool.ntp.org iburst/g' /etc/ntp.conf
        sed -i 's/server 1.centos.pool.ntp.org iburst/#server 0.centos.pool.ntp.org iburst/g' /etc/ntp.conf
        sed -i 's/server 2.centos.pool.ntp.org iburst/server cn.ntp.org.cn iburst/g' /etc/ntp.conf
        sed -i 's/server 3.centos.pool.ntp.org iburst/server ntp.aliyun.com iburst/g' /etc/ntp.conf
        ntpdate -d ntp.aliyun.com &> /dev/null #同步一次时间
        hwclock --systohc #同步到硬件时钟
        # 将系统时间同步写入crontab，每周一自动校时。
        echo "* * * * 1 root /usr/sbin/ntpdate ntp.aliyun.com &> /dev/null" >> /etc/crontab
        systemctl restart crond.service
        echo ""
        echo -e "\033[32m   完成将系统时间同步到硬件时钟. \033[0m"
        sleep 3

        # 通过date -R可以看到，时区已经更改成东8区了(+8)
        date -R
        systemctl start ntpd
        systemctl enable ntpd
        systemctl status ntpd
        ntpq -p
        timedatectl
        echo ""
        echo -e "\033[32m   完成时间同步设置. \033[0m"
        sleep 3

        # 从本地磁盘安装.
        if [[ $INSTALL_FROM == "localdisk" ]]; then
                cd /tmp/
                yum install -y lz4-devel lzo-devel pam-devel openssl-devel systemd-devel sqlite-devel autoconf automake libtool libtool-ltdl gcc gcc-c++ gnustep-base-libs libobjc &> /dev/null
                if [[ -e /tmp/openvpn-2.4.12.tar.gz ]]; then
                        tar xf /tmp/openvpn-2.4.12.tar.gz &> /dev/null
                        cd /tmp/openvpn-2.4.12
                        echo ""
                        echo -e "\033[32m   编译安装中...请稍等... \033[0m"
                        autoreconf -i -v -f &> /dev/null
                        ./configure --prefix=/usr/local/openvpn --enable-lzo --enable-lz4 --enable-crypto --enable-server --enable-plugins --enable-port-share --enable-iproute2 --enable-pf --enable-plugin-auth-pam --enable-pam-dlopen --enable-systemd &> /dev/null
                        make &> /dev/null && make install &> /dev/null
                        echo ""
                        echo -e "\033[32m   完成OpenVPN的编译安装. \033[0m"
                        sleep 3
                        ln -s /usr/local/openvpn/sbin/openvpn /usr/local/sbin/openvpn
                        sed -i '/ExecStart/s/^/#/' /usr/local/openvpn/lib/systemd/system/openvpn-server@.service
                        sed -i '/#ExecStart/i\ExecStart=/usr/local/openvpn/sbin/openvpn --config server.conf' /usr/local/openvpn/lib/systemd/system/openvpn-server@.service
                        cp -a /usr/local/openvpn/lib/systemd/system/openvpn-server@.service /usr/lib/systemd/system/openvpn.service
                        systemctl enable openvpn.service &> /dev/null
                        echo ""
                        echo -e "\033[32m   完成 OpenVPN-2.4.12 服务配置. \033[0m"
                        sleep 3
                else
                        echo ""
                        echo -e "\033[32m   请先将 openvpn-2.4.12.tar.gz 和 EasyRSA-3.0.8.tgz 安装包复制到 /tmp/，再运行脚本进行安装. \033[0m"
                        installError
                        exit 1
                fi
        fi
        
        # 从GitHub下载安装.
        if [[ $INSTALL_FROM == "cloud" ]]; then
                cd /tmp/
                yum install -y lz4-devel lzo-devel pam-devel openssl-devel systemd-devel sqlite-devel autoconf automake libtool libtool-ltdl gcc gcc-c++ gnustep-base-libs libobjc &> /dev/null
                wget https://github.com/OpenVPN/openvpn/archive/v2.4.12.tar.gz &> /dev/null
                wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.8/EasyRSA-3.0.8.tgz &> /dev/null
                if [[ -e /tmp/v2.4.12.tar.gz ]]; then
                        if [[ -e /tmp/EasyRSA-3.0.8.tgz ]]; then
                                mv v2.4.12.tar.gz openvpn-2.4.12.tar.gz
                                tar xf /tmp/openvpn-2.4.12.tar.gz &> /dev/null
                                cd /tmp/openvpn-2.4.12
                                echo ""
                                echo "编译安装中...请稍等..."
                                autoreconf -i -v -f &> /dev/null
                                ./configure --prefix=/usr/local/openvpn --enable-lzo --enable-lz4 --enable-crypto --enable-server --enable-plugins --enable-port-share --enable-iproute2 --enable-pf --enable-plugin-auth-pam --enable-pam-dlopen --enable-systemd &> /dev/null
                                make &> /dev/null && make install &> /dev/null
                                echo ""
                                echo -e "\033[32m   完成OpenVPN的编译安装. \033[0m"
                                sleep 3
                                ln -s /usr/local/openvpn/sbin/openvpn /usr/local/sbin/openvpn
                                sed -i '/ExecStart/s/^/#/' /usr/local/openvpn/lib/systemd/system/openvpn-server@.service
                                sed -i '/#ExecStart/i\ExecStart=/usr/local/openvpn/sbin/openvpn --config server.conf' /usr/local/openvpn/lib/systemd/system/openvpn-server@.service
                                cp -a /usr/local/openvpn/lib/systemd/system/openvpn-server@.service /usr/lib/systemd/system/openvpn.service
                                systemctl enable openvpn.service &> /dev/null
                                echo ""
                                echo -e "\033[32m   完成 OpenVPN-2.4.12 服务配置. \033[0m"
                                sleep 3
                        else
                                echo ""
                                echo -e "\033[32m   无法下载应用，请先将 openvpn-2.4.12.tar.gz 和 EasyRSA-3.0.8.tgz 安装包复制到 /tmp/，再运行脚本进行安装. \033[0m"
                                installError
                                exit 1
                        fi
                else
                        echo ""
                        echo -e "\033[32m   无法下载应用，请先将 openvpn-2.4.12.tar.gz 和 EasyRSA-3.0.8.tgz 安装包复制到 /tmp/，再运行脚本进行安装. \033[0m"
                        installError
                        exit 1
                fi
        fi

        # 安装最新版EasyRSA.
        if [[ ! -d /etc/openvpn/easyrsa/ ]]; then
                cd /tmp/
                mkdir -p /etc/openvpn/
                tar xf /tmp/EasyRSA-3.0.8.tgz &> /dev/null
                mv /tmp/EasyRSA-3.0.8 /etc/openvpn/easyrsa
                echo ""
                echo -e "\033[32m   完成EasyRSA安装. \033[0m"
                sleep 3
                cd /etc/openvpn/easyrsa/
                cp -a /etc/openvpn/easyrsa/vars.example /etc/openvpn/easyrsa/vars
                checkcountry                
                checkprovince                
                checkcity                
                checkorg                
                checkemail                
                checkiou                
                checkcaexpire                
                checkcerexpire                
                cat >> /etc/openvpn/easyrsa/vars << EOF
set_var EASYRSA_REQ_COUNTRY     "${COUNTRY}"
set_var EASYRSA_REQ_PROVINCE    "${PROVINCE}"
set_var EASYRSA_REQ_CITY        "${CITY}"
set_var EASYRSA_REQ_ORG         "${ORG}"
set_var EASYRSA_REQ_EMAIL       "${EMAIL}"
set_var EASYRSA_REQ_OU          "${IOU}"
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_ALGO            rsa
set_var EASYRSA_CRL_DAYS        "90"
set_var EASYRSA_CA_EXPIRE      ${CAEXPIRE}
set_var EASYRSA_CERT_EXPIRE    ${CEREXPIRE}
EOF
                # Create the PKI, set up the CA, the DH params and the server certificate
                ./easyrsa init-pki
                ./easyrsa build-ca
                echo ""
                echo -e "\033[32m   完成EasyRSA服务器配置，以上输入的CA密码务必牢记！！！ \033[0m"
                echo ""
                echo -e "\033[35m   牢 记 CA 密 码 \033[0m"
                echo -e "\033[35m   牢 记 CA 密 码 \033[0m"
                echo -e "\033[35m   牢 记 CA 密 码 \033[0m"
                echo ""
                echo -e "\033[32m   下面生成服务器证书的过程中，需要输入 CA 密码. \033[0m"
                sleep 3
                ./easyrsa build-server-full server nopass
                echo ""
                echo -e "\033[32m   完成服务器证书生成. \033[0m"
                sleep 3
                ./easyrsa gen-dh
                echo -e "\033[32m   完成创建Diffie-Hellman. \033[0m"
                sleep 3
                openvpn --genkey --secret /etc/openvpn/ta.key
                echo ""
                echo -e "\033[32m   完成 CA 配置. \033[0m"
                sleep 3
        else
                echo ""
                echo -e "\033[32m   EasyRSA 已经安装了，无需再次安装. \033[0m"
                exit 1
        fi

        # 整理服务器证书
        mkdir -p /etc/openvpn/server/
        cp -a /etc/openvpn/easyrsa/pki/ca.crt /etc/openvpn/server/
        cp -a /etc/openvpn/easyrsa/pki/private/server.key /etc/openvpn/server/
        cp -a /etc/openvpn/easyrsa/pki/issued/server.crt /etc/openvpn/server/
        cp -a /etc/openvpn/easyrsa/pki/dh.pem /etc/openvpn/server/
        mv /etc/openvpn/ta.key /etc/openvpn/server/
        echo ""
        echo -e "\033[32m   完成服务器证书整理. \033[0m"

        # 配置LDAP
        echo ""
        echo -e "\033[32m   接下来将配置ldap.conf文件，请根据提示输入相关信息. \033[0m"
        sleep 3
        # Generate ldap.conf
        mkdir /etc/openvpn/auth/
        LdapSetting
        mv /tmp/openvpn-auth-ldap.so /usr/lib64/
        chmod +x /usr/lib64/openvpn-auth-ldap.so
        echo ""
        echo -e "\033[32m   ldap.conf文件配置完成. \033[0m"

        # Generate server.conf
        echo "port $PORT" >/etc/openvpn/server/server.conf
        echo "proto $PROTOCOL" >>/etc/openvpn/server/server.conf
        echo "dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
user nobody
group nobody
server 10.8.1.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push \"route $ROUTE_IP\"
cipher AES-256-CBC
compress lz4-v2
push \"compress lz4-v2\"
keepalive 10 120
max-clients 200
status openvpn-status.log
verb 3
client-to-client
log /var/log/openvpn.log
persist-key
persist-tun
tls-auth /etc/openvpn/server/ta.key 0
key-direction 0
plugin /usr/lib64/openvpn-auth-ldap.so \"/etc/openvpn/auth/ldap.conf sAMAccountName=%u\"
username-as-common-name" >>/etc/openvpn/server/server.conf
        echo ""
        echo -e "\033[32m   完成 server.conf 配置. \033[0m"
        sleep 3

        systemctl start openvpn
        systemctl status openvpn
        echo ""
        echo -e "\033[32m   你 OpenVPN 的所有安装配置均已完成，开始愉快的玩耍吧. \033[0m"
        sleep 3

        # Generate the custom client.ovpn
        newClient
        echo ""
        echo -e "\033[32m   如果你需要配置更多用户，可以再次运行这个脚本. \033[0m"
        sleep 3
}
#-----------------------------------------------------------------------------------------------------
function newClient() {
        echo ""
        echo -e "\033[32m   新建一个VPN用户，请输入用户名(用户名必须由字母和数字组成，它也可以包含下划线或破折号). \033[0m"
        echo ""
        until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
                read -rp "请输入用户名: " -e CLIENT
        done
        echo ""
        echo "你希望启用客户端证书密码吗?"
        echo "   1) 证书无密码"
        echo "   2) 证书有密码(密码必须六位及以上)"
        until [[ $PASS =~ ^[1-2]$ ]]; do
                read -rp "请选择 [1-2]: " -e -i 1 PASS
        done

        CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easyrsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
        if [[ $CLIENTEXISTS == '1' ]]; then
                echo ""
                echo -e "\033[32m   该用户已存在. \033[0m"
                exit
        else
                cd /etc/openvpn/easyrsa/ || return
                case $PASS in
                1)
                        ./easyrsa build-client-full "$CLIENT" nopass
                        ;;
                2)
                        echo -e "\033[35m   下面将要求您输入客户端证书密码 \033[0m"
                        ./easyrsa build-client-full "$CLIENT"
                        ;;
                esac
                echo ""
                echo -e "\033[32m   客户端 $CLIENT 的证书创建完成. \033[0m"
                sleep 3
        fi
        echo ""
        read -rp "请设置账户密码:" CLIENT_PASS
        echo "$CLIENT $CLIENT_PASS" >>/etc/openvpn/server/openvpnpass
        echo ""
        echo -e "\033[32m   要修改${CLIENT}的密码，可以编辑/etc/openvpn/server/openvpnpass进行更改. \033[0m"
        sleep 3

        mkdir -p /etc/openvpn/$CLIENT/
        cp -a /etc/openvpn/easyrsa/pki/ca.crt /etc/openvpn/$CLIENT/
        cp -a /etc/openvpn/easyrsa/pki/private/$CLIENT.key /etc/openvpn/$CLIENT/
        cp -a /etc/openvpn/easyrsa/pki/issued/$CLIENT.crt /etc/openvpn/$CLIENT/
        cp -a /etc/openvpn/server/ta.key /etc/openvpn/$CLIENT/
        echo ""
        echo -e "\033[32m   完成用户${CLIENT}所有证书的整理. \033[0m"
        sleep 3
        echo ""
        echo -e "\033[32m   准备 OpenVPN 提供服务所需的公网IP或域名. \033[0m"
        echo ""
        PUBLICIP=$(curl -s https://api.ipify.org)
        read -rp "请输入公网IP或域名:" -e -i $PUBLICIP PUBLICIP
        PORT=`cat /etc/openvpn/server/server.conf | grep 'port' | awk -F ' ' '{print $2}'`
        PROTOCOL=`cat /etc/openvpn/server/server.conf | grep 'proto' | awk -F ' ' '{print $2}'`

        # Generates the custom client.ovpn
        echo "port $PORT" >/etc/openvpn/$CLIENT/$CLIENT.ovpn
        echo "proto $PROTOCOL" >>/etc/openvpn/$CLIENT/$CLIENT.ovpn
        echo "dev tun
client
remote $PUBLICIP $PORT
resolv-retry infinite
nobind
ca ca.crt
cert $CLIENT.crt
key $CLIENT.key
verb 3
persist-key
persist-tun
remote-cert-tls server
tls-auth ta.key 1
cipher AES-256-CBC
key-direction 1
compress lz4-v2
auth-user-pass
auth-nocache" >>/etc/openvpn/$CLIENT/$CLIENT.ovpn

        echo ""
        echo -e "\033[32m   客户端配置文件已生成完毕：/etc/openvpn/${CLIENT}/${CLIENT}.ovpn. \033[0m"
        echo ""
        echo -e "\033[32m   下载 /etc/openvpn/${CLIENT}/ 目录，并拷贝到客户端程序安装目录. \033[0m"
        echo ""
        exit 0
}
#-----------------------------------------------------------------------------------------------------
function revokeClient() {
        NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easyrsa/pki/index.txt | grep -c "^V")
        if [[ $NUMBEROFCLIENTS == '0' ]]; then
                echo ""
                echo -e "\033[32m   没有用户可被注销. \033[0m"
                exit 1
        fi

        echo ""
        echo "选择你想注销的证书"
        tail -n +2 /etc/openvpn/easyrsa/pki/index.txt | cut -d '=' -f 2 | nl -s ') '
        until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
                if [[ $CLIENTNUMBER == '1' ]]; then
                        read -rp "你想注销的证书是 [1]: " CLIENTNUMBER
                else
                        echo ""
                        read -rp "选择你想注销的证书 [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
                fi
        done
        CLIENT=$(tail -n +2 /etc/openvpn/easyrsa/pki/index.txt | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
        cd /etc/openvpn/easyrsa/
        ./easyrsa revoke "$CLIENT"
        ./easyrsa gen-dh
        rm -rf /etc/openvpn/server/dh.pem
        cp -a /etc/openvpn/easyrsa/pki/dh.pem /etc/openvpn/server/
        rm -rf "/etc/openvpn/$CLIENT/"
        sed -i "/^$CLIENT,.*/d" /etc/openvpn/server/ipp.txt
        sed -i "/^$CLIENT/d" /etc/openvpn/server/openvpnpass
        cp /etc/openvpn/easyrsa/pki/index.txt{,.bk}
        sed -i "/^R/d" /etc/openvpn/easyrsa/pki/index.txt
        echo ""
        echo -e "\033[32m   用户 $CLIENT 已被注销. \033[0m"
}
#-----------------------------------------------------------------------------------------------------
function removeOpenVPN() {
        echo ""
        read -rp "你真的要卸载 OpenVPN? [y/n]: " -e -i n REMOVE
        if [[ $REMOVE == 'y' ]]; then
                # Get OpenVPN port from the configuration
                PORT=$(grep '^port ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
                PROTOCOL=$(grep '^proto ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
                # Stop OpenVPN
                systemctl disable openvpn.service &> /dev/null
                systemctl stop openvpn.service
                # Remove customised service
                rm -rf /usr/local/openvpn/
                rm -rf /usr/lib/systemd/system/openvpn.service
                rm -rf /etc/openvpn/
                rm -rf /usr/lib64/openvpn/
                rm -rf /usr/local/sbin/openvpn
                rm -rf /var/log/openvpn.log             
                rm -rf /tmp/openvpn-2.4.12.tar.gz
                rm -rf /tmp/openvpn-2.4.12
                rm -rf /tmp/EasyRSA-3.0.8.tgz
                rm -rf /tmp/EasyRSA-3.0.8
                firewall-cmd --zone=public --remove-port=$PORT/tcp --permanent &> /dev/null
                firewall-cmd --remove-masquerade --permanent &> /dev/null
                firewall-cmd --remove-service=openvpn --permanent &> /dev/null
                echo -e "\033[32m   防火墙关闭为 OpenVPN 而开放的所有服务和端口. \033[0m"
                firewall-cmd --reload &> /dev/null
                echo ""
                echo -e "\033[32m   OpenVPN 卸载完成. \033[0m"
        else
                echo ""
                echo -e "\033[32m   取消卸载 OpenVPN. \033[0m"
        fi
}
#-----------------------------------------------------------------------------------------------------
function newRouteLan() {
        echo ""
        echo -e "\033[32m   请输入希望新增的允许VPN用户访问的网段地址.例如允许访问内网192.168.10.0段，则输入192.168.10.0 255.255.255.0 \033[0m"
        echo ""
        read -rp "请输入内网网段: " newRouteLan_IP
        echo "push \"route $newRouteLan_IP\"" >>/etc/openvpn/server/server.conf
        echo ""
        echo -e "\033[32m   可被访问的网段已添加. \033[0m"
        echo ""
        cat /etc/openvpn/server/server.conf
}
#-----------------------------------------------------------------------------------------------------
function removeRouteLan() {
        echo ""
        echo -e "\033[32m   请输入希望禁止访问网段.例如192.168.10.0 255.255.255.0 \033[0m"
        echo ""
        read -rp "请输入要禁止访问的网段: " removeRouteLan_IP
        sed -i "/${removeRouteLan_IP}/d" /etc/openvpn/server/server.conf
        echo ""
        echo -e "\033[32m   网段已禁止. \033[0m"
        echo ""
        cat /etc/openvpn/server/server.conf
}
#-----------------------------------------------------------------------------------------------------
function manageMenu() {
        echo ""
        echo -e "\033[32m   欢迎使用 OpenVPN \033[0m"
        echo ""
        echo -e "\033[32m   你的 OpenVPN 已经安装好了. \033[0m"
        echo ""
        echo "你可以："
        echo "   1) 新增一个用户"
        echo "   2) 注销一个用户"
        echo "   3) 所有用户列表"
        echo "   4) 新增一个内网段"
        echo "   5) 删除一个内网段"
        echo "   6) 重新输入LDAP信息"
        echo "   7) 卸载OpenVPN"
        echo "   8) 退出"
        until [[ $MENU_OPTION =~ ^[1-8]$ ]]; do
                read -rp "选项 [1-8]: " MENU_OPTION
        done

        case $MENU_OPTION in
        1)
                newClient
                ;;
        2)
                revokeClient
                ;;
        3)
                tail -n +2 /etc/openvpn/easyrsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
                ;;
        4)
                newRouteLan
                ;;
        5)
                removeRouteLan
                ;;
        6)
                LdapSetting
                ;;
        7)
                removeOpenVPN
                ;;
        8)
                exit 0
                ;;
        esac
}
# Check if OpenVPN is already installed
if [[ -e /etc/openvpn/server/server.conf ]]; then
        manageMenu
else
        installOpenVPN
fi
