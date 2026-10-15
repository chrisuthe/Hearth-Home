# Updating

Hearth updates itself **over the air (OTA)**. It checks for a new release **on boot and
daily**, downloads the new app bundle, swaps it in, and restarts — and if a new bundle fails
to start repeatedly, it **rolls back** to the previous one automatically.

On an **Android tablet** the update is an APK install that Android asks you to confirm — see
[On Android](#on-android) below.

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

## What an update can change outside the app

Besides swapping the app bundle, the updater keeps three root-owned pieces current from
files shipped inside the bundle: itself (`/usr/bin/hearth-updater`), the launcher that starts
flutter-pi (`/usr/local/bin/hearth-launch`), and the rule that lets Hearth restart its own
service. A new version of the updater only *runs* on the following update, so a change of
this kind — screen rotation was the first — reaches an existing install **one update after**
the release that ships it. To apply it straight away:

```bash
sudo hearth-updater --migrate-only && sudo systemctl restart hearth.service
```

## Rollback

Each successful update keeps the **previous** bundle as a fallback. If the kiosk fails to
start several times in a row after an update, a systemd rollback service swaps the previous
bundle back and restarts — so a bad update doesn't leave you with a dead screen.

## On Android

A tablet updates from the `hearth-android-*.apk` attached to each release, from the same
**Update Source** (GitHub or Gitea).

- **Auto-update** checks about two minutes after Hearth starts and then daily. When a newer
  version is out it downloads the APK, checks it against the release's checksum, and hands it
  to Android.
- **Android confirms every install.** The first time, Hearth needs permission to **install
  unknown apps**: it opens that Android settings page for you — turn it on for Hearth. After
  that Android shows *"Do you want to update this app?"* for each update; tap **Update**. If
  you tap **Cancel**, Hearth doesn't ask again for that version until it restarts — use
  **Install Update** in the portal to try again.
- **Check for Updates**, **Install Update** and **Force Update** in the portal work the same
  way and end at the same Android prompt.
- Hearth restarts on the new version with your settings kept.
- There's **no rollback** on Android: Android won't install an older version over a newer
  one. The shell commands above are Pi-only.

## Troubleshooting

- **Update seems stuck** — check the kiosk's logs (linked from the portal) for the updater
  output; confirm the Pi can reach your chosen source (GitHub or Gitea). See
  [[Troubleshooting & FAQ]].
- **Android: "needs permission"** — turn on **Install unknown apps** for Hearth in Android's
  settings, then install again. See [[Android Tablet]].
- **Wrong source** — Gitea updates need **Update Source** set to Gitea (and a token for
  private repos).
