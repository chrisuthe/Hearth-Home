# People

The household, kept by Hearth: who each [[calendar|Calendar]] and [[chore list|Lists & Chores]]
belongs to. Each person has a **name** and a **colour**, and can be linked to a Home Assistant
person (`person.*`) for a picture and whether they're home.

## Add people

In the [[web portal|The Web Portal]] or on-device Settings, open **People**.

- **Add** a person by name, or pick their **Home Assistant person**: the name fills in from HA,
  and you can change it — Hearth always shows the name you keep here.
- **Import from Home Assistant** adds one person for each HA person not linked yet. Running it
  again adds nobody twice.
- **Edit** to rename, recolour, or link and unlink someone.
- **Delete** removes the person. Their calendars and lists stay, just no longer assigned to anyone.

Then assign people on the **Lists** panel (a list with a person is their chore list) and the
**Calendar** panel (*Belongs to*).

## What linking adds

| From Home Assistant | Where it shows |
| --- | --- |
| **Picture** — the one set on the person in HA | Their chore column and the idle chore glance; the People panel. Without one, Hearth draws their initial on their colour |
| **Presence** — home, away, or the zone they're in | A dot on the picture: green at home, grey away, amber in another zone. It follows HA live, and disappears when HA isn't connected or doesn't know |

HA works out presence from the person's trackers (the companion app, a router integration…). A
person with no tracker shows no dot.

Pictures uploaded in HA are served to Hearth without a login. In the web portal, the browser
loads the picture straight from Home Assistant, so it shows only if that browser can reach HA.
