FROM valyriantech/comfyui-with-flux:latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Override startup script only. All other base image behavior is preserved.
COPY --chmod=755 docker/start-mulen.sh /start.sh

EXPOSE 8188
EXPOSE 8888
EXPOSE 8443

CMD ["/start.sh"]
