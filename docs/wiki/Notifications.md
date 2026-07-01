# Notifications

Hearth can show **notification cards** on the kiosk — a doorbell press, a laundry
cycle finishing, an "someone's at the gate" alert. Unlike most of this wiki,
notifications are pushed *into* Hearth (usually from Home Assistant) rather than
configured on the device. Each one surfaces as a card on the kiosk's **bottom
deck**, with an arrival chime and a coloured source chip.

There are exactly **two ways to send** a notification, and both accept the same
payload:

- **MQTT** — publish JSON to the kiosk's `.../notify` topic. Best if you already
  run **[[Home Assistant Device (MQTT)]]**.
- **HTTP** — `POST` to the kiosk's local API. The fallback when you don't have
  an MQTT broker.

## Send over MQTT

Publish a JSON payload to:

```
hearth/<clientId>/notify
```

`<clientId>` is the kiosk's hostname (see
[Finding your clientId and address](#finding-your-clientid-and-address) below).
From Home Assistant there are two ways to publish to it.

### 1. The `notify.mqtt` entity (HA 2024.5+)

The simplest path: define an MQTT notify entity whose command topic is Hearth's
notify topic. This sends a **message-only** card (the message becomes the card's
heading; you don't get title/priority/sticky control this way):

```yaml
mqtt:
  - notify:
      name: Hearth
      command_topic: "hearth/<clientId>/notify"
      command_template: '{"message": {{ value | to_json }}}'
```

Then call it like any notifier — e.g. `action: notify.hearth` with
`data.message: "Someone's at the door"`.

### 2. The `mqtt.publish` action (full control)

Publish the JSON yourself when you want a title, priority, or stickiness — e.g.
from an automation:

```yaml
action: mqtt.publish
data:
  topic: "hearth/<clientId>/notify"
  payload: >-
    {"title": "Laundry", "message": "Cycle finished",
     "priority": "info", "sticky": false}
```

## Send over HTTP

If you don't run an MQTT broker, `POST` the same JSON to the kiosk's local API on
port **8090**:

```
POST http://<hearth-ip>:8090/api/notify
```

Like every `/api/*` endpoint, this needs the kiosk's **API key** as a bearer
token (`Authorization: Bearer <key>`). The key is auto-generated and shown under
**[[The Web Portal]] → API key** — see *"The API key (for scripts)"* there for
where to find it.

A Home Assistant `rest_command` is the tidy way to wire it up:

```yaml
rest_command:
  hearth_notify:
    url: "http://192.168.1.50:8090/api/notify"
    method: POST
    headers:
      authorization: "Bearer YOUR_API_KEY"
      content-type: "application/json"
    payload: '{"title": "{{ title }}", "message": "{{ message }}", "priority": "{{ priority | default(''info'') }}"}'
```

Then call `action: rest_command.hearth_notify` with `data` for `title`,
`message`, and `priority`. A successful post returns `{"status": "ok", ...}`; a
payload with neither a title nor a message is rejected with a `400`.

## Finding your clientId and address

Both paths need to know *which* kiosk to reach:

- **`<clientId>` (for MQTT)** — the kiosk's hostname, lowercased, with anything
  that isn't a letter, digit, or underscore replaced by `_`. A Pi named
  `Hearth-Kitchen` becomes `hearth_kitchen`. If the hostname can't be read it
  falls back to `hearth`. The quickest check is the **Hearth** device's MQTT
  topics in Home Assistant (they all start `hearth/<clientId>/`).
- **`<hearth-ip>:8090` (for HTTP)** — the kiosk's IP and portal port. The
  **[[Network|Network & System]]** panel on the kiosk shows the exact address
  (prefer the numeric IP, e.g. `192.168.1.50`, over `hearth.local`).

## Payload fields

Every field is optional **except** that you must send at least one of `title` or
`message`. Both delivery paths share this schema:

| Field | Values / default | What it does |
| --- | --- | --- |
| `title` | string | The card's heading. If omitted, the `message` is promoted to the heading (a message-only card). |
| `message` | string (alias `body`) | The card's body text. One of `title`/`message` is required. |
| `priority` | `alert` \| `info` — default `info` | Sets the accent colour, the chime, and the default stickiness. |
| `sticky` | `true` \| `false` — default: sticky for `alert`, transient for `info` | Whether the card stays until dismissed, or auto-dismisses after 6 seconds. |
| `source` | `frigate` \| `unifi` \| `ha` \| `push` \| `timer` — default `ha` | Drives the source chip. `protect` is accepted as an alias for `unifi`. |
| `source_label` | string | Overrides the chip text (default derived from `source`, e.g. `HOME ASST`). |
| `muted` | `true` \| `false` — default `false` | Arrives with no chime. Rarely set — muting is normally a per-card toggle on the kiosk. |

## On the kiosk

When a notification arrives:

- **Bottom deck** — cards stack along the bottom edge of the screen, newest
  nearest your hand.
- **Arrival chime** — an `alert` plays the **Ember Alert** (an urgent triple
  beep); an `info` plays the **Soft Ping** (a single gentle tone).
- **Night mode silences the chime** — while the display is in night mode
  (**[[Display & Night Mode]]**) cards still appear, but arrive silently. A
  `muted` card is likewise silent.
- **Sticky vs transient** — a sticky card stays until you dismiss it; a transient
  card auto-dismisses after **6 seconds**. `alert` defaults to sticky, `info` to
  transient (override with the `sticky` field).
- **Source chip** — each card shows an uppercase chip for its source:
  `FRIGATE`, `PROTECT`, `HOME ASST`, `PUSH`, or `TIMER` (or your `source_label`).

## Troubleshooting

- **No card appears** — for MQTT, double-check the topic's `<clientId>` matches
  the kiosk (they all start `hearth/<clientId>/` in Home Assistant); for HTTP,
  check the `<hearth-ip>:8090` address and that the `Authorization: Bearer` key
  is correct (a wrong key returns `401`). Confirm your payload has a `title` or
  `message`.
- **Card appears but no sound** — the kiosk is likely in **night mode** (chimes
  are suppressed), or the payload set `muted: true`.

See [[Troubleshooting & FAQ]] for more.
