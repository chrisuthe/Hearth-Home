# Chores and Lists — Design

**Date:** 2026-10-14
**Status:** Design. Child task 1 (data layer) built.
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

- An HA automation that re-adds chores or sets them back to `needs_action` each morning, using `get_items` and `update_item`. This needs no Hearth code (**assumed** workable; not built).
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
  final String person;     // '' for a plain list; a name makes it that person's chores
}
```

A list mapped to a person is a **chore list**. That is the whole mapping. The person is a display name, not an HA `person.*` entity: the chart needs a name and a colour, and linking `person.*` adds a lookup for nothing it uses. Two lists may name the same person; the chart shows them as one column.

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

**Writes and what the user sees.** A write changes nothing locally. The push that follows it is the new truth. To keep a check tap feeling immediate, the screen holds a small **pending map** (uid → the status or text it sent). A row in it draws the new value with a faint spinner. An error reply reverts the entry and shows HA's message in a snackbar. A success reply clears it at the next push, or at once if the last push already shows the change. `call_service` is blocking (**verified**, `websocket_api/commands.py:288`), so the reply comes only after the integration has written: on Google Tasks that includes HA's refresh from Google (`google_tasks/todo.py:130`). `request()`'s 10 s timeout is the only timer, and a timeout reverts like an error ("Couldn't confirm the change"). The write may still have landed, and the next push shows it if it did.

**What a write sends.** Only fields that changed, and only fields the list supports. A field the list lacks is an error even as `null` (`todo/services.py:86-98`), so the edit sheet never sends it. To clear a due date it sends the field the list supports (`due_date` if it can, else `due_datetime`) as `null`.

## The module

`lib/modules/lists/lists_module.dart`: id `lists`, name `Lists`, icon `Icons.checklist`, `defaultOrder` **7**, between Calendar (5) and Controls (10). `isConfigured` is `todoLists.isNotEmpty`. It goes into `_staticModules`; not into `defaultModulePlacements`, like Calendar. CLAUDE.md's screen-order line gets it in the screen task.

The screen has two views, chosen by a segmented control in its header: **Lists** and **Chores**. Chores appears only when at least one list has a person. The header starts `x20` from the left, clear of HubShell's mic toggle, the fix Calendar needed (`28392b9`).

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

- One column per person, merging that person's chore lists, in config order.
- **Each column shows:** open items due today or overdue (overdue first, marked "late"), then open items with no due date, then items completed today (when HA gives `completed`), struck through. Open items due later sit under "Upcoming (n)", collapsed. Completed items without a `completed` time are not shown here; the Lists view has them.
- The header count is done-today over done-today plus open-shown.
- **The whole row is the tap target** for complete and uncomplete, big enough for a child's finger. Editing is the Lists view's job. A list without `canUpdate` shows its chores without checkboxes.
- No add field, no reorder. The chart is for doing chores, not for managing them.

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

- The Lists view pads its bottom by `MediaQuery.viewInsetsOf(context).bottom` and scrolls the add field into view, so the keyboard never covers what is being typed.
- The add field and the name field use `TextInputAction.done` and `onSubmitted`; the OSK's Enter submits a single-line field. The description field is `TextInputType.multiline`, where Enter inserts a newline (`osk_control.dart:236-242`).
- The edit sheet is a dialog, which already respects `viewInsets`.
- `test/portrait/osk_portrait_test.dart` gets a case with the add field focused at all three sizes.

## The settings plugin

`lib/plugins/lists/lists_plugin.dart`, id `hearth.lists`, category `feature`, in `_firstPartyPlugins`, always visible. Device panel and `:8090` fragment from one definition, as every plugin.

- **Lists:** a `ListSection<TodoListConfig>`. Each row shows the colour, name, person (or "List"), live status, and what the list supports ("add · edit · reorder · due dates"), from its features.
  - *Add*: the entity picker filtered to `todo.*` (`lib/plugins/framework/fields/ha_entity_picker_field.dart`), then name (prefilled from `friendly_name`), colour, and person (blank by default).
  - *Edit*: name, colour, person. To change the entity, delete and add again.
- **Show today's chores when idle:** the `todoChoreGlance` toggle, off by default.

The live status is read from the entity HA already caches, not from an item subscription, so the panel opens no `todo/item/subscribe` per list: a `todo.*` entity's state is its count of incomplete items (`TodoListEntity.state` in `homeassistant/components/todo/entity.py`), shown as "3 open" or "All done", with "Not found in Home Assistant" and "Unavailable" for a missing entity and an `unknown`/`unavailable` state.

The `ListSection` HTML render is read-only (`lib/plugins/framework/list_section.dart`), so the portal needs routes, as Calendar's do: `GET /api/plugin/hearth.lists/lists` (with status and features), `POST …/lists`, `PUT …/lists/<entity_id>`, `DELETE …/lists/<entity_id>`. A second add of the same entity answers 409. Each handler validates its own input.

## The idle glance

`ChoreGlance`, a `ConsumerWidget` in `HomeScreen`'s bottom column next to `CalendarGlance` (`lib/screens/home/home_screen.dart:69`). It shows only when `todoChoreGlance` is on and a chore list exists:

```
  ● Ava   Feed the cat · late
  ● Ben   Trash out
  ● Ava   Make bed  +3 more
```

- At most three lines, then "+n more". Draws nothing when nothing is open for today.
- The person's colour as the dot, the same text shadows as the clock.
- A tap jumps to the Lists page on the Chores view, when the module is in the swipe row.
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
- **A person is a name on a list.** No `person.*` link, no Hearth chore state.
- **Undated chores stay off the glance** and appear on the chart every day.
