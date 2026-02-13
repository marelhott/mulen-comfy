#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[mulen-comfy] $*"
}

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
JUPYTER_VENV="${WORKSPACE_DIR}/.venvs/jupyter"
CODE_SERVER_DIR="${WORKSPACE_DIR}/tools/code-server"
CODE_SERVER_BIN="${CODE_SERVER_DIR}/bin/code-server"

mkdir -p "${WORKSPACE_DIR}"

if [[ -n "${PUBLIC_KEY:-}" ]]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "${PUBLIC_KEY}" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    service ssh start || true
fi

# Keep ComfyUI and AI toolkit persisted on the network volume.
/comfyui-on-workspace.sh
/ai-toolkit-on-workspace.sh || true

if [[ -n "${HF_TOKEN:-}" ]] && [[ "${HF_TOKEN}" != "enter_your_huggingface_token_here" ]]; then
    hf auth login --token "${HF_TOKEN}" || true
fi

# Persisted Jupyter installation on /workspace.
if [[ ! -x "${JUPYTER_VENV}/bin/jupyter" ]]; then
    log "Bootstrapping Jupyter venv to ${JUPYTER_VENV}"
    mkdir -p "${WORKSPACE_DIR}/.venvs"
    python3 -m venv "${JUPYTER_VENV}"
    "${JUPYTER_VENV}/bin/pip" install --upgrade pip
    "${JUPYTER_VENV}/bin/pip" install --no-cache-dir jupyterlab
fi

mkdir -p \
    "${WORKSPACE_DIR}/.jupyter" \
    "${WORKSPACE_DIR}/.local/share/jupyter/runtime" \
    "${WORKSPACE_DIR}/.cache/jupyter"

export JUPYTER_CONFIG_DIR="${WORKSPACE_DIR}/.jupyter"
export JUPYTER_DATA_DIR="${WORKSPACE_DIR}/.local/share/jupyter"
export JUPYTER_RUNTIME_DIR="${WORKSPACE_DIR}/.local/share/jupyter/runtime"
export JUPYTERLAB_SETTINGS_DIR="${WORKSPACE_DIR}/.jupyter/lab/user-settings"

# Persist code-server files into /workspace on first run.
if [[ ! -x "${CODE_SERVER_BIN}" ]]; then
    log "Seeding code-server into ${CODE_SERVER_DIR}"
    mkdir -p "${WORKSPACE_DIR}/tools"
    cp -a /usr/lib/code-server "${CODE_SERVER_DIR}"
fi

mkdir -p \
    "${WORKSPACE_DIR}/.local/share/code-server" \
    "${WORKSPACE_DIR}/.local/share/code-server/extensions"

log "Starting JupyterLab on :8888 without password/token"
"${JUPYTER_VENV}/bin/jupyter" lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --allow-root \
    --notebook-dir="${WORKSPACE_DIR}" \
    --ServerApp.token='' \
    --ServerApp.password='' \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --NotebookApp.allow_origin='*' \
    > "${WORKSPACE_DIR}/jupyter.log" 2>&1 &

log "Starting code-server on :8443 without password"
"${CODE_SERVER_BIN}" \
    --bind-addr 0.0.0.0:8443 \
    --auth none \
    --disable-telemetry \
    --user-data-dir "${WORKSPACE_DIR}/.local/share/code-server" \
    --extensions-dir "${WORKSPACE_DIR}/.local/share/code-server/extensions" \
    "${WORKSPACE_DIR}" \
    > "${WORKSPACE_DIR}/code-server.log" 2>&1 &

if [[ ! -f "${WORKSPACE_DIR}/start_user.sh" ]]; then
    cp /start-original.sh "${WORKSPACE_DIR}/start_user.sh"
    chmod +x "${WORKSPACE_DIR}/start_user.sh"
fi

log "Starting ComfyUI from persisted /workspace/ComfyUI on :8188"
exec bash "${WORKSPACE_DIR}/start_user.sh"
