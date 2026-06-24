# Authoring a framework plugin

A Windswept plugin is a self-contained, **disabled-by-default** system that any schema can
turn on. The framework ships a stack of them (doors, radio, wallet, power, documents,
restraints, photography, permadeath, vendors, business…); this guide is how to write your
own, and the rule for deciding what belongs in a plugin versus a schema.

## Where code goes (the rule)

- Any schema would want it **+ core infrastructure** → the **framework core**.
- Any schema would want it **+ a self-contained on/off system** → a **framework plugin**.
- Assumes *your game's* specifics (this setting, these items, this content policy) → the
  **schema**.

A plugin is **mechanism**; the schema supplies **content** and **tuning**. Before extracting
anything, sort it into three buckets:

- **ENGINE** → the plugin: the generic mechanism — lib functions, net/action handlers,
  entity behaviour, item **bases** (`base_battery_device`, `base_clothing`), the config
  flag, neutral defaults.
- **CONTENT** → the schema: concrete items (your cash/coins, your outfits, your weapons),
  model→material maps, world flavour. They set `ITEM.base = "base_x"`.
- **TUNING / GLUE** → the schema: your numbers, palettes, and the cross-plugin wiring for
  *your* game (often a thin "bridge" plugin — see `photography_windswept_bridge`, or the
  Colony's `plugins/doors` / `plugins/radio` bridges).

Litmus: *"would a wildly different server want this exact value or item?"* If no, it's
content/tuning — keep it in the schema.

## Folder shape

Drop your plugin under `windswept/plugins/<name>/` (or your schema's `plugins/<name>/` for a
schema-local one). The per-plugin loader sweeps these subfolders automatically, in order:

```
plugins/<name>/
├── sh_plugin.lua     manifest + config flag (loaded LAST, after the sweep below)
├── languages/        sh_english.lua … (your localized strings)
├── libs/             sh_*/sv_*/cl_* library files (your ws.<name>.* API)
├── items/            items + item bases
├── derma/            client panels
└── entities/         entities/ weapons/ effects/
```

Realm is by **filename prefix** — `sh_` (shared), `sv_` (server), `cl_` (client) — not by
`if SERVER`/`if CLIENT` blocks. Don't manually `ws.util.Include` a swept subfolder; that
double-loads it.

## The manifest + the kill-switch

`sh_plugin.lua` declares the plugin and (for a feature plugin) its config flag:

```lua
local PLUGIN = PLUGIN

PLUGIN.name = "Doors"
PLUGIN.author = "Windswept"
PLUGIN.description = "Physical doors, locks, and keys. Off by default."

ws.doors = ws.doors or {}

ws.config.Add("doorsEnabled", false, "Enables the physical door/lock system.")  -- DEFAULT FALSE
```

Two kinds of plugin:

- **Base-library plugins** (power, documents) have **no flag**. They are inert until a
  schema includes items that build on their bases — nothing happens otherwise, so there's
  nothing to gate.
- **Feature plugins** that *do something on their own* (a hook that rewrites map doors, a
  voice override, a routing wrapper) **must be gated** with `ws.config.Add("<x>Enabled",
  false)` and a kill-switch, so the framework — and a zero-plugin skeleton schema — boot
  untouched. The kill-switch is an early return at the top of every active hook/handler:

  ```lua
  hook.Add("InitPostEntity", "wsDoorsInit", function()
      if (!ws.config.Get("doorsEnabled")) then return end
      -- … take over the map's doors …
  end)
  ```

A schema **enables** a feature plugin from its `sh_configs.lua`, in an `InitializedConfig`
hook (it fires during config load — before `InitPostEntity` — and again after the saved
config loads, so it lands in time *and* wins over any persisted value):

```lua
hook.Add("InitializedConfig", "myschemaPlugins", function()
    ws.config.Set("doorsEnabled", true)
end)
```

## Dependencies and load order (read this twice)

`ws.plugin.Initialize` loads **framework plugins first, then the schema, then the schema's
plugins.** Within a directory, plugins load **alphabetically** — `PLUGIN.dependencies` is
metadata only; the loader does **not** reorder by it.

Consequences:

- **`ws.constants` (a schema lib) does not exist when a framework plugin loads.** Any
  moved file that references `ws.constants.X` (or any schema global) must do so at
  **runtime** (inside a function body), never at file scope. Framework-side, the canonical
  ownership/range helpers live in **`ws.access`** (`GetCharacterInventory`,
  `VerifyItemOwnership`, `WithinRange`, …) — use those in plugin code.
- **Item bases resolve eagerly.** A framework-plugin item whose `ITEM.base` lives in a
  *later-sorting* plugin fails to load. So battery-powered or clothing **items stay schema
  content** (the schema loads after every framework plugin); the plugin ships only the
  **base**.

When a plugin needs game-specific names it must not hardcode them — expose a **seam** the
schema fills. The door engine carries no weapon class names; the schema registers them:

```lua
-- framework: plugins/doors/libs/sh_doors_core.lua
function ws.doors.RegisterDamageSource(class, opts) ws.doors.damageSources[class] = opts end
ws.doors.installToolClass = ws.doors.installToolClass  -- a schema sets this

-- schema: plugins/doors/sh_plugin.lua (a thin bridge)
ws.doors.RegisterDamageSource("ws_hands", { fist = true })
ws.doors.installToolClass = "ws_door"
```

The radio (`ws.radio.itemID` / `stationaryClass`), wallet (`ws.wallet.itemID` /
`cashID` / `coinID`), and appearance (model/option registration) plugins follow the same
pattern — generic engine, content wired in through seams.

## Trust boundary (non-negotiable)

This is multiplayer: treat **every** `net.Read*` as attacker-controlled.

- Route client→server actions through **`ws.action.Register`** (it enforces caller
  authority, target ownership/accessibility, interaction range, and numeric bounds *by
  construction*). The active-weapon analogue is **`ws.weapon.NetReceive`**.
- Never hand-roll a `net.Receive` that mutates state. A **net-handler gate**
  (`tools/check-net-handlers.sh`, in CI) fails on any new raw `net.Receive("…")` that
  isn't on the reviewed allowlist — so a genuinely-needed raw handler (a server→client
  receiver, a two-phase token) is a conscious, reviewed line.
