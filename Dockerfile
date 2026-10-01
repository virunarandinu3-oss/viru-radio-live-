FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Install base dependencies and tools
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
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Official Google Chrome Stable
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/trusted.gpg.d/google-chrome.gpg && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends google-chrome-stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 3. Create non-root streamer user for smooth PulseAudio & Chrome operations
RUN useradd -m -s /bin/bash streamer && \
    usermod -aG audio,video streamer

WORKDIR /home/streamer

COPY start.sh /home/streamer/start.sh
RUN chmod +x /home/streamer/start.sh && chown -R streamer:streamer /home/streamer

USER streamer

ENV TARGET_URL="https://original-site-orpin.vercel.app/"
ENV YOUTUBE_STREAM_KEY=""

CMD ["/home/streamer/start.sh"]
