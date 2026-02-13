#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[mulen-comfy] $*"
}

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
# Avoid copying huge trees to /workspace. This is the default.
PERSIST_STRATEGY="${PERSIST_STRATEGY:-symlink}"  # symlink|move

# Jupyter
JUPYTER_VENV="${WORKSPACE_DIR}/.venvs/jupyter"
PERSIST_JUPYTER_VENV="${PERSIST_JUPYTER_VENV:-false}"

# Paths
COMFY_DIR="/ComfyUI"
COMFY_MODELS_IMAGE="${COMFY_DIR}/models.image"
COMFY_CUSTOM_NODES_IMAGE="${COMFY_DIR}/custom_nodes.image"

WS_COMFY_DATA_DIR="${WORKSPACE_DIR}/ComfyUI-data"
WS_AI_TOOLKIT_OUTPUT_DIR="${WORKSPACE_DIR}/ai-toolkit-output"

mkdir -p "${WORKSPACE_DIR}"

if [[ -n "${PUBLIC_KEY:-}" ]]; then
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  echo "${PUBLIC_KEY}" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  service ssh start || true
fi

seed_files_as_symlinks() {
  local src_root="$1"
  local dst_root="$2"

  # Create dst tree and symlink files from src into dst, preserving dirs.
  # This keeps disk usage near-zero while still exposing models.
  if [[ ! -d "${src_root}" ]]; then
    return 0
  fi

  mkdir -p "${dst_root}"

  (cd "${src_root}" && find . -type d -print0) | while IFS= read -r -d '' d; do
    mkdir -p "${dst_root}/${d#./}"
  done

  (cd "${src_root}" && find . -type f -print0) | while IFS= read -r -d '' f; do
    local dst="${dst_root}/${f#./}"
    if [[ ! -e "${dst}" ]]; then
      ln -s "${src_root}/${f#./}" "${dst}"
    fi
  done
}

