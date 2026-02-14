FROM valyriantech/comfyui-without-flux:latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install code-server into the base image once.
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Use custom startup with persistent /workspace handling.
COPY --chmod=755 docker/start-mulen.sh /start.sh

EXPOSE 8188
EXPOSE 8888
EXPOSE 8443

CMD ["/start.sh"]
