# Multi-Room Audio (Sendspin)

**Sendspin** turns Hearth itself into a **Music Assistant audio player** — so the kiosk can
join synchronized multi-room playback alongside your other speakers. This is different from
the **[[Music Assistant]]** screen (which *controls* other players); Sendspin makes Hearth a
*player* Music Assistant can send audio to.

Hearth speaks **Sendspin 1.0**. Every connection is encrypted, and it only works with a
server that also speaks 1.0 — an older Music Assistant cannot connect to it.

## Enable Sendspin

Open **Sendspin** in the [[web portal|The Web Portal]] or in Settings on the kiosk:

| Field | Example | Notes |
| --- | --- | --- |
| **Player Name** | `Kitchen Display` | Required. The name this kiosk shows up as in Music Assistant. |
| **Enable Sendspin Player** | *(toggle)* | Disabled until you've set a Player Name. |
| **Server URL** | `ws://192.168.1.x:8927` | Optional. Must start with `ws://`. See below. |
| **Buffer Size** | `5 seconds` | How much audio the kiosk can hold ahead: 5, 7, or 10 seconds. |
| **Allow unpaired servers** | *(toggle, on)* | Whether a server you haven't paired with may play here. |

**Server URL — two ways to connect:**

- **Left blank:** the kiosk announces itself on the network and your server connects to it.
  This is the recommended setup, and it is the one that copes with more than one server.
- **Filled in:** the kiosk connects out to that one server and keeps retrying if it is down.

## Pairing and unpaired servers

Each kiosk has its own identity, created the first time Sendspin starts. Your server
recognises the kiosk by it.

- **Unpaired (default).** With **Allow unpaired servers** on, a server can play to the kiosk
  once you approve the new player in that server. Nothing to do on the kiosk.
- **Paired.** For a server the kiosk should trust permanently, open **Settings → Sendspin**
  **on the kiosk** and scan the QR code (or type the token under it) into your server. The
  token is only shown on the device, never in the web portal.
- Turn **Allow unpaired servers** off to accept only servers you have paired.

## Using it

Once enabled, Hearth appears as a player in Music Assistant. Add it to a group or send audio
to it like any other Music Assistant player.

## Upgrading from Hearth 1.20 or earlier

The kiosk gets a **new identity** with this version, so Music Assistant sees it as a **new
player**. Approve or pair it once, then remove the old entry and re-add the kiosk to any
groups it was in.

## Troubleshooting

- **Kiosk doesn't appear in Music Assistant** — check the server is on Sendspin 1.0, and
  either leave the Server URL blank or point it at the right server. A new kiosk may be
  waiting for approval in the server.
- **It appears but won't play** — with **Allow unpaired servers** off, the kiosk has to be
  paired first.
- **Audio is out of sync with other rooms** — sync is automatic. If one room is consistently
  early or late because of an amplifier or soundbar, set that player's output delay in the
  server. See [[Troubleshooting & FAQ]].