setup_symlink_persistence() {
  mkdir -p "${WS_COMFY_DATA_DIR}"

  # Make /workspace/ComfyUI point to code in the image for compatibility with base workflows/scripts.
  # If it already exists, we don't overwrite it.
  if [[ ! -e "${WORKSPACE_DIR}/ComfyUI" ]]; then
    ln -s "${COMFY_DIR}" "${WORKSPACE_DIR}/ComfyUI"
  fi

  # Persist output/input/user.
  for d in output input user; do
    mkdir -p "${WS_COMFY_DATA_DIR}/${d}"
    rm -rf "${COMFY_DIR:?}/${d}" || true
    ln -s "${WS_COMFY_DATA_DIR}/${d}" "${COMFY_DIR}/${d}"
  done

  # Persist models without copying the large files.
  if [[ -d "${COMFY_DIR}/models" && ! -L "${COMFY_DIR}/models" && ! -d "${COMFY_MODELS_IMAGE}" ]]; then
    mv "${COMFY_DIR}/models" "${COMFY_MODELS_IMAGE}"
  fi
  mkdir -p "${WS_COMFY_DATA_DIR}/models"
  if [[ -d "${COMFY_MODELS_IMAGE}" ]]; then
    seed_files_as_symlinks "${COMFY_MODELS_IMAGE}" "${WS_COMFY_DATA_DIR}/models"
  fi
  rm -rf "${COMFY_DIR}/models" || true
  ln -s "${WS_COMFY_DATA_DIR}/models" "${COMFY_DIR}/models"

  # Persist custom_nodes directory itself (so you can add new nodes) but seed existing ones as symlinks.
  if [[ -d "${COMFY_DIR}/custom_nodes" && ! -L "${COMFY_DIR}/custom_nodes" && ! -d "${COMFY_CUSTOM_NODES_IMAGE}" ]]; then
    mv "${COMFY_DIR}/custom_nodes" "${COMFY_CUSTOM_NODES_IMAGE}"
  fi
  mkdir -p "${WS_COMFY_DATA_DIR}/custom_nodes"
  if [[ -d "${COMFY_CUSTOM_NODES_IMAGE}" ]]; then
    # Symlink top-level node dirs/files.
    shopt -s dotglob nullglob
    for e in "${COMFY_CUSTOM_NODES_IMAGE}"/*; do
      base="$(basename "$e")"
      if [[ ! -e "${WS_COMFY_DATA_DIR}/custom_nodes/${base}" ]]; then
        ln -s "$e" "${WS_COMFY_DATA_DIR}/custom_nodes/${base}"
      fi
    done
  fi
  rm -rf "${COMFY_DIR}/custom_nodes" || true
  ln -s "${WS_COMFY_DATA_DIR}/custom_nodes" "${COMFY_DIR}/custom_nodes"

  # AI-Toolkit: avoid copying it to /workspace. Keep code in image; persist only output.
  if [[ ! -e "${WORKSPACE_DIR}/ai-toolkit" ]]; then
    ln -s /ai-toolkit "${WORKSPACE_DIR}/ai-toolkit" || true
  fi
  mkdir -p "${WS_AI_TOOLKIT_OUTPUT_DIR}"
  rm -rf /ai-toolkit/output || true
  ln -s "${WS_AI_TOOLKIT_OUTPUT_DIR}" /ai-toolkit/output

  # Ensure training dirs exist like in the original template.
  mkdir -p "${WORKSPACE_DIR}/training_set" "${WORKSPACE_DIR}/LoRas"
}

setup_move_persistence() {
  # Legacy behavior from ValyrianTech (can be extremely large on /workspace).
  /comfyui-on-workspace.sh
  /ai-toolkit-on-workspace.sh || true
}

if [[ "${PERSIST_STRATEGY}" == "move" ]]; then
  log "PERSIST_STRATEGY=move (may fill /workspace quickly)"
  setup_move_persistence
else
  setup_symlink_persistence
fi

if [[ -n "${HF_TOKEN:-}" ]] && [[ "${HF_TOKEN}" != "enter_your_huggingface_token_here" ]]; then
  hf auth login --token "${HF_TOKEN}" || true
fi

# Start AI-Toolkit UI (if present) without forcing a copy to /workspace.
if [[ -d "/ai-toolkit/ui" ]]; then
  log "Starting AI-Toolkit UI on :8675"
  cd /ai-toolkit/ui
  if [[ -d .next ]] && [[ -f dist/worker.js ]]; then
    nohup npm run start > "${WORKSPACE_DIR}/ai-toolkit-ui.log" 2>&1 &
  else
    nohup npm run build_and_start > "${WORKSPACE_DIR}/ai-toolkit-ui.log" 2>&1 &
  fi
  cd - >/dev/null 2>&1 || true
fi

if [[ "${DOWNLOAD_WAN:-false}" == "true" ]] && [[ -x /download_wan2.1.sh ]]; then
  /download_wan2.1.sh
fi

if [[ "${DOWNLOAD_FLUX:-false}" == "true" ]] && [[ -x /download_Files.sh ]]; then
  /download_Files.sh
fi

service nginx start || true

# Persist Jupyter runtime/config on /workspace.
mkdir -p \
  "${WORKSPACE_DIR}/.jupyter" \
  "${WORKSPACE_DIR}/.local/share/jupyter/runtime" \
  "${WORKSPACE_DIR}/.cache/jupyter"

export JUPYTER_CONFIG_DIR="${WORKSPACE_DIR}/.jupyter"
export JUPYTER_DATA_DIR="${WORKSPACE_DIR}/.local/share/jupyter"
export JUPYTER_RUNTIME_DIR="${WORKSPACE_DIR}/.local/share/jupyter/runtime"
export JUPYTERLAB_SETTINGS_DIR="${WORKSPACE_DIR}/.jupyter/lab/user-settings"

JUPYTER_BIN=""
if [[ "${PERSIST_JUPYTER_VENV}" == "true" ]]; then
  if [[ ! -x "${JUPYTER_VENV}/bin/jupyter" ]]; then
    log "Bootstrapping persistent Jupyter venv to ${JUPYTER_VENV}"
    mkdir -p "${WORKSPACE_DIR}/.venvs"
    python3 -m venv "${JUPYTER_VENV}"
    "${JUPYTER_VENV}/bin/pip" install --upgrade pip
    "${JUPYTER_VENV}/bin/pip" install --no-cache-dir jupyterlab
  fi
  JUPYTER_BIN="${JUPYTER_VENV}/bin/jupyter"
else
  if command -v jupyter >/dev/null 2>&1; then
    JUPYTER_BIN="$(command -v jupyter)"
  else
    JUPYTER_BIN="python3 -m jupyter"
  fi
fi

log "Starting JupyterLab on :8888 without password/token"
# shellcheck disable=SC2086
${JUPYTER_BIN} lab \
  --ip=0.0.0.0 \
  --port=8888 \
  --no-browser \
  --allow-root \
  --ServerApp.root_dir="${WORKSPACE_DIR}" \
  --notebook-dir="${WORKSPACE_DIR}" \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --NotebookApp.token='' \
  --NotebookApp.password='' \
  --NotebookApp.allow_origin='*' \
  > "${WORKSPACE_DIR}/jupyter.log" 2>&1 &

# Persist code-server settings/extensions only.
mkdir -p \
  "${WORKSPACE_DIR}/.local/share/code-server" \
  "${WORKSPACE_DIR}/.local/share/code-server/extensions"

CODE_SERVER_BIN=""
if command -v code-server >/dev/null 2>&1; then
  CODE_SERVER_BIN="$(command -v code-server)"
elif [[ -x /usr/bin/code-server ]]; then
  CODE_SERVER_BIN="/usr/bin/code-server"
fi

if [[ -z "${CODE_SERVER_BIN}" ]]; then
  log "ERROR: code-server binary not found"
  exit 1
fi

log "Starting code-server on :8443 without password"
"${CODE_SERVER_BIN}" \
  --bind-addr 0.0.0.0:8443 \
  --auth none \
  --disable-telemetry \
  --user-data-dir "${WORKSPACE_DIR}/.local/share/code-server" \
  --extensions-dir "${WORKSPACE_DIR}/.local/share/code-server/extensions" \
  "${WORKSPACE_DIR}" \
  > "${WORKSPACE_DIR}/code-server.log" 2>&1 &

if [[ -x /check_files.sh ]]; then
  bash /check_files.sh || true
fi

if [[ -d "${WORKSPACE_DIR}/venv" ]]; then
  # shellcheck disable=SC1090
  source "${WORKSPACE_DIR}/venv/bin/activate"
fi

if [[ ! -f "${WORKSPACE_DIR}/start_user.sh" ]]; then
  cp /start-original.sh "${WORKSPACE_DIR}/start_user.sh"
  # Ensure it runs ComfyUI from the image location (we no longer copy /ComfyUI to /workspace).
  sed -i 's#python3 /workspace/ComfyUI/main.py#python3 /ComfyUI/main.py#g' "${WORKSPACE_DIR}/start_user.sh" || true
  chmod +x "${WORKSPACE_DIR}/start_user.sh"
fi

log "Starting ComfyUI on :8188"
exec bash "${WORKSPACE_DIR}/start_user.sh"
