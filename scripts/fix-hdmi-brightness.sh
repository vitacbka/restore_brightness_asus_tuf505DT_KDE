#!/bin/bash
# Восстановление яркости внешнего HDMI монитора (NVIDIA)
# Используется xrandr для установки gamma и brightness

XAUTH="${XAUTHORITY:-/run/user/1000/xauth_*$USER}"
export DISPLAY=":0"

# Находим XAUTHORITY если не установлен
if [ ! -f "$XAUTHORITY" ]; then
    for f in /run/user/$(id -u)/xauth_* /home/$USER/.Xauthority; do
        [ -f "$f" ] && export XAUTHORITY="$f" && break
    done
fi

# Получаем список подключённых мониторов (кроме eDP - встроенного)
MONITORS=$(xrandr --listmonitors 2>/dev/null | tail -n +2 | awk '{print $NF}' | grep -v eDP)

if [ -z "$MONITORS" ]; then
    exit 0
fi

# Значения яркости (настраиваемые)
GAMMA="${1:-1.2:1.2:1.2}"
BRIGHTNESS="${2:-1.1}"

for mon in $MONITORS; do
    xrandr --output "$mon" --gamma "$GAMMA" --brightness "$BRIGHTNESS" 2>/dev/null
    echo "[$(date '+%H:%M:%S')] $mon: gamma=$GAMMA brightness=$BRIGHTNESS"
done
