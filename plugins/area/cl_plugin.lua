
local PLUGIN = PLUGIN

function PLUGIN:GetPlayerAreaTrace()
	local client = LocalPlayer()

	return util.TraceLine({
		start = client:GetShootPos(),
		endpos = client:GetShootPos() + client:GetForward() * 96,
		filter = client
	})
end

function PLUGIN:StartEditing()
	ws.area.bEditing = true
	self.editStart = nil
	self.editProperties = nil
end

function PLUGIN:StopEditing()
	ws.area.bEditing = false

	if (IsValid(ws.gui.areaEdit)) then
		ws.gui.areaEdit:Remove()
	end
end
