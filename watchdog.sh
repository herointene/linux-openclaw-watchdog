#!/bin/bash

# ==========================================
# OpenClaw Bash Watchdog
# ==========================================

# 1. 載入環境變數與清理
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
    # 使用迴圈清理引號，避免 systemd EnvironmentFile 帶入引號
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        # 移除前後引號與空白
        value=$(echo "$value" | sed -e 's/^[[:space:]]*["'\'']//' -e 's/["'\''][[:space:]]*$//')
        export "$key=$value"
    done < "$PROJECT_DIR/.env"
fi

# 自動偵測 XDG_RUNTIME_DIR
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# 2. 路徑解析 (優先使用絕對路徑)
RAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
# 再次確保波浪號展開
OPENCLAW_CONFIG="${RAW_CONFIG/#\~/$HOME}"
BACKUP_PATH="${OPENCLAW_CONFIG}.bak"

# 參數設定
WEBHOOK_URL="${WATCHDOG_WEBHOOK_URL}"
CHECK_INTERVAL="${WATCHDOG_CHECK_INTERVAL:-15}"
GRACE_SEC="${WATCHDOG_GRACE_SEC:-120}"

log() {
    echo "[$(date -Iseconds)] $1"
}

send_discord() {
    local title="$1"
    local desc="$2"
    local color="$3"
    [[ -z "$WEBHOOK_URL" ]] && return
    local payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$desc" \
        --arg color "$color" \
        --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{embeds: [{title: $title, description: $desc, color: ($color | tonumber), timestamp: $time}]}')
    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" > /dev/null
}

# 啟動自檢
log "🐾 OpenClaw Watchdog (Rigorous Edition) 啟動"
log "📍 監控目標: $OPENCLAW_CONFIG"

# 狀態變數
INVALID_SINCE=0
LAST_MTIME=0
NOTIFIED_EDITING=0

while true; do
    # --- 階段 1: JSON 完整性審計 ---
    JSON_OK=0
    ERROR_MSG=""

    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        ERROR_MSG="找不到設定檔"
        JSON_OK=1
    elif [[ ! -r "$OPENCLAW_CONFIG" ]]; then
        ERROR_MSG="權限不足，無法讀取"
        JSON_OK=1
    else
        # 執行 jq 並捕獲錯誤訊息
        JQ_ERR=$(jq . "$OPENCLAW_CONFIG" 2>&1 >/dev/null)
        if [[ $? -ne 0 ]]; then
            ERROR_MSG="JSON 格式解析失敗: ${JQ_ERR}"
            JSON_OK=1
        fi
    fi

    # --- 階段 2: 處理異常狀態 ---
    if [[ $JSON_OK -ne 0 ]]; then
        CURRENT_MTIME=$(stat -c %Y "$OPENCLAW_CONFIG" 2>/dev/null || echo 0)
        
        if [[ $INVALID_SINCE -eq 0 ]]; then
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            log "⚠️ 偵測到異常: $ERROR_MSG"
            log "🕒 進入 $GRACE_SEC 秒寬限期..."
        elif [[ $CURRENT_MTIME -ne $LAST_MTIME ]]; then
            # 文件正在變動，代表有人正在編輯
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            if [[ $NOTIFIED_EDITING -eq 0 ]]; then
                log "👤 偵測到文件持續變動 (人工編輯中)，暫停自動回退。"
                send_discord "⚠️ Config 正在被修改" "JSON 格式暫時失效，但檢測到人為編輯。Watchdog 已暫停回退..." 16766720
                NOTIFIED_EDITING=1
            fi
        else
            # 文件停止變動且依然無效
            NOW=$(date +%s)
            DIFF=$((NOW - INVALID_SINCE))
            if [[ $DIFF -gt $GRACE_SEC ]]; then
                log "⏳ 寬限期結束 ($DIFF 秒)，Config 依然無效。準備執行自動回退..."
                if [[ -f "$BACKUP_PATH" ]]; then
                    cp "$BACKUP_PATH" "$OPENCLAW_CONFIG"
                    log "✅ 已從備份恢復 Config。"
                    systemctl --user restart openclaw-gateway
                    send_discord "🚨 嚴重異常：Config 自動恢復" "Config 損壞且無人修正，已自動回退備份並重啟服務。" 16711680
                else
                    log "💥 錯誤: 無法執行回退，因為找不到備份檔 $BACKUP_PATH"
                    send_discord "💥 致命錯誤" "Config 損壞且無備份可恢復！請立即人工檢查。" 16711680
                fi
                INVALID_SINCE=0
                NOTIFIED_EDITING=0
            fi
        fi
    else
        # 狀態恢復正常
        if [[ $INVALID_SINCE -gt 0 ]]; then
            log "✅ Config 格式已恢復正常。"
            [[ $NOTIFIED_EDITING -eq 1 ]] && send_discord "✅ Config 已修復" "人工修改完成，格式合法。" 65280
            INVALID_SINCE=0
            NOTIFIED_EDITING=0
        fi

        # --- 階段 3: 監控 Gateway 運行狀態 ---
        if ! systemctl --user is-active --quiet openclaw-gateway; then
            log "❌ 偵測到 Gateway 離線，準備重啟..."
            systemctl --user restart openclaw-gateway
            sleep 5
            if systemctl --user is-active --quiet openclaw-gateway; then
                log "✅ Gateway 重啟成功。"
                send_discord "⚠️ Gateway 崩潰恢復" "Gateway 離線，已自動重啟。" 16766720
            else
                log "💀 嚴重異常: Gateway 重啟失敗！"
                send_discord "💀 嚴重異常" "無法啟動 Gateway 服務，請檢查服務日誌。" 16711680
            fi
        else
            # 狀態健康，同步備份
            if [[ -f "$OPENCLAW_CONFIG" ]]; then
                if ! cmp -s "$OPENCLAW_CONFIG" "$BACKUP_PATH"; then
                    cp "$OPENCLAW_CONFIG" "$BACKUP_PATH"
                    log "🔄 已備份最新的健康 Config。"
                fi
            fi
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
