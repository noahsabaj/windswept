--[[
    Skeleton Schema (Windswept)

    The minimal schema: it boots straight to character creation on the framework with
    ZERO plugins enabled and no custom content beyond one example item. It is the
    "everything default-off works" reference -- if a fresh schema boots clean on this,
    every framework plugin's disabled path is sound.

    To start your own schema:
      1. Copy this skeleton-schema/ folder to garrysmod/gamemodes/<your-id>/.
      2. Rename skeleton.txt -> <your-id>.txt and change its id ("skeleton") + title.
      3. Set Schema.name / author / description below.
      4. Enable the framework plugins you want in schema/sh_configs.lua (all off by default).
      5. Add your content under schema/items/, schema/libs/, etc.

    See windswept-colony for a maximal, real-world schema built on the same framework.
]]--

Schema.name = "Skeleton"
Schema.author = "Windswept"
Schema.description = "A minimal Windswept schema -- copy this folder to start your own."
