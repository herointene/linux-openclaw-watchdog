#!/bin/bash

# 確保腳本在專案根目錄執行
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
USER_NAME=$(whoami)

echo "🐾 準備部署 OpenClaw Watchdog (Universal Edition)..."

# 1. 檢查 .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "⚠️ 找不到 .env 檔案！正在從 .env.example 複製..."
    cp .env.example .env
    echo "❌ 請先編輯 .env 檔案填入 WATCHDOG_WEBHOOK_URL，然後再執行此腳本。"
    exit 1
fi

# 2. 處理 Python 依賴
echo "📦 正在安裝 Python 依賴..."

# 嘗試使用虛擬環境 (最優解)
if python3 -m venv venv 2>/dev/null; then
    echo "✅ 虛擬環境建立成功。"
    PYTHON_EXEC="$PROJECT_DIR/venv/bin/python3"
    $PYTHON_EXEC -m pip install -r requirements.txt
else
    # 如果 venv 失敗 (缺少 python3-venv)，則使用 --break-system-packages 強行安裝 (相容性方案)
    echo "⚠️ 虛擬環境建立失敗，切換到全域強行安裝模式 (--break-system-packages)..."
    PYTHON_EXEC="/usr/bin/python3"
    python3 -m pip install --break-system-packages -r requirements.txt || pip3 install --break-system-packages -r requirements.txt
fi

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
ExecStart=$PYTHON_EXEC $PROJECT_DIR/watchdog.py
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
