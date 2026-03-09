import os
import time
import json
import shutil
import subprocess
import requests
from datetime import datetime

# 嘗試載入 .env 檔案
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# === 環境變數配置區 ===
WEBHOOK_URL = os.getenv("WATCHDOG_WEBHOOK_URL")
CONFIG_PATH = os.path.expanduser(os.getenv("OPENCLAW_CONFIG_PATH", "~/.openclaw/openclaw.json"))
BACKUP_PATH = f"{CONFIG_PATH}.bak"

CHECK_INTERVAL = int(os.getenv("WATCHDOG_CHECK_INTERVAL", "10"))         # 基礎檢查頻率(秒)
HUMAN_EDIT_GRACE_SEC = int(os.getenv("WATCHDOG_GRACE_SEC", "120"))       # 人工修改寬限期(秒)

def log(msg):
    print(f"[{datetime.now().isoformat()}] {msg}", flush=True)

def send_discord_alert(title, description, color=16711680):
    if not WEBHOOK_URL: 
        log("Webhook 未設定，跳過通知。")
        return
        
    data = {
        "embeds": [{
            "title": title, 
            "description": description, 
            "color": color,
            "timestamp": datetime.utcnow().isoformat()
        }]
    }
    try:
        requests.post(WEBHOOK_URL, json=data, timeout=5)
    except Exception as e:
        log(f"Webhook 發送失敗: {e}")

def is_config_valid():
    if not os.path.exists(CONFIG_PATH):
        return False
    try:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            json.load(f)
        return True
    except (json.JSONDecodeError, UnicodeDecodeError):
        return False

def check_gateway_status():
    try:
        result = subprocess.run(["openclaw", "gateway", "status"], capture_output=True, text=True)
        if "running" in result.stdout.lower() or "active" in result.stdout.lower():
            return True
        return False
    except Exception as e:
        log(f"檢查狀態失敗: {e}")
        return False

def restart_gateway():
    log("執行重啟: openclaw gateway restart")
    subprocess.run(["openclaw", "gateway", "restart"], capture_output=True)

def main():
    log("🐾 OpenClaw Watchdog 已啟動...")
    if not WEBHOOK_URL:
        log("⚠️ 警告：未設定 WATCHDOG_WEBHOOK_URL，將不會發送任何通知！")
    else:
        send_discord_alert("🟢 Watchdog 上線", "OpenClaw 守護進程已啟動，支援智能防呆。", 65280)
    
    invalid_since = 0
    last_mtime = 0
    notified_editing = False

    while True:
        try:
            config_ok = is_config_valid()
            
            # --- 1. 智能識別 Config 狀態 ---
            if not config_ok:
                current_mtime = os.path.getmtime(CONFIG_PATH) if os.path.exists(CONFIG_PATH) else 0
                
                # 第一次發現無效
                if invalid_since == 0:
                    invalid_since = time.time()
                    last_mtime = current_mtime
                    log(f"⚠️ 發現 config 格式錯誤，進入 {HUMAN_EDIT_GRACE_SEC} 秒人工修改觀察期...")
                    
                # 發現文件仍在被修改
                elif current_mtime != last_mtime:
                    invalid_since = time.time()
                    last_mtime = current_mtime
                    if not notified_editing:
                        log("👤 檢測到文件持續修改中，重置觀察計時器。")
                        send_discord_alert("⚠️ Config 正在被修改", "檢測到 JSON 格式錯誤，但文件頻繁變動，判定為人工修改中。Watchdog 暫停回退...", 16766720)
                        notified_editing = True
                
                # 超過寬限期，強制回退
                elif time.time() - invalid_since > HUMAN_EDIT_GRACE_SEC:
                    log("⏳ 觀察期結束，文件依然無效，準備強制回退...")
                    if os.path.exists(BACKUP_PATH):
                        shutil.copy2(BACKUP_PATH, CONFIG_PATH)
                        log("✅ 已恢復備份配置。")
                        restart_gateway()
                        send_discord_alert(
                            "🚨 嚴重異常：Config 損壞且無人修改", 
                            "檢測到 `openclaw.json` 解析失敗且超時未修復。\n✅ 已自動使用 `.bak` 覆蓋並重啟 Gateway。",
                            16711680
                        )
                    else:
                        send_discord_alert("💥 致命錯誤：Config 損壞且無備份", "需要人工緊急介入！", 16711680)
                    
                    invalid_since = 0
                    notified_editing = False
                    time.sleep(30)
                    continue
            else:
                if invalid_since > 0:
                    log("✅ Config 格式已修復（人工修改完成）。")
                    if notified_editing:
                        send_discord_alert("✅ Config 已修復", "人工修改已完成，JSON 格式合法。", 65280)
                    invalid_since = 0
                    notified_editing = False

            # --- 2. 處理 Gateway 崩潰 ---
            gateway_ok = check_gateway_status()
            if not gateway_ok and config_ok:
                log("❌ 檢測到 Gateway 離線！準備重啟...")
                restart_gateway()
                time.sleep(5)
                if check_gateway_status():
                    log("✅ Gateway 自動重啟成功。")
                    send_discord_alert("⚠️ Gateway 崩潰", "Gateway 進程消失，✅ 已成功自動重啟。", 16766720)
                else:
                    log("💀 Gateway 重啟失敗！")
                    send_discord_alert("💀 嚴重異常：Gateway 重啟失敗", "無法透過 CLI 重啟 Gateway，請登入 Server 檢查！", 16711680)
                time.sleep(30)
                continue

            # --- 3. 狀態健康：備份正常的配置檔 ---
            if config_ok and gateway_ok and invalid_since == 0:
                needs_backup = True
                if os.path.exists(BACKUP_PATH):
                    with open(CONFIG_PATH, 'rb') as f1, open(BACKUP_PATH, 'rb') as f2:
                        if f1.read() == f2.read():
                            needs_backup = False
                
                if needs_backup:
                    shutil.copy2(CONFIG_PATH, BACKUP_PATH)
                    log("🔄 已備份最新、健康的 openclaw.json。")

        except Exception as e:
            log(f"Watchdog 內部錯誤: {e}")
            
        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
