# 🐾 OpenClaw Watchdog | OpenClaw 守門犬

[English](#english) | [中文](#中文)

---

<a name="english"></a>
## English

OpenClaw Watchdog is a lightweight, high-reliability background daemon designed for [OpenClaw](https://github.com/openclaw/openclaw).

Built natively for Linux environments, it provides real-time monitoring of your OpenClaw Gateway and its configuration integrity. When the gateway crashes or a configuration file becomes corrupted, the Watchdog performs automated recovery and broadcasts status alerts to your Discord channels.

### ✨ Key Features

1.  **Systemd Integration**: Native management of the OpenClaw Gateway service via `systemctl --user`, ensuring the process is restarted immediately upon failure.
2.  **Configuration Guard**: Automatically backs up valid `openclaw.json` files and performs an atomic rollback if the current configuration is unparseable.
3.  **🛡️ Gateway Crash Rollback**: If Gateway fails to start, Watchdog automatically rolls back to the last known good config and retries — no more stuck states.
4.  **🧠 Smart Debounce**: Designed for human interaction. Detects manual edits, waits for a debounce settle period (default 5s), then starts the grace window (120s), preventing rollbacks while you're mid-edit.
5.  **Zero-Dependency Design**: Written entirely in Bash. Requires only standard system utilities: `bash`, `curl`, and `jq`.
6.  **Instant Notifications**: Real-time logging and Discord Webhook alerts for all recovery actions (restarts, backups, rollbacks) **and service startup**.

### 🚀 Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/herointene/linux-openclaw-watchdog.git
cd linux-openclaw-watchdog

# 2. Setup environment
cp .env.example .env
nano .env  # Enter your WATCHDOG_WEBHOOK_URL

# 3. Deploy
bash install.sh
```

### 🔧 Configuration (.env)

| Variable | Required | Default | Description |
| :--- | :--- | :--- | :--- |
| `WATCHDOG_WEBHOOK_URL` | ✅ Yes | - | Discord Webhook URL for alerts |
| `OPENCLAW_CONFIG_PATH` | ❌ No | `~/.openclaw/openclaw.json` | Absolute path to your config |
| `WATCHDOG_CHECK_INTERVAL` | ❌ No | `15` | Polling frequency in seconds |
| `WATCHDOG_GRACE_SEC` | ❌ No | `120` | Grace period for manual edits |
| `WATCHDOG_EDIT_DEBOUNCE_SEC` | ❌ No | `5` | Debounce period after file stops changing |

---

<a name="中文"></a>
## 中文

OpenClaw Watchdog 是一個輕量、高可靠的背景守護程式 (Daemon)，專為 [OpenClaw](https://github.com/openclaw/openclaw) 量身打造。

基於原生 Linux 環境開發，它能即時監控 OpenClaw Gateway 的運行狀態與配置文件的完整性。當服務崩潰或配置損壞時，Watchdog 會自動執行恢復流程，並將狀態告警發布至您的 Discord 頻道。

### ✨ 核心特色

1.  **原生系統整合**：透過 `systemctl --user` 直接管理 OpenClaw 服務，確保進程崩潰時秒級重啟。
2.  **配置自動防護**：自動備份健康的 `openclaw.json`，並在偵測到當前配置無法解析時自動執行原子級回退。
3.  **🛡️ Gateway 崩潰回退**：Gateway 啟動失敗時，自動回退到上次已知可用的配置再重試，不再只報錯放棄。
4.  **🧠 智能防呆 (Smart Debounce)**：針對人工操作優化。當偵測到文件正在被編輯時，進入 debounce 等待期（預設 5 秒），確認編輯完成後才開始正式寬限期（120 秒），避免在修改到一半時強制還原。
5.  **零依賴設計**：純 Bash 編寫，無需安裝任何運行環境。僅需系統自帶的 `bash`, `curl`, `jq`。
6.  **即時告警系統**：所有恢復行為（重啟、備份、回退）以及服務啟動均會記錄至系統日誌並透過 Discord Webhook 即時推播。

### 🚀 快速開始

```bash
# 1. 下載倉庫
git clone https://github.com/herointene/linux-openclaw-watchdog.git
cd linux-openclaw-watchdog

# 2. 配置文件
cp .env.example .env
nano .env  # 填入您的 WATCHDOG_WEBHOOK_URL

# 3. 部署服務
bash install.sh
```

### 🔧 配置說明 (.env)

| 變數名稱 | 必填 | 預設值 | 說明 |
| :--- | :--- | :--- | :--- |
| `WATCHDOG_WEBHOOK_URL` | ✅ 是 | - | 用於發送告警的 Discord Webhook |
| `OPENCLAW_CONFIG_PATH` | ❌ 否 | `~/.openclaw/openclaw.json` | 設定檔的絕對路徑 |
| `WATCHDOG_CHECK_INTERVAL` | ❌ 否 | `15` | 輪詢檢查頻率（秒） |
| `WATCHDOG_GRACE_SEC` | ❌ 否 | `120` | 人工修改寬限期（秒） |
| `WATCHDOG_EDIT_DEBOUNCE_SEC` | ❌ 否 | `5` | 文件停止變動後的 debounce 等待期（秒） |

---

## 📄 License | 授權條款

MIT License
