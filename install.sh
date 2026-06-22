#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误：${plain} 请使用 root 权限运行此脚本 \n " && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "检测系统版本失败，请联系作者！" >&2
    exit 1
fi
echo "当前系统版本：$release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}不支持的 CPU 架构！ ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "架构：$(arch)"

install_base() {
    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

random_string() {
    local length=${1:-8}
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c ${length}
}

random_port() {
    shuf -i 20000-65535 -n 1
}

config_after_install() {
    local is_fresh_install=false
    if [[ ! -f "/usr/local/s-ui/db/s-ui.db" ]]; then
        is_fresh_install=true
    fi

    echo -e "${yellow}正在迁移数据... ${plain}"
    /usr/local/s-ui/sui migrate

    if [[ "${is_fresh_install}" == "true" ]]; then
        local config_port=$(random_port)
        local config_subPort=$(random_port)
        while [[ "${config_subPort}" == "${config_port}" ]]; do
            config_subPort=$(random_port)
        done
        local config_path="/$(random_string 10)"
        local config_subPath="/$(random_string 10)"
        local usernameTemp="$(random_string 10)"
        local passwordTemp="$(random_string 16)"

        echo -e "${yellow}检测到全新安装，正在生成随机安全配置...${plain}"
        /usr/local/s-ui/sui setting -port ${config_port} -path ${config_path} -subPort ${config_subPort} -subPath ${config_subPath}
        /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}

        echo -e "###############################################"
        echo -e "${green}面板端口：${config_port}${plain}"
        echo -e "${green}面板路径：${config_path}${plain}"
        echo -e "${green}订阅端口：${config_subPort}${plain}"
        echo -e "${green}订阅路径：${config_subPath}${plain}"
        echo -e "${green}管理员用户名：${usernameTemp}${plain}"
        echo -e "${green}管理员密码：${passwordTemp}${plain}"
        echo -e "###############################################"
        echo -e "${red}请务必保存以上随机登录信息；如果忘记，可输入 ${green}s-ui${red} 打开配置菜单重新设置${plain}"
        return
    fi

    echo -e "${yellow}安装/更新完成！这是升级操作，将保留原有设置 ${plain}"
    read -p "是否继续修改面板设置 [y/n]：" config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        echo -e "请输入${yellow}面板端口${plain}（留空则保持现有/默认值）："
        read config_port
        echo -e "请输入${yellow}面板路径${plain}（留空则保持现有/默认值）："
        read config_path

        # Sub configuration
        echo -e "请输入${yellow}订阅端口${plain}（留空则保持现有/默认值）："
        read config_subPort
        echo -e "请输入${yellow}订阅路径${plain}（留空则保持现有/默认值）："
        read config_subPath

        # Set configs
        echo -e "${yellow}正在初始化，请稍候...${plain}"
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
        [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
        /usr/local/s-ui/sui setting ${params}

        read -p "是否修改管理员账号密码 [y/n]：" admin_confirm
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            read -p "请设置用户名：" config_account
            read -p "请设置密码：" config_password

            echo -e "${yellow}正在初始化，请稍候...${plain}"
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        else
            echo -e "${yellow}您当前的管理员账号信息： ${plain}"
            /usr/local/s-ui/sui admin -show
        fi
    else
        echo -e "${red}已取消，将保留原有设置。如果忘记登录信息，可输入 ${green}s-ui${red} 打开配置菜单${plain}"
    fi
}

prepare_services() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        echo -e "${yellow}正在停止 sing-box 服务... ${plain}"
        systemctl stop sing-box
        rm -f /usr/local/s-ui/bin/sing-box /usr/local/s-ui/bin/runSingbox.sh /usr/local/s-ui/bin/signal
    fi
    if [[ -e "/usr/local/s-ui/bin" ]]; then
        echo -e "###############################################################"
        echo -e "${green}/usr/local/s-ui/bin${red} 目录已存在！"
        echo -e "请检查目录内容，迁移完成后请手动删除 ${plain}"
        echo -e "###############################################################"
    fi
    systemctl daemon-reload
}

install_acme() {
    cd ~
    echo -e "${green}[信息]${plain} 正在安装 acme..."
    curl https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        echo -e "${red}[错误]${plain} 安装 acme 失败"
        return 1
    else
        echo -e "${green}[信息]${plain} 安装 acme 成功"
    fi
    return 0
}

