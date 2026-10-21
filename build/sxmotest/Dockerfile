# Тестовое окружение для слоя B пакета skladenos-config: настоящий sxmo-utils (arm64) + sway для проверки конфигов.
FROM debian:trixie-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    sxmo-utils sway jq python3 sudo systemd swaybg network-manager dpkg-dev debhelper fakeroot ca-certificates procps \
 && rm -rf /var/lib/apt/lists/*
