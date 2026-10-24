# Сборочное окружение эмуляторов skladenOS: тот же дистрибутив (Debian testing, arm64), что и на телефоне.
FROM debian:testing-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git build-essential ninja-build meson pkg-config python3 python3-venv python3-setuptools flex bison \
      libglib2.0-dev libpixman-1-dev libsdl2-dev libslirp-dev zlib1g-dev \
      qtbase5-dev qt5-qmake libasound2-dev libwayland-dev libxkbcommon-dev libdecor-0-dev wayland-protocols libwayland-bin libasound2-dev \
      debhelper dpkg-dev fakeroot lintian \
    && rm -rf /var/lib/apt/lists/*
