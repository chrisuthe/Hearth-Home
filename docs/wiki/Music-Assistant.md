# Music Assistant

The **Music** screen is a full-bleed now-playing player backed by
[Music Assistant](https://music-assistant.io/). It shows album art, transport controls, a
volume slider, and lets you pick which player/zone you're controlling. Music Assistant
connects **directly** — it does not depend on Home Assistant.

![Music Assistant now-playing with album art and transport controls](images/music.png)

## Connect Music Assistant

In the [[web portal|The Web Portal]], open **Music Assistant** and enter:

| Field | Example | Where to get it |
| --- | --- | --- |
| **Music Assistant URL** | `http://192.168.1.x:8095` | Your Music Assistant server |
| **Music Assistant Token** | *(paste it)* | A Music Assistant long-lived token |

## Options

- **Default Music Zone** — the player Hearth controls by default, as a `media_player` entity
  ID (e.g. `media_player.living_room`). If you leave it blank, the connection still works but
  the plugin is marked *partial* — set a default so the Music screen opens on the right player.

## Using the Music screen

- **Now playing** — album art, track/artist/album, and a progress bar.
- **Transport** — play/pause and skip.
- **Volume** — a slider for the current player.
- **Zones** — switch which Music Assistant player you're controlling for multi-room setups.
- **Browse** — a drawer to browse your library by category, album, and artist.

## Troubleshooting

- **Nothing plays / the screen is empty** — confirm the URL and token are correct and the
  server is reachable from the Pi, and that **Default Music Zone** points at a real player.
- **Multi-room out of sync** — that's a Music Assistant concern; also see
  **[[Multi-Room Audio (Sendspin)]]** if you want Hearth itself to be a synced player.
