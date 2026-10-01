#!/usr/bin/env bash
set -e

echo "=================================================="
echo "    VIRU RADIO 24/7 YOUTUBE STREAMER (V2 WARP)    "
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

echo "[+] Target Website    : $TARGET_URL"
echo "[+] Canvas Size (UI)  : ${CANVAS_WIDTH}x${CANVAS_HEIGHT} (Proper UI Proportions)"
echo "[+] Output Stream     : ${OUT_WIDTH}x${OUT_HEIGHT} (240p Bandwidth Saving)"
echo "[+] Frame Rate        : $FPS fps"
echo "[+] Video Bitrate     : $VIDEO_BITRATE"
echo "[+] Audio Bitrate     : $AUDIO_BITRATE (Studio Clean 128 kbps)"

# Graceful cleanup
cleanup() {
  echo "[!] Stopping all background processes..."
  kill $(jobs -p) 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# ==============================================================
# 1. Start Cloudflare 1.1.1.1 WARP (Bypasses YouTube Bot Detection)
# ==============================================================
echo "[+] Initializing Cloudflare WARP Service..."
mkdir -p /run/dbus /var/run/dbus /var/lib/cloudflare-warp
dbus-daemon --system --fork || true
warp-svc &
sleep 4

echo "[+] Configuring WARP Local SOCKS5 Proxy on port 40000..."
warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register 2>/dev/null || true
warp-cli --accept-tos mode proxy 2>/dev/null || warp-cli --accept-tos set-mode proxy 2>/dev/null || true
warp-cli --accept-tos proxy port 40000 2>/dev/null || warp-cli --accept-tos set-proxy-port 40000 2>/dev/null || true
warp-cli --accept-tos connect 2>/dev/null || true

PROXY_ARG=""
for i in {1..7}; do
  echo "[*] Verifying WARP connection ($i/7)..."
  if curl --socks5 127.0.0.1:40000 -s --max-time 3 https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp=on"; then
    echo "[✓] SUCCESS: Cloudflare WARP is CONNECTED! Residential IP Active."
    PROXY_ARG="--proxy-server=socks5://127.0.0.1:40000"
    break
  fi
  sleep 1
done

if [ -z "$PROXY_ARG" ]; then
  echo "[!] WARP connection skipped or timed out. Proceeding with enhanced anti-bot browser headers..."
fi

# ==============================================================
# 2. Virtual Display at 1280x720 (Fixes Giant UI Size!)
# ==============================================================
export DISPLAY=:99
echo "[+] Initializing Virtual Display (:99) at ${CANVAS_WIDTH}x${CANVAS_HEIGHT}..."
Xvfb :99 -screen 0 "${CANVAS_WIDTH}x${CANVAS_HEIGHT}x24" -ac +extension GLX +render -noreset &
sleep 2

# ==============================================================
# 3. Virtual Audio System (PulseAudio)
# ==============================================================
echo "[+] Starting PulseAudio..."
su - streamer -c "pulseaudio -D --exit-idle-time=-1" || true
sleep 1
su - streamer -c "pactl load-module module-null-sink sink_name=VirtualSink sink_properties=device.description=VirtualSink" || true
su - streamer -c "pactl set-default-sink VirtualSink" || true
su - streamer -c "pactl set-sink-volume VirtualSink 65536" || true

# ==============================================================
# 4. Launch Chromium Browser (with Anti-Bot & SOCKS5 Routing)
# ==============================================================
echo "[+] Launching Chromium in Kiosk Mode..."
su - streamer -c "DISPLAY=:99 chromium \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-blink-features=AutomationControlled \
  --disable-infobars \
  --user-agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36' \
  --window-size=${CANVAS_WIDTH},${CANVAS_HEIGHT} \
  --window-position=0,0 \
  --kiosk \
  --autoplay-policy=no-user-gesture-required \
  --mute-audio=false \
  $PROXY_ARG \
  --app='$TARGET_URL' &"

echo "[+] Waiting 8 seconds for page and YouTube player to load..."
sleep 8

# Unlock audio and trigger play
CLICK_X=$((CANVAS_WIDTH / 2))
CLICK_Y=$((CANVAS_HEIGHT / 2))
echo "[+] Triggering click at center ($CLICK_X, $CLICK_Y)..."
xdotool mousemove $CLICK_X $CLICK_Y click 1 || true

# ==============================================================
# 5. FFmpeg: Downscale 1280x720 to 426x240 for 240p Stream to YouTube
# ==============================================================
echo "[+] Launching FFmpeg Stream Engine to YouTube Live..."
GOP_SIZE=$((FPS * 2))

while true; do
  su - streamer -c "ffmpeg -y \
    -thread_queue_size 1024 \
    -f x11grab -draw_mouse 0 -video_size ${CANVAS_WIDTH}x${CANVAS_HEIGHT} -framerate $FPS -i :99.0 \
    -thread_queue_size 1024 \
    -f pulse -i VirtualSink.monitor \
    -vf 'scale=${OUT_WIDTH}:${OUT_HEIGHT}:flags=bilinear' \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -b:v $VIDEO_BITRATE -maxrate $VIDEO_BITRATE -bufsize 450k \
    -pix_fmt yuv420p -g $GOP_SIZE -keyint_min $FPS \
    -c:a aac -b:a $AUDIO_BITRATE -ar 44100 -ac 2 \
    -f flv 'rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_STREAM_KEY}'" || true

  echo "[!] Stream disconnected or network hiccup. Reconnecting in 5 seconds..."
  sleep 5
done
