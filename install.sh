#!/bin/bash

# ==========================================
# OpenClaw Watchdog Installer
# ==========================================

# 確保腳本在專案根目錄執行
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)

# 1. 偵測真實使用者 (即使使用 sudo 執行也應對應到原使用者)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")

echo "🐾 正在部署 OpenClaw Watchdog..."
echo "👤 執行使用者: $REAL_USER"
echo "🏠 使用者目錄: $REAL_HOME"

# 2. 檢查必要工具
for tool in jq curl; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "❌ 錯誤: 系統未安裝 $tool。請執行: sudo apt install $tool"
        exit 1
    fi
done

# 3. 初始化 .env 並寫入絕對路徑 (避免 ~ 展開問題)
CONFIG_PATH="$REAL_HOME/.openclaw/openclaw.json"

if [ ! -f ".env" ]; then
    echo "📝 建立預設 .env 檔案..."
    cat > .env << EOF
WATCHDOG_WEBHOOK_URL=""
OPENCLAW_CONFIG_PATH="$CONFIG_PATH"
WATCHDOG_CHECK_INTERVAL=15
WATCHDOG_GRACE_SEC=120
EOF
    echo "⚠️  請編輯 .env 並填入 WATCHDOG_WEBHOOK_URL，然後再次執行此腳本。"
    exit 1
else
    # 更新 .env 中的路徑為絕對路徑 (如果尚未設定)
    if ! grep -q "OPENCLAW_CONFIG_PATH" .env; then
        echo "OPENCLAW_CONFIG_PATH=\"$CONFIG_PATH\"" >> .env
    fi
fi

# 4. 產生 Systemd 服務 (固定 User 並確保路徑正確)
SERVICE_FILE="/etc/systemd/system/openclaw-watchdog.service"
echo "⚙️  正在配置 Systemd 服務..."

sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=OpenClaw Gateway Watchdog
After=network.target

[Service]
Type=simple
User=$REAL_USER
Group=$(id -gn $REAL_USER)
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
# 強制設定 HOME 確保 ~ 展開正常
Environment=HOME=$REAL_HOME
ExecStart=/usr/bin/bash $PROJECT_DIR/watchdog.sh
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

# 5. 啟動服務
echo "🚀 啟動守護進程..."
sudo systemctl daemon-reload
sudo systemctl enable openclaw-watchdog
sudo systemctl restart openclaw-watchdog

echo ""
echo "✅ 部署成功！"
echo "🔍 查看即時日誌: journalctl -u openclaw-watchdog -f"
