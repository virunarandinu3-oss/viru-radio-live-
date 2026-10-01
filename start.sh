#!/usr/bin/env bash
set -e

echo "=================================================="
echo "    VIRU RADIO 24/7 YOUTUBE STREAMER (128 kbps)   "
echo "=================================================="

if [ -z "$YOUTUBE_STREAM_KEY" ]; then
  echo "[-] ERROR: YOUTUBE_STREAM_KEY variable is NOT set in Railway!"
  echo "[-] Please add YOUTUBE_STREAM_KEY in Railway Variables tab."
  sleep 3600
  exit 1
fi

export DISPLAY=:99
WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2)

echo "[+] Target Website : $TARGET_URL"
echo "[+] Resolution     : ${WIDTH}x${HEIGHT} (240p Standard)"
echo "[+] Frame Rate     : $FPS fps"
echo "[+] Video Bitrate  : $VIDEO_BITRATE"
echo "[+] Audio Bitrate  : $AUDIO_BITRATE (Crystal Clean 128 kbps)"

# Graceful cleanup
cleanup() {
  echo "[!] Stopping all background processes..."
  kill $(jobs -p) 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# 1. Start Virtual Display (Xvfb)
echo "[+] Initializing Virtual Display (:99)..."
Xvfb :99 -screen 0 "${WIDTH}x${HEIGHT}x24" -ac +extension GLX +render -noreset &
sleep 2

# 2. Start PulseAudio Virtual Sound System
echo "[+] Initializing Virtual PulseAudio..."
pulseaudio -D --exit-idle-time=-1 || true
sleep 1
pactl load-module module-null-sink sink_name=VirtualSink sink_properties=device.description=VirtualSink || true
pactl set-default-sink VirtualSink || true
pactl set-sink-volume VirtualSink 65536 || true

# 3. Start Chromium Browser in Kiosk Mode
echo "[+] Launching Chromium on virtual screen..."
chromium \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --disable-software-rasterizer \
  --disable-extensions \
  --disable-background-networking \
  --window-size="${WIDTH},${HEIGHT}" \
  --window-position=0,0 \
  --kiosk \
  --autoplay-policy=no-user-gesture-required \
  --mute-audio=false \
  --app="$TARGET_URL" &

# Wait for player to boot
echo "[+] Waiting 8 seconds for web player and playlist..."
sleep 8

# Click screen to ensure audio unlock
CLICK_X=$((WIDTH / 2))
CLICK_Y=$((HEIGHT / 2))
echo "[+] Triggering virtual click at center ($CLICK_X, $CLICK_Y) to unlock audio..."
xdotool mousemove $CLICK_X $CLICK_Y click 1 || true

# 4. Start FFmpeg 24/7 Stream Engine with 128 kbps AAC
echo "[+] Launching FFmpeg RTMP Live Stream..."
GOP_SIZE=$((FPS * 2))

while true; do
  ffmpeg -y \
    -thread_queue_size 1024 \
    -f x11grab -draw_mouse 0 -video_size "${WIDTH}x${HEIGHT}" -framerate "$FPS" -i :99.0 \
    -thread_queue_size 1024 \
    -f pulse -i VirtualSink.monitor \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_BITRATE" -bufsize 450k \
    -pix_fmt yuv420p -g "$GOP_SIZE" -keyint_min "$FPS" \
    -c:a aac -b:a "$AUDIO_BITRATE" -ar 44100 -ac 2 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}" || true

  echo "[!] Stream disconnected or network hiccup. Reconnecting in 5 seconds..."
  sleep 5
done
