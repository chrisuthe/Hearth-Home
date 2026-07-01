# The Web Portal

The web portal at **`http://hearth.local:8090`** is where you configure Hearth. It mirrors
the on-device Settings screen as a **plugin sidebar**, so nearly everything can be set up
from a browser on your phone or laptop instead of typing on the kiosk.

Almost every other page in this wiki points back here — when a page says "open **X** in the
portal sidebar," this is the surface it means.

![The Hearth web portal with its plugin sidebar](images/settings.png)
*The on-device Settings screen — the portal presents the same plugins in a browser.*

## Getting in

1. On any device on the same network, browse to `http://hearth.local:8090`.
   - If `hearth.local` doesn't resolve, use the Pi's IP: `http://<pi-ip>:8090`. The
     **[[Network|Network & System]]** panel on the kiosk shows the exact URL and a QR code.
2. Enter the **PIN** shown on the kiosk display.
3. You're in — your browser holds a session for about a day before asking again.

The PIN gates the portal so only someone who can see the kiosk can configure it. A new PIN
is generated each time the app starts.

## How the sidebar is organized

Plugins are grouped into two categories:

- **Feature** — external services and features: Home Assistant, Immich, Music Assistant,
  Frigate, Mealie, Alarm Clock, Sendspin, DLNA, MQTT, Webviews, Weather.
- **Device** — settings about the kiosk itself: Screens & Order, Voice, Display, Network,
  System, and (when enabled) Capture.

Each plugin shows a **status dot**: configured, needs setup, partially set up, or an active
error (e.g. Home Assistant disconnected). Some plugins are **hidden until relevant** — for
example, **Capture** only appears once you enable *Capture tools* under
**[[System|Network & System]]**.

Everything you change **saves immediately** — there is no save button.

## The API key (for scripts)

Beyond the PIN-gated browser session, Hearth has an **API key** that lets scripts drive the
same `/api/*` endpoints with an `Authorization: Bearer <key>` header. It's auto-generated on
first run and stored in the Pi's `hub_config.json`. The portal shows it only as `••••••••`
and never lets you overwrite it — it's a read-only credential for automation.

You don't need the API key for normal setup; it exists for people who want to script Hearth
(toggle night mode, push an update, manage alarms) from elsewhere on the network.

## The logs page

The portal also serves a **logs** view (linked from the portal) showing the kiosk's recent
`journalctl` output plus live system stats — CPU/GPU temperature, memory, and uptime. It's
the first place to look when something isn't behaving. See [[Troubleshooting & FAQ]].
