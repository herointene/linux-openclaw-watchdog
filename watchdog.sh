#!/bin/bash

# ==========================================
# OpenClaw Bash Watchdog (Ultra-Reliable v2)
# ==========================================

# 加載環境變數
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$PROJECT_DIR/.env" ]] && source "$PROJECT_DIR/.env"

# 自動偵測 XDG_RUNTIME_DIR 以確保 systemctl --user 可用
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# 預設路徑處理 (支援 ~ 展開)
OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
OPENCLAW_CONFIG=$(echo "$OPENCLAW_CONFIG" | sed "s|^~|$HOME|")
BACKUP_PATH="${OPENCLAW_CONFIG}.bak"

# 修正部分環境變數
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

log "🐾 OpenClaw Bash Watchdog 啟動..."
log "🔍 偵錯: CONFIG=$OPENCLAW_CONFIG"
log "🔍 偵錯: BACKUP=$BACKUP_PATH"

# 初始化狀態
INVALID_SINCE=0
LAST_MTIME=0
NOTIFIED_EDITING=0

while true; do
    # 1. 檢查 JSON 合法性
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        log "❌ 錯誤: 找不到設定檔 $OPENCLAW_CONFIG"
        JSON_OK=1
    elif [[ ! -r "$OPENCLAW_CONFIG" ]]; then
        log "❌ 錯誤: 無法讀取設定檔 (權限不足)"
        JSON_OK=1
    else
        # 靜默檢查 JSON
        jq . "$OPENCLAW_CONFIG" > /dev/null 2>&1
        JSON_OK=$?
    fi

    if [[ $JSON_OK -ne 0 ]]; then
        # 格式錯誤處理
        CURRENT_MTIME=$(stat -c %Y "$OPENCLAW_CONFIG" 2>/dev/null || echo 0)
        
        if [[ $INVALID_SINCE -eq 0 ]]; then
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            log "⚠️ 警告: Config 目前無效 (可能是暫時的)，開始 $GRACE_SEC 秒觀察期..."
        elif [[ $CURRENT_MTIME -ne $LAST_MTIME ]]; then
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            if [[ $NOTIFIED_EDITING -eq 0 ]]; then
                log "👤 偵測到持續修改中，暫停回退..."
                send_discord "⚠️ Config 正在被修改" "檢測到 JSON 格式錯誤，但文件頻繁變動。Watchdog 暫停回退..." 16766720
                NOTIFIED_EDITING=1
            fi
        else
            NOW=$(date +%s)
            DIFF=$((NOW - INVALID_SINCE))
            if [[ $DIFF -gt $GRACE_SEC ]]; then
                log "⏳ 寬限期結束，Config 依然損壞，嘗試從備份恢復..."
                if [[ -f "$BACKUP_PATH" ]]; then
                    cp "$BACKUP_PATH" "$OPENCLAW_CONFIG"
                    log "✅ 已恢復備份配置，正在重啟 Gateway..."
                    systemctl --user restart openclaw-gateway
                    send_discord "🚨 Config 自動恢復" "Config 損壞且超時未修復，已自動恢復備份並重啟 Gateway。" 16711680
                else
                    log "💥 錯誤: 找不到備份檔 $BACKUP_PATH"
                    send_discord "💥 致命錯誤" "Config 損壞且無備份！請立即手動檢查。" 16711680
                fi
                INVALID_SINCE=0
                NOTIFIED_EDITING=0
            fi
        fi
    else
        # JSON 正常
        if [[ $INVALID_SINCE -gt 0 ]]; then
            log "✅ Config 格式已恢復正常。"
            [[ $NOTIFIED_EDITING -eq 1 ]] && send_discord "✅ Config 已修復" "人工修改完成，格式合法。" 65280
            INVALID_SINCE=0
            NOTIFIED_EDITING=0
        fi
        
        # 2. 檢查 Gateway 服務狀態
        if ! systemctl --user is-active --quiet openclaw-gateway; then
            log "❌ 偵測到 Gateway 離線，正在重啟..."
            systemctl --user restart openclaw-gateway
            sleep 5
            if systemctl --user is-active --quiet openclaw-gateway; then
                log "✅ Gateway 重啟成功。"
                send_discord "⚠️ Gateway 崩潰恢復" "Gateway 離線，已成功自動重啟。" 16766720
            else
                log "💀 Gateway 重啟失敗！"
                send_discord "💀 嚴重錯誤" "無法重啟 Gateway，請檢查服務日誌。" 16711680
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
