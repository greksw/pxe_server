#!/bin/bash

# Функция для проверки успешности выполнения команды
check_success() {
    if [ $? -ne 0 ]; then
        echo "Ошибка при выполнении: $1"
        exit 1
    else
        echo "Успешно: $1"
    fi
}

# Функция для повторных попыток команды
retry_command() {
    local retries=5
    local wait=5
    local attempt=1
    local cmd="$@"
    
    until $cmd; do
        if (( attempt == retries )); then
            echo "Команда '$cmd' не удалась после $retries попыток."
            exit 1
        fi
        echo "Попытка $attempt из $retries завершилась с ошибкой. Повтор через $wait секунд..."
        sleep $wait
        ((attempt++))
    done
    echo "Успешно: $cmd"
}

# Получение последней версии ThinStation из репозитория
get_latest_version() {
    echo "Получение последней версии ThinStation..."
    latest_version=$(git ls-remote --tags https://github.com/Thinstation/thinstation.git | \
                     grep -o 'refs/tags/v[0-9]*\.[0-9]*\.[0-9]*' | \
                     sort -V | tail -n1 | sed 's/refs\/tags\///')
    echo "Последняя версия ThinStation: $latest_version"
}

# Обновление системы
echo "Обновление системы..."
sudo dnf update -y
check_success "Обновление системы"

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
sudo dnf install -y dnsmasq tftp-server nfs-utils syslinux wget vim git curl tmux tar cifs-utils rsync
check_success "Установка пакетов"

# Включение и запуск необходимых сервисов
echo "Включение и запуск сервисов dnsmasq, tftp и nfs..."
sudo systemctl enable --now dnsmasq
check_success "Запуск dnsmasq"
sudo systemctl enable --now tftp.socket
check_success "Запуск tftp"
sudo systemctl enable --now nfs-server
check_success "Запуск nfs-server"

# Настройка dnsmasq для PXE, без раздачи IP
echo "Настройка dnsmasq..."
cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
# Настройки для PXE сервера
interface=ens18
dhcp-boot=pxelinux.0,192.168.2.244
enable-tftp
tftp-root=/var/lib/tftpboot
EOF
check_success "Настройка dnsmasq"

# Перезапуск dnsmasq с новыми настройками
echo "Перезапуск dnsmasq..."
sudo systemctl restart dnsmasq
check_success "Перезапуск dnsmasq"

# Настройка TFTP сервера
echo "Настройка TFTP сервера..."
sudo mkdir -p /var/lib/tftpboot
cd /var/lib/tftpboot

# Копирование файлов загрузчика
echo "Загрузка и распаковка syslinux..."
retry_command wget https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.gz -O syslinux.tar.gz
check_success "Загрузка syslinux"
tar -xzf syslinux.tar.gz
check_success "Распаковка syslinux"

if [ -f syslinux-6.03/bios/core/pxelinux.0 ]; then
    cp syslinux-6.03/bios/core/pxelinux.0 /var/lib/tftpboot/
    check_success "Копирование pxelinux.0"
else
    echo "Ошибка: не удалось найти pxelinux.0 в syslinux-6.03."
    exit 1
fi

cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 /var/lib/tftpboot/
cp syslinux-6.03/bios/com32/menu/menu.c32 /var/lib/tftpboot/
cp syslinux-6.03/bios/com32/libutil/libutil.c32 /var/lib/tftpboot/
sudo chown -R nobody:nobody /var/lib/tftpboot/
sudo chmod -R 755 /var/lib/tftpboot/
check_success "Копирование файлов загрузчика"

# Получение последней версии ThinStation
get_latest_version

# Настройка ThinStation
echo "Настройка ThinStation..."
mkdir -p /var/lib/tftpboot/thinstation
cd /var/lib/tftpboot/thinstation

# Загрузка ThinStation с использованием последней версии
echo "Загрузка ThinStation версии $latest_version через git..."
retry_command git clone --branch "$latest_version" https://github.com/Thinstation/thinstation.git .
check_success "Загрузка ThinStation $latest_version"

# Сборка файлов ThinStation с настройками RDP
echo "Настройка ThinStation для RDP..."
cat <<EOF > /var/lib/tftpboot/thinstation/build.conf
NET_USE_DHCP=On
SESSION_0_TYPE=rdesktop
SESSION_0_TITLE="Remote Desktop"
SESSION_0_RDESKTOP_SERVER="192.168.2.25"    # IP адрес RDP сервера
SESSION_0_RDESKTOP_OPTIONS="-f -u user -p password" # Настройки подключения (замените на свои)
EOF
check_success "Создание build.conf для RDP подключения"

# Сборка ThinStation для PXE
echo "Сборка ThinStation для PXE..."
cd /var/lib/tftpboot/thinstation
retry_command ./build -b pxe
check_success "Сборка ThinStation для PXE"

# Создание конфигурации PXE
echo "Создание конфигурации PXE..."
mkdir -p /var/lib/tftpboot/pxelinux.cfg
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT menu.c32
TIMEOUT 600
PROMPT 0
ONTIMEOUT local
LABEL thinstation
    MENU LABEL ThinStation
    KERNEL /thinstation/bzImage
    APPEND initrd=/thinstation/initrd console=ttyS0
EOF
check_success "Создание PXE конфигурации"

# Настройка NFS для раздачи файлов
echo "Настройка NFS..."
echo "/var/lib/tftpboot *(ro,sync,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -r
sudo systemctl restart nfs-server
check_success "Настройка NFS"

# Открытие портов на firewall
echo "Открытие портов на firewall..."
sudo firewall-cmd --permanent --zone=public --add-service=tftp
sudo firewall-cmd --permanent --zone=public --add-service=nfs
sudo firewall-cmd --reload
check_success "Открытие портов на firewall"

echo "ThinStation PXE сервер установлен и настроен. Перезагрузите сервер для применения настроек."
