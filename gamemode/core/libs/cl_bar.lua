
ws.bar = ws.bar or {}
ws.bar.list = {}
ws.bar.delta = ws.bar.delta or {}
ws.bar.actionText = ""
ws.bar.actionStart = 0
ws.bar.actionEnd = 0
ws.bar.totalHeight = 0

-- luacheck: globals BAR_HEIGHT
BAR_HEIGHT = 10

function ws.bar.Get(identifier)
	for _, v in ipairs(ws.bar.list) do
		if (v.identifier == identifier) then
			return v
		end
	end
end

function ws.bar.Remove(identifier)
	local bar = ws.bar.Get(identifier)

	if (bar) then
		table.remove(ws.bar.list, bar.index)

		if (IsValid(ws.gui.bars)) then
			ws.gui.bars:RemoveBar(bar.panel)
		end
	end
end

function ws.bar.Add(getValue, color, priority, identifier)
	if (identifier) then
		ws.bar.Remove(identifier)
	end

	local index = #ws.bar.list + 1

	color = color or Color(math.random(150, 255), math.random(150, 255), math.random(150, 255))
	priority = priority or index

	ws.bar.list[index] = {
		index = index,
		color = color,
		priority = priority,
		GetValue = getValue,
		identifier = identifier,
		panel = IsValid(ws.gui.bars) and ws.gui.bars:AddBar(index, color, priority)
	}

	return priority
end

local gradientD = ws.util.GetMaterial("vgui/gradient-d")

local TEXT_COLOR = Color(240, 240, 240)
local SHADOW_COLOR = Color(20, 20, 20)

function ws.bar.DrawAction()
	local start, finish = ws.bar.actionStart, ws.bar.actionEnd
	local curTime = CurTime()
	local scrW, scrH = ScrW(), ScrH()

	if (finish > curTime) then
		local fraction = 1 - math.TimeFraction(start, finish, curTime)
		local alpha = fraction * 255

		if (alpha > 0) then
			local w, h = scrW * 0.35, 28
			local x, y = (scrW * 0.5) - (w * 0.5), (scrH * 0.725) - (h * 0.5)

			ws.util.DrawBlurAt(x, y, w, h)

			surface.SetDrawColor(35, 35, 35, 100)
			surface.DrawRect(x, y, w, h)

			surface.SetDrawColor(0, 0, 0, 120)
			surface.DrawOutlinedRect(x, y, w, h)

			surface.SetDrawColor(ws.config.Get("color"))
			surface.DrawRect(x + 4, y + 4, math.max(w * fraction, 8) - 8, h - 8)

			surface.SetDrawColor(200, 200, 200, 20)
			surface.SetMaterial(gradientD)
			surface.DrawTexturedRect(x + 4, y + 4, math.max(w * fraction, 8) - 8, h - 8)

			draw.SimpleText(ws.bar.actionText, "wsMediumFont", x + 2, y - 22, SHADOW_COLOR)
			draw.SimpleText(ws.bar.actionText, "wsMediumFont", x, y - 24, TEXT_COLOR)
		end
	end
end

do
	ws.bar.Add(function()
		return math.max(LocalPlayer():Health() / LocalPlayer():GetMaxHealth(), 0)
	end, Color(200, 50, 40), nil, "health")

	ws.bar.Add(function()
		return math.min(LocalPlayer():Armor() / 100, 1)
	end, Color(30, 70, 180), nil, "armor")
end

net.Receive("wsActionBar", function()
	local start, finish = net.ReadFloat(), net.ReadFloat()
	local text = net.ReadString()

	if (text:sub(1, 1) == "@") then
		text = L2(text:sub(2)) or text
	end

	ws.bar.actionStart = start
	ws.bar.actionEnd = finish
	ws.bar.actionText = text:utf8upper()
end)

net.Receive("wsActionBarReset", function()
	ws.bar.actionStart = 0
	ws.bar.actionEnd = 0
	ws.bar.actionText = ""
end)