set_setting_value() {
    local key=$1
    local value=$2
    local dbPath="/usr/local/s-ui/db/s-ui.db"
    sqlite3 "${dbPath}" "UPDATE settings SET value='${value}' WHERE key='${key}'; INSERT INTO settings (key, value) SELECT '${key}', '${value}' WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='${key}');"
}

apply_ip_cert_to_panel() {
    local serverIP=$1
    local certFile="/root/cert/${serverIP}/fullchain.pem"
    local keyFile="/root/cert/${serverIP}/privkey.pem"
    local dbPath="/usr/local/s-ui/db/s-ui.db"

    if [[ ! -f "${dbPath}" ]]; then
        echo -e "${red}[错误]${plain} 未找到 s-ui 数据库：${dbPath}，无法自动应用证书"
        return 1
    fi
    if [[ ! -f "${certFile}" || ! -f "${keyFile}" ]]; then
        echo -e "${red}[错误]${plain} 未找到证书文件，无法自动应用证书"
        return 1
    fi
    if ! command -v sqlite3 &>/dev/null; then
        echo -e "${red}[错误]${plain} 未找到 sqlite3，无法自动写入面板证书配置"
        return 1
    fi

    set_setting_value "webCertFile" "${certFile}"
    set_setting_value "webKeyFile" "${keyFile}"
    set_setting_value "subCertFile" "${certFile}"
    set_setting_value "subKeyFile" "${keyFile}"

    echo -e "${green}[信息]${plain} 已将证书应用到面板和订阅配置"
    if [[ -f "/etc/systemd/system/s-ui.service" ]]; then
        systemctl restart s-ui
        echo -e "${green}[信息]${plain} 已重启 s-ui 服务，请使用 https:// 访问面板"
    fi
}

