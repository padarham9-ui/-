#!/data/data/com.termux/files/usr/bin/bash
set -e

clear
echo "configfars | telegram = configfars"
sleep 2
echo ""

# ===============================
# Install Requirements
# ===============================
echo "🚀 Installing requirements..."
pkg update -y >/dev/null 2>&1
pkg install -y python nodejs php curl wget openssl >/dev/null 2>&1

# ===============================
# Install Cloudflared
# ===============================
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

# ===============================
# Ask for file/url
# ===============================
echo ""
read -p "📌 Enter file path OR https url: " INPUT

WORKDIR="$HOME/configfars_runtime"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
rm -rf * >/dev/null 2>&1

# ===============================
# Download / Copy file
# ===============================
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

echo "✅ Loaded file into: $WORKDIR/codefile"

# ===============================
# Detect Code Type by content
# ===============================
CONTENT=$(cat codefile)

RUNTIME="html"

if echo "$CONTENT" | grep -q "<html"; then
    RUNTIME="html"
elif echo "$CONTENT" | grep -q "<?php"; then
    RUNTIME="php"
elif echo "$CONTENT" | grep -q "import " && echo "$CONTENT" | grep -q "from"; then
    RUNTIME="node"
elif echo "$CONTENT" | grep -q "console.log"; then
    RUNTIME="node"
elif echo "$CONTENT" | grep -q "export default" && echo "$CONTENT" | grep -q "fetch"; then
    RUNTIME="worker"
elif echo "$CONTENT" | grep -q "addEventListener('fetch'"; then
    RUNTIME="worker"
elif echo "$CONTENT" | grep -q "def " && echo "$CONTENT" | grep -q "print"; then
    RUNTIME="python"
elif echo "$CONTENT" | grep -q "#!/bin/bash"; then
    RUNTIME="bash"
fi

echo ""
echo "🔍 Detected runtime: $RUNTIME"

# ===============================
# Run based on runtime
# ===============================
PORT=8080

kill_port() {
    pkill -f "http.server $PORT" >/dev/null 2>&1 || true
    pkill -f "node server.js" >/dev/null 2>&1 || true
    pkill -f "php -S 127.0.0.1:$PORT" >/dev/null 2>&1 || true
}

kill_port

# ===============================
# HTML MODE
# ===============================
if [[ "$RUNTIME" == "html" ]]; then
    cp codefile index.html
    echo "🌐 Starting HTML server..."
    nohup python -m http.server $PORT >/dev/null 2>&1 &

# ===============================
# PHP MODE
# ===============================
elif [[ "$RUNTIME" == "php" ]]; then
    cp codefile index.php
    echo "🐘 Starting PHP server..."
    nohup php -S 127.0.0.1:$PORT >/dev/null 2>&1 &

# ===============================
# PYTHON MODE
# ===============================
elif [[ "$RUNTIME" == "python" ]]; then
    echo "🐍 Python detected but needs a web server to show URL."
    echo "⚡ Running Python as a local script (no website)."
    nohup python codefile >/dev/null 2>&1 &
    echo "❌ Python scripts cannot automatically become a website unless they use Flask/FastAPI."

    echo "👉 Tip: use HTML or Node/Worker code for web output."
    exit 0

# ===============================
# BASH MODE
# ===============================
elif [[ "$RUNTIME" == "bash" ]]; then
    echo "🐚 Bash detected (runs locally, not a website)."
    nohup bash codefile >/dev/null 2>&1 &
    echo "❌ Bash script cannot become a website automatically."
    exit 0

# ===============================
# NODE MODE
# ===============================
elif [[ "$RUNTIME" == "node" ]]; then
    echo "🟢 Node.js detected..."

    cat > server.js <<EOF
const http = require("http");

const code = require("./codefile");

const server = http.createServer(async (req, res) => {
  try {
    res.writeHead(200, {"content-type": "text/plain; charset=utf-8"});
    res.end("✅ Node code loaded (but no handler detected)");
  } catch (err) {
    res.writeHead(500, {"content-type": "text/plain; charset=utf-8"});
    res.end("❌ Error: " + err.toString());
  }
});

server.listen($PORT, "127.0.0.1", () => {
  console.log("Server running on http://127.0.0.1:$PORT");
});
EOF

    nohup node server.js >/dev/null 2>&1 &

# ===============================
# WORKER MODE (REAL FIX)
# ===============================
elif [[ "$RUNTIME" == "worker" ]]; then
    echo "⚡ Cloudflare Worker code detected!"
    echo "🔥 Converting Worker to Node server..."

    cat > server.js <<'EOF'
const http = require("http");
const fs = require("fs");

let workerCode = fs.readFileSync("./codefile", "utf8");

// Worker Compatibility Layer
global.Response = class {
  constructor(body, init = {}) {
    this.body = body || "";
    this.status = init.status || 200;
    this.headers = init.headers || {};
  }
};

function createRequest(url, method="GET") {
  return { url, method };
}

let worker = null;

// Case 1: export default { fetch() }
try {
  const moduleObj = {};
  const exportsObj = {};

  const wrapped = new Function("module", "exports", workerCode + "\nreturn exports;");
  const out = wrapped(moduleObj, exportsObj);

  if (out && out.default && typeof out.default.fetch === "function") {
    worker = out.default;
  }
} catch (e) {}

// Case 2: addEventListener('fetch', ...)
let eventHandler = null;
if (!worker) {
  global.addEventListener = (type, cb) => {
    if (type === "fetch") {
      eventHandler = cb;
    }
  };

  try {
    eval(workerCode);
  } catch (e) {}
}

const server = http.createServer(async (req, res) => {
  try {
    let result = null;

    if (worker && worker.fetch) {
      const requestObj = createRequest(req.url, req.method);
      result = await worker.fetch(requestObj, {}, {});
    } else if (eventHandler) {
      let responseObj = null;
      const event = {
        request: createRequest(req.url, req.method),
        respondWith: (resp) => {
          responseObj = resp;
        }
      };
      await eventHandler(event);
      result = responseObj;
    } else {
      result = new Response("❌ Worker code detected but no fetch handler found", { status: 500 });
    }

    res.writeHead(result.status || 200, result.headers || { "content-type": "text/plain; charset=utf-8" });
    res.end(result.body || "");
  } catch (err) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    res.end("❌ Worker runtime error: " + err.toString());
  }
});

server.listen(8080, "127.0.0.1", () => {
  console.log("Worker runtime running on http://127.0.0.1:8080");
});
EOF

    nohup node server.js >/dev/null 2>&1 &
fi

sleep 2

# ===============================
# Cloudflare Tunnel
# ===============================
echo ""
echo "🌐 Starting Cloudflare Temporary Tunnel..."
cloudflared tunnel --url http://127.0.0.1:$PORT --no-autoupdate 2>&1 | tee cf.log &

sleep 4

echo ""
echo "=============================="
echo "🌍 Your Temporary URL:"
grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare.com" cf.log | head -n 1
echo "=============================="
echo ""
echo "⚡ Done. Keep Termux open to keep tunnel alive."
