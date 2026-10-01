#!/usr/bin/env bash
set -e

echo "=================================================="
echo "    STREAM VIRU RADIO TO YOUTUBE (16-DAY PLAN)    "
echo "=================================================="

if [ -z "$YOUTUBE_STREAM_KEY" ]; then
  echo "[-] ERROR: YOUTUBE_STREAM_KEY variable is NOT set in Railway!"
  echo "[-] Please add YOUTUBE_STREAM_KEY in Railway Variables tab."
  sleep 3600
  exit 1
fi

TARGET_URL="${TARGET_URL:-https://original-site-orpin.vercel.app/}"

# Append autoplay=1 parameter safely
if [[ "$TARGET_URL" == *"?"* ]]; then
  FULL_URL="${TARGET_URL}&autoplay=1"
else
  FULL_URL="${TARGET_URL}?autoplay=1"
fi

echo "[+] Target URL     : $FULL_URL"
echo "[+] Video Quality  : 240p (426x240 @ 15fps, 200 kbps)"
echo "[+] Audio Quality  : 128 kbps AAC (Crystal Clear)"
echo "[+] Duration Target: 16 Days within Railway \$5 Budget"

# Graceful cleanup
cleanup() {
  echo "[!] Stopping processes..."
  kill $(jobs -p) 2>/dev/null || true
  exit 0
}
trap cleanup SIGTERM SIGINT

# 1. Start Virtual Display in 720p (Normal TV Proportions)
echo "[+] Starting Xvfb Display on :99..."
Xvfb :99 -screen 0 1280x720x24 &
export DISPLAY=:99
sleep 2

# 2. Setup PulseAudio Virtual Sink
echo "[+] Initializing PulseAudio Virtual Sink..."
pulseaudio --start --exit-idle-time=-1
sleep 2
pactl load-module module-null-sink sink_name=VirtualSink sink_properties=device.description=VirtualSink
pactl set-default-sink VirtualSink
export PULSE_SINK=VirtualSink
pactl set-sink-mute VirtualSink 0 || true
pactl set-sink-volume VirtualSink 65536 || true
pactl set-source-mute VirtualSink.monitor 0 || true
pactl set-source-volume VirtualSink.monitor 65536 || true

# 3. Suppress Chrome Prompts
mkdir -p ~/.config/google-chrome
touch ~/.config/google-chrome/'First Run'

# 4. Launch Clean Official Google Chrome (No Automation Banners, Pure Consumer Mode)
echo "[+] Launching Official Google Chrome..."
google-chrome \
  --no-sandbox \
  --no-first-run \
  --no-default-browser-check \
  --disable-search-engine-choice-screen \
  --disable-dev-shm-usage \
  --disable-blink-features=AutomationControlled \
  --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" \
  --autoplay-policy=no-user-gesture-required \
  --disable-gpu \
  --window-size=1280,720 \
  --window-position=0,0 \
  --start-fullscreen \
  --kiosk "$FULL_URL" &

# 5. Wait for page load and trigger broadcast clicks & keys to unmute
(
  echo "[+] Starting Unmute Watchdog..."
  for i in 1 2 3 4 5; do
    sleep 6
    xdotool search --onlyvisible --class "google-chrome" windowfocus || true
    xdotool mousemove 640 360 click 1 || true
    xdotool key space Return || true
    echo "[*] Triggered broadcast unmute click & keys (attempt $i)."
  done
) &

# 6. Stream Engine: Downscale 1280x720 to 240p (200k Video + 128k Audio = 16 Days)
echo "[+] Launching FFmpeg Stream to YouTube Live..."
while true; do
  ffmpeg -hide_banner -loglevel warning \
    -thread_queue_size 512 -f x11grab -draw_mouse 0 -video_size 1280x720 -framerate 15 -i :99.0 \
    -thread_queue_size 512 -f pulse -i VirtualSink.monitor \
    -vf "scale=426:240:flags=bilinear" \
    -c:v libx264 -preset ultrafast -tune zerolatency \
    -fps_mode cfr -r 15 -g 30 -keyint_min 30 -sc_threshold 0 \
    -b:v 200k -maxrate 200k -bufsize 400k -pix_fmt yuv420p \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY" || true

  echo "[!] Stream disconnected. Reconnecting in 5 seconds..."
  sleep 5
done
