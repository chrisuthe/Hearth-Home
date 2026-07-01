# Recipes (Mealie)

The **Recipes** screen browses and displays recipes from your
[Mealie](https://mealie.io/) server — handy for pulling up a recipe on the kiosk while you
cook.

## Connect Mealie

In the [[web portal|The Web Portal]], open **Mealie** and enter:

| Field | Example | Where to get it |
| --- | --- | --- |
| **Mealie URL** | `http://192.168.1.x:9925` | Your Mealie server |
| **Mealie Token** | *(paste it)* | Mealie → **Settings → API Tokens** |

Both are required for the Recipes screen to appear and load.

## Using the Recipes screen

- **Browse** — scroll your recipes with a search box.
- **Category filter** — narrow the list to a category.
- **Meal plan** — today's planned meal is surfaced where available.
- **Recipe detail** — opens the recipe with its image and an ingredient list you can check
  off as you go.

## Troubleshooting

- **Recipes don't load** — confirm the URL is reachable from the Pi and the token is valid.
  Tokens are created per-user in Mealie. See [[Troubleshooting & FAQ]].
