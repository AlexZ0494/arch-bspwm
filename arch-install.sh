#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Arch Linux Live: Full Base + GUI Prep Setup (Fixed) ===${NC}"
echo ""

if [[ \$(id -u) -ne 0 ]]; then
  echo -e "${RED}Ошибка: запускай от root.${NC}"
  exit 1
fi
if [[ "\$(hostname)" != "archiso" ]]; then
  echo -e "${YELLOW}Предупреждение: скрипт рассчитан на Arch Linux live USB.${NC}"
fi

read -p "Введи имя диска для установки (например, /dev/sda или /dev/nvme0n1): " DISK
if [[ ! "\$DISK" =~ ^/dev/ ]]; then
  echo -e "${RED}Некорректное имя диска.${NC}"
  exit 1
fi

echo "Разметка диска \$DISK (EFI + root)..."
sgdisk --zap-all "\$DISK"
sgdisk -n 1::+512M -t 1:EF00 -c 1:"EFI" "\$DISK"
sgdisk -n 2::0   -t 2:8300 -c 2:"root" "\$DISK"

echo "Форматирование разделов..."
mkfs.fat -F32 "\${DISK}1"
mkfs.ext4 "\${DISK}2"

echo "Монтирование файловых систем..."
mount "\${DISK}2" /mnt
mkdir -p /mnt/boot
mount "\${DISK}1" /mnt/boot

echo "Установка пакетов: base, linux, grub, GUI deps..."
pacstrap /mnt base base-devel linux linux-firmware grub efibootmgr networkmanager sudo nano git

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<'EOF_CHROOT'
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "arch-bspwm" > /etc/hostname
echo "root:root" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
EOF_CHROOT

echo "Подготовка GUI‑конфигов в /etc/skel..."

mkdir -p /mnt/etc/skel/.config/bspwm
mkdir -p /mnt/etc/skel/.config/sxhkd
mkdir -p /mnt/etc/skel/.config/polybar
mkdir -p /mnt/etc/skel/.config/rofi
mkdir -p /mnt/etc/skel/.config/alacritty
mkdir -p /mnt/etc/skel/.config/picom
mkdir -p /mnt/etc/skel/.local/share/polybar-icons

cat > /mnt/etc/skel/.config/bspwm/bspwmrc <<'EOF'
bspc config focus_follows_pointer true
bspc config pointer_follows_window true
bspc config border_width 2
bspc config window_gap 8
bspc monitor -d 1 2 3 4 5 6 7 8 9 0
for m in \$(bspc query -M); do
    polybar --monitor="\$m" main &
done
EOF

cat > /mnt/etc/skel/.config/sxhkd/sxhkdrc <<'EOF'
super + Return
    alacritty
super + d
    rofi -show run
super + Shift + c
    bspc window kill
super + h
    bspc node -f
super + l
    bspc node -f -c 'state=tiled'
super + m
    bspc node -f -c 'state=monocle'
EOF

cat > /mnt/etc/skel/.config/picom/picom.conf <<'EOF'
shadow = true;
shadow-radius = 12;
shadow-opacity = 0.7;
shadow-offset-x = -12;
shadow-offset-y = -12;
detect-transient = true;
detect-active-window = true;
inactive-dim = 0.2;
opacity-rule = [
    "85:name *= 'polybar'"
];
EOF

echo "Скачивание тем (polybar Shapes, rofi Type‑3, alacritty Tokyo Night)..."

git clone --depth 1 https://github.com/adi1090x/polybar-themes.git /tmp/polybar-themes-repo
cp -r /tmp/polybar-themes-repo/collection/shapes/* /mnt/etc/skel/.config/polybar/
if [ -d /tmp/polybar-themes-repo/collection/shapes/icons ]; then
  cp -r /tmp/polybar-themes-repo/collection/shapes/icons/* /mnt/etc/skel/.local/share/polybar-icons/
fi

git clone --depth 1 https://github.com/orkhasnat/rofi-themes.git /tmp/rofi-themes-repo
cp /tmp/rofi-themes-repo/launchers/type-3/config.rasi /mnt/etc/skel/.config/rofi/config.rasi
for f in /tmp/rofi-themes-repo/launchers/type-3/*.rasi; do
  [ -e "$f" ] && cp "$f" /mnt/etc/skel/.config/rofi/
done

git clone --depth 1 https://github.com/zatchheems/tokyo-night-alacritty-theme.git /tmp/alacritty-themes-repo
cp /tmp/alacritty-themes-repo/tokyo-night.yml /mnt/etc/skel/.config/alacritty/alacritty.yml

tee /mnt/usr/share/xsessions/bspwm.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=BSPWM
Comment=Tiling window manager
Exec=bspwm
TryExec=bspwm
Type=Application
EOF

echo ""
echo -e "${GREEN}=== Готово! ===${NC}"
echo ""
echo "1. Перезагрузи ПК, выбери диск в BIOS/UEFI."
echo "2. Зайди как root (пароль: root)."
echo "3. Создай пользователя:"
echo "     useradd -m -G wheel -s /bin/bash username"
echo "     passwd username"
echo "4. Выйди из root, войди под обычным пользователем."
echo "5. В дисплейном менеджере выбери сессию BSPWM."
echo ""
echo "Конфиги bspwm, sxhkd, polybar, rofi, alacritty и picom"
echo "автоматически скопированы в твой \$HOME благодаря /etc/skel."
