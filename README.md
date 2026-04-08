# Restore Brightness — ASUS TUF A15 FA505DT (KDE, AMD + NVIDIA)

Fix display brightness not recovering after suspend/resume on ASUS laptops with hybrid AMD + NVIDIA graphics running KDE Plasma on Linux.

---

## Table of Contents

- [Problem Description](#problem-description)
- [Affected Systems](#affected-systems)
- [Root Cause](#root-cause)
- [Solution Overview](#solution-overview)
- [Installation](#installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [File Reference](#file-reference)
- [How It Works](#how-it-works)
- [Credits](#credits)

---

## Problem Description

### Built-in Laptop Display (AMD GPU)

After the system wakes up from suspend/sleep:

- The screen remains **dim** even though brightness was set to maximum before sleep.
- Using the keyboard brightness hotkeys (Fn + F3/F4) temporarily changes the value, but it **reverts back to a dim state** immediately.
- The `brightness` sysfs file shows the correct value, but `actual_brightness` remains low.
- **After a reboot, brightness works normally** — confirming this is a suspend/resume issue, not a driver absence.

### External HDMI Monitor (NVIDIA GPU)

- The external monitor connected via HDMI is also **dim after resume**.
- HDMI displays do not have a hardware backlight control interface (`/sys/class/backlight`).
- Brightness for HDMI must be controlled through **gamma correction** (`xrandr`) or NVIDIA settings.
- After suspend, these settings are **lost** and never restored automatically.

---

## Affected Systems

This solution was developed and tested on:

| Component | Value |
|---|---|
| **Laptop** | ASUS TUF Gaming A15 FA505DT |
| **CPU** | AMD Ryzen |
| **iGPU** | AMD Radeon (Vega) — `amdgpu` driver |
| **dGPU** | NVIDIA GeForce GTX 1650 — `nvidia` 595.58.03 |
| **Display** | Internal: `eDP-1` (`amdgpu_bl2`) / External: `HDMI-A-1` |
| **Desktop** | KDE Plasma |
| **Kernel** | Linux 6.19 (CachyOS) — also works on Arch, Fedora, Ubuntu |
| **Init** | systemd |

> **This guide is also applicable to other ASUS laptops with AMD GPUs and similar hybrid graphics configurations.**

---

## Root Cause

### 1. AMD GPU — `amdgpu_bl2` Scale Bug

The `amdgpu_bl2` backlight interface uses a **non-linear brightness scale**. The driver writes the value to the register, but the hardware does not always apply it correctly after a power state transition (suspend/resume).

**Before suspend:**
```
/sys/class/backlight/amdgpu_bl2/brightness       → 61680
/sys/class/backlight/amdgpu_bl2/actual_brightness → 58762  (OK, near max)
```

**After resume:**
```
/sys/class/backlight/amdgpu_bl2/brightness       → 18505  (corrupted by hotkeys)
/sys/class/backlight/amdgpu_bl2/actual_brightness → 9418   (DIM!)
```

Additionally, `systemd-backlight@.service` **caches the last brightness value** in `/var/lib/systemd/backlight/`. When a hotkey is pressed and sets a low value, that value gets cached. On resume, systemd restores the cached dim value instead of the maximum.

### 2. NVIDIA HDMI — No Backlight Interface

HDMI-connected monitors **do not expose** a backlight control interface via `/sys/class/backlight`. The brightness must be controlled through:

- **xrandr gamma** (`--gamma 1.2:1.2:1.2`)
- **xrandr brightness** (`--brightness 1.1`)
- **nvidia-settings DigitalVibrance**

These settings are **X server session-specific** and are lost when the display manager restarts the session after suspend. Systemd sleep hooks running as root **do not have access** to the user's X session (`$DISPLAY`, `$XAUTHORITY`), so they cannot restore HDMI brightness.

---

## Solution Overview

The fix consists of **three layers**:

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: systemd sleep hook (root)                  │
│  → Fixes AMD internal display brightness            │
│  → Runs at system level, before X session starts     │
├─────────────────────────────────────────────────────┤
│ Layer 2: KDE autostart scripts (user)               │
│  → Fixes HDMI brightness via xrandr                  │
│  → Runs inside the user's X session                  │
├─────────────────────────────────────────────────────┤
│ Layer 3: D-Bus suspend watcher (user)               │
│  → Listens for resume signals from KDE PowerDevil   │
│  → Re-applies HDMI brightness automatically          │
└─────────────────────────────────────────────────────┘
```

---

## Installation

### Step 1: Clone This Repository

```bash
cd ~
git clone https://github.com/vitacbka/restore_brightness_asus_tuf505DT_KDE.git
cd restore_brightness_asus_tuf505DT_KDE
```

### Step 2: Install System-Level Scripts (root)

```bash
# Copy system scripts
sudo cp scripts/fix-brightness.sh /usr/local/bin/fix-brightness.sh
sudo cp scripts/fix-hdmi-brightness.sh /usr/local/bin/fix-hdmi-brightness.sh
sudo cp scripts/fix-hdmi-brightness-watch.sh /usr/local/bin/fix-hdmi-brightness-watch.sh

# Make them executable
sudo chmod +x /usr/local/bin/fix-brightness.sh
sudo chmod +x /usr/local/bin/fix-hdmi-brightness.sh
sudo chmod +x /usr/local/bin/fix-hdmi-brightness-watch.sh

# Install systemd sleep hook
sudo cp services/systemd-fix-brightness-after-sleep /usr/lib/systemd/system-sleep/fix-brightness-after-sleep
sudo chmod +x /usr/lib/systemd/system-sleep/fix-brightness-after-sleep
```

### Step 3: Install User-Level Autostart (as your KDE user)

```bash
# Copy autostart .desktop files
mkdir -p ~/.config/autostart
cp autostart/fix-hdmi-brightness.desktop ~/.config/autostart/
cp autostart/fix-hdmi-brightness-watch.desktop ~/.config/autostart/

# Copy xprofile (runs at X session start)
cp .xprofile ~/.xprofile
```

### Step 4: Fix the Cached Brightness Value

The dim value is stored in systemd's cache. Fix it:

```bash
# Find your backlight device name
ls /var/lib/systemd/backlight/

# Example output: pci-0000:05:00.0:backlight:amdgpu_bl2

# Write the maximum value (61680 for amdgpu_bl2)
# Replace the filename with YOUR actual device name:
echo 61680 | sudo tee /var/lib/systemd/backlight/pci-0000:05:00.0:backlight:amdgpu_bl2
```

### Step 5: Install xrandr (if not already installed)

```bash
# Arch / CachyOS / Manjaro
sudo pacman -S xorg-xrandr

# Ubuntu / Kubuntu / Debian
sudo apt install x11-xserver-utils

# Fedora
sudo dnf install xorg-x11-server-utils
```

### Step 6: Verify

```bash
# Test internal display fix
sudo /usr/local/bin/fix-brightness.sh

# Test HDMI fix (run as your KDE user, not root)
fix-hdmi-brightness.sh
```

### Step 7: Reboot

```bash
sudo reboot
```

After reboot, both displays should have correct brightness. Test suspend/resume with:

```bash
systemctl suspend
# Wait, then wake up — both screens should be bright
```

---

## Usage

### Manual Brightness Fix (Internal Display)

```bash
sudo /usr/local/bin/fix-brightness.sh
```

This restores the AMD internal display to maximum brightness and logs the action.

### Manual Brightness Fix (External HDMI)

```bash
fix-hdmi-brightness.sh
```

Or with custom values:

```bash
# gamma 1.3:1.3:1.3, brightness 1.2 (brighter)
fix-hdmi-brightness.sh 1.3:1.3:1.3 1.2

# Default (gamma 1.2, brightness 1.1)
fix-hdmi-brightness.sh
```

### Adjusting Brightness Levels

Edit the default values in `/usr/local/bin/fix-hdmi-brightness.sh`:

```bash
# Default values
GAMMA="${1:-1.2:1.2:1.2}"
BRIGHTNESS="${2:-1.1}"
```

| Gamma | Brightness | Effect |
|---|---|---|
| `1.0:1.0:1.0` | `1.0` | Default (no change) |
| `1.2:1.2:1.2` | `1.1` | Slightly brighter (default) |
| `1.3:1.3:1.3` | `1.2` | Noticeably brighter |
| `1.5:1.5:1.5` | `1.3` | Much brighter |

> **Warning:** Values above `1.5` may wash out colors. Test incrementally.

### Viewing Logs

```bash
# Brightness change history
tail -50 /var/log/brightness-history.log

# Full diagnostic info
cat /var/log/brightness-diagnostic.log
```

---

## Troubleshooting

### Internal display is still dim after resume

1. Check current values:
   ```bash
   cat /sys/class/backlight/amdgpu_bl2/brightness
   cat /sys/class/backlight/amdgpu_bl2/actual_brightness
   cat /sys/class/backlight/amdgpu_bl2/max_brightness
   ```

2. If `brightness` shows a low value (e.g., 18505), the systemd cache may be corrupted:
   ```bash
   cat /var/lib/systemd/backlight/*
   ```

3. Fix it:
   ```bash
   echo 61680 | sudo tee /var/lib/systemd/backlight/pci-0000:05:00.0:backlight:amdgpu_bl2
   sudo systemctl restart systemd-backlight@backlight:amdgpu_bl2.service
   ```

4. Force restore:
   ```bash
   sudo /usr/local/bin/fix-brightness.sh
   ```

### HDMI monitor is still dim

1. Verify `xrandr` is installed and can see the monitor:
   ```bash
   xrandr --listmonitors
   ```
   You should see something like:
   ```
   Monitors: 2
    0: +*eDP-1 ...
    1: +HDMI-A-1 ...
   ```

2. Test xrandr manually:
   ```bash
   xrandr --output HDMI-A-1 --gamma 1.3:1.3:1.3 --brightness 1.2
   ```

3. If xrandr doesn't work, try `nvidia-settings`:
   ```bash
   nvidia-settings
   # Go to "X Server Color Correction" → adjust Digital Vibrance / Brightness
   ```

4. Check that the autostart entries are active:
   ```bash
   ls -la ~/.config/autostart/fix-hdmi-brightness*.desktop
   ```

5. Check the `.xprofile` is loaded:
   ```bash
   cat ~/.xprofile
   ```

### The D-Bus watcher script doesn't work

The watcher relies on KDE PowerDevil D-Bus signals. Test:

```bash
# In one terminal:
dbus-monitor --session "type='signal',interface='org.kde.Solid.PowerManagement'"

# In another:
systemctl suspend
# Wake up and check if the signal was captured
```

If it doesn't catch the signal, you can add a cron job as fallback:

```bash
# Create /etc/systemd/system/resume-brightness.service
cat << 'EOF' | sudo tee /etc/systemd/system/resume-brightness.service
[Unit]
Description=Restore HDMI Brightness After Suspend
After=suspend.target hibernate.target hybrid-sleep.target

[Service]
Type=oneshot
User=vitaliy
Environment=DISPLAY=:0
ExecStart=/bin/sh -c 'for f in /run/user/1000/xauth_*; do export XAUTHORITY=$f; break; done; /usr/local/bin/fix-hdmi-brightness.sh'

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable resume-brightness.service
```

---

## File Reference

### System Scripts (`/usr/local/bin/`)

| File | Purpose | Run As |
|---|---|---|
| `fix-brightness.sh` | Restores internal AMD display + triggers HDMI fix | root |
| `fix-hdmi-brightness.sh` | Restores HDMI brightness via xrandr gamma | user (with X session) |
| `fix-hdmi-brightness-watch.sh` | D-Bus listener for suspend/resume events | user |

### Systemd Hook

| File | Purpose |
|---|---|
| `/usr/lib/systemd/system-sleep/fix-brightness-after-sleep` | Runs before/after suspend. Fixes AMD display. |

### User Autostart (`~/.config/autostart/`)

| File | Purpose |
|---|---|
| `fix-hdmi-brightness.desktop` | Runs HDMI fix at KDE session start |
| `fix-hdmi-brightness-watch.desktop` | Starts D-Bus watcher for resume events |

### User Config

| File | Purpose |
|---|---|
| `~/.xprofile` | Runs at X session start (fallback if autostart fails) |
| `~/.config/systemd/user/fix-hdmi-brightness.service` | Optional: systemd user-level service |

### Logs

| File | Purpose |
|---|---|
| `/var/log/brightness-history.log` | History of all brightness restore operations |
| `/var/log/brightness-diagnostic.log` | One-time diagnostic snapshot (before/after reboot comparison) |

---

## How It Works

### AMD Internal Display (`amdgpu_bl2`)

```
Suspend → System saves brightness to cache
         ↓
Resume  → systemd-backlight restores cached value
         ↓
Sleep hook intercepts the resume event
         ↓
Writes MAX value to /sys/class/backlight/amdgpu_bl2/brightness
         ↓
Repeats 3× with 1s delays (works around amdgpu non-linear scale bug)
```

### External HDMI Monitor (NVIDIA)

```
Resume → X session restarts
         ↓
Layer 2: ~/.xprofile runs → fix-hdmi-brightness.sh
         ↓
Layer 2: KDE autostart → fix-hdmi-brightness.desktop → fix-hdmi-brightness.sh
         ↓
Layer 3: D-Bus watcher detects resume → fix-hdmi-brightness-watch.sh → fix-hdmi-brightness.sh
         ↓
xrandr --output HDMI-A-1 --gamma 1.2:1.2:1.2 --brightness 1.1
         ↓
Monitor brightness restored
```

### Why Three Layers for HDMI?

X session timing is unpredictable. The three-layer approach ensures at least one method catches:

1. **`.xprofile`** — runs immediately when X starts (may be too early for monitors to be detected)
2. **Autostart `.desktop`** — runs when KDE finishes loading (usually catches the display)
3. **D-Bus watcher** — continuously listens for resume signals (most reliable, catches late resumes)

---

## Credits

- **Author:** vitaliy ([@vitacbka](https://github.com/vitacbka))
- **Laptop:** ASUS TUF Gaming A15 FA505DT
- **Tested on:** CachyOS (Arch-based), KDE Plasma, Linux 6.19
- **Kernel parameters that did NOT help:** `acpi_backlight=native`, `amdgpu.backlight=0`

---

## License

MIT License — feel free to use, modify, and share.

---

> **Note:** This fix addresses a known issue with the `amdgpu_bl2` non-linear brightness scale and KDE's brightness caching behavior. If your system behaves differently, please open an issue on GitHub.
