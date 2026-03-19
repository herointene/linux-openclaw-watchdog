#!/bin/bash

# ==========================================
# OpenClaw Bash Watchdog v3.0
# 修復: Gateway 崩潰回退、備份時機、編輯 debounce
# ==========================================

# 1. 載入環境變數與清理
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$PROJECT_DIR/.env" ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        value=$(echo "$value" | sed -e 's/^[[:space:]]*["'\'']//' -e 's/["'\''][[:space:]]*$//')
        export "$key=$value"
    done < "$PROJECT_DIR/.env"
fi

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# 2. 路徑解析
RAW_CONFIG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
OPENCLAW_CONFIG="${RAW_CONFIG/#\~/$HOME}"
BACKUP_PATH="${OPENCLAW_CONFIG}.bak"

# 參數設定
WEBHOOK_URL="${WATCHDOG_WEBHOOK_URL}"
CHECK_INTERVAL="${WATCHDOG_CHECK_INTERVAL:-15}"
GRACE_SEC="${WATCHDOG_GRACE_SEC:-120}"
EDIT_DEBOUNCE_SEC="${WATCHDOG_EDIT_DEBOUNCE_SEC:-5}"

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
log "🐾 OpenClaw Watchdog v3.0 啟動"
log "📍 監控目標: $OPENCLAW_CONFIG"
log "⏱️ 寬限期: ${GRACE_SEC}s | 編輯 debounce: ${EDIT_DEBOUNCE_SEC}s"
send_discord "🐾 Watchdog v3.0 啟動" "監控目標: \`${OPENCLAW_CONFIG}\`\n寬限期: ${GRACE_SEC}s | 編輯 debounce: ${EDIT_DEBOUNCE_SEC}s" 3447003

# 狀態變數
INVALID_SINCE=0
LAST_MTIME=0
NOTIFIED_EDITING=0
EDIT_SETTLED_AT=0    # 編輯穩定時間 (debounce)

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
            # 首次偵測到異常
            INVALID_SINCE=$(date +%s)
            LAST_MTIME=$CURRENT_MTIME
            EDIT_SETTLED_AT=0
            log "⚠️ 偵測到異常: $ERROR_MSG"
            log "🕒 進入 $GRACE_SEC 秒寬限期..."
        elif [[ $CURRENT_MTIME -ne $LAST_MTIME ]]; then
            # mtime 變了 → 重新計時 (debounce: 等穩定後才算「編輯完成」)
            LAST_MTIME=$CURRENT_MTIME
            EDIT_SETTLED_AT=0
            if [[ $NOTIFIED_EDITING -eq 0 ]]; then
                log "👤 偵測到文件變動，暫停自動回退。"
                send_discord "⚠️ Config 正在被修改" "JSON 格式暫時失效，但檢測到人為編輯。Watchdog 已暫停回退..." 16766720
                NOTIFIED_EDITING=1
            fi
        else
            # mtime 沒變 → 開始 debounce 計時
            NOW=$(date +%s)
            if [[ $EDIT_SETTLED_AT -eq 0 ]]; then
                EDIT_SETTLED_AT=$NOW
                log "📝 文件停止變動，開始 ${EDIT_DEBOUNCE_SEC}s debounce..."
            fi

            EDIT_STABLE=$((NOW - EDIT_SETTLED_AT))
            if [[ $EDIT_STABLE -lt $EDIT_DEBOUNCE_SEC ]]; then
                # 還在 debounce 期內，繼續等
                :
            else
                # debounce 結束且文件依然無效 → 進入正式寬限期
                DIFF=$((NOW - INVALID_SINCE))
                if [[ $DIFF -gt $GRACE_SEC ]]; then
                    log "⏳ 寬限期結束 ($DIFF 秒)，Config 依然無效。執行自動回退..."
                    if [[ -f "$BACKUP_PATH" ]]; then
                        cp "$BACKUP_PATH" "$OPENCLAW_CONFIG"
                        log "✅ 已從備份恢復 Config。"
                        systemctl --user restart openclaw-gateway
                        send_discord "🚨 Config 自動恢復" "Config 損壞且無人修正，已自動回退備份並重啟服務。" 16711680
                    else
                        log "💥 無法回退: 找不到備份檔 $BACKUP_PATH"
                        send_discord "💥 致命錯誤" "Config 損壞且無備份可恢復！請立即人工檢查。" 16711680
                    fi
                    INVALID_SINCE=0
                    NOTIFIED_EDITING=0
                    EDIT_SETTLED_AT=0
                fi
            fi
        fi
    else
        # --- JSON 正常 ---
        if [[ $INVALID_SINCE -gt 0 ]]; then
            log "✅ Config 格式已恢復正常。"
            [[ $NOTIFIED_EDITING -eq 1 ]] && send_discord "✅ Config 已修復" "人工修改完成，格式合法。" 65280
            INVALID_SINCE=0
            NOTIFIED_EDITING=0
            EDIT_SETTLED_AT=0
        fi

        # --- 階段 3: Gateway 運行狀態 ---
        if ! systemctl --user is-active --quiet openclaw-gateway; then
            log "❌ Gateway 離線，嘗試重啟..."
            systemctl --user restart openclaw-gateway
            sleep 5

            if systemctl --user is-active --quiet openclaw-gateway; then
                log "✅ Gateway 重啟成功。"
                send_discord "⚠️ Gateway 崩潰恢復" "Gateway 離線，已自動重啟。" 16766720
            else
                # 重啟失敗 → 嘗試回退配置再重啟
                log "💀 Gateway 重啟失敗！嘗試回退配置..."
                if [[ -f "$BACKUP_PATH" ]]; then
                    cp "$BACKUP_PATH" "$OPENCLAW_CONFIG"
                    log "🔄 已回退到備份配置，再次重啟..."
                    systemctl --user restart openclaw-gateway
                    sleep 5

                    if systemctl --user is-active --quiet openclaw-gateway; then
                        log "✅ 回退配置後重啟成功！"
                        send_discord "🚨 Gateway 配置回退恢復" "Gateway 因配置問題啟動失敗，已回退備份並成功重啟。" 16766720
                    else
                        log "💀 回退後仍失敗！需人工介入。"
                        send_discord "💀 嚴重異常" "Gateway 啟動失敗，回退配置也無法恢復！請立即人工檢查。" 16711680
                    fi
                else
                    log "💀 無備份可回退！需人工介入。"
                    send_discord "💀 嚴重異常" "Gateway 啟動失敗且無備份配置可回退！" 16711680
                fi
            fi
        else
            # Gateway 在線 → 備份健康配置
            if [[ -f "$OPENCLAW_CONFIG" ]]; then
                if ! cmp -s "$OPENCLAW_CONFIG" "$BACKUP_PATH"; then
                    cp "$OPENCLAW_CONFIG" "$BACKUP_PATH"
                    log "🔄 已備份最新健康 Config。"
                fi
            fi
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
