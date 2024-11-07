#!/bin/bash

# Обновление системы
sudo dnf update -y

# Установка необходимых пакетов
sudo dnf install -y dnsmasq tftp-server nfs-utils syslinux wget

# Включение и запуск необходимых сервисов
sudo systemctl enable --now dnsmasq
sudo systemctl enable --now tftp.socket
sudo systemctl enable --now nfs-server

# Настройка DHCP через dnsmasq (без настройки диапазона IP, так как DHCP на другом сервере)
cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
# Настройки для PXE сервера
interface=ens18           # Используем интерфейс ens18, замените на нужный
#dhcp-range=192.168.2.20,192.168.2.50,12h # Диапазон IP для DHCP если на этом сервере DHCP сервер
dhcp-boot=pxelinux.0,192.168.2.244  # Имя файла загрузчика и IP PXE-сервера
enable-tftp              # Включаем TFTP
tftp-root=/var/lib/tftpboot # Папка с TFTP файлами
EOF

# Перезапуск dnsmasq с новыми настройками
sudo systemctl restart dnsmasq

# Настройка TFTP сервера
sudo mkdir -p /var/lib/tftpboot
cd /var/lib/tftpboot

# Копирование файлов загрузчика
wget https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.04-pre1.tar.gz
tar -xzf syslinux-6.04-pre1.tar.gz

# Копирование pxelinux.0
cp syslinux-6.04-pre1/bios/core/pxelinux.0 /var/lib/tftpboot/

# Создание конфигурации PXE
mkdir -p /var/lib/tftpboot/pxelinux.cfg
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT menu
LABEL menu
    MENU TITLE PXE Boot Menu
    MENU BACKGROUND splash.png
    TIMEOUT 100
    ONTIMEOUT local
    PROMPT 0
    LABEL ubuntu
        MENU LABEL Ubuntu 24.04.1 LTS
        KERNEL /ubuntu-installer/amd64/linux
        APPEND initrd=/ubuntu-installer/amd64/initrd.gz
    LABEL almalinux
        MENU LABEL AlmaLinux 9.4
        KERNEL /almalinux-9.4/isolinux/vmlinuz
        APPEND initrd=/almalinux-9.4/isolinux/initrd.img
EOF

# Скачиваем необходимые файлы ядра и initrd для Ubuntu 24.04.1
cd /var/lib/tftpboot
mkdir -p ubuntu-installer/amd64
wget https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-desktop-amd64.iso -O /var/lib/tftpboot/ubuntu-installer/amd64/ubuntu-24.04.1-desktop-amd64.iso
mount -o loop /var/lib/tftpboot/ubuntu-installer/amd64/ubuntu-24.04.1-desktop-amd64.iso /mnt
cp /mnt/casper/vmlinuz /var/lib/tftpboot/ubuntu-installer/amd64/
cp /mnt/casper/initrd /var/lib/tftpboot/ubuntu-installer/amd64/
umount /mnt

# Скачиваем файлы для AlmaLinux 9.4
mkdir -p almalinux-9.4/isolinux
wget https://raw.repo.almalinux.org/almalinux/9.4/live/x86_64/AlmaLinux-9.4-x86_64-Live-GNOME-Mini.iso -O /var/lib/tftpboot/almalinux-9.4/isolinux/AlmaLinux-9.4-x86_64-Live-GNOME-Mini.iso
mount -o loop /var/lib/tftpboot/almalinux-9.4/isolinux/AlmaLinux-9.4-x86_64-Live-GNOME-Mini.iso /mnt
cp /mnt/isolinux/vmlinuz /var/lib/tftpboot/almalinux-9.4/isolinux/
cp /mnt/isolinux/initrd.img /var/lib/tftpboot/almalinux-9.4/isolinux/
umount /mnt

# Открытие портов на firewall
sudo firewall-cmd --permanent --zone=public --add-service=dhcp
sudo firewall-cmd --permanent --zone=public --add-service=tftp
sudo firewall-cmd --permanent --zone=public --add-service=nfs
sudo firewall-cmd --reload

echo "PXE сервер установлен и настроен. Перезагрузите сервер."
