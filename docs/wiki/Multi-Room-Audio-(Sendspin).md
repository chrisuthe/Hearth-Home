# Multi-Room Audio (Sendspin)

**Sendspin** turns Hearth itself into a **Music Assistant audio player** — so the kiosk can
join synchronized multi-room playback alongside your other speakers. This is different from
the **[[Music Assistant]]** screen (which *controls* other players); Sendspin makes Hearth a
*player* Music Assistant can send audio to.

## Enable Sendspin

Open **Sendspin** in the [[web portal|The Web Portal]]:

| Field | Example | Notes |
| --- | --- | --- |
| **Player Name** | `Kitchen Display` | Required. The name this kiosk shows up as in Music Assistant. |
| **Enable Sendspin Player** | *(toggle)* | Disabled until you've set a Player Name. |
| **Server URL** | `ws://192.168.1.x:8095` | Optional — **leave blank to auto-discover** the server over mDNS. |
| **Buffer Size** | `5 seconds` | Audio buffer for sync: 5, 7, or 10 seconds. |

> **First-time enable must be done on the kiosk.** Toggling *Enable* on-device generates the
> player's internal ID. The web checkbox doesn't seed that ID, so enable it once from the
> device; after that you can manage it from either surface. Disabling later keeps the ID for
> when you re-enable.

## Using it

Once enabled, Hearth appears as a player in Music Assistant. Add it to a group or send audio
to it like any other Music Assistant player; the buffer setting helps keep it in sync with the
rest of the group.

## Troubleshooting

- **Kiosk doesn't appear in Music Assistant** — make sure you enabled it **on the device** at
  least once, and either leave the Server URL blank (mDNS) or point it at the right server.
- **Audio drifts out of sync** — try a larger **Buffer Size**. See [[Troubleshooting & FAQ]].
