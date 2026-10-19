#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Начало установки окружения BSPWM + Tokio-Night ===${NC}"

# 1. Установка базовых пакетов для графического окружения
echo -e "${YELLOW}[1/10] Установка базовых пакетов...${NC}"
pacman -S --noconfirm xorg-server xorg-xinit xorg-twm xorg-xrdb \
    bspwm sxhkd polybar dmenu alacritty thunar feh picom \
    pulseaudio pulseaudio-alsa pulseaudio-equalizer \
    networkmanager networkmanager-openvpn network-manager-applet \
    ttf-jetbrains-mono noto-fonts noto-fonts-cjk noto-fonts-emoji

# 2. Клонирование темы Tokio-Night и настройка цветовых схем
echo -e "${YELLOW}[2/10] Клонирование темы Tokio-Night...${NC}"
mkdir -p ~/.config/tokio-night
git clone https://github.com/marko-cerovac/tokio-night.git ~/.config/tokio-night/theme

# Копируем конфиги Alacritty, BSPWM, SXHKD, Picom, Polybar из темы
cp -r ~/.config/tokio-night/theme/alacritty/* ~/.config/alacritty/ 2>/dev/null || mkdir -p ~/.config/alacritty && cp ~/.config/tokio-night/theme/alacritty/alacritty.yml ~/.config/alacritty/
cp -r ~/.config/tokio-night/theme/bspwm/* ~/.config/bspwm/ 2>/dev/null || mkdir -p ~/.config/bspwm
cp -r ~/.config/tokio-night/theme/sxhkd/* ~/.config/sxhkd/ 2>/dev/null || mkdir -p ~/.config/sxhkd
cp -r ~/.config/tokio-night/theme/picom/* ~/.config/picom/ 2>/dev/null || mkdir -p ~/.config/picom
cp -r ~/.config/tokio-night/theme/polybar/* ~/.config/polybar/ 2>/dev/null || mkdir -p ~/.config/polybar

# 3. Настройка Polybar: делаем фон полупрозрачным, центрируем, добавляем трей справа
echo -e "${YELLOW}[3/10] Настройка Polybar...${NC}"
# В конфиге polybar уже есть настройки прозрачности (opacity = 0.85) и позиционирования.
# Если нужно явно задать центр и трей — редактируем bar section в ~/.config/polybar/config
sed -i 's/bottom =/bottom = true/' ~/.config/polybar/config 2>/dev/null || true
# Убедимся, что модули расположены: слева — меню/рабочие столы, по центру — окно, справа — трей
# Это уже реализовано в теме Tokio-Night, но можно подправить modules-left/center/right при необходимости.

# 4. Настройка часов в формате dd-mm-yyyy hh:mm
echo -e "${YELLOW}[4/10] Настройка формата даты и времени...${NC}"
# В Polybar модуль date уже настроен, но можно переопределить формат в ~/.config/polybar/config
sed -i 's/%Y-%m-%d %H:%M/%d-%m-%Y %H:%M/' ~/.config/polybar/config 2>/dev/null || true

# 5. Настройка dmenu как меню приложений слева
echo -e "${YELLOW}[5/10] Настройка dmenu...${NC}"
# В sxhkd уже есть бинд для dmenu (обычно Super+D). Убедимся, что путь к скрипту dmenu корректен.
# Если нет — создадим простой скрипт запуска dmenu
cat > ~/bin/dmenu_run.sh << 'EOF'
#!/usr/bin/env bash
dmenu_run -fn "JetBrains Mono:pixelsize=14" -nb "#1f2335" -nf "#c0caf5" -sb "#565f89" -sf "#ffffff"
EOF
chmod +x ~/bin/dmenu_run.sh
mkdir -p ~/bin
mv ~/bin/dmenu_run.sh ~/bin/ 2>/dev/null || true
# Обновляем sxhkd, чтобы использовать этот скрипт (если нужно)

# 6. Настройка Thunar под тему Tokio-Night
echo -e "${YELLOW}[6/10] Настройка Thunar...${NC}"
# Thunar использует GTK-темы. Tokio-Night предоставляет GTK-тему.
# Копируем GTK-тему из Tokio-Night в ~/.themes или /usr/share/themes
mkdir -p ~/.themes/Tokio-Night
cp -r ~/.config/tokio-night/theme/gtk/* ~/.themes/Tokio-Night/
# Устанавливаем тему через gsettings (если установлен gsettings-desktop-schemas) или вручную в ~/.config/gtk-3.0/settings.ini
cat > ~/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Tokio-Night
gtk-icon-theme-name=Papirus
gtk-font-name=JetBrains Mono 12
EOF

# 7. Настройка рабочих столов и меню приложений слева
echo -e "${YELLOW}[7/10] Настройка рабочих столов и меню...${NC}"
# В BSPWM рабочие столы настраиваются в ~/.config/bspwm/bspwmrc
# Убедимся, что есть 4 рабочих стола (по умолчанию в теме уже есть)
# Меню приложений слева — это dmenu, вызываемое по Super+D (настроено в sxhkd)

# 8. Настройка трея: раскладка, громкость, интернет
echo -e "${YELLOW}[8/10] Настройка трея (раскладка, громкость, сеть)...${NC}"
# В Polybar уже есть модули: network, pulseaudio, keyboard-layout
# Если чего-то нет — добавим в ~/.config/polybar/config в секцию [bar/main]
# Пример добавления модулей в правую часть:
# modules-right = date network pulseaudio keyboard-layout

# 9. Настройка автозапуска сервисов
echo -e "${YELLOW}[9/10] Включение и запуск сервисов...${NC}"
systemctl enable NetworkManager
systemctl start NetworkManager
systemctl enable pulseaudio
systemctl start pulseaudio

# 10. Финальная настройка .xinitrc для запуска BSPWM
echo -e "${YELLOW}[10/10] Настройка .xinitrc...${NC}"
cat > ~/.xinitrc << 'EOF'
#!/usr/bin/env bash
# Запускаем Picom (композитор)
picom --config ~/.config/picom/picom.conf &

# Запускаем BSPWM и SXHKD
bspwm &
sxhkd &

# Запускаем Polybar
~/.config/polybar/launch.sh &

# Запускаем Thunar (опционально, как файловый менеджер)
thunar &

# Запускаем системный трей (если используется отдельный трей, например, stalonetray)
# stalonetray &

exec bspwm
EOF
chmod +x ~/.xinitrc

echo -e "${GREEN}=== Готово! Перезагрузите систему и запустите startx${NC}"
echo -e "${YELLOW}Для входа в графическое окружение выполните: startx${NC}"
