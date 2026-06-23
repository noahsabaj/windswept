# Windswept skeleton schema

The smallest schema that boots on the Windswept framework: zero plugins enabled, one
example item. Copy it to start your own schema, or use it as the reference for
"everything default-off works."

## What's here

```
skeleton-schema/
├── skeleton.txt              gamemode definition (base = "windswept")
├── README.md                 this file
└── schema/
    ├── sh_schema.lua         Schema.name / author / description
    ├── sh_configs.lua        how to enable framework plugins
    └── items/
        └── sh_canned_food.lua  one trivial custom item
```

A schema needs no `init.lua` / `cl_init.lua` / `shared.lua` — it sets `base = "windswept"`
in its `.txt`, and the framework (inherited via that base) loads this `schema/` folder
automatically (`DeriveGamemode("windswept")` happens in the framework's own init).

## Start your own schema

1. Copy `skeleton-schema/` to `garrysmod/gamemodes/<your-id>/`.
2. Rename `skeleton.txt` → `<your-id>.txt`; change its id (`"skeleton"`) and `"title"`.
3. Edit `schema/sh_schema.lua` (`Schema.name` / `author` / `description`).
4. Launch with `+gamemode <your-id>` — you should reach character creation.

## Turn things on

Every framework plugin is **off by default**. Enable the ones you want in
`schema/sh_configs.lua` (see the comments there): physical doors, radio, wallet routing,
the business menu, etc. Some plugins (power batteries, documents, restraints, photography,
permadeath) are inert until your content uses their item bases — no flag needed.

Conservation of matter is the framework default: vendors won't mint money or items unless
you set `vendorAllowInfinite`. For a full, real-world build on this same framework, read
`windswept-colony`.

See also: `windswept/docs/manual/authoring-plugins.md` for writing your own framework
plugin, and the API docs at <https://noahsabaj.github.io/windswept/>.
