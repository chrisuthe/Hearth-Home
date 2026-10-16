# Chores and Lists — Design

**Date:** 2026-10-14
**Status:** Built. Child tasks 1–5 (data layer, screen, settings, chore chart, glance) and the hardware pass (6, [below](#hardware-pass)) are done.
**Goal:** Specify Skylight-style lists and a chore chart on Hearth, built on Home Assistant `todo` entities, and break the work into the tasks the epic will follow.
**Tracking:** issue 214 (Skylight feature inventory). The Calendar epic did the calendar half; this is the lists and chores half.

## How to read this

- **verified** — read in source at the version under [Sources read](#sources-read). The file and line are named inline.
- **assumed** — reasoned from that source, not settled by code we read or a test we ran.

Home Assistant paths are relative to `homeassistant/components/` in HA core, except `helpers/…`, which is `homeassistant/helpers/`. Line numbers are at tag `2026.10.1` unless another tag is named.

## Sources read

| Short name | Repository | Version | Notes |
|---|---|---|---|
| HA core | `home-assistant/core` | tag `2026.10.1` (`abe1fdd7`) | `todo/`, `shopping_list/todo.py`, `local_todo/todo.py`, `google_tasks/todo.py` + `coordinator.py`, `caldav/todo.py`, `websocket_api/`, `helpers/entity.py`, `helpers/json.py`, `exceptions.py` |
| HA core, history | `home-assistant/core` | tags `2023.11.0`, `2023.12.0`, `2025.11.0`, `2025.12.0` and others | `todo/__init__.py` (and `entity.py` where it exists) at each tag, to date when each command and field appeared |
| HA frontend | `home-assistant/frontend` | tag `20260930.3` (the version `frontend/manifest.json` pins in core 2026.10.1) | `src/data/todo.ts`, `src/panels/lovelace/cards/hui-todo-list-card.ts` |
| Hearth | this repository | `d4489da` | |

## Settled decisions

These were decided before this spec and are not reopened here.

- **Read-write.** From the kiosk: complete and uncomplete, add, edit, delete, reorder.
- **Chores are HA to-do lists, one per person.** Settings map a list to a person. Hearth stores no chore state of its own; recurrence is whatever backs the list.
- **No stars, points or rewards.**
- **Idle Home glance:** today's open chores (due today or overdue). Optional, **off by default**.
- **HA to-do is the only source.** No Skylight, Google or Microsoft account of Hearth's own; those reach Hearth through HA.

## Scope

In scope: every `todo.*` entity the user adds in settings, shown as a list; the lists that are mapped to a person also shown as a chore chart; the glance.

Out of scope, on purpose:

- Stars, points, rewards, streaks, a "who did it" history.
- Hearth-side recurrence, reminders or notifications.
- Creating or deleting whole lists. That is HA's job (a Local To-do config entry, a Google Tasks list).
- Meal plans and recipes-to-list. Mealie is a separate module.
- Any source other than HA.

## Home Assistant to-do API

The `todo` component registers three WebSocket commands and five services (**verified**, `todo/__init__.py:53-57`, `todo/services.py:197-268`). It has no REST view: nothing else is registered in `async_setup`. So, unlike Calendar, there is no fallback for an HA that lacks a command.

### History

| What | First release | How we know |
|---|---|---|
| `todo` component, `todo/item/list`, `todo/item/move`, the add/update/remove services | **2023.11.0** | Present in `todo/__init__.py` at `2023.11.0`; the component did not exist at `2023.10.0` (the file 404s) |
| `todo/item/subscribe`, `due` and `description`, the `SET_DUE_*` / `SET_DESCRIPTION` flags, `get_items`, `remove_completed_items` | **2023.12.0** | Absent at `2023.11.0`, present at `2023.12.0` |
| `completed` (the time an item was completed) on `TodoItem` | **2025.12.0** | Absent at `2025.11.0`, present at `2025.12.0` |

**verified** by fetching the file at each tag and searching it. The exact pull requests were not traced.

Hearth requires **2023.12.0** for the subscription. An older HA answers `unknown_command` (**verified**, `websocket_api/const.py:42`), and Hearth shows "Home Assistant 2023.12 or newer is needed for lists" instead of a list. It treats `completed` as optional, since HA before 2025.12.0 and integrations that never set it send none.

### `todo/item/subscribe`

Request:

```json
{"id": 42, "type": "todo/item/subscribe", "entity_id": "todo.ava_chores"}
```

`entity_id` must be in the `todo` domain (**verified**, `todo/__init__.py:73-78`).

Responses, all carrying the request's `id`:

1. `{"type":"result","success":true,"result":null}` (`:108`).
2. `{"type":"event","event":{"items":[ ... ]}}`: the current items, pushed to this subscriber only (`:110-111`).
3. Another `event` with the **whole list** each time it changes. No deltas (`:94-103`).
4. An unknown entity is `success:false` with code **`invalid_entity_id`** (`:86-92`). That is not the `not_found` that `todo/item/list` and Calendar use.

**When pushes happen.** The entity pushes from `_async_write_ha_state` (**verified**, `todo/entity.py:137-142`), so after any state write. A push is skipped when the items equal the last ones broadcast (`entity.py:122-135`), so, unlike Calendar's, an unchanged list is not re-pushed. How soon a change outside Hearth shows up depends on the integration:

| Integration | Refresh |
|---|---|
| Shopping List | At once. It writes state from its own data listener (**verified**, `shopping_list/todo.py:34`, `:92`) |
| Local To-do | At once on every change made through HA. Not polled (`local_todo/todo.py:151`) |
| Google Tasks | Every 30 minutes (**verified**, `google_tasks/coordinator.py:16`), and right after each write made through HA (`google_tasks/todo.py:130`, `:141`, `:147`, `:155`). A change made in the Google app can take 30 minutes to reach the kiosk |
| CalDAV | Every 15 minutes (**verified**, `caldav/todo.py:30`) |

**Unsubscribe** with the generic `{"type":"unsubscribe_events","subscription":42}`. The todo subscription is stored in `connection.subscriptions` (**verified**, `todo/__init__.py:105-107`), which is the map `unsubscribe_events` pops (`websocket_api/commands.py:253-263`).

### The pushed item

Each element of `items` is `serialize_todo_item(item)`: every `TodoItem` field, **including nulls** (**verified**, `todo/entity.py:45-53`). The WebSocket layer encodes it with orjson and HA's default hook, which writes `date` and `datetime` as ISO 8601 (`helpers/json.py:39-66`, `websocket_api/messages.py`). That orjson's own date output is the same as `isoformat()` is **assumed**; the `api_items_factory` path below calls `isoformat()` explicitly, and the two shapes agree in HA's own frontend, which reads both.

| Key | Type | Notes (`todo/entity.py:17-37`) |
|---|---|---|
| `uid` | string or null | The item's id. Every integration read here sets it. Hearth treats an item without one as read-only (below) |
| `summary` | string or null | The text of the item |
| `status` | `"needs_action"`, `"completed"` or null | `TodoItemStatus` (`todo/const.py:47-54`). Local To-do maps RFC 5545's `IN-PROCESS` to `needs_action` and `CANCELLED` to `completed` (`local_todo/todo.py:36-41`). Null is shown as open |
| `due` | `"2026-10-14"`, `"2026-10-14T17:00:00-05:00"`, or null | A date or a datetime. A string containing `T` is a datetime; that is how the frontend tells them apart (**verified**, `src/data/todo.ts:100-104`) |
| `description` | string or null | |
| `completed` | datetime or null | Since 2025.12.0 only; set by Local To-do (`local_todo/todo.py:186`), not by Shopping List (`shopping_list/todo.py:94-111`) |

`todo/item/list` and the `get_items` service return the same items through `api_items_factory`, which **drops null fields** and turns every value into a string (**verified**, `todo/entity.py:145-155`, `todo/__init__.py:133-143`). Hearth only reads the subscription shape. Its parser still accepts a missing key as null, so a test fixture in either shape parses.

The entity's **state** is the count of open items (**verified**, `todo/entity.py:68-75`), and its attributes include `supported_features` (`helpers/entity.py:1175-1176`). Both already arrive in Hearth's entity cache through `state_changed`. So the open count for a list Hearth is not subscribed to is free, and so are its features.

### Feature flags

`TodoListEntityFeature` (**verified**, `todo/const.py:35-44`):

| Flag | Value | Gates |
|---|---|---|
| `CREATE_TODO_ITEM` | 1 | `todo.add_item` |
| `DELETE_TODO_ITEM` | 2 | `todo.remove_item`, `todo.remove_completed_items` |
| `UPDATE_TODO_ITEM` | 4 | `todo.update_item`, so completing, uncompleting and renaming |
| `MOVE_TODO_ITEM` | 8 | `todo/item/move` |
| `SET_DUE_DATE_ON_ITEM` | 16 | the `due_date` field on add and update |
| `SET_DUE_DATETIME_ON_ITEM` | 32 | the `due_datetime` field on add and update |
| `SET_DESCRIPTION_ON_ITEM` | 64 | the `description` field on add and update |

The service-level gates are `required_features` on the registration (`todo/services.py:216`, `:243`, `:255`, `:267`). HA enforces them for an explicitly targeted entity with `ServiceNotSupported` (**verified**, `helpers/service.py:750-759`). The field-level gates are checked per call by `_validate_supported_features`, which raises `ServiceValidationError` (`update_field_not_supported`) when a field is present at all, even as null (`todo/services.py:86-98`). `get_items` has no gate (`:257-262`).

What each integration supports (**verified**, the `_attr_supported_features` of each):

| Integration | Add | Delete | Update | Move | Due date | Due time | Description |
|---|---|---|---|---|---|---|---|
| Shopping List (`shopping_list/todo.py:35-40`) | ✓ | ✓ | ✓ | ✓ | – | – | – |
| Local To-do (`local_todo/todo.py:142-150`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Google Tasks (`google_tasks/todo.py:95-102`) | ✓ | ✓ | ✓ | ✓ | ✓ | – | ✓ |
| CalDAV (`caldav/todo.py:109-116`) | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ |

Other integrations (Todoist, Mealie, Bring!, Grocy …) were not read. Hearth reads the flags from the entity rather than knowing integrations, so they work without a code change, and each still needs checking on hardware (**assumed**).

### Services

Each is a `call_service` with `"domain":"todo"` and `"target":{"entity_id":"todo.x"}`.

| Service | Fields | Notes (`todo/services.py`) |
|---|---|---|
| `add_item` | `item` (required), `due_date` or `due_datetime`, `description` | `item` is stripped and must be non-empty (`:207-209`). At most one of the two due fields (`:75`). Created as `needs_action` (`:111-124`). No uid is returned; the new item arrives in the next push |
| `update_item` | `item` (required, the uid), at least one of `rename`, `status`, `due_date`, `due_datetime`, `description` (`:236-240`) | A partial update: fields not sent keep their value, and a field sent as `null` is cleared (`:140-155`). `rename` is stripped, non-empty (`:226-228`) |
| `remove_item` | `item`: one uid or a list of them (`:249-251`) | Every one must be found, or nothing is removed (`:158-170`) |
| `remove_completed_items` | none | Deletes every `completed` item that has a uid (`:186-194`). Gated by `DELETE_TODO_ITEM` |
| `get_items` | `status` (optional list) | Response only (`SupportsResponse.ONLY`, `:261`); with no `status`, every item (`:173-183`). `services.yaml` shows a `needs_action` default, which is only the UI's default. Hearth does not use it: the subscription carries everything |

**How an item is addressed.** `update_item` and `remove_item` take `item`, which matches the first item whose **uid or summary** equals it (**verified**, `todo/services.py:101-108`). Hearth always sends the uid. A summary match could only win if an item listed earlier had a summary equal to the uid, which a random id makes implausible. An item with no uid cannot be removed (`:163`), and Hearth shows it without actions.

**Due values sent.** `due_date` is a `YYYY-MM-DD` string. `due_datetime` is a datetime string, converted to HA's local zone on the way in (`:57`, `dt_util.as_local`). Hearth sends it with an offset so it means the instant the user picked.

**Errors.** `call_service` answers `success:false` with `error.code` (**verified**, `websocket_api/commands.py:276-340`, codes at `websocket_api/const.py:35-46`):

- `service_validation_error`: item not found, a field the list does not support, and `ServiceNotSupported`, which is a subclass (`exceptions.py:430`). The message is in `error.message`, with `translation_key` beside it.
- `invalid_format`: the schema rejected the data (an empty name, both due fields).
- `home_assistant_error`: the integration failed, e.g. Google rejected the write.

### `todo/item/move`

```json
{"id": 43, "type": "todo/item/move", "entity_id": "todo.groceries",
 "uid": "abc", "previous_uid": "xyz"}
```

Moves `uid` to just after `previous_uid`; with no `previous_uid` it moves to the top (**verified**, `todo/__init__.py:147-153`, `todo/entity.py:94-103`). Gated by `MOVE_TODO_ITEM`: without it the answer is `not_supported` (`todo/__init__.py:164-175`). An unknown entity is `not_found`, and an integration error is `failed` with the message (`:160-162`, `:180-181`). Local To-do raises when either uid is not in the list (`local_todo/todo.py:222-245`). Success is `result: null`.

### Recurrence

`TodoItem` has no recurrence field (**verified**, `todo/entity.py:17-37`), and no service or command takes one. HA's to-do model cannot express a repeating chore, so "recurrence is whatever backs the list" means something outside the to-do API:

- An HA automation that re-adds chores or sets them back to `needs_action` each morning, using `get_items` and `update_item`. This needs no Hearth code. The hardware pass ran one ([the recipe](#repeating-chores-an-automation-recipe)), which adds the day's chores with `add_item`.
- An integration that repeats tasks on its own side. Whether Google Tasks' repeating tasks survive a completion made through HA was not checked; Google's API is not part of HA's source (**assumed** unknown).

Hearth shows what the list holds and nothing more. The hardware pass tries one automation recipe so the docs can point at it.

## Can it all go over the existing WebSocket?

Yes. `HomeAssistantService` (`lib/services/home_assistant_service.dart`) already has the pieces, with one gap.

- **Subscription:** `subscribe(message, onEvent:, onError:)` (`:393-415`) routes `event` messages by id (`:181-189`), replays every subscription with a new id on each `auth_ok` (`:166-174`), passes a failed `result`'s `error` to `onError` (`:212-223`), and unsubscribes with `unsubscribe_events`, which works for the todo subscription (above). Calendar's `HaCalendarSource` uses it the same way. **No change needed.**
- **Writes:** there is a gap. `callService` (`:282-300`) sends and never reads the result. `sendCommand` (`:343-362`) and `callServiceWithResponse` complete with `null` both on failure and on a successful `result: null` (`:225-243`). Every todo write and `todo/item/move` succeed with no payload, so with these methods a failure looks the same as a success. Add one method:

  ```dart
  /// Sends [message] and returns HA's `result`: success or the error.
  /// A dropped connection or a 10 s timeout is an error, never a success.
  Future<HaReply> request(Map<String, dynamic> message);

  class HaReply {
    final bool success;
    final dynamic result;      // result on success
    final String? errorCode;   // error.code, or 'not_connected' / 'timeout'
    final String? errorMessage;
  }
  ```

  It shares `_pendingResponses`, but its completer receives the whole `result` message instead of the unwrapped payload. The existing methods stay as they are. `return_response` is never needed, since Hearth does not call `get_items`.

## Data model

`lib/modules/lists/models.dart`:

```dart
enum TodoStatus { needsAction, completed }

/// A due date, or a due instant when [hasTime].
class TodoDue {
  final DateTime value;   // !hasTime: local midnight of the date; hasTime: UTC instant
  final bool hasTime;
}

class TodoItem {
  final String? uid;          // null: shown, but no action is offered
  final String summary;       // '' when null
  final TodoStatus status;    // null from HA reads as needsAction
  final TodoDue? due;
  final String? description;
  final DateTime? completed;  // HA 2025.12+, and only some integrations
}

/// Bit flags from the entity's `supported_features` attribute.
class TodoFeatures {
  final int bits;
  bool get canAdd, canDelete, canUpdate, canMove,
      canSetDueDate, canSetDueTime, canSetDescription;
}
```

- A date-only due is a calendar date and never moves with a zone, as Calendar does with all-day events. A due time is an instant, shown in the device zone.
- Items keep HA's order, which is the order a reorder changes. Hearth does not sort.
- Identity for keys and the pending state below is `uid`.

## Configuration

New `HubConfig` fields, persisted like every other (`copyWith`, `toJson`, `fromJson` with defaults):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `todoLists` | `List<TodoListConfig>` | `[]` | The lists, in display order |
| `todoChoreGlance` | `bool` | `false` | Show today's open chores on the idle Home screen |

```dart
class TodoListConfig {
  final String entityId;   // 'todo.groceries'; the id, unique in the list
  final String name;       // defaults to the entity's friendly_name
  final int color;         // ARGB, from the same eight-colour palette as Calendar
  final String personId;   // '' for a plain list; a Person id makes it that person's chores
}
```

A list mapped to a person is a **chore list**. Two lists may name the same person; the chart shows them as one column.

**Superseded 2026-10-15.** This spec first stored the person as free text and chose not to link HA `person.*`, since the chart only needed a name and a colour. That decision is reversed. People are now a first-class registry (`HubConfig.people`), shared with Calendar. A list stores a `personId`, and the column takes its name and colour from the `Person`. A person may be linked to a `person.*` entity, which adds an avatar and presence to the column header. Free-text `person` values are migrated on load. See [`2026-10-15-people-design.md`](2026-10-15-people-design.md).

Items are not cached to disk. A kiosk that boots offline shows each list's "can't reach" note, as Calendar does.

## Data layer

`lib/modules/lists/`, all *self-initializing providers* (CLAUDE.md). No init call in `main.dart`.

```
todoListProvider          StreamProvider.autoDispose.family<TodoListState, String>(entityId)
   │  builds nothing unless entityId is in config.todoLists
   │  HaTodoList: subscribe todo/item/subscribe, parse each push
   │
todoFeaturesProvider      Provider.family<TodoFeatures, String>(entityId)
   │  supported_features from the HA entity cache; 0 until it arrives
   │
todoActionsProvider       Provider<TodoActions>
   │  add / update / remove / clearCompleted / move, each Future<String?>
   │  (null on success, HA's message on failure), through HomeAssistantService.request
   │
choresTodayProvider       Provider.autoDispose<List<ChoreLine>>
      watches every chore list; the glance rule below; recomputed at local midnight
      and when a timed chore falls due
```

`TodoListState` is `{List<TodoItem> items, ListStatus status, String? error}`, with `ListStatus` one of `loading`, `ok`, `stale`, `error`. As in Calendar, a lost connection keeps the items and marks them `stale`. `invalid_entity_id` is an `error` ("List not found in Home Assistant") that waits for a config change. `unknown_command` is an `error` naming HA 2023.12.

**autoDispose, on purpose.** Calendar's hardware pass found that a non-autoDispose family kept a disabled source subscribed until restart (`d8ceb00`). Here a list stays subscribed only while a view or the glance watches it, and a list removed from config builds nothing. With the glance on, chore lists are always watched, because Home is always built. `choresTodayProvider` is autoDispose for the same reason: a plain `Provider` read once would keep every chore list subscribed for good.

**Writes and what the user sees.** A write changes nothing locally. The push that follows it is the new truth. To keep a check tap feeling immediate, the screen holds a small **pending map** (uid → the status or text it sent). A row in it draws the new value with a faint spinner. An error reply reverts the entry and shows HA's message in a snackbar. A success reply clears it at the next push, or at once if a push came in while it waited or the last push already shows the change. HA sends the push before the reply, and that push carries fields the overlay lacks (`completed`), so waiting for the *next* one would leave the row spinning. `call_service` is blocking (**verified**, `websocket_api/commands.py:288`), so the reply comes only after the integration has written: on Google Tasks that includes HA's refresh from Google (`google_tasks/todo.py:130`). `request()`'s 10 s timeout is the only timer, and a timeout reverts like an error ("Couldn't confirm the change"). The write may still have landed, and the next push shows it if it did.

**What a write sends.** Only fields that changed, and only fields the list supports. A field the list lacks is an error even as `null` (`todo/services.py:86-98`), so the edit sheet never sends it. To clear a due date it sends the field the list supports (`due_date` if it can, else `due_datetime`) as `null`.

## The module

`lib/modules/lists/lists_module.dart`: id `lists`, name `Lists`, icon `Icons.checklist`, `defaultOrder` **7**, between Calendar (5) and Controls (10). `isConfigured` is `todoLists.isNotEmpty`. It goes into `_staticModules`; not into `defaultModulePlacements`, like Calendar. CLAUDE.md's screen-order line gets it in the screen task.

The screen has two views, chosen by a segmented control in its header: **Lists** and **Chores**. Chores appears only when at least one list has a person. The chosen view is `listsViewProvider`, outside the screen, so the glance can open the screen on Chores by setting it to `ListsView.chores` before jumping to the page. The header starts `x20` from the left, clear of HubShell's mic toggle, the fix Calendar needed (`28392b9`).

Horizontal swipes belong to HubShell's PageView, so nothing in the module uses one: no swipe-to-delete, no horizontal paging between lists or people. Reordering uses a drag handle and is vertical.

### Lists view

```
1184x864
┌───────────────┬──────────────────────────────────────────────┐
│ Lists   Chores│  Groceries                        Clear done │
├───────────────┼──────────────────────────────────────────────┤
│ ● Groceries  7│  [ Add an item…                          + ] │
│ ● Hardware   2│  ☐ Milk                                   ≡  │
│ ● Ava        3│  ☐ Eggs · due Fri                         ≡  │
│ ● Ben        1│  ☐ Bread                                  ≡  │
│               │  ▸ Completed (4)                             │
└───────────────┴──────────────────────────────────────────────┘
```

- **Left rail:** each list's colour, name and open count, taken from the entity's state, so it costs no subscription. Selecting one subscribes to it.
- **Add field** at the top, shown when `canAdd`. Submitting adds the item and keeps the field focused for the next one, the way a shopping list is typed in.
- **Rows:** a checkbox when `canUpdate` (otherwise none; HA's card disables it instead, `hui-todo-list-card.ts:650-655`), the summary, a second line for the due date and the first line of the description, and a drag handle `≡` on open items when `canMove`. A due date that has passed is drawn in the error colour, a due date of today in the accent.
- **Tap a row** to open the edit sheet. **Long-press does nothing**, so a slow tap on a kiosk never starts an unexpected drag.
- **Completed** items sit collapsed under "Completed (n)". "Clear done" (`remove_completed_items`) shows when `canDelete` and there is a completed item, and asks first.
- **Reorder:** `ReorderableListView` with `buildDefaultDragHandles: false` and a `ReorderableDragStartListener` on the handle, sending `todo/item/move` with the uid and the uid of the open item now above it (none at the top). Only open items move, as in HA's card (`hui-todo-list-card.ts:634-635`).

**Edit sheet**, a dialog that respects `viewInsets`: name (`rename`), description when `canSetDescription`, due date when `canSetDueDate`, with a time when `canSetDueTime`, and Delete when `canDelete`. A field the list does not support is absent, not disabled. Save sends only what changed.

### Chore chart view

```
1184x864
┌──────────────────────────────────────────────────────────────┐
│ Lists [Chores]                                     Wed Oct 14 │
├───────────────────┬───────────────────┬──────────────────────┤
│ ● Ava        2/5  │ ● Ben        1/3  │ ● Mom & Dad    0/2   │
│ ☐ Feed cat  late  │ ☐ Trash out       │ ☐ Pay bills          │
│ ☐ Make bed        │ ☐ Homework        │ ☐ Water plants       │
│ ☐ Read 20 min     │ ☑ Dishes          │                      │
│ ☑ Teeth           │                   │                      │
│ ☑ Pack bag        │ ▸ Upcoming (2)    │                      │
└───────────────────┴───────────────────┴──────────────────────┘
```

- One column per person, merging that person's chore lists, in config order of each person's first list. The header is the person's name and colour from the People registry; a person linked to HA `person.*` shows their avatar and a presence dot instead of the colour dot (2026-10-15).
- **Each column shows:** open items due today or overdue (overdue first, marked "late"), then open items with no due date, then items completed today (when HA gives `completed`), struck through. Open items due later sit under "Upcoming (n)", collapsed. Completed items without a `completed` time are not shown here; the Lists view has them.
- The header count is done-today over done-today plus open-shown.
- **The whole row is the tap target** for complete and uncomplete, big enough for a child's finger. Editing is the Lists view's job. A list without `canUpdate` shows its chores without checkboxes.
- No add field, no reorder. The chart is for doing chores, not for managing them.
- Completing a chore draws it under done today at once, stamped with the local time; HA's push replaces the stamp. On an integration that gives no `completed`, the chore leaves the chart when that push lands.

### Portrait and narrow widths

Every view branches on `LayoutBuilder` constraints, never on `displayOrientation`, and holds at 1184x864, 864x1184 and 800x1280.

- **Lists:** below about 900 px of width the rail becomes a dropdown of lists in the header, and the list takes the full width.
- **Chores:** columns = `clamp(width ~/ 260, 1, people)`. When people outnumber columns, the extra columns wrap into another row and the page scrolls vertically. At 864 that is three across, at 800 three, at 1184 four.
- The edit sheet is full width below 600 px.

```
864x1184, Chores, 4 people
┌──────────────────────────────┐
│ Lists [Chores]    Wed Oct 14 │
├─────────┬─────────┬──────────┤
│ ● Ava   │ ● Ben   │ ● Cy     │
│ ☐ …     │ ☐ …     │ ☐ …      │
├─────────┴─────────┴──────────┤
│ ● Mom & Dad                  │
│ ☐ …                          │
└──────────────────────────────┘
```

The thresholds are logical pixels after `uiScale`, a starting point for the screen task to tune on the panel.

## On-screen keyboard

`hearth_osk` is a `TextInputControl` installed for the whole app (`lib/packages/hearth_osk/src/osk_control.dart:16`). Any `TextField` brings it up with no extra code. While it shows, `HearthOskScope` adds its height to `MediaQuery.viewInsets.bottom` (`osk_scope.dart:57-67`). So:

- The Lists view needs no padding of its own. The root `Scaffold` (`lib/app/app.dart`) resizes its body above the keyboard and gives it `viewInsets` of zero, so HubShell and every page already end at the keyboard's top. The add field sits at the top of the list and stays in view. (This said earlier to pad by `viewInsets.bottom`; under that `Scaffold` the value is zero.)
- The add field and the name field use `TextInputAction.done` and `onSubmitted`; the OSK's Enter submits a single-line field. The description field is `TextInputType.multiline`, where Enter inserts a newline (`osk_control.dart:236-242`).
- The edit sheet is a dialog, which already respects `viewInsets`.
- `test/portrait/osk_portrait_test.dart` gets a case with the add field focused at all three sizes.

## The settings plugin

`lib/plugins/lists/lists_plugin.dart`, id `hearth.lists`, category `feature`, in `_firstPartyPlugins`, always visible. Device panel and `:8090` fragment from one definition, as every plugin.

- **Lists:** a `ListSection<TodoListConfig>`. Each row shows the colour, name, person (or "List"), live status, and what the list supports ("add · edit · reorder · due dates"), from its features.
  - *Add*: the entity picker filtered to `todo.*` (`lib/plugins/framework/fields/ha_entity_picker_field.dart`), then name (prefilled from `friendly_name`), colour, and person (none by default).
  - *Edit*: name, colour, person. To change the entity, delete and add again.
  - The person is a dropdown of the People registry since 2026-10-15, on both surfaces; it was free text before.
- **Show today's chores when idle:** the `todoChoreGlance` toggle, off by default.

The live status is read from the entity HA already caches, not from an item subscription, so the panel opens no `todo/item/subscribe` per list: a `todo.*` entity's state is its count of incomplete items (`TodoListEntity.state` in `homeassistant/components/todo/entity.py`), shown as "3 open" or "All done", with "Not found in Home Assistant" and "Unavailable" for a missing entity and an `unknown`/`unavailable` state.

The `ListSection` HTML render is read-only (`lib/plugins/framework/list_section.dart`), so the portal needs routes, as Calendar's do: `GET /api/plugin/hearth.lists/lists` (with status and features), `POST …/lists`, `PUT …/lists/<entity_id>`, `DELETE …/lists/<entity_id>`. A second add of the same entity answers 409. Each handler validates its own input.

## The idle glance

`ChoreGlance` (`lib/modules/lists/chore_glance.dart`), a `ConsumerWidget` in `HomeScreen`'s bottom column, just above `CalendarGlance`. It shows only when `todoChoreGlance` is on and a chore list exists:

```
  ● Ava   Feed the cat · late
  ● Ben   Trash out
  ● Ava   Make bed  +3 more
```

- At most three lines, then "+n more". Draws nothing when nothing is open for today.
- The person's colour as the dot, or their avatar when linked to HA, with the same text shadows as the clock.
- A tap jumps to the Lists page on the Chores view when the module is in the swipe row, and does nothing otherwise. HubShell sets `listsViewProvider` to `ListsView.chores`, then moves to the page.
- It watches `choresTodayProvider` through `select`, so a push that changes nothing for today does not rebuild it.

### What counts as today

An open item (`status` not `completed`) of a chore list is **today's** when:

- **due is a date:** that date is today or earlier, in the device's local calendar. It is **late** when the date is before today.
- **due is a datetime:** the instant is before the start of tomorrow, local time. It is **late** when the instant has passed.
- **no due:** not in the glance. It does appear in the chart, which shows undated chores every day.

This matches HA's own card, which reads a date-only due as the **end** of that day and a datetime as its instant, and calls a date-only item "today" when it falls on the current day (**verified**, `hui-todo-list-card.ts:613-618`, `:636-638`). Undated items are left out of the glance because a list with no dates at all would otherwise fill the idle screen with every chore, every day.

**One source of skew.** Local To-do stores the RFC 5545 exclusive `DUE` and hands HA the day before it, so `due` reads as the day the user picked (**verified**, `local_todo/todo.py:47-63`, `:170-176`). CalDAV passes the server's date through unchanged (`caldav/todo.py:87-92`). A CalDAV client that writes an exclusive date would then show a day late (**assumed**; depends on the client, not tested). Hearth uses HA's value as given.

The provider recomputes at local midnight, as Calendar's window moves, so yesterday's chores turn "late" without a push. It also recomputes at the next timed chore's instant, so a chore due at 17:00 turns late at 17:00 rather than at the next push or midnight.

## Test plan

Fixtures in `test/fixtures/lists/`, captured from a real HA where possible.

**Data layer** (`test/modules/lists/ha_todo_list_test.dart`, with the existing `FakeWebSocketChannel`):

- Subscribe sends `todo/item/subscribe`; `result` then `event` fills the items, nulls included; a second `event` replaces.
- Parse: date due, datetime due with offset, no due, `completed` present and absent, `status: null`, an item without `uid`, and the `get_items` shape (nulls omitted, strings) parsing to the same items.
- `invalid_entity_id` → `error`, no retry; `unknown_command` → the 2023.12 message.
- Socket drop: `stale`, then a new subscribe after `auth_ok`.
- `HomeAssistantService.request`: success with `result: null` is a success; `success:false` carries code and message; a dropped socket and the timeout are errors.
- `TodoActions`: each service's exact payload; uid as `item`; only changed fields; a clear sends the supported field as `null`; an unsupported field is never sent.
- `todo/item/move`: `previous_uid` omitted at the top; `not_supported` reported.
- The today rule: date today, date yesterday (late), datetime later today, datetime an hour ago (late), datetime tomorrow 00:30 (not today), no due; across a midnight tick.

**Layouts** (`test/portrait/module_lists_portrait_test.dart`): `testLayouts` pumps the Lists view (long names, a full list, a list with no features) and the Chores view with one, three and five people at 1184x864, 864x1184 and 800x1280, and asserts no overflow. The glance gets a case in `screens_portrait_test.dart`, the add field in `osk_portrait_test.dart`.

**Hardware pass:** on the Pi and the tablet, against a real HA with a Shopping List, a Local To-do with dates, and a Google Tasks list:

- Every action on each list, and the actions a list lacks are absent.
- A change made in HA's own UI shows on the kiosk: at once for Shopping List and Local To-do, within 30 minutes for Google Tasks.
- A change made on the kiosk shows in HA's UI.
- Reorder, then compare the order with HA's card.
- Chores and glance at midnight: yesterday's open chore turns late.
- Resubscribe after the socket drops.
- Typing with the OSK in both orientations.
- One automation recipe for repeating chores, recorded here.

## Hardware pass

**Date:** 2026-10-15
**Commit tested:** `60e3b17` (this branch: `main` at `433774d` plus the two commits below). The Pi ran `433774d` for the first half of the pass and `60e3b17` from the late-tag check on; the tablet ran `60e3b17` throughout

**verified** here means observed in this pass, with the evidence named in the row; **not run** gives the reason; **not settled** means looked at without a conclusion. Screenshots were taken for every view, through the capture plugin on the Pi and `adb exec-out screencap` on the tablet; the Home ones show household photos, so they are described here rather than committed.

### Setup

| | |
|---|---|
| Pi | `hearthDev`, Raspberry Pi 5, kernel 6.12.47, flutter-pi through `/usr/local/bin/hearth-launch`. Canvas captures at 1920x1200 |
| Pi bundle | Built on the development host the way `build-pi-image.yml` does it (`prepare-pi-build.sh`, `flutterpi_tool` at the pinned commit, `--release --arch=arm64 --cpu=pi4`), with host Flutter 3.47.6, not the 3.47.7 pin. Two builds: `433774d` (bundle sha256 `1a594505…`) and `60e3b17` (`ebaae220…`) |
| Tablet APK | `flutter build apk --debug --build-name 1.20.0 --build-number 1020000` at `60e3b17`, sha256 `b6af964c…`, installed over adb keeping its data. Apolosign 21.5", Android 16, 1080x1920 panel |
| Home Assistant | The house instance, 2026.10.1. It had **no** `todo.*` entity before the pass. Three were created for it, with the human's go-ahead, through the config-flow API: Local To-do `Hearth test` (`todo.hearth_test`, features 127) and `Hearth test 2` (`todo.hearth_test_2`, 127), and the Shopping List integration (`todo.shopping_list`, 15: add, delete, update, move) |
| Lists on the kiosk | Added through `POST /api/plugin/hearth.lists/lists`: `todo.hearth_test` (person "Test parent" from midway), `todo.shopping_list`, `todo.hearth_test_2` (person "Test kid"), and `todo.nope`, which does not exist. The module was enabled and placed, and the glance switched on, through `POST /api/config` |
| Changes from HA's side | Made over HA's WebSocket API from the development host (`call_service` for `todo.add_item` / `update_item` / `remove_item`, and `todo/item/move`), the same calls HA's to-do card makes. HA's own UI was not clicked; see the human's checks |
| Input | Pi: touches written into the touchscreen's evdev node as root, as in the Calendar pass. Tablet: `adb shell input tap` / `swipe` |

### Pi results

| Check | Result | Evidence |
|---|---|---|
| Real pushes match the fixtures | **verified** after a fix | Pushes and `get_items` captured from the three lists matched the hand-written shapes field for field, with two details the fixture lacked: Local To-do sends `completed` in UTC with microseconds (`2026-10-15T13:25:22.747356+00:00`), and Shopping List keeps `"completed": null` on a completed item. Both added to `test/fixtures/lists/todo_items.json` in `f97f1b1` |
| Routes | **verified** | `POST` answered with name, colour, person, status (`3 open`, `All done`) and features (`add · edit · reorder · due dates` for Local To-do, `add · edit · reorder` for Shopping List). A second add: 409 `todo.hearth_test is already added`; `light.kitchen`: 400 `Pick a todo.* entity`; `PUT` with another `entityId`: 400; `name: ""`: 400; an unknown list: 404; `DELETE` removed `todo.nope` |
| A missing entity | **verified** | `todo.nope` was accepted with status `Not found in Home Assistant`; selecting it shows `List not found in Home Assistant` under the header and an empty body. One `[W/Lists] todo.nope: subscribe failed: invalid_entity_id`, no retry |
| Lists view | **verified** | Rail with colour, name and open count; add field; rows with due line (`due tomorrow · A dozen`, an overdue `due yesterday 5:00 PM` in red); drag handles; `Completed (n)` folded; `Clear done` |
| Add (Local To-do) | **verified** | Typed `tea` on the OSK in the add field and pressed Enter: HA's list gained `tea`, the field kept focus for the next item |
| Edit: description, date, time, clear, rename | **verified** | Description `2l` typed on the OSK and saved: HA `description: "2l"`. The ✕ cleared a due: HA `due: null`. Date picker to Oct 20 then time picker to 6 PM: HA `due: 2026-10-20T18:00:00-05:00`, row `due Tuesday, Oct 20 6:00 PM`. Name `Milk` → `Milks`: HA `summary: "Milks"` |
| Delete | **verified** | Delete in the sheet removed `Eggs` from HA at once (no confirmation, as specified) |
| Complete, uncomplete, Clear done | **verified** | Checkbox: HA `completed`; reopening `Jam` under the expanded Completed: HA `needs_action`. Clear done asked `Removes 3 completed items from Hearth test in Home Assistant.`; after Clear, HA held only the three open items |
| Absent actions | **verified** | Shopping List's sheet has only Name and Delete, no description, date or time, matching features 15 |
| Reorder on the kiosk | **verified** | Dragging `tea`'s handle to the top: HA's order became `tea, Milk, Eggs, Pay bills` (`get_items` and the subscription, which are the order HA's card draws). Same on Shopping List: `Butter` above `Bread` |
| Reorder from HA | **verified** | `todo/item/move` of `tea` after `Pay bills`: the kiosk redrew it last within a second |
| A change from HA shows on the kiosk | **verified** | Reopening `Make bed` from HA at 08:29:16.8: a capture finished at 08:29:17 already showed it open. Adds and completions from HA likewise, Local To-do and Shopping List both |
| A change on the kiosk shows in HA | **verified** | Completing `Make bed` on the chart: HA's next push had `status: completed` within 1.5 s; every edit above was read back from HA the same way |
| Chores view | **verified** | One person, then two side by side in config order, each with its count (`0/2`, `1/6`): late first (`Feed cat` due yesterday), then today's, then undated (`Practice piano`), then done today struck through, `Upcoming (1)` folded (`Homework`, due tomorrow) |
| Glance on idle Home | **verified** (landscape and portrait) | `Test kid Feed cat · late`, `Test kid Make bed`, `Test kid Trash out`; undated and tomorrow's chores left out; with five lines due, three and `+2 more`, late first across both people |
| Glance tap lands on Chores | **verified** (landscape and portrait) | Tapping the glance opened the Lists page on Chores |
| A timed chore turns late | **verified** | Midnight was not waited for; timed chores due a few minutes ahead exercise the same recompute. Glance: `Water plants` due 08:37 read `· late` and moved up in a capture at 08:37:02, with no push. Chores screen: `Trash out` due 08:33 was not yet late at 08:33:08 and was late, moved above `Make bed`, at 08:34:02; the screen re-reads the clock once a minute, so it can lag the glance by up to a minute. The date rollover at midnight is the same timer path and is covered by `choresTodayProvider`'s midnight test |
| Resubscribe after the socket drops | **verified** | Hearth's sockets to HA were shut down from outside the process, as in the Calendar pass: `[I/HA] WebSocket closed` 08:37:46, `Reconnected` 08:37:47. Completing `Feed cat` from HA at 08:37:57 removed it from the glance by 08:37:58 |
| HA restart | **not run** | Replaced by the socket drop, as for Calendar |
| OSK, landscape | **verified** | The add field, the description and the name field: the keyboard comes up, the sheet lifts above it, typed text reaches HA |
| OSK, portrait | **verified** | After `displayOrientation: portrait` and the Display plugin's restart (`inEffect`, 90°): typed `jam` in the add field (reached HA); the edit sheet lifts above the keyboard with the description focused |
| Portrait layouts | **verified** | Lists swaps the rail for a dropdown in the header; Chores keeps two columns at half width |
| Late tag position | **verified** after a fix | On `433774d` the chart's `late` sat 8 px from the column edge while the count above sat 16 px in. Fixed in `60e3b17`, re-checked on the Pi and the tablet: the two line up |
| Settings panel on the device | **verified** | Three rows with colour, person or `List`, `4 open`/`3 open`/`6 open` and the features line; edit and delete buttons; Add; `Show today's chores when idle` on |
| Portal parity | **verified** | The Pi's portal opened in Chrome on the tablet (PIN from the Network panel): the same three rows, colours, person/kind, counts and features, Edit/Delete, `+ Add list`, the glance checkbox. Edit there changed Shopping list's colour to green; `GET …/lists` returned `#81c784` |
| Repeating chores recipe | **verified** | The actions of the recipe below, run once through HA's `execute_script` against `todo.hearth_test_2` (nothing installed): `Recipe: make bed` due `2026-10-15` and `Recipe: trash out` due `2026-10-15T19:00:00-05:00` appeared on the chart as `due today` and `due today 7:00 PM`; `remove_completed_items` cleared the two done chores |
| Logs | **verified** | No `[E/` line from lists code, `NRestarts=0` across the pass |
| Google Tasks, the 30-minute poll | **not run** | No Google Tasks list was set up for the pass |
| A list without `update` or `move` | **not run** | Neither integration used lacks them; the absent checkbox and handle are covered by widget tests |
| An item without a uid | **not run** | No integration here sends one |

### Tablet results

| Check | Result | Evidence |
|---|---|---|
| Cold start | **verified** | After the install, `Local API server listening on port 8090`, no `FATAL EXCEPTION` or `E/flutter` in logcat |
| Glance, portrait and landscape | **verified** | Three chore lines above the calendar glance; tap opened Chores |
| Chores, both orientations | **verified** | Two columns, late tags lined up with the count |
| Cross-device | **verified** | `Make bed` completed on the tablet: HA `completed`, and the Pi's chart read `2/6` with it struck through, within 1.5 s |
| OSK, landscape and portrait | **verified** | `tea` typed on Hearth's keyboard in the add field reached HA; the edit sheet lifts above the keyboard in portrait |
| Drag reorder | **verified** (by `adb` swipe) | `tea` dragged from last to first: HA's order `tea, Milks, Pay bills, …`. How it feels under a finger is the human's call, below |

### Tablet and eyes-on checks (the human)

The human took this checklist on the tablet and the Pi panel, with the three test lists configured: on the tablet's Chores view, tap a chore row to tick it and again to undo, and judge whether it feels immediate and the pending state looks right; drag an item by its handle with a finger in Lists → Hearth test, then compare the order with HA's to-do panel; add or tick an item in HA's own To-do UI and watch the kiosk; type with the keyboard in both orientations; judge the idle glance's legibility over photos on the Pi and the tablet. Their answer: "All looks good". No item was reported individually, so each is recorded as passed on their word, not observed here.

### Repeating chores: an automation recipe

HA's to-do model has no recurrence, so a repeating chore is an automation that adds it again. This one adds the day's chores just after midnight and clears yesterday's finished ones; HA 2024.10 or newer for this syntax. Replace `todo.ava_chores` with the person's list:

```yaml
alias: Ava's chores
triggers:
  - trigger: time
    at: "00:05:00"
actions:
  - action: todo.remove_completed_items
    target:
      entity_id: todo.ava_chores
  - action: todo.add_item
    target:
      entity_id: todo.ava_chores
    data:
      item: Make bed
      due_date: "{{ now().date() }}"
  - if:
      - condition: time
        weekday: [thu]
    then:
      - action: todo.add_item
        target:
          entity_id: todo.ava_chores
        data:
          item: Trash out
          due_datetime: "{{ today_at('19:00') }}"
```

An open chore from yesterday stays and shows as late next to today's copy. To replace it instead, remove it first (`todo.remove_item` with its name) before adding. Lists without due dates (Shopping List) take the `item` alone, and then the chore shows on the chart every day rather than in the glance.

### Findings

Fixed on this branch, each with a test that fails without the fix:

- `f97f1b1` — the fixture lacked two shapes real HA sends: microsecond UTC `completed` and a completed item with `completed: null`. Both parse correctly; the fixture and its test now carry them.
- `60e3b17` — the chart's `late` tag sat against the column edge. It now has the row's right inset and lines up with the count.

Not changed:

- The Chores screen re-reads the clock once a minute, so a timed chore turns late there up to a minute after the glance shows it. Left as it is.
- HubShell's mic toggle sits over the `FEATURES` heading of the Settings sidebar (seen, not Lists code).

### Device state

**Home Assistant:** the three test lists were emptied, then their config entries deleted through the config-entries API, with the human's go-ahead. HA has no `todo.*` entity again, as before the pass. Removing Shopping List answered `require_restart: true`; the house HA was not restarted. Its now-empty `.shopping_list.json` stays in HA's config directory. No household list existed, and none was read or written.

**Pi:** `hub_config.json` restored from the pre-pass copy (sha256 `643e8b6d…`, byte-identical when copied back, and unchanged after the next start). Lists is not enabled, orientation is `auto`, `captureToolsEnabled` and `micMuted` are `true` as found. `/opt/hearth/bundle` is the pass's build of `60e3b17`; the bundle it replaced is `/opt/hearth/bundle.pre-lists-test`. `/etc/hearth-version` still says 1.20.0, so the updater will install the next release over it. The backup, the bundles and the helper scripts are in `~/hearth-lists-test`.

**Tablet:** left on the debug APK of `60e3b17`, with `hub_config.json` restored from the pre-pass copy (sha256 `10757be0…`, byte-identical).

## Child tasks

In order. Each is one pull request.

1. **Data layer.** `HomeAssistantService.request`; `lib/modules/lists/models.dart`; `HubConfig.todoLists` and `todoChoreGlance`; `HaTodoList`, `todoListProvider`, `todoFeaturesProvider`, `todoActionsProvider`, `choresTodayProvider`. Unit tests and fixtures. No UI.
2. **Screen.** `ListsModule`, the Lists view (rail, add field, rows, edit sheet, reorder, clear done, pending state), registry entry, portrait and OSK tests, CLAUDE.md screen-order line. Touches `lib/modules/lists/`, `lib/modules/module_registry.dart`, `test/portrait/`, `CLAUDE.md`.
3. **Settings plugin.** `hearth.lists`: list section on device and portal, the routes, person mapping, the glance toggle. Touches `lib/plugins/lists/`, `lib/plugins/plugin_registry.dart`.
4. **Chore chart.** The Chores view and its layout rules, on top of 2. Touches `lib/modules/lists/` and its portrait test.
5. **Glance.** `ChoreGlance` on `HomeScreen`, its portrait case. Touches `lib/modules/lists/`, `lib/screens/home/home_screen.dart`, `test/portrait/screens_portrait_test.dart`.
6. **Hardware pass.** On the Pi and the tablet, recorded in this document, plus a wiki page.

Tasks 2 and 3 can run in parallel after 1; 4 needs 2; 5 needs 1 and the person mapping from 3.

## Decisions

- **Subscription only, no fallback.** HA has no REST route for items, and the subscription has been there since 2023.12.0. Older HA gets a clear message.
- **Features from the entity, never from the integration name.** Every action is shown only when the entity's flags allow it, so a new integration works without code.
- **Uid, always.** HA would accept a summary; Hearth never sends one.
- **The push is the truth.** A pending overlay makes taps feel immediate, with no local copy that can drift.
- ~~**A person is a name on a list.** No `person.*` link, no Hearth chore state.~~ Reversed 2026-10-15: people are a registry, optionally linked to `person.*` ([People design](2026-10-15-people-design.md)). Still no Hearth chore state.
- **Undated chores stay off the glance** and appear on the chart every day.
