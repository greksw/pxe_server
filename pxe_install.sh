#!/bin/bash

# Функция для проверки выполнения команды
check_command() {
    "$@"
    if [ $? -ne 0 ]; then
        echo "Ошибка при выполнении команды: $*"
        exit 1
    fi
}

# Обновление системы и установка необходимых пакетовecho "Обновление системы..."
check_command sudo dnf update -y
echo "Установка epel репозитория..."
check_command sudo dnf install -y epel-release
echo "Установка необходимых пакетов..."
check_command sudo dnf install -y dnsmasq tftp-server syslinux wget vim curl git tar \
    openssh-clients dbus genisoimage ImageMagick samba-client passwd


# Настройка SSH-ключа для GitHub
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "Создаем SSH ключ..."
    ssh-keygen -t rsa -b 4096 -C "greksw@gmail.com" -N "" -f "$HOME/.ssh/id_rsa"
    echo "Добавьте следующий публичный ключ в ваш GitHub аккаунт:"
    cat "$HOME/.ssh/id_rsa.pub"
    read -p "Нажмите Enter, когда ключ будет добавлен на GitHub..."
else
    echo "SSH ключ уже существует."
fi

# Настройка брандмауэра для TFTP, DNS и DHCP
echo "Настройка брандмауэра для TFTP, DNS и DHCP..."
check_command sudo firewall-cmd --permanent --add-service=http
check_command sudo firewall-cmd --permanent --add-service=https
check_command sudo firewall-cmd --permanent --add-port=53/udp
check_command sudo firewall-cmd --permanent --add-port=53/tcp
check_command sudo firewall-cmd --permanent --add-port=67/udp
check_command sudo firewall-cmd --permanent --add-service=tftp
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

# Клонирование или обновление репозитория ThinStation
REPO_URL="git@github.com:Thinstation/thinstation.git"
THINSTATION_DIR="/usr/src/thinstation"

if [ -d "$THINSTATION_DIR" ]; then
    if [ -d "$THINSTATION_DIR/.git" ]; then
        echo "Репозиторий уже существует. Выполняем обновление..."
        cd "$THINSTATION_DIR"
        check_command sudo git pull
    else
        echo "Каталог $THINSTATION_DIR существует, но не является репозиторием. Удалите его или очистите."
        exit 1
    fi
else
    echo "Клонирование репозитория ThinStation..."
    check_command sudo git clone --depth 1 "$REPO_URL" "$THINSTATION_DIR"
fi

# Настройка сборочной среды и выход из chroot
echo "Выполнение setup-chroot..."
cd "$THINSTATION_DIR" || { echo "Ошибка: каталог ThinStation не найден."; exit 1; }
check_command ./setup-chroot <<EOF
exit
EOF

# Установка недостающих зависимостей внутри chroot-среды
echo "Установка недостающих зависимостей внутри chroot-среды..."
check_command sudo dnf install -y gdk-pixbuf2 gdk-pixbuf-query-loaders glib2 rsvg-convert samba-common-tools

# Создание конфигурации для сборки
echo "Настройка конфигурации ThinStation для RDP..."
cat <<EOF > build/build.conf
NET_USE_DHCP=On
SESSION_0_TYPE=rdesktop
SESSION_0_TITLE="Remote Desktop"
SESSION_0_RDESKTOP_SERVER="192.168.2.25"  # Замените на IP-адрес вашего RDP-сервера
SESSION_0_RDESKTOP_OPTIONS="-f"           # Полноэкранный режим
EOF

# Сборка образа для PXE
echo "Сборка ThinStation для PXE..."
cd build || { echo "Ошибка: каталог build не найден."; exit 1; }
check_command ./build -b pxe

# Копирование собранных файлов в TFTP-директорию
echo "Копирование файлов для PXE-загрузки..."
check_command sudo cp -r /usr/src/thinstation/build/pxe/* /var/lib/tftpboot

# Настройка PXE-загрузки
echo "Настройка PXE конфигурации для ThinStation..."
cat <<EOF | sudo tee /var/lib/tftpboot/pxelinux.cfg/default > /dev/null
DEFAULT thinstation
LABEL thinstation
  KERNEL thinstation/vmlinuz
  APPEND initrd=thinstation/initrd ramdisk_size=65536 root=/dev/ram0 rw
EOF

echo "Настройка завершена. Теперь ThinStation готов к загрузке через PXE с преднастроенным RDP-клиентом."
