#!/bin/bash

# 確保腳本在專案根目錄執行
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
USER_NAME=$(whoami)

echo "🐾 準備部署 OpenClaw Watchdog (Venv Edition)..."

# 1. 檢查 .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "⚠️ 找不到 .env 檔案！正在從 .env.example 複製..."
    cp .env.example .env
    echo "❌ 請先編輯 .env 檔案填入 WATCHDOG_WEBHOOK_URL，然後再執行此腳本。"
    exit 1
fi

# 2. 建立虛擬環境 (解決 externally-managed-environment 報錯)
echo "虚拟环境：正在初始化 venv..."
if [ ! -d "venv" ]; then
    python3 -m venv venv || { echo "❌ 無法建立虛擬環境，請執行 'sudo apt install python3-venv' 後再試"; exit 1; }
fi

# 3. 安裝依賴到虛擬環境
echo "📦 正在安裝 Python 依賴到虛擬環境..."
./venv/bin/pip install -r requirements.txt || { echo "❌ 依賴安裝失敗"; exit 1; }

# 4. 建立 Systemd 服務 (ExecStart 指向虛擬環境的 Python)
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
# 使用虛擬環境中的 python 執行，這樣就不會受到系統 Python 限制的影響
ExecStart=$PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/watchdog.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 5. 啟動服務
echo "🚀 正在重新載入 Systemd 並啟動服務..."
sudo systemctl daemon-reload
sudo systemctl enable openclaw-watchdog
sudo systemctl restart openclaw-watchdog

echo ""
echo "✅ 部署完成！(已自動配置虛擬環境)"
echo "狀態檢查: sudo systemctl status openclaw-watchdog"
