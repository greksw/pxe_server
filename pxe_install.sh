#!/bin/bash

# Функция для проверки выполнения команды
check_command() {
    "$@"
    if [ $? -ne 0 ]; then
        echo "Ошибка при выполнении команды: $@"
        exit 1
    fi
}

# Обновление системы и установка необходимых пакетов
echo "Обновление системы..."
check_command sudo dnf update -y

echo "Установка необходимых пакетов..."
check_command sudo dnf install -y dnsmasq tftp-server syslinux wget vim curl git tar

# Настройка брандмауэра для разрешения HTTP и HTTPS
echo "Настройка брандмауэра для HTTP и HTTPS..."
check_command sudo firewall-cmd --permanent --add-port=80/tcp
check_command sudo firewall-cmd --permanent --add-port=443/tcp
check_command sudo firewall-cmd --reload

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

# Клонирование репозитория ThinStation
echo "Клонирование репозитория ThinStation..."
check_command sudo git clone --depth 1 https://github.com/Thinstation/thinstation.git /usr/src/thinstation

# Настройка и сборка ThinStation
echo "Настройка и сборка ThinStation..."
cd /usr/src/thinstation || { echo "Ошибка: каталог /usr/src/thinstation не найден."; exit 1; }
check_command sudo ./setup-chroot
cd /usr/src/thinstation/build

# Создание конфигурационного файла для сборки с настройками RDP
echo "Настройка ThinStation для RDP..."
cat <<EOF | sudo tee build.conf > /dev/null
NET_USE_DHCP=On
SESSION_0_TYPE=rdesktop
SESSION_0_TITLE="Remote Desktop"
SESSION_0_RDESKTOP_SERVER="192.168.2.25"  # Замените на IP-адрес вашего RDP-сервера
SESSION_0_RDESKTOP_OPTIONS="-f"           # Полноэкранный режим
EOF

# Сборка образа ThinStation для PXE
echo "Сборка ThinStation для PXE..."
check_command sudo ./build -b pxe

# Копирование собранных файлов в TFTP-директорию
echo "Копирование файлов для PXE-загрузки..."
check_command sudo cp -r /usr/src/thinstation/build/pxe/* /var/lib/tftpboot

# Настройка PXE конфигурации для ThinStation
echo "Настройка PXE конфигурации для ThinStation..."
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT thinstation
LABEL thinstation
  KERNEL thinstation/vmlinuz
  APPEND initrd=thinstation/initrd ramdisk_size=65536 root=/dev/ram0 rw
EOF

echo "Настройка завершена. Теперь ThinStation готов к загрузке через PXE с преднастроенным RDP-клиентом."
