#!/usr/bin/env bash

#####################################################
# 源自 https://mailinabox.email/ 
# 由 cryptopool.builders 更新用于加密货币使用...
#####################################################

# 检测 Ubuntu 版本
DISTRO=$(lsb_release -cs)
# 设置 YiiMP 仓库地址
YiiMPRepo=${YiiMPRepo:-"https://github.com/cryptopool-builders/yiimp.git"}

if [[ ! "$DISTRO" =~ ^(xenial|bionic|focal|jammy)$ ]]; then
    echo "不支持的 Ubuntu 版本: $DISTRO"
    echo "本脚本仅支持 Ubuntu 16.04 (xenial), 18.04 (bionic), 20.04 (focal) 和 22.04 (jammy)"
    exit 1
fi

clear
source /etc/functions.sh
source $STORAGE_ROOT/yiimp/.yiimp.conf
source $HOME/multipool/yiimp_single/.wireguard.install.cnf

# 设置严格模式,遇到错误立即退出
set -eu -o pipefail

# 错误处理函数
function print_error {
    read line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

# 如果启用了 WireGuard,加载其配置
if [[ ("$wireguard" == "true") ]]; then
source $STORAGE_ROOT/yiimp/.wireguard.conf
fi

# 如果使用域名,设置主机名
if [[ ("$UsingDomain" == "yes") ]]; then
	echo ${DomainName} | hide_output sudo tee -a /etc/hostname
	sudo hostname "${DomainName}"
fi

# 设置时区为 UTC
echo -e " Setting TimeZone to UTC...$COL_RESET"
if [ ! -f /etc/timezone ]; then
echo "Setting timezone to UTC."
echo "Etc/UTC" > sudo /etc/timezone
restart_service rsyslog
fi
echo -e "$GREEN Done...$COL_RESET"

# 添加必要的软件源
echo -e " Adding the required repsoitories...$COL_RESET"
if [ ! -f /usr/bin/add-apt-repository ]; then
echo "Installing add-apt-repository..."
hide_output sudo apt-get -y update
apt_install software-properties-common
fi
echo -e "$GREEN Done...$COL_RESET"

# 添加 PHP 8.1 PPA 源
echo -e " Installing Ondrej PHP PPA...$COL_RESET"
if [ ! -f /etc/apt/sources.list.d/ondrej-php-jammy.list ]; then
hide_output sudo add-apt-repository -y ppa:ondrej/php
fi
echo -e "$GREEN Done...$COL_RESET"

# 添加 MariaDB 仓库
echo -e " Installing MariaDB Repository...$COL_RESET"
hide_output sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
# 更新为支持 Ubuntu 22.04 (jammy)
if [[ ("$DISTRO" == "16") ]]; then
  sudo add-apt-repository 'deb [arch=amd64,arm64,i386,ppc64el] http://mirror.one.com/mariadb/repo/10.6/ubuntu xenial main' >/dev/null 2>&1
else
  sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] http://mirror.one.com/mariadb/repo/10.6/ubuntu jammy main' >/dev/null 2>&1
fi
echo -e "$GREEN Done...$COL_RESET"

# 更新系统包
echo -e " Updating system packages...$COL_RESET"
# 使用 mktemp 替代 tempfile
TEMP_FILE=$(mktemp)
hide_output sudo apt-get update > "$TEMP_FILE" 2>&1
rm -f "$TEMP_FILE"
echo -e "$GREEN Done...$COL_RESET"

# 升级系统包
echo -e " Upgrading system packages...$COL_RESET"
if [ ! -f /boot/grub/menu.lst ]; then
apt_get_quiet upgrade
else
sudo rm /boot/grub/menu.lst
hide_output sudo update-grub-legacy-ec2 -y
apt_get_quiet upgrade
fi
echo -e "$GREEN Done...$COL_RESET"

# 执行发行版升级
echo -e " Running Dist-Upgrade...$COL_RESET"
apt_get_quiet dist-upgrade
echo -e "$GREEN Done...$COL_RESET"

# 清理不需要的包
echo -e " Running Autoremove...$COL_RESET"
apt_get_quiet autoremove

echo -e "$GREEN Done...$COL_RESET"

# 安装基础系统包
echo -e " Installing Base system packages...$COL_RESET"
apt_install python3 python3-dev python3-pip \
wget curl git sudo coreutils bc \
haveged pollinate unzip \
unattended-upgrades cron ntp fail2ban screen rsyslog

