#!/bin/bash

# --- НАСТРОЙКИ (ИЗМЕНИТЕ ПЕРЕД ЗАПУСКОМ) ---
DISK="/dev/sda"          # Диск для установки (ВНИМАНИЕ! ВСЕ ДАННЫЕ БУДУТ СТЕРТЫ)
USERNAME="archuser"      # Имя пользователя
USERPASS="archlinux"     # Пароль пользователя
ROOTPASS="root"          # Пароль root
TIMEZONE="Europe/Moscow" # Часовой профиль

# --- ЦВЕТОВАЯ СХЕМА TOKIO-NIGHT ---
BG="#1a1b26"
FG="#c0caf5"
PINK="#bb9af7"
BLUE="#7aa2f7"
YELLOW="#e0af68"
GREEN="#9ece6a"
RED="#f7768e"
CYAN="#7dcfff"

echo "1. Синхронизация времени..."
timedatectl set-ntp true

echo "2. Разметка диска $DISK (GPT, 1 раздел)..."
sgdisk --zap-all $DISK
sgdisk -n 1:0:0 -t 1:8300 $DISK
mkfs.ext4 -F "${DISK}1"
mount "${DISK}1" /mnt

echo "3. Установка базовой системы (kernel-zen, base-devel, git)..."
pacstrap /mnt base base-devel linux-zen linux-firmware vim networkmanager git wget curl
genfstab -U /mnt >> /mnt/etc/fstab

echo "4. Копирование скрипта внутрь системы для chroot..."
cp "$0" /mnt/root/installer.sh
chmod +x /mnt/root/installer.sh

echo "5. Вход в chroot и настройка системы..."
arch-chroot /mnt /bin/bash << 'INNER_EOF'

# --- ПЕРЕДАЧА ПЕРЕМЕННЫХ ИЗ ВНЕШНЕГО СКРИПТА ---
DISK="/dev/sda"
USERNAME="archuser"
USERPASS="archlinux"
ROOTPASS="root"
TIMEZONE="Europe/Moscow"

# --- СИСТЕМНАЯ НАСТРОЙКА ---
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/#$en_US.UTF-8 UTF-8$/\1/' /etc/locale.gen
sed -i 's/#$ru_RU.UTF-8 UTF-8$/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=ru" > /etc/vconsole.conf

echo "archhost" > /etc/hostname
cat > /etc/hosts << EOH
127.0.0.1   localhost
::1         localhost
127.0.1.1   archhost.localdomain archhost
EOH

systemctl enable NetworkManager
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$ROOTPASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- УСТАНОВКА СОФТА ---
pacman -S --noconfirm --needed xorg-server xorg-xinit xorg-xrandr \
    bspwm sxhkd alacritty thunar dmenu picom feh \
    polybar noto-fonts ttf-joypixels \
    pulseaudio pulseaudio-alsa pavucontrol \
    network-manager-applet blueman \
    dunst unclutter

# --- НАСТРОЙКА КОНФИГОВ ПОЛЬЗОВАТЕЛЯ ---
sudo -u $USERNAME bash << 'USER_EOF'
mkdir -p ~/.config/{bspwm,sxhkd,polybar,alacritty}

# BSPWM
cat > ~/.config/bspwm/bspwmrc << 'BSPWM_EOF'
#!/bin/sh
bspc monitor -d I II III IV V VI VII VIII IX X
bspc config border_width 2
bspc config window_gap 12
bspc config split_ratio 0.52
bspc config borderless_monocle true
bspc config gapless_monocle true
bspc rule -a Polybar state=above
pkill -USR1 -x sxhkd
BSPWM_EOF

# SXHKD
cat > ~/.config/sxhkd/sxhkdrc << 'SXHKD_EOF'
super + Return
    alacritty
super + d
    dmenu_run
super + e
    thunar
super + shift + q
    bspc node -c
super + {_,shift + }{h,j,k,l}
    bspc node -{f,s} {west,south,north,east}
super + b
    $HOME/.config/polybar/launch.sh
SXHKD_EOF

# ALACRITTY
cat > ~/.config/alacritty/alacritty.yml << 'ALAC_EOF'
window:
  padding: {x: 8, y: 8}
colors:
  primary: {background: '0x1a1b26', foreground: '0xc0caf5'}
  normal: {black: '0x15161e', red: '0xf7768e', green: '0x9ece6a', yellow: '0xe0af68', blue: '0x7aa2f7', magenta: '0xbb9af7', cyan: '0x7dcfff', white: '0xa9b1d6'}
ALAC_EOF

# POLYBAR (Конфигурация согласно вашему запросу)
mkdir -p ~/.config/polybar/themes
git clone --depth 1 https://github.com/adi1090x/polybar-themes.git /tmp/polybar-themes
cp -r /tmp/polybar-themes/shapes ~/.config/polybar/themes/

cat > ~/.config/polybar/config << 'POLY_EOF'
[colors]
background = #1a1b26
background-alt = #292e42
foreground = #c0caf5
primary = #bb9af7
secondary = #7aa2f7
alert = #f77686

[bar/main]
width = 100%
height = 32
background = ${background}
foreground = ${foreground}
modules-left = bspwm menu
modules-center = xwindow
modules-right = pulseaudio wlan xkeyboard date tray
tray-position = right
wm-restack = bspwm
override-redirect = true
font-0 = NotoSans-Regular:pixelsize=11;3

[module/xwindow]
type = internal/xwindow
label = "%title%"
label-background = ${background-alt}
label-background-alpha = 0.8
label-padding = 8

[module/date]
type = internal/date
date = "%d-%m-%Y"
time = "%H:%M"
label = "%date% %time%"

[module/menu]
type = custom/text
content = " "
content-foreground = ${primary}
click-left = "dmenu_run"
POLY_EOF

cat > ~/.config/polybar/launch.sh << 'LAUNCH_EOF'
#!/bin/bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done
polybar main &
LAUNCH_EOF
chmod +x ~/.config/polybar/launch.sh

# XINITRC
cat > ~/.xinitrc << 'XINIT_EOF'
#!/bin/sh
picom --config /dev/null --experimental-backends &
dunst &
unclutter --idle 3 &
$HOME/.config/polybar/launch.sh
exec bspwm
XINIT_EOF

USER_EOF

# --- ЗАГРУЗЧИК (GRUB) ---
pacman -S --noconfirm grub efibootmgr
grub-install --target=i386-pc $DISK
# Для UEFI (раскомментировать если нужно):
mkdir -p /boot/efi
mount /dev/sda1 /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Установка завершена. Выйдите из chroot и перезагрузитесь."
INNER_EOF

echo "6. Очистка..."
umount -R /mnt
echo "Скрипт завершил работу. Введите 'reboot'."
