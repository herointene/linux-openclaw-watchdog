#!/bin/bash

# ==========================================
# OpenClaw Bash Watchdog (Ultra-Reliable)
# ==========================================
# 監控 OpenClaw Gateway 狀態、配置 JSON 合法性與自動恢復
# 
# 免 Python、免 venv、原生 systemctl 整合。

# 配置區 (從 .env 讀取或使用預設)
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$PROJECT_DIR/.env" ]] && source "$PROJECT_DIR/.env"

# 自動偵測 XDG_RUNTIME_DIR 以確保 systemctl --user 可用
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# 預設路徑
OPENCLAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
# 展開波浪號並處理引號
OPENCLAW_CONFIG=$(echo "$OPENCLAW_CONFIG" | sed "s|^~|$HOME|")
BACKUP_PATH="${OPENCLAW_CONFIG}.bak"
WEBHOOK_URL="${WATCHDOG_WEBHOOK_URL}"
CHECK_INTERVAL="${WATCHDOG_CHECK_INTERVAL:-15}"
GRACE_SEC="${WATCHDOG_GRACE_SEC:-120}"

log() {
    # 輸出到 stdout 供 systemd journal 捕獲，同時紀錄詳細內容
    echo "[$(date -Iseconds)] $1"
}

# 偵錯：啟動時列印關鍵變數
log "🔍 偵錯資訊: USER=$USER, HOME=$HOME, PROJECT_DIR=$PROJECT_DIR"
log "🔍 偵錯資訊: OPENCLAW_CONFIG=$OPENCLAW_CONFIG"
log "🔍 偵錯資訊: XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

send_discord() {
    local title="$1"
    local desc="$2"
    local color="$3" # Dec color (e.g. 16711680 red, 65280 green, 16766720 yellow)
    
    [[ -z "$WEBHOOK_URL" ]] && return
    
    # 建立 JSON payload (使用 jq 以防內容含特殊字符)
    local payload=$(jq -n \
        --arg title "$title" \
        --arg desc "$desc" \
        --arg color "$color" \
        --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            embeds: [{
                title: $title,
                description: $desc,
                color: ($color | tonumber),
                timestamp: $time
            }]
        }')
        
    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$WEBHOOK_URL" > /dev/null
}

# --- 核心邏輯 ---

log "🐾 OpenClaw Bash Watchdog 啟動..."
send_discord "🟢 Watchdog (Bash) 上線" "守護進程已啟動，監控路徑: $OPENCLAW_CONFIG" 65280

# 初始化狀態
INVALID_SINCE=0
LAST_MTIME=0
NOTIFIED_EDITING=0

while true; do
    # 1. 檢查 JSON 合法性 (需要 jq)
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        log "❌ 找不到設定檔: $OPENCLAW_CONFIG"
        JSON_OK=1
    else
        # 強制使用絕對路徑並檢查讀取權限
        if [[ ! -r "$OPENCLAW_CONFIG" ]]; then
            log "❌ 無法讀取設定檔 (權限不足): $OPENCLAW_CONFIG"
            JSON_OK=1
        else
            # 獲取 jq 輸出以便偵錯
            JQ_OUT=$(jq . "$OPENCLAW_CONFIG" 2>&1 >/dev/null)
            JSON_OK=$?
            if [[ $JSON_OK -ne 0 ]]; then
                log "❌ JSON 格式檢查失敗: $JQ_OUT"
            fi
        fi
    fi

    if [[ $JSON_OK -ne 0 ]]; then
        CURRENT_MTIME=$(stat -c %Y "$OPENCLAW_CONFIG" 2>/dev/null || echo 0)
        
        # 第一次發現無效
        if [[ $INVALID_SINCE -eq 0 ]]; then
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            log "⚠️ 發現 Config 格式錯誤，進入 $GRACE_SEC 秒觀察期..."
            
        # 發現文件仍在變動 (人工修改中)
        elif [[ $CURRENT_MTIME -ne $LAST_MTIME ]]; then
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            if [[ $NOTIFIED_EDITING -eq 0 ]]; then
                log "👤 檢測到文件變動，判定為人工修改中。暫停回退..."
                send_discord "⚠️ Config 正在被修改" "檢測到 JSON 格式錯誤，但文件頻繁變動，判定為人工修改中。Watchdog 暫停回退..." 16766720
                NOTIFIED_EDITING=1
            fi
            
        # 超過寬限期
        else
            NOW=$(date +%s)
            DIFF=$((NOW - INVALID_SINCE))
            if [[ $DIFF -gt $GRACE_SEC ]]; then
                log "⏳ 寬限期結束 ($DIFF 秒)，Config 依然損壞，嘗試強制回退..."
                if [[ -f "$BACKUP_PATH" ]]; then
                    cp "$BACKUP_PATH" "$OPENCLAW_CONFIG"
                    log "✅ 已從備份恢復 Config。"
                    # 重啟服務
                    systemctl --user restart openclaw-gateway
                    send_discord "🚨 嚴重異常：Config 損壞且無人修改" "檢測到 openclaw.json 解析失敗且超時未修復。\n✅ 已自動從備份恢復並重啟 Gateway。" 16711680
                else
                    send_discord "💥 致命錯誤：Config 損壞且無備份" "需要人工緊急介入！" 16711680
                fi
                INVALID_SINCE=0
                NOTIFIED_EDITING=0
            fi
        fi
    else
        # JSON 正常，重置標記
        if [[ $INVALID_SINCE -gt 0 ]]; then
            log "✅ Config 格式已修復。"
            [[ $NOTIFIED_EDITING -eq 1 ]] && send_discord "✅ Config 已修復" "人工修改完成，JSON 格式合法。" 65280
            INVALID_SINCE=0
            NOTIFIED_EDITING=0
        fi
        
        # 2. 檢查 Gateway 狀態 (使用 systemctl --user)
        # 這樣就不會受到 XDG_RUNTIME_DIR 或 TTY 環境限制
        if ! systemctl --user is-active --quiet openclaw-gateway; then
            log "❌ 檢測到 Gateway 離線！準備重啟..."
            systemctl --user restart openclaw-gateway
            sleep 5
            if systemctl --user is-active --quiet openclaw-gateway; then
                log "✅ Gateway 自動重啟成功。"
                send_discord "⚠️ Gateway 崩潰" "Gateway 進程離線，✅ 已成功自動重啟。" 16766720
            else
                log "💀 Gateway 重啟失敗！"
                send_discord "💀 嚴重異常：Gateway 重啟失敗" "無法透過 systemctl 重啟 Gateway，請登入 Server 檢查！" 16711680
            fi
        else
            # 狀態正常時同步備份
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
