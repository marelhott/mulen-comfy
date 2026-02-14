#!/usr/bin/env bash

set -euo pipefail

echo "pod started"

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
mkdir -p "${WORKSPACE_DIR}"

# Optional SSH key bootstrap (same as upstream)
if [[ -n "${PUBLIC_KEY:-}" ]]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "${PUBLIC_KEY}" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    service ssh start || true
fi

# Keep base image persistence behavior (ComfyUI + ai-toolkit on /workspace).
if [[ -x /comfyui-on-workspace.sh ]]; then
    /comfyui-on-workspace.sh
else
    echo "WARN: /comfyui-on-workspace.sh not found; skipping ComfyUI workspace setup"
fi

if [[ -x /ai-toolkit-on-workspace.sh ]]; then
    /ai-toolkit-on-workspace.sh || true
fi

# HuggingFace login (same as upstream)
if [[ -z "${HF_TOKEN:-}" ]] || [[ "${HF_TOKEN}" == "enter_your_huggingface_token_here" ]]; then
    echo "HF_TOKEN is not set"
else
    echo "HF_TOKEN is set, logging in..."
    hf auth login --token "${HF_TOKEN}" || true
fi

# Start AI-Toolkit UI (same as upstream, if present)
if [[ -d "${WORKSPACE_DIR}/ai-toolkit/ui" ]]; then
    echo "Starting AI-Toolkit UI in background on port 8675"
    cd "${WORKSPACE_DIR}/ai-toolkit/ui"
    if [[ -d .next ]] && [[ -f dist/worker.js ]]; then
        echo "Prebuilt artifacts found. Running: npm run start"
        nohup npm run start > "${WORKSPACE_DIR}/ai-toolkit/ui/server.log" 2>&1 &
    else
        echo "Prebuilt artifacts not found. Falling back to: npm run build_and_start (this may take a while)"
        nohup npm run build_and_start > "${WORKSPACE_DIR}/ai-toolkit/ui/server.log" 2>&1 &
    fi
    cd - >/dev/null 2>&1 || true
else
    echo "AI-Toolkit UI directory not found at ${WORKSPACE_DIR}/ai-toolkit/ui; skipping UI startup"
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
if command -v jupyter >/dev/null 2>&1; then
    jupyter lab \
      --ip=0.0.0.0 \
      --port=8888 \
      --no-browser \
      --allow-root \
      --notebook-dir="${WORKSPACE_DIR}" \
      --NotebookApp.allow_origin='*' \
      --ServerApp.token='' \
      --ServerApp.password='' \
      --NotebookApp.token='' \
      --NotebookApp.password='' \
      > "${WORKSPACE_DIR}/jupyter.log" 2>&1 &
    echo "JupyterLab started"
else
    echo "WARN: jupyter not found; skipping JupyterLab start"
fi

# Start code-server (VS Code) without auth on :8443
if command -v code-server >/dev/null 2>&1; then
    mkdir -p \
      "${WORKSPACE_DIR}/.local/share/code-server" \
      "${WORKSPACE_DIR}/.local/share/code-server/extensions"
    code-server \
      --bind-addr 0.0.0.0:8443 \
      --auth none \
      --disable-telemetry \
      --user-data-dir "${WORKSPACE_DIR}/.local/share/code-server" \
      --extensions-dir "${WORKSPACE_DIR}/.local/share/code-server/extensions" \
      "${WORKSPACE_DIR}" \
      > "${WORKSPACE_DIR}/code-server.log" 2>&1 &
    echo "code-server started"
else
    echo "WARN: code-server not found; skipping code-server start"
fi

# Run base check if present
if [[ -x /check_files.sh ]]; then
    bash /check_files.sh || true
fi

# Activate persistent venv if present (same as upstream)
if [[ -d "${WORKSPACE_DIR}/venv" ]]; then
    echo "venv directory found, activating it"
    # shellcheck disable=SC1091
    source "${WORKSPACE_DIR}/venv/bin/activate"
fi

# Ensure user's script exists in /workspace (same as upstream)
if [[ ! -f "${WORKSPACE_DIR}/start_user.sh" ]]; then
    cp /start-original.sh "${WORKSPACE_DIR}/start_user.sh"
    chmod +x "${WORKSPACE_DIR}/start_user.sh"
fi

# Execute the user's script (starts ComfyUI on 8188)
bash "${WORKSPACE_DIR}/start_user.sh"

sleep infinity
