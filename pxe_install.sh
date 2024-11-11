#!/bin/bash

# Функция для логгирования и проверки успешности команды
check_command() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "Ошибка при выполнении: $@" >&2
        exit $status
    else
        echo "Успешно: $@"
    fi
    return $status
}

# Обновление системы и установка необходимых пакетов
echo "Обновление системы..."
check_command sudo dnf update -y
echo "Установка необходимых пакетов..."
check_command sudo dnf install -y dnsmasq tftp-server syslinux wget vim curl git tar

# Включение и запуск TFTP и DHCP сервисов
echo "Включение и запуск сервисов..."
check_command sudo systemctl enable --now dnsmasq
check_command sudo systemctl enable --now tftp.socket

# Настройка dnsmasq для PXE
echo "Настройка dnsmasq для PXE..."
cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
interface=ens18                 # Используем интерфейс, замените на нужный
dhcp-boot=pxelinux.0,192.168.2.244
enable-tftp
tftp-root=/var/lib/tftpboot
EOF
check_command sudo systemctl restart dnsmasq

# Настройка TFTP сервера
echo "Настройка TFTP сервера..."
check_command sudo mkdir -p /var/lib/tftpboot
cd /var/lib/tftpboot

# Копирование PXE-загрузчика
echo "Загрузка и распаковка syslinux..."
check_command wget https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.gz
check_command tar -xzf syslinux-6.03.tar.gz
check_command cp syslinux-6.03/bios/core/pxelinux.0 /var/lib/tftpboot/
check_command cp syslinux-6.03/bios/com32/menu/menu.c32 /var/lib/tftpboot/
check_command cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 /var/lib/tftpboot/
check_command cp syslinux-6.03/bios/com32/libutil/libutil.c32 /var/lib/tftpboot/

# Настройка PXE меню
echo "Настройка PXE меню..."
check_command mkdir -p /var/lib/tftpboot/pxelinux.cfg
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT menu.c32
PROMPT 0
TIMEOUT 50
ONTIMEOUT thinstation

LABEL thinstation
    MENU LABEL ThinStation RDP Client
    KERNEL thinstation/vmlinuz
    APPEND initrd=thinstation/initrd splash lang=en screen=1024x768
EOF

# Загрузка и установка ThinStation
echo "Загрузка ThinStation из репозитория..."
check_command mkdir -p /var/lib/tftpboot/thinstation
cd /var/lib/tftpboot/thinstation
check_command git clone https://github.com/Thinstation/thinstation.git .
check_command ./setup-chroot.sh

# Сборка файлов ThinStation с настройками RDP
echo "Настройка ThinStation для RDP..."
cat <<EOF > build.conf
NET_USE_DHCP=On
SESSION_0_TYPE=rdesktop
SESSION_0_TITLE="Remote Desktop"
SESSION_0_RDESKTOP_SERVER="192.168.2.25"    # IP адрес RDP сервера
#SESSION_0_RDESKTOP_OPTIONS="-f -u user -p password" # Настройки подключения (замените на свои)
EOF

echo "Сборка ThinStation для PXE..."
check_command ./build.sh -b pxe

# Копирование сгенерированных файлов в TFTP директорию
echo "Копирование сгенерированных файлов в TFTP директорию..."
check_command cp boot-images/pxe/vmlinuz /var/lib/tftpboot/thinstation/
check_command cp boot-images/pxe/initrd /var/lib/tftpboot/thinstation/

# Открытие необходимых портов на firewall
echo "Открытие необходимых портов на firewall..."
check_command sudo firewall-cmd --permanent --zone=public --add-service=tftp
check_command sudo firewall-cmd --permanent --zone=public --add-service=dhcp
check_command sudo firewall-cmd --reload

echo "ThinStation PXE сервер установлен и настроен. Перезагрузите сервер для применения настроек."