# 初始化系统随机数生成器
echo -e "$GREEN Done...$COL_RESET"
echo -e " Initializing system random number generator...$COL_RESET"
hide_output dd if=/dev/random of=/dev/urandom bs=1 count=32 2> /dev/null
hide_output sudo pollinate -q -r
echo -e "$GREEN Done...$COL_RESET"

# 初始化 UFW 防火墙
echo -e " Initializing UFW Firewall...$COL_RESET"
set +eu +o pipefail
if [ -z "${DISABLE_FIREWALL:-}" ]; then
	apt_install ufw
	ufw_allow ssh
	ufw_allow http
	ufw_allow https
	# 添加 YiiMP 所需的其他端口
	# ufw_allow 3333  # 例如：挖矿端口
	# ufw_allow 6379  # 例如：Redis 端口
fi
sudo ufw --force enable;
fi 
set -eu -o pipefail
echo -e "$GREEN Done...$COL_RESET"

# 安装 YiiMP 所需的系统包
echo -e " Installing YiiMP Required system packages...$COL_RESET"
# 如果安装了 Apache,先移除它
if [ -f /usr/sbin/apache2 ]; then
echo Removing apache...
hide_output apt-get -y purge apache2 apache2-*
hide_output apt-get -y --purge autoremove
fi

hide_output sudo apt-get update

# 根据不同的 Ubuntu 版本安装相应的包
if [[ ("$DISTRO" == "16") ]]; then
apt_install php8.1-fpm php8.1-opcache php8.1 php8.1-common php8.1-gd \
php8.1-mysql php8.1-imap php8.1-cli php8.1-cgi \
php-pear php-auth-sasl mcrypt imagemagick libruby \
php8.1-curl php8.1-intl php8.1-pspell php8.1-sqlite3 \
php8.1-tidy php8.1-xmlrpc php8.1-xsl memcached php-memcache \
php-imagick php-gettext php8.1-zip php8.1-mbstring \
fail2ban ntpdate python3 python3-dev python3-pip \
curl git sudo coreutils pollinate unzip unattended-upgrades cron \
pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev \
libkrb5-dev libldap2-dev libidn11-dev gnutls-dev librtmp-dev \
build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev \
automake cmake gnupg2 ca-certificates lsb-release nginx certbot libsodium-dev \
libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev
else
apt_install php8.1-fpm php8.1-opcache php8.1 php8.1-common php8.1-gd \
php8.1-mysql php8.1-imap php8.1-cli php8.1-cgi \
php-pear php-auth-sasl imagemagick libruby \
php8.1-curl php8.1-intl php8.1-pspell php8.1-sqlite3 \
php8.1-tidy php8.1-xmlrpc php8.1-xsl memcached php-memcache \
php-imagick php-gettext php8.1-zip php8.1-mbstring \
fail2ban ntpdate python3 python3-dev python3-pip \
curl git sudo coreutils pollinate unzip unattended-upgrades cron \
pwgen libgmp3-dev libmysqlclient-dev libcurl4-gnutls-dev \
libkrb5-dev libldap2-dev libidn11-dev librtmp-dev \
build-essential libtool autotools-dev automake pkg-config libevent-dev bsdmainutils libssl-dev \
libpsl-dev libnghttp2-dev automake cmake gnupg2 ca-certificates lsb-release nginx certbot libsodium-dev \
libnghttp2-dev librtmp-dev libssh2-1 libssh2-1-dev libldap2-dev libidn11-dev libpsl-dev libkrb5-dev
fi

# 禁止系统升级提示
# 防止在 Ubuntu 20 发布时提示升级
if [ -f /etc/update-manager/release-upgrades ]; then
sudo editconf.py /etc/update-manager/release-upgrades Prompt=never
sudo rm -f /var/lib/ubuntu-release-upgrader/release-upgrade-available
fi

echo -e "$GREEN Done...$COL_RESET"

# 下载 YiiMP 代码库
echo -e " Downloading CryptoPool.builders YiiMP Repo...$COL_RESET"
hide_output sudo git clone ${YiiMPRepo} $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
if [[ ("$CoinPort" == "yes") ]]; then
	cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
	sudo git fetch
	sudo git checkout multi-port >/dev/null 2>&1
fi
echo -e "$GREEN System files installed...$COL_RESET"

set +eu +o pipefail
cd $HOME/multipool/yiimp_single
