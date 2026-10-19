#!/usr/bin/env bash
set -euo pipefail

# ================= НАСТРОЙКИ =================
DISK="/dev/sda"                 # Целевой диск (ОПАСНО: будет полностью стёрт!)
ESP_SIZE="512M"                 # Размер EFI‑раздела
ROOT_SIZE="100%"                # Размер корневого раздела (оставшееся место)
HOSTNAME="archbspwm"            # Имя хоста
TIMEZONE="Europe/Moscow"        # Часовой пояс
LOCALE="ru_RU.UTF-8"            # Локаль (должна быть в /etc/locale.gen)
USER="alex"                     # Имя пользователя
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Начало полной установки Arch Linux + BSPWM (Tokio‑Night) ===${NC}"
echo -e "${RED}ВНИМАНИЕ: Диск ${DISK} будет полностью стёрт!\${NC}"

# 1. Разметка диска (GPT, UEFI)
echo -e "${YELLOW}[1/12] Разметка диска (GPT, UEFI)...${NC}"
sgdisk -Z "\$DISK" 2>/dev/null || true
sgdisk -n 1:0:+${ESP_SIZE} -t 1:EF00 -c 1:"EFI System" "$DISK"
sgdisk -n 2:0:+${ROOT_SIZE} -t 2:8300 -c 2:"Linux Root" "$DISK"

# 2. Форматирование разделов
echo -e "${YELLOW}[2/12] Форматирование разделов...${NC}"
mkfs.fat -F32 "\${DISK}1"
mkfs.ext4 "\${DISK}2"

# 3. Монтирование разделов
echo -e "${YELLOW}[3/12] Монтирование разделов...${NC}"
mkdir -p /mnt/boot
mount "\${DISK}2" /mnt
mount "\${DISK}1" /mnt/boot

# 4. Установка базовой системы
echo -e "${YELLOW}[4/12] Установка базовой системы (base, linux, grub)...${NC}"
pacstrap /mnt base base-devel linux linux-firmware nano git networkmanager grub efibootmgr

# 5. Генерация fstab
echo -e "${YELLOW}[5/12] Генерация fstab...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab

# 6. Настройка системы (chroot)
echo -e "${YELLOW}[6/12] Настройка системы (chroot)...${NC}"
arch-chroot /mnt <<EOF
set -euo pipefail

# Часовой пояс и время
ln -sf /usr/share/zoneinfo/\${TIMEZONE} /etc/localtime
hwclock --systohc

# Локаль
sed -i 's/#${LOCALE}/${LOCALE}/' /etc/locale.gen
locale-gen
echo "LANG=\${LOCALE}" > /etc/locale.conf

# Имя хоста
echo "\${HOSTNAME}" > /etc/hostname

# Пароль root
echo "root:root" | chpasswd

# Создание пользователя и пароль
useradd -m -G wheel -s /bin/bash \${USER}
echo "\${USER}:password" | chpasswd

# Настройка sudo (раскомментировать wheel)
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Включение NetworkManager
systemctl enable NetworkManager

# Установка GRUB (UEFI)
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# 7. Установка пакетов для BSPWM и окружения
echo -e "${YELLOW}[7/12] Установка пакетов для BSPWM, Polybar, Alacritty...${NC}"
arch-chroot /mnt pacman -S --noconfirm \
    xorg-server xorg-xinit xorg-twm xorg-xrdb \
    bspwm sxhkd polybar dmenu alacritty thunar feh picom \
    pulseaudio pulseaudio-alsa pulseaudio-equalizer \
    ttf-jetbrains-mono noto-fonts noto-fonts-cjk noto-fonts-emoji

# 8. Клонирование темы Tokio‑Night и копирование конфигов
echo -e "${YELLOW}[8/12] Клонирование темы Tokio‑Night и настройка конфигов...${NC}"
arch-chroot /mnt bash -c "
mkdir -p /home/\${USER}/.config/tokio-night
git clone https://github.com/marko-cerovac/tokio-night.git /home/\${USER}/.config/tokio-night/theme
chown -R ${USER}:${USER} /home/\${USER}/.config
"

# Копируем конфиги под пользователя (вне chroot, чтобы корректно работали права)
mkdir -p "/mnt/home/\${USER}/.config/alacritty"
mkdir -p "/mnt/home/\${USER}/.config/bspwm"
mkdir -p "/mnt/home/\${USER}/.config/sxhkd"
mkdir -p "/mnt/home/\${USER}/.config/picom"
mkdir -p "/mnt/home/\${USER}/.config/polybar"
mkdir -p "/mnt/home/\${USER}/.config/gtk-3.0"
mkdir -p "/mnt/home/\${USER}/.themes/Tokio-Night"

cp -r "/mnt/home/${USER}/.config/tokio-night/theme/alacritty/"* "/mnt/home/${USER}/.config/alacritty/" 2>/dev/null || true
cp -r "/mnt/home/${USER}/.config/tokio-night/theme/bspwm/"* "/mnt/home/${USER}/.config/bspwm/" 2>/dev/null || true
cp -r "/mnt/home/${USER}/.config/tokio-night/theme/sxhkd/"* "/mnt/home/${USER}/.config/sxhkd/" 2>/dev/null || true
cp -r "/mnt/home/${USER}/.config/tokio-night/theme/picom/"* "/mnt/home/${USER}/.config/picom/" 2>/dev/null || true
cp -r "/mnt/home/${USER}/.config/tokio-night/theme/polybar/"* "/mnt/home/${USER}/.config/polybar/" 2>/dev/null || true
cp -r "/mnt/home/${USER}/.config/tokio-night/theme/gtk/"* "/mnt/home/${USER}/.themes/Tokio-Night/" 2>/dev/null || true

# 9. Настройка GTK (Thunar) и шрифтов
echo -e "${YELLOW}[9/12] Настройка GTK и шрифтов для Thunar...${NC}"
cat > "/mnt/home/\${USER}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Tokio-Night
gtk-icon-theme-name=Papirus
gtk-font-name=JetBrains Mono 12
EOF
chown -R "${USER}:${USER}" "/mnt/home/\${USER}/.config/gtk-3.0"

# 10. Настройка Polybar (формат даты, модули)
echo -e "${YELLOW}[10/12] Настройка Polybar (дата, модули, прозрачность)...${NC}"
# Формат даты dd-mm-yyyy hh:mm
sed -i 's/%Y-%m-%d %H:%M/%d-%m-%Y %H:%M/' "/mnt/home/\${USER}/.config/polybar/config" 2>/dev/null || true
# Убедимся, что модули справа (трей) и по центру (окно)
# Это уже есть в теме, но можно явно задать в секции [bar/main]
# modules-left = dmenu workspaces
# modules-center = window
# modules-right = date network pulseaudio keyboard-layout

# 11. Настройка .xinitrc для запуска BSPWM
echo -e "${YELLOW}[11/12] Настройка .xinitrc...${NC}"
cat > "/mnt/home/\${USER}/.xinitrc" <<'EOF'
#!/usr/bin/env bash
picom --config ~/.config/picom/picom.conf &
bspwm &
sxhkd &
~/.config/polybar/launch.sh &
thunar &
exec bspwm
EOF
chmod +x "/mnt/home/\${USER}/.xinitrc"
chown "${USER}:${USER}" "/mnt/home/\${USER}/.xinitrc"

# 12. Финальные штрихи и выход
echo -e "${YELLOW}[12/12] Завершение установки...${NC}"
umount -R /mnt
echo -e "${GREEN}=== Готово! Перезагрузите систему, войдите под пользователем ${USER} и выполните 'startx' ===\${NC}"
