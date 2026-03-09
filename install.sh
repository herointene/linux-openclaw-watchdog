#!/bin/bash

# 確保腳本在專案根目錄執行
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
USER_NAME=$(whoami)

echo "🐾 準備部署 OpenClaw Watchdog..."

# 1. 檢查 .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "⚠️ 找不到 .env 檔案！正在從 .env.example 複製..."
    cp .env.example .env
    echo "❌ 請先編輯 .env 檔案填入 WATCHDOG_WEBHOOK_URL，然後再執行此腳本。"
    exit 1
fi

# 2. 安裝 Python 依賴 (改用 python3 -m pip 以提高相容性)
echo "📦 正在安裝 Python 依賴 (requests, python-dotenv)..."
python3 -m pip install -r requirements.txt || pip3 install -r requirements.txt || { echo "❌ 依賴安裝失敗，請確認已安裝 python3-pip"; exit 1; }

# 3. 建立 Systemd 服務
SERVICE_FILE="/etc/systemd/system/openclaw-watchdog.service"
echo "⚙️ 正在產生 Systemd 服務檔 ($SERVICE_FILE)..."

sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=OpenClaw Gateway Watchdog
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=/usr/bin/python3 $PROJECT_DIR/watchdog.py
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
