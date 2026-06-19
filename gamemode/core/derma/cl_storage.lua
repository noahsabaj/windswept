
local PANEL = {}

AccessorFunc(PANEL, "money", "Money", FORCE_NUMBER)

function PANEL:Init()
	self:DockPadding(1, 1, 1, 1)
	self:SetTall(64)
	self:Dock(BOTTOM)

	self.moneyLabel = self:Add("DLabel")
	self.moneyLabel:Dock(TOP)
	self.moneyLabel:SetFont("wsGenericFont")
	self.moneyLabel:SetText("")
	self.moneyLabel:SetTextInset(2, 0)
	self.moneyLabel:SizeToContents()
	self.moneyLabel.Paint = function(panel, width, height)
		derma.SkinFunc("DrawImportantBackground", 0, 0, width, height, ws.config.Get("color"))
	end

	self.amountEntry = self:Add("wsTextEntry")
	self.amountEntry:Dock(FILL)
	self.amountEntry:SetFont("wsGenericFont")
	self.amountEntry:SetNumeric(true)
	self.amountEntry:SetValue("0")

	self.transferButton = self:Add("DButton")
	self.transferButton:SetFont("wsIconsMedium")
	self:SetLeft(false)
	self.transferButton.DoClick = function()
		local amount = math.max(0, math.Round(tonumber(self.amountEntry:GetValue()) or 0))
		self.amountEntry:SetValue("0")

		if (amount != 0) then
			self:OnTransfer(amount)
		end
	end

	self.bNoBackgroundBlur = true
end

function PANEL:SetLeft(bValue)
	if (bValue) then
		self.transferButton:Dock(LEFT)
		self.transferButton:SetText("s")
	else
		self.transferButton:Dock(RIGHT)
		self.transferButton:SetText("t")
	end
end

function PANEL:SetMoney(money)
	local name = string.gsub(ws.util.ExpandCamelCase(ws.currency.plural), "%s", "")

	self.money = math.max(math.Round(tonumber(money) or 0), 0)
	self.moneyLabel:SetText(string.format("%s: %d", name, money))
end

function PANEL:OnTransfer(amount)
end

function PANEL:Paint(width, height)
	derma.SkinFunc("PaintBaseFrame", self, width, height)
end

vgui.Register("wsStorageMoney", PANEL, "EditablePanel")

DEFINE_BASECLASS("Panel")
PANEL = {}

AccessorFunc(PANEL, "fadeTime", "FadeTime", FORCE_NUMBER)
AccessorFunc(PANEL, "frameMargin", "FrameMargin", FORCE_NUMBER)
AccessorFunc(PANEL, "storageID", "StorageID", FORCE_NUMBER)

function PANEL:Init()
	if (IsValid(ws.gui.openedStorage)) then
		ws.gui.openedStorage:Remove()
	end

	ws.gui.openedStorage = self

	self:SetSize(ScrW(), ScrH())
	self:SetPos(0, 0)
	self:SetFadeTime(0.25)
	self:SetFrameMargin(4)

	self.storageInventory = self:Add("wsInventory")
	self.storageInventory.bNoBackgroundBlur = true
	self.storageInventory:ShowCloseButton(true)
	self.storageInventory:SetTitle("Storage")
	self.storageInventory.Close = function(this)
		net.Start("wsStorageClose")
		net.SendToServer()
		self:Remove()
	end

	-- REMOVED: Physical currency system - money is now inventory items (cash/coins)
	-- self.storageMoney removed - cash can be dragged like any other item

	ws.gui.inv1 = self:Add("wsInventory")
	ws.gui.inv1.bNoBackgroundBlur = true
	ws.gui.inv1:ShowCloseButton(true)
	ws.gui.inv1.Close = function(this)
		net.Start("wsStorageClose")
		net.SendToServer()
		self:Remove()
	end

	-- REMOVED: Physical currency system - money is now inventory items (cash/coins)
	-- self.localMoney removed - cash can be dragged like any other item

	self:SetAlpha(0)
	self:AlphaTo(255, self:GetFadeTime())

	self.storageInventory:MakePopup()
	ws.gui.inv1:MakePopup()
end

function PANEL:OnChildAdded(panel)
	panel:SetPaintedManually(true)
end

function PANEL:SetLocalInventory(inventory)
	if (IsValid(ws.gui.inv1) and !IsValid(ws.gui.menu)) then
		ws.gui.inv1:SetInventory(inventory)
		ws.gui.inv1:SetPos(self:GetWide() / 2 + self:GetFrameMargin() / 2, self:GetTall() / 2 - ws.gui.inv1:GetTall() / 2)
	end
end

function PANEL:SetLocalMoney(money)
	-- Physical currency: money is items, no separate display needed
end

function PANEL:SetStorageTitle(title)
	self.storageInventory:SetTitle(title)
end

function PANEL:SetStorageInventory(inventory)
	self.storageInventory:SetInventory(inventory)
	self.storageInventory:SetPos(
		self:GetWide() / 2 - self.storageInventory:GetWide() - 2,
		self:GetTall() / 2 - self.storageInventory:GetTall() / 2
	)

	ws.gui["inv" .. inventory:GetID()] = self.storageInventory
end

function PANEL:SetStorageMoney(money)
	-- Physical currency: money is items, no separate display needed
end

function PANEL:Paint(width, height)
	ws.util.DrawBlurAt(0, 0, width, height)

	for _, v in ipairs(self:GetChildren()) do
		v:PaintManual()
	end
end

function PANEL:Remove()
	self:SetAlpha(255)
	self:AlphaTo(0, self:GetFadeTime(), 0, function()
		BaseClass.Remove(self)
	end)
end

function PANEL:OnRemove()
	if (!IsValid(ws.gui.menu)) then
		self.storageInventory:Remove()
		ws.gui.inv1:Remove()
	end
end

vgui.Register("wsStorageView", PANEL, "Panel")
