#!/bin/bash

# Обновление системы
sudo dnf update -y

# Установка необходимых пакетов
sudo dnf install -y dnsmasq tftp-server nfs-utils syslinux wget

# Включение и запуск необходимых сервисов
sudo systemctl enable --now dnsmasq
sudo systemctl enable --now tftp.socket
sudo systemctl enable --now nfs-server

# Настройка DHCP через dnsmasq
cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
# Настройки для PXE сервера
interface=eth0           # Используем интерфейс eth0, замените на нужный
dhcp-boot=pxelinux.0,192.168.2.244  # Имя файла загрузчика и IP PXE-сервера(если DHCP сервером является др сервер или роутер)
#dhcp-range=192.168.2.20,192.168.2.50,12h # Диапазон IP для DHCP если он развернут на этом сервере
dhcp-boot=pxelinux.0     # Имя файла загрузчика
enable-tftp              # Включаем TFTP
tftp-root=/var/lib/tftpboot # Папка с TFTP файлами
EOF

# Перезапуск dnsmasq с новыми настройками
sudo systemctl restart dnsmasq

# Настройка TFTP сервера
sudo mkdir -p /var/lib/tftpboot
cd /var/lib/tftpboot

# Копирование файлов загрузчика (syslinux)
# Скачиваем pxelinux.0 и другие необходимые файлы
cp /path/to/syslinux-6.03/bios/com32/pxelinux/pxelinux.0 /var/lib/tftpboot/
cp /path/to/syslinux-6.03/bios/com32/menu/ldlinux.c32 /var/lib/tftpboot/
cp /path/to/syslinux-6.03/bios/com32/menu/menu.c32 /var/lib/tftpboot/

# Создание конфигурации PXE
mkdir -p /var/lib/tftpboot/pxelinux.cfg
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT ubuntu
LABEL ubuntu
    KERNEL vmlinuz
    APPEND initrd=initrd.img
    MENU LABEL Install Ubuntu
    IPAPPEND 2
EOF

# Скачиваем необходимые файлы ядра и initrd для Ubuntu
cd /var/lib/tftpboot
wget http://archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux -O vmlinuz
wget http://archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz -O initrd.img

# Настройка NFS для раздачи файлов
echo "/var/lib/tftpboot *(ro,sync,no_root_squash)" | sudo tee -a /etc/exports

# Перезапуск NFS
sudo exportfs -r
sudo systemctl restart nfs-server

# Открытие портов на firewall
sudo firewall-cmd --permanent --zone=public --add-service=dhcp
sudo firewall-cmd --permanent --zone=public --add-service=tftp
sudo firewall-cmd --permanent --zone=public --add-service=nfs
sudo firewall-cmd --reload

echo "PXE сервер установлен и настроен. Перезагрузите сервер."

#!/bin/bash
# Обновление системы
sudo dnf update -y
# Установка необходимых пакетов
sudo dnf install -y dnsmasq tftp-server nfs-utils syslinux wget tmux curl tar
# Включение и запуск необходимых сервисов
sudo systemctl enable --now dnsmasq
sudo systemctl enable --now tftp.socket
sudo systemctl enable --now nfs-server
# Настройка dnsmasq для PXE, без раздачи IP
cat <<EOF | sudo tee /etc/dnsmasq.conf > /dev/null
# Настройки для PXE сервера
interface=eth0                  # Используем интерфейс eth0, замените на нужный
dhcp-boot=pxelinux.0,192.168.2.244  # Имя файла загрузчика и IP PXE-сервера
enable-tftp                     # Включаем TFTP
tftp-root=/var/lib/tftpboot     # Папка с TFTP файлами
EOF
# Перезапуск dnsmasq с новыми настройками
sudo systemctl restart dnsmasq
# Настройка TFTP сервера
sudo mkdir -p /var/lib/tftpboot
cd /var/lib/tftpboot
# Копирование файлов загрузчика
wget https://github.com/ricksumner/syslinux/releases/download/v6.04/pxelinux.0 -O /var/lib/tftpboot/pxelinux.0
# Создание конфигурации PXE
mkdir -p /var/lib/tftpboot/pxelinux.cfg
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT linux
LABEL linux
    KERNEL vmlinuz
    APPEND initrd=initrd.img
EOF
# Скачивание необходимых файлов ядра и initrd для AlmaLinux
cd /var/lib/tftpboot
wget http://archive.ubuntu.com/ubuntu/dists/focal-updates/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux -O vmlinuz
wget http://archive.ubuntu.com/ubuntu/dists/focal-updates/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz -O initrd.img
# Настройка NFS для раздачи файлов
echo "/var/lib/tftpboot *(ro,sync,no_root_squash)" | sudo tee -a /etc/exports
# Перезапуск NFS
sudo exportfs -r
sudo systemctl restart nfs-server
# Открытие портов на firewall
sudo firewall-cmd --permanent --zone=public --add-service=tftp
sudo firewall-cmd --permanent --zone=public --add-service=nfs
sudo firewall-cmd --reload
echo "PXE сервер установлен и настроен. Перезагрузите сервер."
