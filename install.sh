#!/bin/bash

# ==========================================
# OpenClaw Bash Watchdog (Ultra-Reliable)
# ==========================================
# 原生 Bash 版本，免虛擬環境與 Python 依賴。

# 確保腳本在專案根目錄執行
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
USER_NAME=$(whoami)

echo "🐾 準備部署 OpenClaw Bash Watchdog..."

# 1. 檢查 .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "⚠️ 找不到 .env 檔案！正在建立預設環境檔案..."
    cat > .env << EOF
WATCHDOG_WEBHOOK_URL=""
OPENCLAW_CONFIG_PATH="$HOME/.openclaw/openclaw.json"
WATCHDOG_CHECK_INTERVAL=15
WATCHDOG_GRACE_SEC=120
EOF
    echo "❌ 請編輯 .env 檔案填入 WATCHDOG_WEBHOOK_URL，然後再執行此腳本。"
    exit 1
fi

# 2. 檢查必要工具
for tool in jq curl stat cmp; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "❌ 缺少必要工具: $tool (請先安裝: sudo apt install $tool)"
        exit 1
    fi
done

# 3. 建立 Systemd 服務
SERVICE_FILE="/etc/systemd/system/openclaw-watchdog.service"
echo "⚙️ 正在產生 Systemd 服務檔 ($SERVICE_FILE)..."

sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=OpenClaw Gateway Watchdog (Bash Edition)
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=/usr/bin/bash $PROJECT_DIR/watchdog.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 4. 啟動服務
echo "🚀 正在重新載入 Systemd 並啟動服務..."
sudo systemctl daemon-reload
sudo systemctl enable openclaw-watchdog
sudo systemctl restart openclaw-watchdog

echo ""
echo "✅ 部署完成！"
echo "狀態檢查: sudo systemctl status openclaw-watchdog"
echo "狀態檢查: systemctl --user status openclaw-gateway"
