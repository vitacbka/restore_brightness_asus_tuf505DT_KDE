#!/bin/bash
# KDE-скрипт для восстановления яркости HDMI ПОСЛЕ выхода из сна
# Слушает сигнал PowerDevil о выходе из suspend

export DISPLAY=:0
for f in /run/user/$(id -u)/xauth_*; do
    export XAUTHORITY="$f"
    break
done

logger "fix-hdmi-brightness: Запуск слушателя сигналов сна..."

dbus-monitor --session "type='signal',interface='org.kde.Solid.PowerManagement'" 2>/dev/null | \
while read -r line; do
    if echo "$line" | grep -q "resumingFromSuspend\|screenUnlock"; then
        logger "fix-hdmi-brightness: Обнаружен выход из сна, восстановление..."
        sleep 3
        /usr/local/bin/fix-hdmi-brightness.sh
        logger "fix-hdmi-brightness: Готово"
    fi
done
