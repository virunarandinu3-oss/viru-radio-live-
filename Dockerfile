FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install base utilities, Chromium, Xvfb, PulseAudio, FFmpeg, and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    xvfb \
    pulseaudio \
    pulseaudio-utils \
    ffmpeg \
    xdotool \
    fonts-dejavu-core \
    fonts-liberation \
    ca-certificates \
    curl \
    gnupg \
    dbus \
    dbus-x11 \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Official Cloudflare WARP Client (Bypasses YouTube datacenter bot detection)
RUN curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && apt-get install -y --no-install-recommends cloudflare-warp && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create streamer user for clean PulseAudio & Chromium audio permissions
RUN useradd -m -s /bin/bash streamer && \
    usermod -aG audio,video streamer

WORKDIR /app

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh && chown -R streamer:streamer /home/streamer /app

ENV TARGET_URL="https://original-site-orpin.vercel.app/"
ENV OUTPUT_RESOLUTION="426x240"
ENV CANVAS_RESOLUTION="1280x720"
ENV FPS="15"
ENV VIDEO_BITRATE="200k"
ENV AUDIO_BITRATE="128k"

CMD ["/app/start.sh"]
