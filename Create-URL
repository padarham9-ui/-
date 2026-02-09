#!/data/data/com.termux/files/usr/bin/bash
set -e

clear
echo "configfars | telegram = configfars"
sleep 2

echo ""
echo "🚀 Installing requirements..."
pkg update -y >/dev/null 2>&1
pkg install -y python wget curl openssl >/dev/null 2>&1

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

echo ""
read -p "📌 Enter file path OR https url: " INPUT

WORKDIR="$HOME/configfars_site"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

rm -f index.html

# اگر لینک بود
if [[ "$INPUT" == http* ]]; then
    echo "🌍 Downloading from URL..."
    curl -L "$INPUT" -o index.html
else
    echo "📂 Copying local file..."
    if [ ! -f "$INPUT" ]; then
        echo "❌ File not found: $INPUT"
        exit 1
    fi
    cp "$INPUT" index.html
fi

echo ""
echo "✅ File loaded into: $WORKDIR/index.html"

PORT=8080

echo ""
echo "🌐 Starting local web server on port $PORT..."
nohup python -m http.server $PORT >/dev/null 2>&1 &

sleep 1

echo ""
echo "🔥 Starting Cloudflare Temporary Tunnel..."
echo "⏳ Please wait..."

cloudflared tunnel --url http://127.0.0.1:$PORT --no-autoupdate 2>&1 | tee cf.log &

sleep 3

echo ""
echo "=============================="
echo "🌍 Your Temporary URL:"
grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare.com" cf.log | head -n 1
echo "=============================="
echo ""
echo "⚡ Done. Keep Termux open to keep tunnel alive."
