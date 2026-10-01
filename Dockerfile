FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: Chromium, Xvfb, Openbox (for window focus & audio clicks), PulseAudio, FFmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    xvfb \
    openbox \
    pulseaudio \
    pulseaudio-utils \
    libasound2-plugins \
    ffmpeg \
    xdotool \
    fonts-dejavu-core \
    fonts-liberation \
    ca-certificates \
    curl \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Dedicated streamer user (runs PulseAudio, Chromium, and FFmpeg seamlessly under one user)
RUN useradd -m -s /bin/bash streamer && \
    usermod -aG audio,video streamer

WORKDIR /home/streamer

COPY start.sh /home/streamer/start.sh
RUN chmod +x /home/streamer/start.sh && chown -R streamer:streamer /home/streamer

USER streamer

ENV TARGET_URL="https://original-site-orpin.vercel.app/"
ENV OUTPUT_RESOLUTION="426x240"
ENV CANVAS_RESOLUTION="1280x720"
ENV FPS="15"
ENV VIDEO_BITRATE="200k"
ENV AUDIO_BITRATE="128k"

CMD ["/home/streamer/start.sh"]
