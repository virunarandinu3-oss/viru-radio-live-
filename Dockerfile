FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: Chromium, Xvfb, PulseAudio, FFmpeg, xdotool, fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    xvfb \
    pulseaudio \
    pulseaudio-utils \
    ffmpeg \
    xdotool \
    fonts-noto \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    ca-certificates \
    curl \
    dbus \
    dbus-x11 \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Dedicated streamer user
RUN useradd -m -s /bin/bash streamer && \
    usermod -aG audio,video streamer

WORKDIR /home/streamer

COPY start.sh /home/streamer/start.sh
RUN chmod +x /home/streamer/start.sh && chown -R streamer:streamer /home/streamer

USER streamer

# 16-Day Optimized Defaults ($5 Railway Budget)
ENV TARGET_URL="https://original-site-orpin.vercel.app/"
ENV RESOLUTION="426x240"
ENV FPS="15"
ENV VIDEO_BITRATE="200k"
ENV AUDIO_BITRATE="128k"
ENV YOUTUBE_STREAM_KEY=""

CMD ["/home/streamer/start.sh"]
