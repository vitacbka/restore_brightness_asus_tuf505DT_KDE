#!/bin/bash
# Скрипт восстановления и диагностики яркости
# Для ASUS ноутбука с AMD GPU + NVIDIA (внешний HDMI)

LOG_FILE="/var/log/brightness-history.log"
AMDGPU_BACKLIGHT="/sys/class/backlight/amdgpu_bl2"

timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# Функция логирования
log() {
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Запуск fix-brightness.sh (причина: ${2:-ручной запуск})"
log "=========================================="

# === Встроенный экран (AMD GPU) ===
if [ -d "$AMDGPU_BACKLIGHT" ]; then
    MAX=$(cat "$AMDGPU_BACKLIGHT/max_brightness")
    CURRENT=$(cat "$AMDGPU_BACKLIGHT/brightness")
    ACTUAL=$(cat "$AMDGPU_BACKLIGHT/actual_brightness")
    SCALE=$(cat "$AMDGPU_BACKLIGHT/scale" 2>/dev/null || "unknown")

    log "[eDP] До восстановления:"
    log "  brightness:      $CURRENT / $MAX ($SCALE)"
    log "  actual_brightness: $ACTUAL"

    # Устанавливаем максимум
    echo "$MAX" > "$AMDGPU_BACKLIGHT/brightness"
    sleep 1

    NEW_CURRENT=$(cat "$AMDGPU_BACKLIGHT/brightness")
    NEW_ACTUAL=$(cat "$AMDGPU_BACKLIGHT/actual_brightness")

    log "[eDP] После восстановления:"
    log "  brightness:      $NEW_CURRENT / $MAX"
    log "  actual_brightness: $NEW_ACTUAL"

    if [ "$NEW_ACTUAL" -lt "$((MAX / 2))" ]; then
        log "[eDP] ВНИМАНИЕ: actual_brightness всё ещё низкий!"
        log "[eDP] Попытка повторной записи..."
        echo "$MAX" > "$AMDGPU_BACKLIGHT/brightness"
        sleep 1
        NEW_ACTUAL2=$(cat "$AMDGPU_BACKLIGHT/actual_brightness")
        log "[eDP] actual_brightness после повторной: $NEW_ACTUAL2"
    fi
else
    log "[eDP] amdgpu_bl2 не найден!"
fi

# === Внешний монитор (NVIDIA HDMI) ===
# Используем специализированный скрипт fix-hdmi-brightness.sh
if command -v fix-hdmi-brightness.sh &>/dev/null; then
    XAUTHORITY=$(ls /run/user/1000/xauth_* 2>/dev/null | head -1)
    if [ -n "$XAUTHORITY" ]; then
        DISPLAY=:0 XAUTHORITY="$XAUTHORITY" fix-hdmi-brightness.sh 2>/dev/null
        if [ $? -eq 0 ]; then
            log "[HDMI/NVIDIA] Яркость восстановлена через fix-hdmi-brightness.sh"
        else
            log "[HDMI/NVIDIA] fix-hdmi-brightness.sh вернул ошибку"
        fi
    else
        log "[HDMI/NVIDIA] XAUTHORITY не найден (X-сессия не найдена?)"
    fi
elif command -v nvidia-settings &>/dev/null; then
    DISPLAY=:0 nvidia-settings -a [gpu:0]/DigitalVibrance[DFP-0]=60 2>/dev/null
    log "[HDMI/NVIDIA] Попытка через nvidia-settings"
fi

# === Информация о ядре и параметрах ===
log "[SYSTEM] Ядро: $(uname -r)"
log "[SYSTEM] cmdline: $(cat /proc/cmdline)"
log "[SYSTEM] Время работы: $(uptime -p)"
log "[SYSTEM] backlights: $(ls /sys/class/backlight/ 2>/dev/null | tr '\n' ', ')"

# === Статус сервиса systemd-backlight ===
if systemctl is-active "systemd-backlight@backlight:amdgpu_bl2.service" &>/dev/null; then
    log "[SYSTEMD-backlight] active"
else
    log "[SYSTEMD-backlight] не активен"
fi

log "=========================================="
log ""

echo ""
echo "✅ Яркость восстановлена. Лог: $LOG_FILE"
echo "   Просмотр истории: tail -50 $LOG_FILE"
