# flutter-pi Fork + HDMI Mirror Design

**Status:** Implemented
**Date:** 2026-05-08
**Goal:** Mirror Hearth's rendered output to the Pi 5's second HDMI port at zero CPU cost so an HDMI capture card on HDMI-A-2 can produce a clean OBS source — replacing the kmsgrab + libx264 software-encode path that the Pi 5 cannot sustain at framerate.

## Why a fork

Three previously-shipping flutter-pi patches lived as Python text-replacement substitutions in `scripts/apply_patch.py`, applied at build time on the Pi. That worked for ~30 lines touching one file. It does not scale.

This change touches 8 files and ~250 LOC inside flutter-pi. Text-replacement against upstream master has two terminal failure modes for a change this size:

1. **Whitespace drift.** Any reformatting upstream — even a single `clang-format` pass — silently misses substring matches. The script has one assertion at the end (`if "pipeline_description != NULL" not in src`) that catches *some* failures but misses most.
2. **Pinning loss.** The previous flow cloned `ardera/flutter-pi` master at build time. Two fresh installs a week apart could produce different binaries with no record of which upstream commit was in use.

A real fork solves both: patches are commits with full diff context, and a `UPSTREAM_PIN` file at the repo root captures which upstream SHA we're tracking.

## Why Gitea primary + GitHub mirror

The repo lives at `https://registry.home.chrisuthe.com/chris/flutter-pi-hearth.git` (Gitea, private to the home network) and is mirrored to `https://github.com/chrisuthe/flutter-pi-hearth.git` (public).

Push order in dev is "Gitea first, GitHub second" — same dual-remote pattern as the Hearth repo itself. `setup-pi.sh` clones Gitea first and falls back to GitHub if Gitea is unreachable (e.g. fresh Pi setup off the home network). The Pi can't authenticate to private Gitea repos without a key set up, so in practice the Pi always uses the GitHub fallback today; the Gitea path is for the user's dev machine where credentials are cached.

GitHub's role is purely a passive mirror — fork-of-fork, all changes flow Gitea → GitHub.

## Pi 5 DRM architecture (load-bearing for the patch shape)

Pre-flight via `kmsprint --device=/dev/dri/card1 -l`:

- **Two DRM device nodes:** `card0` (`/dev/dri/card0`) is `1002000000.v3d` — render-only, used for GL via Mesa. `card1` (`/dev/dri/card1`) is `axi:gpu` — display engine, owns all connectors.
- **Both HDMIs on the same card.** Connector 0 (id 33) is HDMI-A-1 (panel, connected). Connector 1 (id 42) is HDMI-A-2 (capture card, connected only when in use). flutter-pi opens `card1` and sees both as siblings.
- **4 CRTCs** (id 57, 76, 92, 104). One drives the panel; one is allocated to the mirror at startup.
- **56 planes**, of which 4 are primary planes pinned to a specific CRTC (Plane 0→CRTC 0, Plane 1→CRTC 1, Plane 2→CRTC 2, Plane 3→CRTC 3) and the remaining 52 are flexible overlay/cursor planes. Plane allocation for the mirror CRTC is never the bottleneck.
- **Encoders 0, 1 are TMDS** (HDMI). Encoders 2, 3 are VIRTUAL (writeback connectors). HDMI-A-1 → Encoder 0, HDMI-A-2 → Encoder 1. Symmetric.

The single-drmdev fact is what makes the patch tractable: a DRM framebuffer (`drm_fb_id`) is device-global, so the same FB the primary CRTC scans out can be referenced by a plane on the second CRTC. Two atomic commits, one allocation, zero memcpy.

## Why "two atomic commits sharing one FB" beats every alternative

| Approach | CPU/GPU cost | Engineering | Fit for kiosk |
|---|---|---|---|
| **Passive HDMI splitter** | 0 (electrical) | 0 (buy a $25 box) | Best for "just send the same image to both"; locks both outputs to identical mode/resolution. |
| **Compositor (sway/wayfire) with `output mirror_of`** | 1–3% CPU + extra GPU composition pass | High — abandon flutter-pi's DRM-direct architecture, run flutter Linux Desktop as a Wayland client | Throws away flutter-pi's leanness for a feature we'd otherwise build cheap. |
| **flutter-pi mirror (this patch)** | ~tens of µs per frame (one extra atomic commit) | Medium — ~250 LOC in C, well-isolated | Different mode per output (panel native + 1080p mirror with hardware scaling), graceful degradation when capture card unplugged, no architectural changes. |
| **DRM lease + helper daemon** | Negligible | High — buffer sharing across processes via dmabuf, frame timing coordination, hot-plug edge cases | Too much for the value vs. option 3. |

The patch lives in the existing fork architecture. Maintenance cost is one rebase per upstream version bump.

## How the patch works

**Initialization** (`kms_window_new` in `src/window.c`):
1. `select_mode` picks the primary's connector + encoder + CRTC + mode (existing behavior — first connected connector wins).
2. If `--mirror-connector NAME` was passed, `find_connector_by_name` locates the secondary connector by its DRM-conventional name (e.g. `HDMI-A-2`).
3. If found and connected, `select_mirror_resources` picks a free encoder + CRTC distinct from the primary's, and selects the connector's preferred mode (or the largest <= 1080p as fallback — capture-card friendly).
4. If the connector is missing or disconnected, the mirror is silently disabled with one warning line; the kiosk continues normally on the primary. **This is the graceful-degradation path** and is what runs when no capture card is plugged in.

