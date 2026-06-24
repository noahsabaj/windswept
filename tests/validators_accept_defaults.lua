-- tests/validators_accept_defaults.lua
--
-- Guards the "reject-vs-clamp" character-creation bug class. A char var whose OnValidate returns
-- `false` for its own default/derived value BLOCKS character creation client-side -- this has
-- bitten physBirthDay, physSkinTone, the hair vars, and physEyeColor/physFacialHair. The framework's
-- appearance content lists default empty (a schema fills them), and a content-less schema must
-- still boot to character creation (see plugins/appearance/libs/sh_appearance_util.lua). So every
-- char var must ACCEPT its declared default even with empty appearance content.
--
-- This loads the real var definitions in a tiny plain-Lua shim (no GMod) and asserts exactly that.
-- Run from the repo root:  lua tests/validators_accept_defaults.lua
-- luacheck: ignore

-- ---- stdlib helpers GMod adds ----
function table.HasValue(t, val)
	for _, v in pairs(t) do if v == val then return true end end
	return false
end
math.Clamp = function(n, lo, hi)
	n = tonumber(n) or lo
	if n < lo then return lo elseif n > hi then return hi else return n end
end
function istable(x) return type(x) == "table" end

-- ---- minimal ws shim ----
ws = {}
ws.type = setmetatable({}, { __index = function() return 0 end })   -- any ws.type.X -> 0
ws.config = { Get = function() return 2200 end }

local vars = {}
ws.char = {
	vars = vars,
	RegisterVar = function(key, data) data.__key = key; vars[key] = data end,
}

-- ---- load the real code under test (paths relative to repo root) ----
local function loadReal(path)
	local chunk, err = loadfile(path)
	if not chunk then error("load failed: " .. path .. ": " .. tostring(err), 0) end
	local ok, rerr = pcall(chunk)
	if not ok then error("run failed: " .. path .. ": " .. tostring(rerr), 0) end
end

loadReal("plugins/appearance/libs/sh_appearance_util.lua")   -- ws.appearance (content lists default {})
loadReal("gamemode/core/libs/sh_birthdata.lua")              -- ws.birthdata
loadReal("plugins/appearance/libs/sh_appearance_vars.lua")   -- registers the char vars

-- ---- assert each var's OnValidate accepts its own default (empty content = the strict case) ----
local payload = {}
for k, v in pairs(vars) do payload[k] = v.default end

local failures, tested = {}, 0
for k, v in pairs(vars) do
	if type(v.OnValidate) == "function" and v.default ~= nil then
		tested = tested + 1
		local ok, res = pcall(function() return { v:OnValidate(v.default, payload, nil) } end)
		if not ok then
			failures[#failures + 1] = ("%s -> OnValidate errored: %s"):format(k, tostring(res))
		elseif res[1] == false then
			failures[#failures + 1] = ("%s -> rejects its own default (%q) with '%s'"):format(
				k, tostring(v.default), tostring(res[2]))
		end
	end
end

if #failures > 0 then
	io.stderr:write("validators: FAIL -- these char vars reject their own default and would block creation:\n")
	for _, f in ipairs(failures) do io.stderr:write("  - " .. f .. "\n") end
	os.exit(1)
end

print(("validators: OK -- all %d char vars accept their defaults under content-less appearance"):format(tested))
