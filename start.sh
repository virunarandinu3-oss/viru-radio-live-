#!/usr/bin/env bash
set -e

echo "=================================================="
echo "    VIRU RADIO 24/7 STREAMER (AUDIO & CLICK FIX)  "
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
export PULSE_SERVER=127.0.0.1:4713

# Graceful cleanup
cleanup() {
  echo "[!] Stopping all background processes..."
  kill $(jobs -p) 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# ==============================================================
# 1. Start Cloudflare 1.1.1.1 WARP
# ==============================================================
echo "[+] Initializing Cloudflare WARP Service..."
mkdir -p /run/dbus /var/run/dbus /var/lib/cloudflare-warp
dbus-daemon --system --fork || true
warp-svc &
sleep 3

warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register 2>/dev/null || true
warp-cli --accept-tos mode proxy 2>/dev/null || warp-cli --accept-tos set-mode proxy 2>/dev/null || true
warp-cli --accept-tos proxy port 40000 2>/dev/null || warp-cli --accept-tos set-proxy-port 40000 2>/dev/null || true
warp-cli --accept-tos connect 2>/dev/null || true

PROXY_ARG=""
for i in {1..6}; do
  if curl --socks5 127.0.0.1:40000 -s --max-time 2 https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp=on"; then
    echo "[✓] Cloudflare WARP is CONNECTED! Residential IP active."
    PROXY_ARG="--proxy-server=socks5://127.0.0.1:40000"
    break
  fi
  sleep 1
done

# ==============================================================
# 2. Virtual Display (Xvfb) & Openbox Window Manager
# ==============================================================
echo "[+] Starting Xvfb Display on :99 (${CANVAS_WIDTH}x${CANVAS_HEIGHT})..."
Xvfb :99 -screen 0 "${CANVAS_WIDTH}x${CANVAS_HEIGHT}x24" -ac +extension GLX +render -noreset &
sleep 2

# Openbox ensures Chromium gets active focus and responds to all clicks/keys!
echo "[+] Starting Openbox Window Manager..."
openbox &
sleep 1

# ==============================================================
# 3. Bulletproof PulseAudio Setup (TCP 127.0.0.1:4713 + VirtualSink)
# ==============================================================
echo "[+] Initializing PulseAudio TCP Server on port 4713..."

# Configure ALSA to always route through our PulseAudio TCP server
cat <<'EOF' > /etc/asound.conf
pcm.!default {
    type pulse
    server "127.0.0.1:4713"
}
ctl.!default {
    type pulse
    server "127.0.0.1:4713"
}
EOF

# Start PulseAudio daemon under streamer
su - streamer -c "pulseaudio -D --exit-idle-time=-1" || true
sleep 1

# Load TCP module so any process (root or user) connects cleanly
su - streamer -c "pactl load-module module-native-protocol-tcp auth-anonymous=1 port=4713 listen=127.0.0.1" || true

# Load Null Sink for capturing audio
su - streamer -c "pactl -s 127.0.0.1:4713 load-module module-null-sink sink_name=VirtualSink sink_properties=device.description=VirtualSink" || true
su - streamer -c "pactl -s 127.0.0.1:4713 set-default-sink VirtualSink" || true

# Maximize volume & unmute BOTH sink and monitor
su - streamer -c "pactl -s 127.0.0.1:4713 set-sink-mute VirtualSink 0" || true
su - streamer -c "pactl -s 127.0.0.1:4713 set-sink-volume VirtualSink 65536" || true
su - streamer -c "pactl -s 127.0.0.1:4713 set-source-mute VirtualSink.monitor 0" || true
su - streamer -c "pactl -s 127.0.0.1:4713 set-source-volume VirtualSink.monitor 65536" || true
echo "[✓] PulseAudio initialized with 100% volume and unmuted monitor!"

# ==============================================================
# 4. Launch Chromium Browser with Full Audio Routing
# ==============================================================
echo "[+] Starting Chromium with Target Website..."
su - streamer -c "DISPLAY=:99 PULSE_SERVER=127.0.0.1:4713 chromium \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-blink-features=AutomationControlled \
  --disable-infobars \
  --user-agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' \
  --window-size=${CANVAS_WIDTH},${CANVAS_HEIGHT} \
  --window-position=0,0 \
  --kiosk \
  --autoplay-policy=no-user-gesture-required \
  --alsa-output-device=pulse \
  --enable-audio-service-sandbox=false \
  --disable-features=AudioServiceOutOfProcess \
  $PROXY_ARG \
  --app='$TARGET_URL' &"

# ==============================================================
# 5. Continuous Unmute & Click Watchdog (Runs for 60 seconds)
# ==============================================================
(
  echo "[+] Starting Audio Unmute Watchdog..."
  for step in {1..12}; do
    sleep 4
    # 1. Activate & Focus Chromium Window
    WID=$(xdotool search --onlyvisible --class chromium 2>/dev/null | tail -n 1 || true)
    if [ -n "$WID" ]; then
      xdotool windowactivate --sync $WID 2>/dev/null || true
      xdotool windowfocus --sync $WID 2>/dev/null || true
    fi

    # 2. Click in center of the video stage
    xdotool mousemove $((CANVAS_WIDTH / 2)) $((CANVAS_HEIGHT / 2)) click 1 2>/dev/null || true

    # 3. Click the TV Logo Bug (top right) which triggers interaction
    xdotool mousemove $((CANVAS_WIDTH - 120)) 45 click 1 2>/dev/null || true

    # 4. Send Keydown events (Space & Enter) which website explicitly listens to!
    xdotool key space Return 2>/dev/null || true
    echo "[*] Watchdog gesture step $step sent (Clicks & Keypresses injected)."
  done
  echo "[✓] Audio Unmute Watchdog completed successfully."
) &

# ==============================================================
# 6. Start FFmpeg 24/7 Stream Engine with PulseAudio TCP Capture
# ==============================================================
echo "[+] Starting FFmpeg Stream to YouTube RTMP (Audio 128k AAC)..."
GOP_SIZE=$((FPS * 2))

while true; do
  ffmpeg -y \
    -thread_queue_size 1024 \
    -f x11grab -draw_mouse 0 -video_size "${CANVAS_WIDTH}x${CANVAS_HEIGHT}" -framerate $FPS -i :99.0 \
    -thread_queue_size 1024 \
    -f pulse -server 127.0.0.1:4713 -i VirtualSink.monitor \
    -vf "scale=${OUT_WIDTH}:${OUT_HEIGHT}:flags=bilinear" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -b:v $VIDEO_BITRATE -maxrate $VIDEO_BITRATE -bufsize 450k \
    -pix_fmt yuv420p -g $GOP_SIZE -keyint_min $FPS \
    -c:a aac -b:a $AUDIO_BITRATE -ar 44100 -ac 2 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}" || true

  echo "[!] FFmpeg stream disconnected. Reconnecting in 5 seconds..."
  sleep 5
done
