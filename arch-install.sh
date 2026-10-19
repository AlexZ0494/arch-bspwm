#!/bin/bash

# --- ПЕРЕМЕННЫЕ (ИЗМЕНИТЕ ПОД СЕБЯ) ---
# Диск для установки (ВНИМАНИЕ! ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ)
DISK="/dev/sda" 
# Имя пользователя
USERNAME="archuser" 
# Пароль пользователя (лучше поменять после установки)
USERPASS="archlinux" 
# Пароль root
ROOTPASS="root" 

# --- 1. НАСТРОЙКА ИНТЕРНЕТА И ВРЕМЕНИ ---
echo "Синхронизация времени..."
timedatectl set-ntp true

echo "Проверка интернет-соединения..."
ping -c 3 archlinux.org > /dev/null
if [ $? -ne 0 ]; then
    echo "Ошибка: Нет интернета. Подключитесь через wifi-menu или systemd-networkd."
    exit 1
fi

# --- 2. РАЗМЕТКА ДИСКА И ФОРМАТИРОВАНИЕ ---
echo "Разметка диска $DISK..."
# Используем GPT и один раздел (для простоты, можно добавить swap)
sgdisk --zap-all $DISK
sgdisk -n 1:0:0 -t 1:8300 $DISK

# Форматируем в ext4
mkfs.ext4 "${DISK}1"

# Монтируем
mount "${DISK}1" /mnt

# --- 3. УСТАНОВКА БАЗОВОЙ СИСТЕМЫ ---
echo "Установка базовой системы и ядра (это может занять 5-15 минут)..."
pacstrap /mnt base base-devel linux-zen linux-firmware vim nano networkmanager git wget

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# --- 4. НАСТРОЙКА СИСТЕМЫ ЧЕРЕЗ ARCH-CHROOT ---
echo "Копирование скрипта настройки внутрь системы для chroot..."
cp "$0" /mnt/root/post_install.sh
chmod +x /mnt/root/post_install.sh

arch-chroot /mnt /root/post_install.sh "$USERNAME" "$USERPASS" "$ROOTPASS"

# --- 5. ВЫХОД И ПЕРЕЗАГРУЗКА ---
echo "Установка завершена. Выходим из chroot..."
exit

echo "Размонтируем диск..."
umount -R /mnt

echo "Установка завершена! Введите 'reboot' для перезагрузки."
echo "Не забудьте извлечь USB-накопитель и настроить загрузчик (рекомендуется GRUB ниже)."

# --- ВНУТРЕННИЙ СКРИПТ ДЛЯ ARCH-CHROOT ---
exit 0
EOF
# ==============================================================================
# НАЧАЛО ВНУТРЕННЕГО СКРИПТА (ТО, ЧТО ВЫПОЛНИТСЯ ВНУТРИ СИСТЕМЫ)
# ==============================================================================
arch-chroot /mnt /bin/bash << 'INNER_EOF'

# Принимаем аргументы из внешнего скрипта
USERNAME=$1
USERPASS=$2
ROOTPASS=$3

echo "Локализация..."
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localdate
hwclock --systohc
sed -i 's/#$en_US.UTF-8 UTF-8$/\1/' /etc/locale.gen
sed -i 's/#$ru_RU.UTF-8 UTF-8$/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Настройка сети..."
echo "archhost" > /etc/hostname
cat > /etc/hosts << EOH
127.0.0.1   localhost
::1         localhost
127.0.1.1   archhost.localdomain archhost
EOH

systemctl enable NetworkManager

echo "Создание пользователя..."
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$ROOTPASS" | chpasswd

# Настройка sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- 6. УСТАНОВКА ГРАФИЧЕСКОГО СТЕКА И ВАШЕГО СОФТА ---
echo "Установка графического сервера и компонентов..."
pacman -S --noconfirm xorg-server xorg-xinit xorg-xrandr \
    bspwm sxhkd alacritty thunar dmenu picom feh \
    polybar noto-fonts-cjk noto-fonts-emoji ttf-joypixels \
    pulseaudio pulseaudio-alsa pavucontrol \
    network-manager-applet blueman \
    git wget curl unzip

# --- 7. НАСТРОЙКА КОНФИГОВ (bspwm, sxhkd, polybar) ---
echo "Настройка конфигурации..."
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config/{bspwm,sxhkd,polybar,alacritty}

# Копируем дефолтные конфиги bspwm и sxhkd
sudo -u $USERNAME cp /usr/share/doc/bspwm/examples/bspwmrc /home/$USERNAME/.config/bspwm/
sudo -u $USERNAME cp /usr/share/doc/bspwm/examples/sxhkdrc /home/$USERNAME/.config/sxhkd/
sudo -u $USERNAME chmod +x /home/$USERNAME/.config/bspwm/bspwmrc

# (Здесь должен быть блок создания конфигов Polybar и Alacritty из предыдущего ответа)
# Для краткости опускаем повторный ввод 200 строк конфига Polybar, 
# но в реальном скрипте они должны быть сгенерированы через 'cat > file << EOF ...'
# ВАЖНО: В конфиге Polybar убедитесь, что в exec_always или автозапуске указан путь к /home/$USERNAME/.config/polybar/launch.sh

# --- 8. УСТАНОВКА ЗАГРУЗЧИКА (GRUB) ---
echo "Установка загрузчика GRUB..."
pacman -S --noconfirm grub efibootmgr
# Если у вас BIOS/Legacy:
grub-install --target=i386-pc $DISK
# Если у вас UEFI (раскомментируйте и укажите точку монтирования EFI раздела, если он есть):
# mkdir -p /boot/efi
# mount /dev/sdaX /boot/efi
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

grub-mkconfig -o /boot/grub/grub.cfg

# --- 9. ВКЛЮЧЕНИЕ СЛУЖБ И АВТОЗАПУСК ---
echo "Включение автозапуска графической сессии..."
# Создаем .xinitrc для пользователя
sudo -u $USERNAME cat > /home/$USERNAME/.xinitrc << 'XINIT_EOF'
#!/bin/sh
picom --config /dev/null --experimental-backends &
dunst &
$HOME/.config/polybar/launch.sh
exec bspwm
XINIT_EOF

sudo -u $USERNAME chmod +x /home/$USERNAME/.xinitrc

# Включаем автозапуск X при логине (опционально, для автологина сложнее)
# echo "startx" >> /home/$USERNAME/.bashrc

echo "Внутренняя настройка завершена."
INNER_EOF