# 为 IP 地址申请 Let's Encrypt 短期证书（6 天有效期，自动续期）
ssl_cert_issue_IP() {
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "未找到 acme.sh，将进行安装"
        install_acme
        if [ $? -ne 0 ]; then
            echo -e "${red}[错误]${plain} 安装 acme 失败，请检查日志"
            exit 1
        fi
    fi
    case "${release}" in
    ubuntu | debian | armbian)
        apt update && apt install socat sqlite3 -y
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum -y install socat sqlite
        ;;
    fedora)
        dnf -y update && dnf -y install socat sqlite
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm socat sqlite
        ;;
    *)
        echo -e "${red}不支持的操作系统，请检查脚本并手动安装必要的软件包。${plain}\n"
        exit 1
        ;;
    esac
    if [ $? -ne 0 ]; then
        echo -e "${red}[错误]${plain} 安装 socat/sqlite3 失败，请检查日志"
        exit 1
    else
        echo -e "${green}[信息]${plain} 安装 socat/sqlite3 成功..."
    fi

    DEFAULT_IP=$(curl -s https://api64.ipify.org)
    local serverIP=""
    if [[ -n "${DEFAULT_IP}" ]]; then
        read -p "请输入服务器的 IP 地址 [默认 ${DEFAULT_IP}]：" serverIP
    else
        read -p "请输入服务器的 IP 地址：" serverIP
    fi
    if [[ -z "${serverIP}" ]]; then
        serverIP="${DEFAULT_IP}"
    fi
    if [[ -z "${serverIP}" ]]; then
        echo -e "${red}[错误]${plain} 未能获取 IP 地址，退出"
        exit 1
    fi
    echo -e "${yellow}[调试]${plain} 您的 IP 地址为：${serverIP}，正在检查..."

    certPath="/root/cert/${serverIP}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    local cert_exists=false
    if ~/.acme.sh/acme.sh --list | awk '{print $1}' | grep -Fxq "${serverIP}"; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        echo -e "${green}[信息]${plain} 系统中已存在该 IP 的证书，将直接安装使用，当前证书详情："
        echo -e "${green}[信息]${plain} $certInfo"
        cert_exists=true
    else
        echo -e "${green}[信息]${plain} 您的 IP 已准备好申请证书..."
    fi

    if [[ "${cert_exists}" != "true" ]]; then
        local WebPort=80
        read -p "请选择用于验证的端口，默认为 80 端口：" WebPort
        if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
            echo -e "${red}[错误]${plain} 您输入的 ${WebPort} 无效，将使用默认端口 80"
            WebPort=80
        fi
        echo -e "${green}[信息]${plain} 将使用端口：${WebPort} 申请证书，请确保该端口已开放..."

        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            echo -e "${red}[错误]${plain} 设置默认 CA Let's Encrypt 失败，退出..."
            exit 1
        fi

        # 使用 short-lived 配置文件申请 6 天有效期的 IP 地址证书
        ~/.acme.sh/acme.sh --issue -d ${serverIP} --standalone --httpport ${WebPort} \
            --default-profile shortzl
        if [ $? -ne 0 ]; then
            echo -e "${red}[错误]${plain} 申请证书失败，请检查日志"
            rm -rf ~/.acme.sh/${serverIP}
            exit 1
        else
            echo -e "${green}[信息]${plain} 申请证书成功，正在安装证书..."
        fi
    fi

    ~/.acme.sh/acme.sh --installcert -d ${serverIP} \
        --key-file /root/cert/${serverIP}/privkey.pem \
        --fullchain-file /root/cert/${serverIP}/fullchain.pem

    if [ $? -ne 0 ]; then
        echo -e "${red}[错误]${plain} 安装证书失败，退出"
        rm -rf ~/.acme.sh/${serverIP}
        exit 1
    else
        echo -e "${green}[信息]${plain} 安装证书成功，正在启用自动续期..."
    fi

    # 新申请证书时设置续期周期为 5 天；已有证书时直接使用现有续期配置
    if [[ "${cert_exists}" != "true" ]]; then
        ~/.acme.sh/acme.sh --renew -d ${serverIP} --force --days 5
    fi
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        echo -e "${red}[错误]${plain} 自动续期设置失败，证书详情："
        ls -lah /root/cert/${serverIP}
        chmod 755 $certPath/*
        exit 1
    else
        echo -e "${green}[信息]${plain} 自动续期设置成功，证书详情："
        ls -lah /root/cert/${serverIP}
        chmod 755 $certPath/*
        apply_ip_cert_to_panel "${serverIP}"
    fi
}

install_s-ui() {
    cd /tmp/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}获取 s-ui 版本失败，可能是由于 Github API 限制，请稍后重试${plain}"
            exit 1
        fi
        echo -e "已获取 s-ui 最新版本：${last_version}，开始安装..."
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 s-ui 失败，请确认服务器能够访问 Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 s-ui v$1"
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 s-ui v$1 失败，请检查该版本是否存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/s-ui/ ]]; then
        systemctl stop s-ui
    fi

    tar zxvf s-ui-linux-$(arch).tar.gz
    rm s-ui-linux-$(arch).tar.gz -f

    echo -e "${yellow}正在更新汉化版管理脚本...${plain}"
    wget -N --no-check-certificate -O s-ui/s-ui.sh https://raw.githubusercontent.com/skadiqin/s-ui/main/s-ui.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载汉化版管理脚本失败，请确认服务器能够访问 Github ${plain}"
        exit 1
    fi

    chmod +x s-ui/sui s-ui/s-ui.sh
    cp s-ui/s-ui.sh /usr/bin/s-ui
    cp -rf s-ui /usr/local/
    cp -f s-ui/*.service /etc/systemd/system/
    rm -rf s-ui

    config_after_install
    prepare_services

    systemctl enable s-ui --now

    echo -e "${green}s-ui v${last_version}${plain} 安装完成，现已启动运行..."
    echo -e "您可以通过以下 URL 访问面板：${green}"
    /usr/local/s-ui/sui uri
    echo -e "${plain}"
    echo -e ""

    # 安装完成后，提示是否为 IP 地址申请 SSL 证书
    read -p "是否为当前服务器 IP 申请 SSL 证书（6 天有效期，自动续期）[y/n]？" ssl_ip_confirm
    if [[ "${ssl_ip_confirm}" == "y" || "${ssl_ip_confirm}" == "Y" ]]; then
        ssl_cert_issue_IP
    fi

    s-ui help
}

echo -e "${green}正在执行...${plain}"

# 支持通过子命令单独为 IP 申请 SSL 证书：bash install.sh ssl-ip
if [[ $# -gt 0 && "$1" == "ssl-ip" ]]; then
    ssl_cert_issue_IP
    exit 0
fi

install_base
install_s-ui $1
