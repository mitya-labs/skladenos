# Окружение сборки ядра skladenOS: Debian trixie (arm64), зависимости из debian/control ядра Mobian (в т.ч. Rust).
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential dpkg-dev debhelper fakeroot quilt patch git ca-certificates \
    bc bison flex cpio kmod rsync libssl-dev libelf-dev device-tree-compiler \
    python3 xz-utils zstd file libclang-dev rustc bindgen rust-src \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
