# 🐾 OpenClaw Watchdog | OpenClaw 守門犬

[English](#english) | [中文](#中文)

---

<a name="english"></a>
## English

OpenClaw Watchdog is a lightweight, intelligent background daemon designed for [OpenClaw](https://github.com/openclaw/openclaw).

It monitors your Gateway status and configuration file (`openclaw.json`) health in real-time. When Gateway crashes or the config is corrupted, it instantly detects, auto-heals, and sends alerts to Discord (or any webhook-supported platform).

### ✨ Key Features

1. **Auto Backup**: Automatically backs up healthy configs to `openclaw.json.bak`
2. **Auto Rollback**: If config corruption causes Gateway crash, automatically restores from `.bak` and restarts
3. **Crash Recovery**: Restarts Gateway immediately if it unexpectedly stops
4. **🧠 Smart Debounce**: **Prevents overwriting your work-in-progress!** When editing `openclaw.json` and saving incomplete JSON, the script detects file modification time (`mtime`). It enters a "grace period" (default 120s) - if the file keeps changing, Watchdog waits patiently without forcing rollback
5. **Real-time Webhook Alerts**: Discord notifications for all status changes

### 🚀 Quick Deploy (One Command)

```bash
# 1. Clone and setup
git clone https://github.com/yourusername/openclaw-watchdog.git
cd openclaw-watchdog
cp .env.example .env
nano .env  # Fill in WATCHDOG_WEBHOOK_URL

# 2. One-command deploy (auto-installs deps + systemd service)
bash install.sh
```

Done! Check status: `sudo systemctl status openclaw-watchdog`

### 🔧 Manual Setup (Alternative)

```bash
pip3 install -r requirements.txt
python3 watchdog.py  # Run directly (not persistent)
```

### Configuration (.env)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WATCHDOG_WEBHOOK_URL` | ✅ Yes | - | Discord webhook URL |
| `OPENCLAW_CONFIG_PATH` | ❌ No | `~/.openclaw/openclaw.json` | Path to config |
| `WATCHDOG_CHECK_INTERVAL` | ❌ No | `10` | Check interval (seconds) |
| `WATCHDOG_GRACE_SEC` | ❌ No | `120` | Human edit grace period (seconds) |

### Testing

- **Gateway Crash**: Run `openclaw gateway stop`, watch Watchdog restart it
- **Config Corruption**: Add a syntax error to `openclaw.json`, wait 2 minutes, watch it auto-restore

---

<a name="中文"></a>
## 中文

OpenClaw Watchdog 是一個輕量級、智慧的背景守護程式 (Daemon)，專門為 [OpenClaw](https://github.com/openclaw/openclaw) 打造。

它能即時監控 Gateway 的運行狀態與配置檔 (`openclaw.json`) 的健康度。當 Gateway 崩潰或設定檔損壞時，它會瞬間識別、自動修復，並發送警告至 Discord (或其他支援 Webhook 的平台)。

### ✨ 核心特色

1. **自動備份配置**：當 Gateway 運行良好且 Config 格式合法時，自動將當前的配置備份為 `openclaw.json.bak`
2. **損壞自動回退 (Rollback)**：如果設定檔損壞導致 Gateway 崩潰，自動讀取 `.bak` 並覆蓋錯誤配置，強制重啟服務
3. **Gateway 崩潰自啟動**：偵測到 Gateway 意外離線，即刻重啟
4. **🧠 智能防呆 (Smart Debounce)**：**防止覆蓋人工修改！** 當編輯 `openclaw.json` 卻尚未完成存檔時，腳本偵測文件修改時間(`mtime`)。給予「寬限期 (預設 120 秒)」，只要這段時間內文件持續變動，Watchdog 不會強制回退，只會默默等待
5. **即時 Webhook 警報**：Discord 推播所有狀態變更

### 🚀 一鍵部署

```bash
# 1. 下載並設定
git clone https://github.com/yourusername/openclaw-watchdog.git
cd openclaw-watchdog
cp .env.example .env
nano .env  # 填入 WATCHDOG_WEBHOOK_URL

# 2. 一鍵部署（自動安裝依賴 + 註冊 systemd 服務）
bash install.sh
```

完成！查看狀態：`sudo systemctl status openclaw-watchdog`

### 🔧 手動運行（替代方案）

```bash
pip3 install -r requirements.txt
python3 watchdog.py  # 直接運行（不會永久駐留）
```

### 配置說明 (.env)

| 變數名 | 必填 | 預設值 | 說明 |
|--------|------|--------|------|
| `WATCHDOG_WEBHOOK_URL` | ✅ 是 | - | Discord Webhook 網址 |
| `OPENCLAW_CONFIG_PATH` | ❌ 否 | `~/.openclaw/openclaw.json` | 設定檔路徑 |
| `WATCHDOG_CHECK_INTERVAL` | ❌ 否 | `10` | 檢查頻率（秒） |
| `WATCHDOG_GRACE_SEC` | ❌ 否 | `120` | 人工修改寬限期（秒） |

### 測試驗證

- **Gateway 崩潰測試**：執行 `openclaw gateway stop`，觀察 Watchdog 自動重啟並發送警報
- **Config 損壞測試**：在 `openclaw.json` 加入語法錯誤，放置 2 分鐘，觀察自動回復

---

## 📄 License | 授權條款

MIT License