- Conserved quantities (money, charge, ink, durability) move through **`ws.resource`** /
  **`ws.currency`** — atomic, all-or-nothing. Never inline-mutate a quantity across the net
  boundary; that's the money-dupe bug class.
- When you move a `net.Receive` into a plugin, `util.AddNetworkString` moves with it (so
  the plugin is self-contained), and its allowlist line moves to the plugin's repo.

## Conservation of matter is a framework default

This pillar is baked into the engine, so your plugin should respect it:

- **Conservation of matter** — vendors refuse to mint money/items unless
  `vendorAllowInfinite` is set; item spawning is gated; the business menu is off by
  default. Don't add a "spawn from nowhere" path without an explicit opt-in config.

## Smallest possible examples

- **`plugins/business`** — a near-minimal feature plugin (a config flag + a couple of
  handlers).
- **`plugins/power`** — a base-library plugin: ships `base_battery_device`; no flag, inert
  until a schema adds a battery-powered item.
- **`plugins/wallet`** — a faithful routing engine behind seams + a kill-switch.
- **`photography_windswept_bridge`** (Colony) — the cross-plugin glue pattern: a thin
  schema plugin that wires two systems together for one game.

## Ship checklist

1. `glualint lint <your plugin>` clean (no `[Error]`, no unused).
2. `luacheck .` clean (it catches >128-char lines and unused locals/values glualint won't).
3. Net-gate green: `bash tools/check-net-handlers.sh`.
4. `ldoc . --fatalwarnings` green (only matters if you documented core API; `ldoc` ignores
   `plugins/`).
5. Boot a schema with your plugin **on** and a skeleton schema with it **off** — both must
   reach character creation.
