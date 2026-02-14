#!/bin/bash

set -euo pipefail

echo "pod started"

# Optional SSH key bootstrap (same as upstream)
if [[ -n "${PUBLIC_KEY:-}" ]]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cd ~/.ssh
    echo "${PUBLIC_KEY}" >> authorized_keys
    chmod 700 -R ~/.ssh
    cd /
    service ssh start || true
fi

# Keep base image persistence behavior (ComfyUI + ai-toolkit on /workspace)
/comfyui-on-workspace.sh

if [[ -x /ai-toolkit-on-workspace.sh ]]; then
  /ai-toolkit-on-workspace.sh
fi

# HuggingFace login (same as upstream)
if [[ -z "${HF_TOKEN:-}" ]] || [[ "${HF_TOKEN}" == "enter_your_huggingface_token_here" ]]; then
    echo "HF_TOKEN is not set"
else
    echo "HF_TOKEN is set, logging in..."
    hf auth login --token "${HF_TOKEN}" || true
fi

# Start AI-Toolkit UI (same as upstream, if present)
if [ -d "/workspace/ai-toolkit/ui" ]; then
    echo "Starting AI-Toolkit UI in background on port 8675"
    cd /workspace/ai-toolkit/ui
    if [ -d .next ] && [ -f dist/worker.js ]; then
        echo "Prebuilt artifacts found. Running: npm run start"
        nohup npm run start > /workspace/ai-toolkit/ui/server.log 2>&1 &
    else
        echo "Prebuilt artifacts not found. Falling back to: npm run build_and_start (this may take a while)"
        nohup npm run build_and_start > /workspace/ai-toolkit/ui/server.log 2>&1 &
    fi
    cd - >/dev/null 2>&1 || true
else
    echo "AI-Toolkit UI directory not found at /workspace/ai-toolkit/ui; skipping UI startup"
fi

# Optional download scripts (same as upstream)
if [[ "${DOWNLOAD_WAN:-false}" == "true" ]] && [[ -x /download_wan2.1.sh ]]; then
    /download_wan2.1.sh
fi

if [[ "${DOWNLOAD_FLUX:-false}" == "true" ]] && [[ -x /download_Files.sh ]]; then
    /download_Files.sh
fi

# Start nginx reverse proxy
service nginx start || true

# Start JupyterLab without token/password on :8888
jupyter lab \
  --ip=0.0.0.0 \
  --port=8888 \
  --no-browser \
  --allow-root \
  --NotebookApp.allow_origin='*' \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --NotebookApp.token='' \
  --NotebookApp.password='' \
  > /workspace/jupyter.log 2>&1 &

echo "JupyterLab started"

# Start code-server (VS Code) without auth on :8443
mkdir -p /workspace/.local/share/code-server /workspace/.local/share/code-server/extensions
code-server \
  --bind-addr 0.0.0.0:8443 \
  --auth none \
  --disable-telemetry \
  --user-data-dir /workspace/.local/share/code-server \
  --extensions-dir /workspace/.local/share/code-server/extensions \
  /workspace \
  > /workspace/code-server.log 2>&1 &

echo "code-server started"

# Run base check if present
if [[ -x /check_files.sh ]]; then
  bash /check_files.sh || true
fi

# Activate persistent venv if present (same as upstream)
if [ -d "/workspace/venv" ]; then
    echo "venv directory found, activating it"
    # shellcheck disable=SC1091
    source /workspace/venv/bin/activate
fi

# Ensure user's script exists in /workspace (same as upstream)
if [ ! -f /workspace/start_user.sh ]; then
    cp /start-original.sh /workspace/start_user.sh
    chmod +x /workspace/start_user.sh
fi

# Execute the user's script (starts ComfyUI on 8188)
bash /workspace/start_user.sh

sleep infinity
