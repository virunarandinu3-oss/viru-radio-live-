FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install base utilities and dependencies
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    ffmpeg \
    pulseaudio \
    pulseaudio-utils \
    xvfb \
    xdotool \
    libasound2-plugins \
    fonts-dejavu-core \
    fonts-liberation \
    dbus \
    dbus-x11 \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Official Google Chrome Stable
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/trusted.gpg.d/google-chrome.gpg && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends google-chrome-stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Install Official Cloudflare WARP Client (jammy / Ubuntu 22.04)
RUN curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" > /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends cloudflare-warp && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Fix X11 and DBus socket directory permissions
RUN mkdir -p /tmp/.X11-unix /var/run/dbus /var/lib/cloudflare-warp && \
    chmod 1777 /tmp/.X11-unix

# 4. Create streamer user
RUN useradd -m -s /bin/bash streamer && \
    usermod -aG audio,video streamer

WORKDIR /home/streamer

COPY start.sh /home/streamer/start.sh
RUN chmod +x /home/streamer/start.sh && chown -R streamer:streamer /home/streamer

# Run as root so start.sh can initialize WARP service, then drop to streamer
USER root

ENV TARGET_URL="https://original-site-orpin.vercel.app/"
ENV YOUTUBE_STREAM_KEY=""

CMD ["/home/streamer/start.sh"]+
