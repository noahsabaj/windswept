--- Client render helpers: screen-space projection, blur, 3D2D and related drawing.
--
-- Split out of core/sh_util.lua for readability (PR-3); pure relocation, the public
-- ws.util.* API is unchanged. Loaded by sh_util.lua after its file-inclusion bootstrap.
-- @module ws.util

do
	local i
	local value
	local character

	local function iterator(table)
		repeat
			i = i + 1
			value = table[i]
			character = value and value:GetCharacter()
		until character or value == nil

		return value, character
	end

	--- Returns an iterator for characters. The resulting key/values will be a player and their corresponding characters. This
	-- iterator skips over any players that do not have a valid character loaded.
	-- @realm shared
	-- @treturn Iterator
	-- @usage for client, character in ws.util.GetCharacters() do
	-- 	print(client, character)
	-- end
	-- > Player [1][Bot01]    character[1]
	-- > Player [2][Bot02]    character[2]
	-- -- etc.
	function ws.util.GetCharacters()
		i = 0
		return iterator, player.GetAll()
	end
end

if (CLIENT) then
	local blur = ws.util.GetMaterial("pp/blurscreen")
	local surface = surface

	--- Blurs the content underneath the given panel. This will fall back to a simple darkened rectangle if the player has
	-- blurring disabled.
	-- @realm client
	-- @tparam panel panel Panel to draw the blur for
	-- @number[opt=5] amount Intensity of the blur. This should be kept between 0 and 10 for performance reasons
	-- @number[opt=0.2] passes Quality of the blur. This should be kept as default
	-- @number[opt=255] alpha Opacity of the blur
	-- @usage function PANEL:Paint(width, height)
	-- 	ws.util.DrawBlur(self)
	-- end
	function ws.util.DrawBlur(panel, amount, passes, alpha)
		amount = amount or 5

		if (ws.option.Get("cheapBlur", false)) then
			surface.SetDrawColor(50, 50, 50, alpha or (amount * 20))
			surface.DrawRect(0, 0, panel:GetWide(), panel:GetTall())
		else
			surface.SetMaterial(blur)
			surface.SetDrawColor(255, 255, 255, alpha or 255)

			local x, y = panel:LocalToScreen(0, 0)

			for i = -(passes or 0.2), 1, 0.2 do
				-- Do things to the blur material to make it blurry.
				blur:SetFloat("$blur", i * amount)
				blur:Recompute()

				-- Draw the blur material over the screen.
				render.UpdateScreenEffectTexture()
				surface.DrawTexturedRect(x * -1, y * -1, ScrW(), ScrH())
			end
		end
	end

	--- Draws a blurred rectangle with the given position and bounds. This shouldn't be used for panels, see `ws.util.DrawBlur`
	-- instead.
	-- @realm client
	-- @number x X-position of the rectangle
	-- @number y Y-position of the rectangle
	-- @number width Width of the rectangle
	-- @number height Height of the rectangle
	-- @number[opt=5] amount Intensity of the blur. This should be kept between 0 and 10 for performance reasons
	-- @number[opt=0.2] passes Quality of the blur. This should be kept as default
	-- @number[opt=255] alpha Opacity of the blur
	-- @usage hook.Add("HUDPaint", "MyHUDPaint", function()
	-- 	ws.util.DrawBlurAt(0, 0, ScrW(), ScrH())
	-- end)
	function ws.util.DrawBlurAt(x, y, width, height, amount, passes, alpha)
		amount = amount or 5

		if (ws.option.Get("cheapBlur", false)) then
			surface.SetDrawColor(30, 30, 30, amount * 20)
			surface.DrawRect(x, y, width, height)
		else
			surface.SetMaterial(blur)
			surface.SetDrawColor(255, 255, 255, alpha or 255)

			local scrW, scrH = ScrW(), ScrH()
			local x2, y2 = x / scrW, y / scrH
			local w2, h2 = (x + width) / scrW, (y + height) / scrH

			for i = -(passes or 0.2), 1, 0.2 do
				blur:SetFloat("$blur", i * amount)
				blur:Recompute()

				render.UpdateScreenEffectTexture()
				surface.DrawTexturedRectUV(x, y, width, height, x2, y2, w2, h2)
			end
		end
	end

	--- Pushes a 3D2D blur to be rendered in the world. The draw function will be called next frame in the
	-- `PostDrawOpaqueRenderables` hook.
	-- @realm client
	-- @func drawFunc Function to call when it needs to be drawn
	function ws.util.PushBlur(drawFunc)
		ws.blurRenderQueue[#ws.blurRenderQueue + 1] = drawFunc
	end

	--- Draws some text with a shadow.
	-- @realm client
	-- @string text Text to draw
	-- @number x X-position of the text
	-- @number y Y-position of the text
	-- @color color Color of the text to draw
	-- @number[opt=TEXT_ALIGN_LEFT] alignX Horizontal alignment of the text, using one of the `TEXT_ALIGN_*` constants
	-- @number[opt=TEXT_ALIGN_LEFT] alignY Vertical alignment of the text, using one of the `TEXT_ALIGN_*` constants
	-- @string[opt="wsGenericFont"] font Font to use for the text
	-- @number[opt=color.a * 0.575] alpha Alpha of the shadow
	function ws.util.DrawText(text, x, y, color, alignX, alignY, font, alpha)
		color = color or color_white

		return draw.TextShadow({
			text = text,
			font = font or "wsGenericFont",
			pos = {x, y},
			color = color,
			xalign = alignX or TEXT_ALIGN_LEFT,
			yalign = alignY or TEXT_ALIGN_LEFT
		}, 1, alpha or (color.a * 0.575))
	end

	--- Wraps text so it does not pass a certain width. This function will try and break lines between words if it can,
	-- otherwise it will break a word if it's too long.
	-- @realm client
	-- @string text Text to wrap
	-- @number maxWidth Maximum allowed width in pixels
	-- @string[opt="wsChatFont"] font Font to use for the text
	function ws.util.WrapText(text, maxWidth, font)
		font = font or "wsChatFont"
		surface.SetFont(font)

		local words = string.Explode("%s", text, true)
		local lines = {}
		local line = ""
		local lineWidth = 0 -- luacheck: ignore 231

		-- we don't need to calculate wrapping if we're under the max width
		if (surface.GetTextSize(text) <= maxWidth) then
			return {text}
		end

		for i = 1, #words do
			local word = words[i]
			local wordWidth = surface.GetTextSize(word)

			-- this word is very long so we have to split it by character
			if (wordWidth > maxWidth) then
				local newWidth

				for i2 = 1, word:utf8len() do
					local character = word[i2]
					newWidth = surface.GetTextSize(line .. character)

					-- if current line + next character is too wide, we'll shove the next character onto the next line
					if (newWidth > maxWidth) then
						lines[#lines + 1] = line
						line = ""
					end

					line = line .. character
				end

				lineWidth = newWidth
				continue
			end

			local space = (i == 1) and "" or " "
			local newLine = line .. space .. word
			local newWidth = surface.GetTextSize(newLine)

			if (newWidth > maxWidth) then
				-- adding this word will bring us over the max width
				lines[#lines + 1] = line

				line = word
				lineWidth = wordWidth
			else
				-- otherwise we tack on the new word and continue
				line = newLine
				lineWidth = newWidth
			end
		end

		if (line != "") then
			lines[#lines + 1] = line
		end

		return lines
	end

	local cos, sin, abs, rad1, log, pow = math.cos, math.sin, math.abs, math.rad, math.log, math.pow

	-- arc drawing functions
	-- by bobbleheadbob
	-- https://facepunch.com/showthread.php?t=1558060
	function ws.util.DrawArc(cx, cy, radius, thickness, startang, endang, roughness, color)
		surface.SetDrawColor(color)
		ws.util.DrawPrecachedArc(ws.util.PrecacheArc(cx, cy, radius, thickness, startang, endang, roughness))
	end

	function ws.util.DrawPrecachedArc(arc) -- Draw a premade arc.
		for _, v in ipairs(arc) do
			surface.DrawPoly(v)
		end
	end

	function ws.util.PrecacheArc(cx, cy, radius, thickness, startang, endang, roughness)
		local quadarc = {}

		-- Correct start/end ang
		startang = startang or 0
		endang = endang or 0

		-- Define step
		-- roughness = roughness or 1
		local diff = abs(startang - endang)
		local smoothness = log(diff, 2) / 2
		local step = diff / (pow(2, smoothness))

		if startang > endang then
			step = abs(step) * -1
		end

		-- Create the inner circle's points.
		local inner = {}
		local outer = {}
		local ct = 1
		local r = radius - thickness

		for deg = startang, endang, step do
			local rad = rad1(deg)
			local cosrad, sinrad = cos(rad), sin(rad) --calculate sin, cos

			local ox, oy = cx + (cosrad * r), cy + (-sinrad * r) --apply to inner distance
			inner[ct] = {
				x = ox,
				y = oy,
				u = (ox - cx) / radius + .5,
				v = (oy - cy) / radius + .5
			}

			local ox2, oy2 = cx + (cosrad * radius), cy + (-sinrad * radius) --apply to outer distance
			outer[ct] = {
				x = ox2,
				y = oy2,
				u = (ox2 - cx) / radius + .5,
				v = (oy2 - cy) / radius + .5
			}

			ct = ct + 1
		end

		-- QUAD the points.
		for tri = 1, ct do
			local p1, p2, p3, p4
			local t = tri + 1
			p1 = outer[tri]
			p2 = outer[t]
			p3 = inner[t]
			p4 = inner[tri]

			quadarc[tri] = {p1, p2, p3, p4}
		end

		-- Return a table of triangles to draw.
		return quadarc
	end

	--- Resets all stencil values to known good (i.e defaults)
	-- @realm client
	function ws.util.ResetStencilValues()
		render.SetStencilWriteMask(0xFF)
		render.SetStencilTestMask(0xFF)
		render.SetStencilReferenceValue(0)
		render.SetStencilCompareFunction(STENCIL_ALWAYS)
		render.SetStencilPassOperation(STENCIL_KEEP)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.ClearStencil()
	end

	-- luacheck: globals derma
	-- Alternative to SkinHook that allows you to pass more arguments to skin methods
	function derma.SkinFunc(name, panel, a, b, c, d, e, f, g)
		local skin = (ispanel(panel) and IsValid(panel)) and panel:GetSkin() or derma.GetDefaultSkin()

		if (!skin) then
			return
		end

		local func = skin[name]

		if (!func) then
			return
		end

		return func(skin, panel, a, b, c, d, e, f, g)
	end

	-- Alternative to Color that retrieves from the SKIN.Colours table
	function derma.GetColor(name, panel, default)
		default = default or ws.config.Get("color")

		local skin = panel:GetSkin()

		if (!skin) then
			return default
		end

		return skin.Colours[name] or default
	end


	hook.Add("OnScreenSizeChanged", "ws.OnScreenSizeChanged", function(oldWidth, oldHeight)
		hook.Run("ScreenResolutionChanged", oldWidth, oldHeight)
	end)
end

-- Vector extension, courtesy of code_gs
do
	local VECTOR = FindMetaTable("Vector")
	local CrossProduct = VECTOR.Cross
	local right = Vector(0, -1, 0)

	function VECTOR:Right(vUp)
		if (self[1] == 0 and self[2] == 0) then
			return right
		end

		if (vUp == nil) then
			vUp = vector_up
		end

		local vRet = CrossProduct(self, vUp)
		vRet:Normalize()

		return vRet
	end

	function VECTOR:Up(vUp)
		if (self[1] == 0 and self[2] == 0) then return Vector(-self[3], 0, 0) end

		if (vUp == nil) then
			vUp = vector_up
		end

		local vRet = CrossProduct(self, vUp)
		vRet = CrossProduct(vRet, self)
		vRet:Normalize()

		return vRet
	end
end
