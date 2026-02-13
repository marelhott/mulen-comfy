# mulen-comfy

Minimal clone image based on `valyriantech/comfyui-with-flux:latest` with:

- ComfyUI on `8188`
- JupyterLab on `8888` without password/token
- code-server (VS Code) on `8443` without password
- persistent app/runtime data in `/workspace`

## What was changed

- `Dockerfile`: adds `code-server` and overrides startup command.
- `docker/start-mulen.sh`: keeps ComfyUI persistence from base image and adds:
  - Jupyter install into `/workspace/.venvs/jupyter`
  - Jupyter runtime/config in `/workspace`
  - code-server files/config in `/workspace`
  - no-auth launch for Jupyter and code-server

## Build and push without local Docker

This repo includes GitHub Actions workflow:

- `.github/workflows/build-and-push.yml`

It builds and pushes to Docker Hub image:

- `mulenmara/mulen-comfy:latest`

Required GitHub repo secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Then run action `Build And Push Image` (manual `workflow_dispatch`) or push to `main`.
