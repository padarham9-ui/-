#!/data/data/com.termux/files/usr/bin/bash
set -e

clear
echo "configfars | telegram = configfars"
sleep 2

# ====== نصب پیش‌نیازها ======
echo "🚀 Installing requirements..."
pkg update -y >/dev/null 2>&1
pkg install -y python wget curl nodejs php bash >/dev/null 2>&1

# نصب cloudflared
if [ ! -f "$PREFIX/bin/cloudflared" ]; then
    echo "🌐 Installing Cloudflared..."
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]]; then
        CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    elif [[ "$ARCH" == "arm"* ]]; then
        CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
    elif [[ "$ARCH" == "x86_64" ]]; then
        CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi
    wget -q "$CF_URL" -O cloudflared
    chmod +x cloudflared
    mv cloudflared "$PREFIX/bin/cloudflared"
fi

# ====== گرفتن فایل یا لینک ======
echo ""
read -p "📌 Enter file path OR https url: " INPUT

WORKDIR="$HOME/configfars_site"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
rm -f * >/dev/null 2>&1

# دانلود یا کپی فایل
if [[ "$INPUT" == http* ]]; then
    echo "🌍 Downloading from URL..."
    curl -L "$INPUT" -o codefile
else
    echo "📂 Copying local file..."
    if [ ! -f "$INPUT" ]; then
        echo "❌ File not found: $INPUT"
        exit 1
    fi
    cp "$INPUT" codefile
fi

echo "✅ File loaded into: $WORKDIR/codefile"

# ====== تشخیص نوع کد ======
FILE_TYPE=$(head -n 1 codefile | grep -Eo "(^<|^#!/usr/bin/python|^#!/bin/bash|^export|^<?php|^export default|^module.exports)" || echo "html")

echo ""
echo "🔍 Detecting file type..."

if [[ "$FILE_TYPE" == "<" ]]; then
    RUNTIME="html"
elif [[ "$FILE_TYPE" == *python* ]]; then
    RUNTIME="python"
elif [[ "$FILE_TYPE" == *bash* ]]; then
    RUNTIME="bash"
elif [[ "$FILE_TYPE" == *php* ]]; then
    RUNTIME="php"
elif [[ "$FILE_TYPE" == *export* || "$FILE_TYPE" == *module.exports* ]]; then
    RUNTIME="node"
else
    RUNTIME="html"
fi

echo "⚡ Detected type: $RUNTIME"

# ====== اجرای کد مناسب ======
PORT=8080

case $RUNTIME in
    html)
        cp codefile index.html
        echo "🌐 Starting Python HTTP server for HTML..."
        nohup python -m http.server $PORT >/dev/null 2>&1 &
        ;;
    python)
        echo "🐍 Running Python code..."
        nohup python codefile >/dev/null 2>&1 &
        ;;
    bash)
        echo "🐚 Running Bash code..."
        nohup bash codefile >/dev/null 2>&1 &
        ;;
    php)
        echo "🐘 Running PHP server..."
        nohup php -S 127.0.0.1:$PORT >/dev/null 2>&1 &
        ;;
    node)
        echo "🟢 Running Node.js code..."
        nohup node codefile >/dev/null 2>&1 &
        ;;
esac

sleep 2

# ====== ساخت Cloudflare Tunnel ======
echo ""
echo "🌐 Starting Cloudflare Temporary Tunnel..."
nohup cloudflared tunnel --url http://127.0.0.1:$PORT --no-autoupdate 2>&1 | tee cf.log &

sleep 3

echo ""
echo "=============================="
echo "🌍 Your Temporary URL:"
grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare.com" cf.log | head -n 1
echo "=============================="
echo ""
echo "⚡ Done. Keep Termux open to keep tunnel alive."
