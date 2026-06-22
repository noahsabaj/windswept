# Windswept

[![CI](https://github.com/noahsabaj/windswept/actions/workflows/ci.yml/badge.svg)](https://github.com/noahsabaj/windswept/actions/workflows/ci.yml)

**Windswept** is a **faction-optional** roleplay framework for [Garry's Mod](https://gmod.facepunch.com/). It gives you a stable, open-source engine — characters, inventories, items, a plugin system, and a hardened client→server trust boundary — so you can spend your time on gameplay instead of plumbing.

The guiding idea: **the framework provides mechanism; the schema provides policy.** Factions, the currency model, UI affordances, and every gameplay system are choices a developer opts into — never defaults the engine forces on you.

## What makes it different

- **Faction-optional.** Factions are a *choice*. The `factionMode` config supports:
  - `required` — every character belongs to a faction (the classic Helix model),
  - `optional` — factionless characters are allowed,
  - `disabled` — no factions at all.

  Every faction-aware subsystem (character creation, scoreboard, HUD, whitelist, vendors, default names/models) degrades gracefully in all three modes. `showFactionColors` further decouples faction identity from UI color, so an anti-metagaming schema can drop faction colors without dropping factions.
- **A real trust boundary.** Client→server actions route through **`ws.action`** (automatic caller / ownership / range / bounds checks); active-weapon SWEPs use **`ws.weapon.NetReceive`**. Conserved resources (money, charge, …) move through atomic primitives (**`ws.resource`**, the currency registry) so quantities are never duplicated across the net boundary. A CI ratchet (`tools/check-net-handlers.sh`) blocks new unchecked `net.Receive` handlers.
- **Self-contained.** The UI assets (fonts, sounds, vignette) ship with the framework — no external workshop content pack required.

## The Windswept suite

This repository is the **framework** (the reusable engine). It's accompanied by:

| Repo | What it is |
|------|------------|
| **windswept** (here) | The framework — a generic RP engine, no game-specific gameplay. Gamemode id `windswept`. |
| [windswept-colony](https://github.com/noahsabaj/windswept-colony) | Windswept Colony RP — the flagship game (schema) built on the framework. |
| [windswept-fire](https://github.com/noahsabaj/windswept-fire) | A standalone, performance-focused fire system addon. |

## Getting started

Windswept is a base gamemode; what players actually run is a **schema** built on top of it. Derive your schema from the framework:

```lua
-- your schema's gamemode (boots as its own gamemode id, e.g. "myschema")
DeriveGamemode("windswept")
```

See [windswept-colony](https://github.com/noahsabaj/windswept-colony) for a complete, working schema to learn from or fork.

## Conventions

- **Namespace `ws.*`**; entities, data tables, and saved keys use the `ws_` prefix.
- **Realms by file prefix:** `sh_` (shared), `cl_` (client), `sv_` (server); entities use `init.lua` / `cl_init.lua` / `shared.lua`.
- **Trust boundary:** treat every `net.Read*` as hostile. Route client→server actions through `ws.action` (SWEPs: `ws.weapon.NetReceive`) — never hand-roll an unchecked `net.Receive`. The CI gate enforces this.
- **Conserved resources** (money, charge, ink, durability) go through `ws.resource` / the currency registry — never inline-mutate a quantity across the net boundary.

## Building the documentation

API docs are generated from the source's LDoc comments using a [forked LDoc](https://github.com/impulsh/LDoc) (requires [LuaRocks](https://luarocks.org/)):

```shell
git clone https://github.com/impulsh/LDoc ldoc
cd ldoc && luarocks make

# then, from the framework repo:
ldoc .
```

After building, copy the files in `docs/js` and `docs/css` into `docs/html` for syntax highlighting.

## Contributing

Pull requests welcome — keep code consistent with the surrounding style. CI runs `luacheck` and the net-handler gate (`tools/check-net-handlers.sh`); please make sure both pass before opening a PR.

## Acknowledgements

Windswept is a fork of [Helix](https://github.com/NebulousCloud/helix) by NebulousCloud, which itself builds on [NutScript](https://github.com/NutScript/NutScript) by [Chessnut](https://github.com/brianhang) and rebel1324.
