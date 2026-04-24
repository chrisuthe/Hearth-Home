#!/bin/sh
# Hearth audio-routing migration
# ------------------------------
# Applies the snd-aloop + /etc/asound.conf setup from setup-pi.sh to an
# already-installed Pi, and updates Wyoming + Sendspin config so system
# audio flows through the new hdmi_tee device.
#
# Idempotent. Safe to re-run.

set -e

log() { echo "[migrate-audio] $1"; }

# --- Load the loopback module ---
if ! lsmod | grep -q '^snd_aloop'; then
    log "Loading snd-aloop kernel module"
    sudo modprobe snd-aloop
fi

sudo tee /etc/modules-load.d/hearth-loopback.conf > /dev/null << 'EOF'
snd-aloop
EOF

# --- Write /etc/asound.conf ---
log "Writing /etc/asound.conf"
sudo tee /etc/asound.conf > /dev/null << 'EOF'
pcm.hdmi_tee {
  type plug
  slave.pcm "hdmi_tee_multi"
}
pcm.hdmi_tee_multi {
  type multi
  slaves.a.pcm "hw:vc4hdmi0,0"
  slaves.b.pcm "hw:Loopback,0,0"
  slaves.a.channels 2
  slaves.b.channels 2
  bindings.0 { slave a; channel 0; }
  bindings.1 { slave a; channel 1; }
  bindings.2 { slave b; channel 0; }
  bindings.3 { slave b; channel 1; }
}
EOF

# --- Sanity check ---
log "Sanity check: tone through hdmi_tee → loopback capture"
speaker-test -D hdmi_tee -t sine -f 440 -l 1 > /dev/null 2>&1 &
SPK_PID=$!
sleep 0.3
arecord -D hw:Loopback,1,0 -d 1 -f S16_LE -r 48000 -c 2 \
    /tmp/hearth-audio-check.wav > /dev/null 2>&1 || true
wait $SPK_PID 2>/dev/null || true
if [ -s /tmp/hearth-audio-check.wav ]; then
    log "OK — loopback capture produced data"
else
    log "WARNING — loopback capture empty. Continuing but stream audio will be silent."
fi
rm -f /tmp/hearth-audio-check.wav

# --- Update Wyoming service ---
WYOMING_UNIT=/etc/systemd/system/wyoming-satellite.service
if [ -f "$WYOMING_UNIT" ]; then
    if grep -q 'plughw:CARD=vc4hdmi0,DEV=0' "$WYOMING_UNIT"; then
        log "Updating Wyoming --snd-command to hdmi_tee"
        sudo sed -i 's|plughw:CARD=vc4hdmi0,DEV=0|hdmi_tee|g' "$WYOMING_UNIT"
        sudo systemctl daemon-reload
        sudo systemctl restart wyoming-satellite.service
    else
        log "Wyoming already using non-default snd device — leaving alone"
    fi
fi

# --- Update Sendspin config only if the user hasn't customized it ---
CONFIG=/home/hearth/.local/share/flutter-pi/hub_config.json
if [ -f "$CONFIG" ]; then
    CURRENT=$(sudo python3 -c "import json,sys
c=json.load(open('$CONFIG'))
print(c.get('sendspinAlsaDevice',''))")
    case "$CURRENT" in
        "plughw:CARD=vc4hdmi0,DEV=0" | "default" | "")
            _migrate_sendspin=true ;;
        *)
            _migrate_sendspin=false ;;
    esac
    if [ "$_migrate_sendspin" = "true" ]; then
        log "Updating sendspinAlsaDevice to hdmi_tee"
        sudo python3 -c "import json, os, tempfile
c=json.load(open('$CONFIG'))
c['sendspinAlsaDevice']='hdmi_tee'
d=os.path.dirname('$CONFIG')
fd, tmp=tempfile.mkstemp(dir=d, prefix='.hub_config-')
try:
    with os.fdopen(fd,'w') as f:
        f.write(json.dumps(c))
    os.replace(tmp,'$CONFIG')
except Exception:
    os.unlink(tmp)
    raise"
        sudo chown hearth:hearth "$CONFIG"
        sudo systemctl restart hearth.service
    else
        log "Sendspin ALSA device customized (=$CURRENT) — leaving alone"
    fi
fi

log "Migration complete."
