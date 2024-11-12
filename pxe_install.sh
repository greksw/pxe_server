#!/bin/bash

# URLs и пути для DevStation и ThinStation
DEVSTATION_URL="https://sourceforge.net/projects/thinstation/files/DevStation-Source/thindev-default-6.3.tar.xz/download"
DEVSTATION_PATH="/usr/src/thindev-default-6.3.tar.xz"
DEVSTATION_DIR="/usr/src/thindev"
ISO_OUTPUT_DIR="/var/lib/tftpboot/thinstation"

# Создание каталога для TFTP и сборочной среды
echo "Создаем каталоги для TFTP и DevStation..."
mkdir -p "$ISO_OUTPUT_DIR"
mkdir -p "$DEVSTATION_DIR"

# Загрузка архива DevStation
if [ ! -f "$DEVSTATION_PATH" ]; then
    echo "Скачиваем архив DevStation..."
    wget -O "$DEVSTATION_PATH" "$DEVSTATION_URL" || { echo "Ошибка при загрузке DevStation."; exit 1; }
else
    echo "Архив DevStation уже загружен."
fi

# Распаковка DevStation
echo "Распаковываем DevStation..."
tar -xf "$DEVSTATION_PATH" -C "$DEVSTATION_DIR" --strip-components=1 || { echo "Ошибка при распаковке DevStation."; exit 1; }

# Перемещение в каталог DevStation для сборки
cd "$DEVSTATION_DIR" || { echo "Ошибка: каталог DevStation не найден."; exit 1; }

# Создание конфигурационного файла для сборки с настройками RDP
echo "Настройка ThinStation для RDP..."
cat <<EOF > build.conf
NET_USE_DHCP=On
SESSION_0_TYPE=rdesktop
SESSION_0_TITLE="Remote Desktop"
SESSION_0_RDESKTOP_SERVER="192.168.2.25"  # Замените на IP-адрес вашего RDP-сервера
SESSION_0_RDESKTOP_OPTIONS="-f"           # Полноэкранный режим
EOF

# Проверка наличия исполняемого файла build
if [ ! -f "./build" ]; then
    echo "Ошибка: исполняемый файл build не найден. Возможно, DevStation не установлена правильно."
    exit 1
fi

# Сборка ThinStation образа для PXE
echo "Сборка ThinStation для PXE..."
./build -b pxe || { echo "Ошибка при сборке ThinStation."; exit 1; }

# Копирование собранных файлов в TFTP-директорию
echo "Копирование файлов для PXE-загрузки..."
cp -r "$DEVSTATION_DIR/build/pxe/"* "$ISO_OUTPUT_DIR" || { echo "Ошибка при копировании файлов."; exit 1; }

# Настройка конфигурации PXE для ThinStation
echo "Настройка PXE конфигурации для ThinStation..."
cat <<EOF > /var/lib/tftpboot/pxelinux.cfg/default
DEFAULT thinstation
LABEL thinstation
  KERNEL thinstation/vmlinuz
  APPEND initrd=thinstation/initrd ramdisk_size=65536 root=/dev/ram0 rw
EOF

echo "Настройка завершена. Теперь ThinStation готов к загрузке через PXE с преднастроенным RDP-клиентом."
