# Web Dashboards

Hearth can render **Home Assistant Lovelace dashboards** — or **any web page** — as
first-class swipe screens, using WPE WebKit composited into the interface. Each dashboard you
add becomes its own screen in the swipe row.

![A Home Assistant Lovelace dashboard rendered as a Hearth swipe screen](images/webview-ha-dashboard.png)

## Adding dashboards

Open **Webviews** in the [[web portal|The Web Portal]]. There are two sections:

### Home Assistant dashboards
If [[Home Assistant is connected|Home Assistant Controls]], Hearth **auto-discovers** your
Lovelace dashboards and lists them with checkboxes — tick the ones you want as screens. Use
**Refresh** to re-fetch the list after adding dashboards in HA.

HA dashboards are **token-injected**: Hearth writes your long-lived token into the page at
load, so the dashboard comes up already signed in — no login prompt on the kiosk.

> If you see *"Configure Home Assistant connection first to auto-discover dashboards,"* set up
> the [[HA connection|Home Assistant Controls]] first.

### Custom URLs
Press **+ Add** to add any URL as a screen. Each custom dashboard has:

- **Name** — the label shown for the screen.
- **URL** — e.g. `https://…`.
- **Icon** — pick from a small set (Dashboard, Web, Analytics, Chart, Electrical, Shopping,
  Print, Cloud, Security, Thermostat).

You can edit or delete custom URLs later from the same panel.

## How web screens behave

- **Touch** — taps, long-presses, and vertical scrolling pass through to the page.
  *Horizontal* drags are reserved for swiping between Hearth screens, so a left/right swipe
  navigates Hearth rather than the page.
- **Idle suspend** — when the kiosk goes idle the dashboard's pipeline **suspends** to save
  resources, and resumes when you wake it.
- **Auto-restart** — if a web pipeline errors, Hearth restarts it automatically.

## Placement

Web dashboards appear in the swipe row at their configured position, alongside the built-in
screens. Use **Screens & Order** to fit them where you want — see
**[[Navigation & Gestures]]**.

## Troubleshooting

- **HA dashboard shows a login screen** — the token injection didn't take; re-check the HA
  URL/token and that the dashboard URL matches your HA instance.
- **A page renders blank** — some sites block embedding; try a different URL. See
  [[Troubleshooting & FAQ]].
