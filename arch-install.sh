#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Arch Linux + BSPWM Setup Orchestrator ===${NC}"
echo ""

# Определяем, где мы: live или установленная система
# В live обычно нет /etc/hostname с нормальным именем или нет пользователя кроме root
if [[ -f /etc/hostname && $(hostname) != "archiso" && $(id -u) -ne 0 ]]; then
    MODE="USER_ENV"
elif [[ -f /etc/hostname && $(hostname) == "archiso" ]]; then
    MODE="LIVE_BASE"
else
    # По умолчанию считаем, что это live (если root и hostname=archiso)
    if [[ $(id -u) -eq 0 && $(hostname) == "archiso" ]]; then
        MODE="LIVE_BASE"
    else
        echo -e "${YELLOW}Не удалось автоматически определить режим.${NC}"
        echo "Пожалуйста, запусти этот скрипт:"
        echo "  - В Arch Linux live USB (как root) — для установки ОС."
        echo "  - В уже установленной системе (как обычный пользователь) — для настройки GUI."
        exit 1
    fi
fi

if [[ "$MODE" == "LIVE_BASE" ]]; then
    echo -e "${YELLOW}Режим: установка базовой системы (Arch Linux live).${NC}"
    echo "Этот этап установит ядро, загрузчик, базовые пакеты."
    echo ""
    read -p "Введи имя диска для установки (например, /dev/sda или /dev/nvme0n1): " DISK
    if [[ ! "$DISK" =~ ^/dev/ ]]; then
        echo -e "${RED}Ошибка: некорректное имя диска.${NC}"
        exit 1
    fi

    echo "Разметка диска $DISK (EFI + root)..."
    sgdisk --zap-all "$DISK"
    sgdisk -n 1::+512M -t 1:EF00 -c 1:"EFI" "$DISK"
    sgdisk -n 2::0   -t 2:8300 -c 2:"root" "$DISK"

    echo "Форматирование разделов..."
    mkfs.fat -F32 "${DISK}1"
    mkfs.ext4 "${DISK}2"

    echo "Монтирование файловых систем..."
    mount "${DISK}2" /mnt
    mkdir -p /mnt/boot
    mount "${DISK}1" /mnt/boot

    echo "Установка пакетов: base, linux, grub и др..."
    pacstrap /mnt base base-devel linux linux-firmware grub efibootmgr networkmanager sudo nano

    genfstab -U /mnt >> /mnt/etc/fstab

    echo "Базовая настройка в chroot..."
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

    echo ""
    echo -e "${GREEN}=== Базовая система установлена! ===${NC}"
    echo "Теперь нужно:"
    echo "1. Перезагрузи ПК, выбери диск в BIOS/UEFI."
    echo "2. Зайди как root (пароль: root)."
    echo "3. Создай пользователя:"
    echo "     useradd -m -G wheel -s /bin/bash username"
    echo "     passwd username"
    echo "4. Выйди из root, войди под обычным пользователем."
    echo "5. Запусти этот же скрипт уже из установленной системы — он сделает GUI."
    exit 0

elif [[ "$MODE" == "USER_ENV" ]]; then
    echo -e "${YELLOW}Режим: настройка окружения (bspwm + polybar + rofi + alacritty).${NC}"
    if [[ $(id -u) -eq 0 ]]; then
        echo -e "${RED}Ошибка: не запускай этот этап от root. Конфиги должны быть в домашнем каталоге пользователя.${NC}"
        exit 1
    fi

    BASE_DIR="$HOME/.config/bspwm-setup-2024"
    POLYBAR_THEME_DIR="$BASE_DIR/polybar-themes/shapes"
    ROFI_THEME_DIR="$BASE_DIR/rofi-themes/type-3"
    ALACRITTY_THEME_DIR="$BASE_DIR/alacritty-themes/tokyo-night"

    mkdir -p "$BASE_DIR"
    mkdir -p "$POLYBAR_THEME_DIR"
    mkdir -p "$ROFI_THEME_DIR"
    mkdir -p "$ALACRITTY_THEME_DIR"

    echo "Обновление и установка пакетов..."
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm bspwm sxhkd polybar rofi alacritty picom git base-devel

    echo "Скачивание тем..."
    git clone --depth 1 https://github.com/adi1090x/polybar-themes.git "$BASE_DIR/polybar-themes-repo"
    cp -r "$BASE_DIR/polybar-themes-repo/shapes/"* "$POLYBAR_THEME_DIR/"

    git clone --depth 1 https://github.com/orkhasnat/rofi-themes.git "$BASE_DIR/rofi-themes-repo"
    cp -r "$BASE_DIR/rofi-themes-repo/launchers/type-3/"* "$ROFI_THEME_DIR/"

    git clone --depth 1 https://github.com/zatchheems/tokyo-night-alacritty-theme.git "$BASE_DIR/alacritty-themes-repo"
    cp "$BASE_DIR/alacritty-themes-repo/tokyo-night.yml" "$ALACRITTY_THEME_DIR/config.yml"

    echo "Создание конфигов..."
    mkdir -p "$HOME/.config/bspwm"
    mkdir -p "$HOME/.config/sxhkd"
    mkdir -p "$HOME/.config/polybar"
    mkdir -p "$HOME/.config/rofi"
    mkdir -p "$HOME/.config/alacritty"
    mkdir -p "$HOME/.config/picom"

    cat > "$HOME/.config/bspwm/bspwmrc" <<'EOF'
bspc config focus_follows_pointer true
bspc config pointer_follows_window true
bspc config border_width 2
bspc config window_gap 8
bspc monitor -d 1 2 3 4 5 6 7 8 9 0
for m in $(bspc query -M); do
    polybar --monitor="$m" main &
done
EOF

    cat > "$HOME/.config/sxhkd/sxhkdrc" <<'EOF'
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

    cp "$POLYBAR_THEME_DIR/config" "$HOME/.config/polybar/config"
    if [ -d "$POLYBAR_THEME_DIR/icons" ]; then
        mkdir -p "$HOME/.local/share/polybar-icons"
        cp -r "$POLYBAR_THEME_DIR/icons/"* "$HOME/.local/share/polybar-icons/"
    fi

    cp "$ROFI_THEME_DIR/config.rasi" "$HOME/.config/rofi/config.rasi"
    for f in "$ROFI_THEME_DIR"/*.rasi; do
        [ -e "$f" ] && cp "$f" "$HOME/.config/rofi/"
    done

    cp "$ALACRITTY_THEME_DIR/config.yml" "$HOME/.config/alacritty/alacritty.yml"

    cat > "$HOME/.config/picom/picom.conf" <<'EOF'
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

    sudo tee /usr/share/xsessions/bspwm.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=BSPWM
Comment=Tiling window manager
Exec=bspwm
TryExec=bspwm
Type=Application
EOF

    echo ""
    echo -e "${GREEN}=== Готово! ===${NC}"
    echo "1. В твоём дисплейном менеджере (gdm/lightdm/sddm) выбери сессию BSPWM."
    echo "2. После входа проверь горячие клавиши: Super+Return (терминал), Super+D (rofi)."
    echo "3. Если polybar не виден — сделай killall polybar, он перезапустится."
    echo ""
    echo "Все конфиги сохранены в $BASE_DIR — при необходимости можно откатиться."
    exit 0
fi
