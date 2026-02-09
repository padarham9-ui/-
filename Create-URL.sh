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
pkg install -y python nodejs php curl wget unzip git >/dev/null 2>&1

# ===============================
# Install Localtunnel (for public URL)
# ===============================
if ! command -v lt >/dev/null 2>&1; then
    echo "🌐 Installing localtunnel..."
    npm install -g localtunnel
fi

# ===============================
# Ask for file/url
# ===============================
echo ""
read -p "📌 Enter file path OR https url: " INPUT

WORKDIR="$HOME/configfars_public"
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
# Detect Code Type
# ===============================
CONTENT=$(cat codefile)
RUNTIME="html"

if echo "$CONTENT" | grep -q "<html"; then
    RUNTIME="html"
elif echo "$CONTENT" | grep -q "<?php"; then
    RUNTIME="php"
elif echo "$CONTENT" | grep -q "export default" || echo "$CONTENT" | grep -q "addEventListener('fetch'"; then
    RUNTIME="worker"
elif echo "$CONTENT" | grep -q "console.log"; then
    RUNTIME="node"
elif echo "$CONTENT" | grep -q "def " && echo "$CONTENT" | grep -q "print"; then
    RUNTIME="python"
elif echo "$CONTENT" | grep -q "#!/bin/bash"; then
    RUNTIME="bash"
fi

echo ""
echo "🔍 Detected runtime: $RUNTIME"

PORT=8080

kill_port() {
    pkill -f "http.server $PORT" >/dev/null 2>&1 || true
    pkill -f "node server.js" >/dev/null 2>&1 || true
    pkill -f "php -S 0.0.0.0:$PORT" >/dev/null 2>&1 || true
}

kill_port

# ===============================
# HTML
# ===============================
if [[ "$RUNTIME" == "html" ]]; then
    cp codefile index.html
    echo "🌐 Starting HTML server..."
    nohup python -m http.server $PORT >/dev/null 2>&1 &

# ===============================
# PHP
# ===============================
elif [[ "$RUNTIME" == "php" ]]; then
    cp codefile index.php
    echo "🐘 Starting PHP server..."
    nohup php -S 0.0.0.0:$PORT >/dev/null 2>&1 &

# ===============================
# PYTHON
# ===============================
elif [[ "$RUNTIME" == "python" ]]; then
    echo "🐍 Python script detected, running locally..."
    nohup python codefile >/dev/null 2>&1 &
    echo "⚡ Python scripts do not automatically create a website."
    exit 0

# ===============================
# BASH
# ===============================
elif [[ "$RUNTIME" == "bash" ]]; then
    echo "🐚 Bash script detected, running locally..."
    nohup bash codefile >/dev/null 2>&1 &
    echo "⚡ Bash scripts do not automatically create a website."
    exit 0

# ===============================
# NODE
# ===============================
elif [[ "$RUNTIME" == "node" ]]; then
    echo "🟢 Node.js detected..."
    cat > server.js <<EOF
const http = require("http");
const code = require("./codefile");

const server = http.createServer(async (req, res) => {
  res.writeHead(200, {"content-type": "text/plain; charset=utf-8"});
  res.end("✅ Node code loaded, but no fetch handler detected");
});

server.listen($PORT, "0.0.0.0", () => {
  console.log("Node server running on http://0.0.0.0:$PORT");
});
EOF
    nohup node server.js >/dev/null 2>&1 &

# ===============================
# WORKER (FIXED)
# ===============================
elif [[ "$RUNTIME" == "worker" ]]; then
    echo "⚡ Worker JS detected, converting to Node server..."
    cat > server.js <<'EOF'
const http = require("http");
const fs = require("fs");

// Load Worker code
let workerCode = fs.readFileSync("./codefile", "utf8");

// Minimal Worker Runtime
global.Response = class {
  constructor(body, init={}) {
    this.body = body || "";
    this.status = init.status || 200;
    this.headers = init.headers || {"content-type":"text/plain; charset=utf-8"};
  }
};

global.addEventListener = (type, cb) => {
  if(type === "fetch") {
    global._fetchHandler = cb;
  }
};

let worker = null;

// Try export default.fetch
try {
  const moduleObj = {};
  const exportsObj = {};
  const wrapped = new Function("module","exports", workerCode + "\nreturn exports;");
  const out = wrapped(moduleObj, exportsObj);
  if(out && out.default && typeof out.default.fetch === "function") {
    worker = out.default;
  }
} catch(e) {}

// Create HTTP server
const server = http.createServer(async (req,res) => {
  try {
    let result = null;
    if(worker && worker.fetch) {
      const requestObj = {url:req.url, method:req.method};
      result = await worker.fetch(requestObj, {}, {});
    } else if(global._fetchHandler) {
      const requestObj = {url:req.url, method:req.method};
      const event = {
        request: requestObj,
        respondWith: (resp) => { result = resp; }
      };
      await global._fetchHandler(event);
    } else {
      result = new Response("❌ Worker handler not found", {status:500});
    }

    res.writeHead(result.status || 200, result.headers || {"content-type":"text/plain; charset=utf-8"});
    res.end(result.body || "");
  } catch(e) {
    res.writeHead(500, {"content-type":"text/plain; charset=utf-8"});
    res.end("❌ Worker runtime error: "+e.toString());
  }
});

server.listen($PORT,"0.0.0.0",()=>console.log("Worker Node server running on http://0.0.0.0:8080"));
EOF
    nohup node server.js >/dev/null 2>&1 &
fi

sleep 2

# ===============================
# Start Localtunnel for Public URL
# ===============================
echo ""
echo "🌐 Starting public URL with localtunnel..."
lt --port $PORT --subdomain configfars_public 2>&1 | tee lt.log &

sleep 4
echo ""
echo "=============================="
echo "🌍 Your Public URL (Internet):"
grep -o "https://[a-zA-Z0-9.-]*\.loca\.lt" lt.log | head -n 1
echo "=============================="
echo "⚡ Keep Termux open to keep server alive."