**Per-frame** (`kms_window_push_composition_locked` in `src/window.c`):
1. The original per-CRTC commit body is refactored into `kms_window_build_req_for_target`, a helper that takes a `mirror_present_target` (CRTC + connector + mode + is_mirror flag).
2. The function is called twice when mirror is enabled — once for primary, once for mirror — building two `kms_req` objects that point at the same Flutter framebuffer.
3. For the mirror, a letterboxed dst rect is computed from `mirror.mode` and passed via `surface_present_kms_opts.dst_override`. The surface impls (EGL/GBM, dmabuf, vulkan/GBM, dummy) honor the override by overwriting `kms_fb_layer.dst_*` after building it. DRM's HVS scales the FB during scanout — zero CPU cost.
4. The cursor plane is primary-only (mirror skips the cursor block).
5. Both reqs land on `frame->req` and `frame->mirror_req` of a single `frame` struct. `frame_scheduler_present_frame_tandem` (a thin wrapper over `frame_scheduler_present_frame` for now) hands the frame to the existing scheduler.
6. In `on_present_frame`, the primary commit runs first (`kms_req_commit_blocking`), then the mirror commit. In `on_cancel_frame`, both reqs are unref'd.

**Mirror failures are non-sticky at commit time** — a failed `kms_req_commit_blocking` on the mirror logs and continues; the next frame retries. **Mirror failures are sticky at build time** — if `kms_window_build_req_for_target` fails for the mirror, `window->mirror.enabled = false` so we never present a half-mirrored frame.

## Buffer lifetime: why this is safe

Each `kms_req` independently holds refs to its FBs and planes via `kms_req_builder_push_fb_layer`'s release callbacks. When a `kms_req` is unref'd (after its commit completes), its releases fire.

When primary and mirror reqs reference the same FB, that FB's refcount goes up by 2 (one per req's plane layer) and down as each req is unref'd. The FB is destroyed when both reqs have completed. The Flutter swap chain doesn't see the FB as "released" until then.

The current implementation uses sequential `kms_req_commit_blocking` calls — the mirror commit waits for the primary's vblank, which delays the second flip by one vblank in the worst case. In practice on Pi 5 both commits land in the same vblank window because `_blocking` returns as soon as the kernel has accepted the commit (not when the flip happens). If profiling reveals tearing or skew between the two outputs, promote `frame_scheduler_present_frame_tandem` to a true vblank-counted tandem: submit both atomic commits non-blocking, count two pageflip events before firing the present-complete callback, then release.

## Rebase procedure

When upstream `ardera/flutter-pi` ships changes worth pulling in:

```bash
cd <flutter-pi-fork>
git fetch upstream
git rebase upstream/master
# Resolve any conflicts manually (most of our patches are localized
# and rarely conflict; player.c is the most likely candidate since
# upstream actively works on it).
# Update UPSTREAM_PIN: bump upstream_sha, upstream_subject, pinned_at.
git add UPSTREAM_PIN
git commit --amend --no-edit  # fold pin update into the rebase
git push --force-with-lease origin hearth
git push --force-with-lease github hearth
```

`--force-with-lease` (not `--force`) catches the case where someone else pushed to `hearth` between fetch and push. For a personal fork that's unlikely, but the safety belt is free.

## CLI surface

- `flutter-pi --mirror-connector HDMI-A-2 ...` — mirror to that connector.
- No flag, or unrecognized connector name, or disconnected connector → mirror disabled with a one-line log warning, primary continues normally.
- The Hearth systemd unit (`scripts/setup-pi.sh:192`) hardcodes `--mirror-connector HDMI-A-2`. Safe as a default because the runtime gracefully degrades when no card is plugged in.

## What's deliberately not solved here

- **Hot-plug.** Plugging in the capture card after boot does NOT enable the mirror — you have to restart the service. Adding hot-plug-aware mirror enablement is ~50 LOC (listen on the drmdev's hot-plug uevent, re-run `select_mirror_resources` when HDMI-A-2 transitions to connected). Deferred — the kiosk reboots more often than the capture card moves.
- **Multiple mirrors.** One mirror connector at a time. No use case for two.
- **Audio routing on HDMI-A-2.** The capture card receives whatever HDMI audio the Pi 5 sends to HDMI-A-2 — currently nothing, since PipeWire's default sink is HDMI-A-1. If you want the capture stream to carry audio, route it. Out of scope.

## References

- Pre-flight evidence: `kmsprint --device=/dev/dri/card1 -l` output captured during planning.
- Plan: `docs/superpowers/plans/2026-05-08-flutter-pi-hdmi-mirror.md` (gitignored — agent's working memory).
- Fork: `https://registry.home.chrisuthe.com/chris/flutter-pi-hearth` (Gitea, primary). Mirror: `https://github.com/chrisuthe/flutter-pi-hearth` (GitHub).
- Upstream: `https://github.com/ardera/flutter-pi` — pinned in `UPSTREAM_PIN` on the fork's `hearth` branch.
