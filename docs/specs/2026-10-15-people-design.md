# People — Design

**Date:** 2026-10-15
**Status:** Built: the registry, its settings plugin (device + portal), the HA `person.*` link (avatar, presence, import), the migration of free-text chore people, and an optional owner per calendar source. Hardware pass not run yet — see [Hardware pass](#hardware-pass).
**Goal:** Give Hearth a household registry of its own that calendars and chore lists belong to, with each person optionally linked to a Home Assistant `person.*` for a picture and presence.

## How to read this

- **verified** — read in source at the commit under [Sources read](#sources-read). The file and line are named inline.
- **assumed** — reasoned from that source, not settled by code we read or a test we ran.

Home Assistant paths are relative to `homeassistant/` in HA core, and frontend paths to `src/` in the frontend. Line numbers are at the commits below. HA's dev branch has moved the person entity into `person/entity.py` and uses `probatio` where releases use `voluptuous`, so line numbers will differ on a stable tag. The behaviour described is unchanged.

## Sources read

| Short name | Repository | Version | Notes |
|---|---|---|---|
| HA core | `home-assistant/core` | dev `8c9b2886` (2026-10-16) | `components/person/` (`__init__.py`, `entity.py`, `const.py`), `components/device_tracker/entity.py`, `components/device_tracker/legacy.py`, `components/image_upload/__init__.py`, `components/websocket_api/commands.py`, `helpers/entity.py`, `core.py` |
| HA frontend | `home-assistant/frontend` | dev `a83d32f7` | `state/connection-mixin.ts`, `components/entity/state-badge.ts`, `components/user/ha-person-badge.ts` |
| Hearth | this repository | `f2b5290` | |

## Settled decisions

These were decided before this spec and are not reopened here.

- **The registry is Hearth's.** People live in `hub_config.json`, not in HA. A person need not exist in HA at all (a child without a phone).
- **Linking is optional, one `person.*` per person.** The link supplies a picture and presence. It **pre-fills** the name; the local name is always what Hearth shows.
- **Calendars get one optional owner; chore lists get one optional person.** Both point at a person by id.
- **The free-text chore person is replaced and migrated.** This reverses the chores spec's decision not to link `person.*` ([chores spec, Data model](2026-10-14-chores-and-lists-design.md#data-model)), which now records the reversal.
- **The Calendar screen is not changed here.** Owner filtering and colouring are [follow-ups](#follow-ups).

## The HA `person` entity

### State

- **How it is computed** (**verified**, `components/person/entity.py:158-210`): the person loops over its `device_trackers` and skips any that are missing or in `IGNORE_STATES = (STATE_UNKNOWN, STATE_UNAVAILABLE)` (`person/const.py:19`). The winner is `latest_connected or latest_legacy_home or latest_gps or latest_not_home` (`entity.py:187`). Within each group the most recently updated tracker wins (`_get_latest`, `:278-282`).
- **The value is the winning tracker's state, copied as is** (**verified**, `entity.py:229-230`, `self._attr_state = state.state`). A tracker's state is:
  - `home` for `zone.home`;
  - `not_home` outside every zone, or when a scanner tracker is disconnected;
  - **otherwise the zone's friendly name, not its entity id** (**verified**, `device_tracker/entity.py:405-410` for GPS, `:566-571` for scanners, `device_tracker/legacy.py:965` for legacy). `State.name` is the `friendly_name` attribute or the object id with `_` as spaces (`core.py:1966-1970`).
  - A GPS tracker that sets `location_name` reports that string verbatim (`device_tracker/entity.py:398-399`). So the state can be any string, not only a zone.
- **No tracker, or every tracker unknown/unavailable** (**verified**, `entity.py:201-207`): the state is set to `None`, which HA writes as `unknown` (`helpers/entity.py:1109-1110`). A person is `unavailable` only when the entity itself is (`helpers/entity.py:1107-1108`).

Hearth maps these to presence in `personPresence` (`lib/services/people.dart`): `home` → **Home**, `not_home` → **Away**, `unknown`/`unavailable` → none, and anything else is shown as given (a zone name, or a GPS `location_name`).

### Attributes

**verified**: `person/entity.py:257-273`, with keys in `person/const.py:24-33`; base attributes in `helpers/entity.py:1183-1184`.

| Attribute | When present | Hearth uses it |
|---|---|---|
| `friendly_name` | always; the person's name (`entity.py:69`) | the name when linking or importing |
| `entity_picture` | only when the person has a picture (`entity.py:70`, `self._attr_entity_picture = self._config.get(CONF_PICTURE)`) | the avatar |
| `id` | always; the person's unique id | no |
| `user_id` | only when the person is linked to an HA user | no |
| `device_trackers` | always, a list | no |
| `in_zones` | always, a list of zone entity ids, maybe empty | no |
| `source` | when a tracker won; its entity id | no |
| `latitude`, `longitude`, `gps_accuracy` | when the winning tracker has them | no |
| `editable` | always | no |

These are ordinary state attributes, written through `async_write_ha_state` (`entity.py:210`). `get_states` sends `state.as_dict_json`, whose `attributes` carry them (**verified**, `components/websocket_api/commands.py:417-445`, `core.py:2012-2014`). So Hearth's existing entity cache (`HomeAssistantService.entities`, fed by `get_states` and `state_changed`) already holds every `person.*`, and **no new subscription is needed**. That `state_changed` carries the same `State` objects is standard core behaviour, **assumed** rather than re-read for this spec.

### The picture: path, auth and base URL

- **An uploaded picture is a relative path** (**verified**, `person/__init__.py:67-69`): `^/api/image/serve/(?P<image_id>[0-9a-f]{32})/(original|\d+x\d+)$`. The size HA's UI picks when it saves is **assumed** to be `512x512`; HA serves any `WxH` or `original`.
- **The serve view needs no auth** (**verified**, `components/image_upload/__init__.py:186-191`): `ImageServeView`, `url = "/api/image/serve/{image_id}/{filename}"`, `requires_auth = False`. It returns 404 for an unknown id and builds a `WxH` thumbnail on first request (`:210-251`). So Hearth loads it with a plain `Image.network`, no token. That the *upload* view requires auth is **assumed** from the default (`http/view.py` not read); it doesn't matter to Hearth.
- **An admin can set any string** (**verified**, `person/__init__.py:170,180`, `Any(str, None)`; YAML `cv.string`, `:79`). So `entity_picture` may also be an absolute external URL. The self-service `person/update_own_profile` path accepts only uploaded-image paths (`:402-412`).
- **The frontend resolves it against the HA base URL** (**verified**, `state/connection-mixin.ts:101-104`, `new URL(path, auth.data.hassUrl)`; used by `components/entity/state-badge.ts:212-218` and `components/user/ha-person-badge.ts:29`). An absolute URL passes through `new URL` unchanged.

Hearth does the same in `personAvatarUrl`: an absolute URL is used as is, and a relative one is resolved against `config.haUrl` with `Uri.resolveUri`. Without a usable `haUrl` a relative picture gives no avatar. The avatar falls back to the person's initial on their colour when there is no picture or it fails to load.

On the portal the browser loads the same URL straight from HA, so the picture shows only when the browser can reach HA (**assumed**: no proxy is added; the `<img>` falls back to the initial on error).

## Data model

`lib/config/person.dart`:

```dart
class Person {
  final String id;               // 'person:<16 hex>', from Random.secure (newPersonId)
  final String name;             // always what Hearth shows
  final int color;               // ARGB, from Calendar's eight-colour palette
  final String haPersonEntityId; // 'person.sam', or '' when not linked
}
```

Flat JSON, every key defaulted in `fromJson`, `copyWith`, `==`/`hashCode`, the same shape as `CalendarSource` and `TodoListConfig`. An entry with no `id` is dropped on load.

**No local avatar override.** A picture comes from HA or not at all; a person without one gets their initial. A local upload would need file storage and a portal upload path for little gain, since anyone who wants a picture can set it in HA. Listed as a [follow-up](#follow-ups).

References, by id:

| Field | Was | Now |
|---|---|---|
| `TodoListConfig.personId` | `person`, a free-text name | `''` for a plain list; a person id makes it a chore list. `isChore` is `personId.isNotEmpty` |
| `CalendarSource.personId` | — | `''` for none; else the one owner |

Neither list nor source may point at a person not in the registry. `HubConfig.withPeople(people)` is the only way the registry changes (both surfaces and every route use it): it sets `people` and clears `personId` on every list and source whose person is gone. The Lists and Calendar routes reject an unknown `personId` with 400. Chore columns skip a list whose person is not found, defensively.

### Presence and avatar: `PersonView`

`lib/services/people.dart`:

- `resolvePerson(person, haUrl, ha)` → `PersonView(person, avatarUrl, presence)`. It is pure, reading the entity cache. When the person is unlinked, HA is not connected, or the entity is not in the cache, both extras are null.
- `personViewProvider` (`Provider.autoDispose.family` by person id) recomputes on each entity push and on connect/disconnect. Riverpod's `Provider` notifies only when the value changes (`!=`), so a push for another entity rebuilds nothing.
- `importablePeople(existing, ha, nextColor)` → one new `Person` per `person.*` no one links yet, named from `friendly_name`, each with the next free palette colour.

`lib/widgets/person_avatar.dart` draws a `PersonView` as the picture or initial, with a presence dot: green at home, grey away, amber in another zone.

## Configuration

| Key | Type | Default | What |
|---|---|---|---|
| `people` | `List<Person>` | `[]` | The household, in display order |
| `calendarSources[].personId` | `String` | `''` | The source's owner |
| `todoLists[].personId` | `String` | `''` | The list's person; replaces `todoLists[].person` |

`people` is unrelated to the Immich photo-people settings in `photoSources` (`peopleEnabled`, `personIds`).

## Settings plugin

`lib/plugins/people/`, id `hearth.people`, category `feature`, order 44 (just before Calendar's 45), always visible.

- **Device** (`people_settings_section.dart`): a `ListSection<Person>`. Each row shows the avatar, the name, and a status line: "Not linked to Home Assistant", or `person.sam · Home`, or why HA can't say (not configured, can't reach, not found). The add/edit dialog has the name, a **Home Assistant person** dropdown (*Not linked*, then each `person.*` not linked to someone else) and the colour picker (`CalendarColorPicker`). Picking an entity fills a blank name, or one that was the previous link's name; a typed name is kept. Below the list: **Import from Home Assistant**, with a one-line result.
- **Portal** (`people_plugin.dart`): a custom fragment with `data-config-path="people"` (the parity marker, on a `<div>` the auto-save binder ignores). One add/edit form: name, an `HaEntityPickerField.form` with `domains=person`, swatches. Plus an import button.

Routes, under `/api/plugin/hearth.people/`:

| Route | Does | Errors |
|---|---|---|
| `GET people` | each person with `color` as `#rrggbb`, `initial`, `avatarUrl`, `presence` and the status line; plus the palette | — |
| `POST people` | adds one; a blank name with a link is named from HA; no colour → next free | 400 no name, bad colour, a non-`person.*` link, a non-string field; 409 the entity is linked to someone else |
| `PUT people/:id` | name, colour, link (`''` unlinks) | 404 unknown id; 400 as above or an empty name; 409 as above |
| `DELETE people/:id` | removes them via `withPeople` | 404 unknown id |
| `POST import` | one person per unlinked `person.*`; `{added: [...]}` | 503 when HA is not connected |

As with every plugin, the routes enforce their own rules; none is gated by `isVisible`.

### Calendar and Lists

- **Lists** (device + portal): the free-text person field is a dropdown, *No one (a plain list)* plus "*Name*'s chores" for each person. Routes take `personId` instead of `person`, and `GET lists` returns the registry (`people: [{id, name}]`) so the portal can fill its `<select>`. A row's kind label is the person's name or "List".
- **Calendar** (device + portal): add (HA and ICS) and edit gain *Belongs to*. `POST sources` and `PUT sources/:id` take `personId` (`''` clears it). `GET sources` returns `personId`, the owner's name and the registry. The settings row's status line names the owner. The Calendar screen and glance are unchanged.
- **Chores view and glance**: columns group by `personId`, in the order of each person's first list. The header takes the name and colour from the `Person`. A linked person gets their avatar and presence dot in place of the colour dot, on the chart and on the glance line.

## Migration

`HubConfig.fromJson` runs `migrateLegacyPeople` on the raw JSON first:

1. If no `todoLists` entry has a non-empty `person` string without a `personId`, the JSON passes through **untouched** (the same map). That makes it idempotent: a migrated config has `people` and `personId` and no `person`, since `toJson` no longer writes it.
2. Otherwise, each distinct trimmed name becomes one `Person`, with a fresh id and **the colour of the first list that names it**, appended to any `people` already there. A name already in `people` is reused, not duplicated. Each such list gets `personId` and loses `person`. A list that has both keeps its `personId`.
3. The list keeps its own colour; only the person takes it.

`HubConfigNotifier.load()` saves straight after a migrating load, so the generated ids are the ones on disk. Without this, the next start would migrate again with new ids, and a portal holding the old ids would point at nobody.

## Deleting a person

Their lists and calendar sources stay, with `personId` cleared, so a deleted person's chore list becomes a plain list. The portal's confirm says so. Nothing in HA is touched.

## Test plan

- `test/config/hub_config_test.dart` (group "HubConfig people"): defaults; `people`, `CalendarSource.personId` and `TodoListConfig.personId` round-trip through JSON text; missing keys default to `''`; `newPersonId` shape and uniqueness; the legacy migration (Sam on two lists, Alex on one: two people, Sam's lists share an id, colours from each first list, a second load changes nothing and returns the same map); a name already registered is reused; `personId` wins over a stale `person`; `withPeople` leaves no dangling id.
- `test/plugins/people/people_routes_test.dart`: GET with avatar and presence resolved, and with HA down; POST, PUT and DELETE including 400/404/409; DELETE clears lists and sources; import adds one per unlinked entity and adds nothing the second time; 503 while HA is down.
- `test/plugins/people/people_plugin_test.dart`: registration and ordering, the portal fragment, and the device panel: rows with avatar and presence, add with link and pre-fill, edit and unlink, delete clearing lists, import twice, import with HA down.
- `test/services/people_test.dart`: presence mapping, avatar URL resolution, `resolvePerson` with unlinked, disconnected and missing entities, `personViewProvider` following pushes and a disconnect live, `importablePeople`.
- Existing Lists, chores and glance tests moved to person ids. `test/portrait/settings_portrait_test.dart` now fills `people` (two linked, two not) and owned calendar sources, so the People panel is pumped at all three canvases.

## Hardware pass

Not run. To do on the Pi and the tablet, with an HA that has at least two `person.*` (one with an uploaded picture, one without) and a phone tracker:

- Upgrade a kiosk whose config has free-text chore people; the Chores view shows the same columns afterwards, and `hub_config.json` has `people` with stable ids across a restart.
- Import from HA on the device and on the portal; link and unlink; rename after linking.
- The uploaded picture shows on the chart and glance; the person without one shows their initial.
- Walk the tracked phone out of `zone.home`; the dot goes grey, then green on return, without touching the kiosk.
- Stop HA; the dots disappear and nothing errors.
- Assign and clear an owner on an HA and an ICS calendar from both surfaces.

## Follow-ups

- Per-person filtering and colouring on the Calendar screen and the Home glance.
- A "my day" view per person: their events and chores together.
- Presence-driven behaviour (e.g. a person's column first when they arrive home).
- More than one owner per calendar source.
- Matching events to people by attendee.
- A local avatar override for people not in HA, or whose HA picture isn't wanted.
- A portal proxy for HA pictures, for a browser that can reach Hearth but not HA.

## Decisions

- **Ids, not names.** A rename touches one record; lists and calendars follow.
- **The local name wins.** HA's `friendly_name` only pre-fills it, so a link can't rename someone on the kiosk.
- **One link per HA person.** Two Hearth people can't share a `person.*`; the routes answer 409 and the device dropdown leaves linked ones out.
- **No new HA traffic.** Presence and pictures come from the entity cache Hearth already keeps.
- **Delete unassigns, never deletes.** Lists and calendars outlive their person.
