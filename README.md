# 🐾 OpenClaw Watchdog | OpenClaw 守門犬 (Bash Edition)

[English](#english) | [中文](#中文)

---

<a name="english"></a>
## English

OpenClaw Watchdog is a lightweight, ultra-reliable background daemon designed for [OpenClaw](https://github.com/openclaw/openclaw). 

**This version is built entirely in Bash**, removing all Python dependencies and virtual environment complexities. It integrates natively with `systemd --user` to manage your OpenClaw Gateway.

### ✨ Key Features

1. **Native Integration**: Uses `systemctl --user` to directly monitor and restart the OpenClaw Gateway.
2. **Auto Backup**: Automatically synchronizes healthy configs to `openclaw.json.bak`.
3. **Auto Rollback**: If config corruption is detected, it automatically restores from `.bak` and restarts the service.
4. **🧠 Smart Debounce**: **Prevents overwriting your work-in-progress!** It detects file modification time (`mtime`) and grants a 120s grace period. If you are actively editing the file, Watchdog waits patiently.
5. **Real-time Webhook Alerts**: Discord notifications for all status changes using `curl` and `jq`.
6. **Zero Dependencies**: No Python, no `pip`, no `venv`. Requires only `bash`, `curl`, and `jq`.

### 🚀 Quick Deploy

```bash
# 1. Clone and setup
git clone https://github.com/yourusername/openclaw-watchdog.git
cd openclaw-watchdog
cp .env.example .env
nano .env  # Fill in WATCHDOG_WEBHOOK_URL

# 2. One-command deploy (Registers systemd service)
bash install.sh
```

Done! Check status: `sudo systemctl status openclaw-watchdog`

### Configuration (.env)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WATCHDOG_WEBHOOK_URL` | ✅ Yes | - | Discord webhook URL |
| `OPENCLAW_CONFIG_PATH` | ❌ No | `~/.openclaw/openclaw.json` | Path to config |
| `WATCHDOG_CHECK_INTERVAL` | ❌ No | `15` | Check interval (seconds) |
| `WATCHDOG_GRACE_SEC` | ❌ No | `120` | Human edit grace period (seconds) |

---

<a name="中文"></a>
## 中文

OpenClaw Watchdog 是一個輕量級、極度可靠的背景守護程式 (Daemon)，專門為 [OpenClaw](https://github.com/openclaw/openclaw) 打造。

**此版本完全基於 Bash 編寫**，移除了所有 Python 依賴與虛擬環境的複雜性，原生整合 `systemd --user` 來管理您的 OpenClaw Gateway。

### ✨ 核心特色

1. **原生整合**：使用 `systemctl --user` 直接監控與重啟 OpenClaw Gateway 服務。
2. **自動備份配置**：當 Config 格式合法時，自動同步備份為 `openclaw.json.bak`。
3. **損壞自動回退 (Rollback)**：偵測到 JSON 格式損壞時，自動從 `.bak` 恢復並重啟服務。
4. **🧠 智能防呆 (Smart Debounce)**：**防止覆蓋人工修改！** 偵測文件修改時間 (`mtime`) 並提供 120 秒寬限期，只要您正在編輯文件，Watchdog 就會耐心等待。
5. **即時 Webhook 警報**：透過 `curl` 與 `jq` 發送 Discord 即時通知。
6. **零依賴**：免 Python、免 `pip`、免 `venv`。僅需 `bash`, `curl`, `jq`。

### 🚀 一鍵部署

```bash
# 1. 下載並設定
git clone https://github.com/yourusername/openclaw-watchdog.git
cd openclaw-watchdog
cp .env.example .env
nano .env  # 填入 WATCHDOG_WEBHOOK_URL

# 2. 一鍵部署（註冊 systemd 服務）
bash install.sh
```

完成！查看狀態：`sudo systemctl status openclaw-watchdog`

### 配置說明 (.env)

| 變數名 | 必填 | 預設值 | 說明 |
|--------|------|--------|------|
| `WATCHDOG_WEBHOOK_URL` | ✅ 是 | - | Discord Webhook 網址 |
| `OPENCLAW_CONFIG_PATH` | ❌ 否 | `~/.openclaw/openclaw.json` | 設定檔路徑 |
| `WATCHDOG_CHECK_INTERVAL` | ❌ 否 | `15` | 檢查頻率（秒） |
| `WATCHDOG_GRACE_SEC` | ❌ 否 | `120` | 人工修改寬限期（秒） |

---

## 📄 License | 授權條款

MIT License
