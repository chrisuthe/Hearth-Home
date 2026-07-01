# Updating

Hearth updates itself **over the air (OTA)**. It checks for a new release **on boot and
daily**, downloads the new app bundle, swaps it in, and restarts — and if a new bundle fails
to start repeatedly, it **rolls back** to the previous one automatically.

## Automatic updates

- Controlled by **Auto-update** under **[[System|Network & System]]** (on by default).
- A systemd timer runs the updater shortly after boot and once a day.
- If **Auto-update** is off, Hearth never downloads on its own — you update manually (below).

## Choosing the update source

Under **[[System|Network & System]] → Update Source**, pick where releases come from:

- **GitHub** *(default)* — the public `Hearth-Home` releases.
- **Gitea** — the `registry.home.chrisuthe.com` releases. For a **private** Gitea repo, set a
  **Gitea API Token** (advanced; web portal only).

The updater compares the installed version against the latest release from your chosen
source, skips pre-releases, downloads the bundle, and verifies its checksum before installing.

## Updating manually

From the **[[System|Network & System]]** panel in the [[web portal|The Web Portal]]:

- **Check for Updates** — see whether a newer version exists.
- **Install Update** — install the available update (the kiosk restarts).
- **Force Update** — download and install the latest bundle without a prior check (the kiosk
  restarts).

From a shell on the Pi, you can also trigger the updater directly:

```bash
sudo systemctl start hearth-updater.service
```

Or re-run the setup script, which updates everything:

```bash
curl -sL https://raw.githubusercontent.com/chrisuthe/Hearth-Home/main/scripts/setup-pi.sh | sudo bash
```

## Rollback

Each successful update keeps the **previous** bundle as a fallback. If the kiosk fails to
start several times in a row after an update, a systemd rollback service swaps the previous
bundle back and restarts — so a bad update doesn't leave you with a dead screen.

## Troubleshooting

- **Update seems stuck** — check the kiosk's logs (linked from the portal) for the updater
  output; confirm the Pi can reach your chosen source (GitHub or Gitea). See
  [[Troubleshooting & FAQ]].
- **Wrong source** — Gitea updates need **Update Source** set to Gitea (and a token for
  private repos).
