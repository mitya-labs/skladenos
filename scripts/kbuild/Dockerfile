# Сборочное окружение для ядра Mobian sdm845 (arm64 нативно на Apple Silicon).
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev device-tree-compiler \
    xz-utils git kmod python3 rsync cpio ca-certificates file zstd \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
