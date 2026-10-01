#!/usr/bin/env bash
set -e

echo "=================================================="
echo "    VIRU RADIO 24/7 STREAMER (FAST DIRECT FIX)    "
echo "=================================================="

if [ -z "$YOUTUBE_STREAM_KEY" ]; then
  echo "[-] ERROR: YOUTUBE_STREAM_KEY variable is NOT set in Railway!"
  echo "[-] Please add YOUTUBE_STREAM_KEY in Railway Variables tab."
  sleep 3600
  exit 1
fi

CANVAS_WIDTH=$(echo "$CANVAS_RESOLUTION" | cut -d'x' -f1)
CANVAS_HEIGHT=$(echo "$CANVAS_RESOLUTION" | cut -d'x' -f2)
OUT_WIDTH=$(echo "$OUTPUT_RESOLUTION" | cut -d'x' -f1)
OUT_HEIGHT=$(echo "$OUTPUT_RESOLUTION" | cut -d'x' -f2)

export DISPLAY=:99

# Graceful cleanup
cleanup() {
  echo "[!] Stopping processes..."
  kill $(jobs -p) 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# ==============================================================
# 1. Virtual Display (Xvfb) & Openbox Window Manager
# ==============================================================
echo "[+] Starting Xvfb Display on :99 (${CANVAS_WIDTH}x${CANVAS_HEIGHT})..."
Xvfb :99 -screen 0 "${CANVAS_WIDTH}x${CANVAS_HEIGHT}x24" -ac +extension GLX +render -noreset &
sleep 2

echo "[+] Starting Openbox Window Manager..."
openbox &
sleep 1

# ==============================================================
# 2. Virtual Audio System (PulseAudio)
# ==============================================================
echo "[+] Initializing PulseAudio and VirtualSink..."
pulseaudio -D --exit-idle-time=-1 || true
sleep 1

pactl load-module module-null-sink sink_name=VirtualSink sink_properties=device.description=VirtualSink || true
pactl set-default-sink VirtualSink || true
pactl set-sink-mute VirtualSink 0 || true
pactl set-sink-volume VirtualSink 65536 || true
pactl set-source-mute VirtualSink.monitor 0 || true
pactl set-source-volume VirtualSink.monitor 65536 || true
echo "[✓] PulseAudio Audio System is ready with 100% Volume!"

# ==============================================================
# 3. Launch Chromium Browser (Direct Connection & Stealth Anti-Bot)
# ==============================================================
echo "[+] Starting Chromium (Direct connection without broken proxy)..."
mkdir -p /home/streamer/chrome-profile

chromium \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-blink-features=AutomationControlled \
  --disable-infobars \
  --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" \
  --window-size=${CANVAS_WIDTH},${CANVAS_HEIGHT} \
  --window-position=0,0 \
  --kiosk \
  --autoplay-policy=no-user-gesture-required \
  --alsa-output-device=pulse \
  --enable-audio-service-sandbox=false \
  --disable-features=AudioServiceOutOfProcess \
  --use-gl=angle \
  --use-angle=swiftshader \
  --enable-webgl \
  --user-data-dir=/home/streamer/chrome-profile \
  --app="$TARGET_URL" &

# ==============================================================
# 4. Background Unmute & Click Watchdog (Runs for 45 seconds)
# ==============================================================
(
  echo "[+] Starting Unmute Watchdog..."
  for step in {1..10}; do
    sleep 4
    WID=$(xdotool search --onlyvisible --class chromium 2>/dev/null | tail -n 1 || true)
    if [ -n "$WID" ]; then
      xdotool windowactivate --sync "$WID" 2>/dev/null || true
      xdotool windowfocus --sync "$WID" 2>/dev/null || true
    fi
    # Click center of video
    xdotool mousemove $((CANVAS_WIDTH / 2)) $((CANVAS_HEIGHT / 2)) click 1 2>/dev/null || true
    # Click TV logo at top right
    xdotool mousemove $((CANVAS_WIDTH - 120)) 45 click 1 2>/dev/null || true
    # Send Keydown Space & Enter to trigger unlockSoundOnInteraction()
    xdotool key space Return 2>/dev/null || true
  done
  echo "[✓] Unmute Watchdog complete."
) &

# ==============================================================
# 5. FFmpeg: Downscale 1280x720 to 240p (200k Video + 128k Audio)
# ==============================================================
echo "[+] Starting FFmpeg Stream to YouTube RTMP..."
GOP_SIZE=$((FPS * 2))

while true; do
  ffmpeg -y \
    -thread_queue_size 1024 \
    -f x11grab -draw_mouse 0 -video_size "${CANVAS_WIDTH}x${CANVAS_HEIGHT}" -framerate $FPS -i :99.0 \
    -thread_queue_size 1024 \
    -f pulse -i VirtualSink.monitor \
    -vf "scale=${OUT_WIDTH}:${OUT_HEIGHT}:flags=bilinear" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -b:v $VIDEO_BITRATE -maxrate $VIDEO_BITRATE -bufsize 450k \
    -pix_fmt yuv420p -g $GOP_SIZE -keyint_min $FPS \
    -c:a aac -b:a $AUDIO_BITRATE -ar 44100 -ac 2 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}" || true

  echo "[!] FFmpeg disconnected. Reconnecting in 5 seconds..."
  sleep 5
done
