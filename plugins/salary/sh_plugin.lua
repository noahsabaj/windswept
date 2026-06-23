PLUGIN.name = "Salary"
PLUGIN.author = "Windswept"
PLUGIN.description = "Periodic faction salary: pays members faction.pay every faction.payTime seconds."

-- Relocated out of framework core (GM:PlayerLoadedCharacter) so faction-pay is a self-contained
-- on/off system. The CanPlayerEarnSalary / GetSalaryAmount hook seams are unchanged, and a faction
-- with no `pay` simply never starts a timer. (fw-hooks-8)
if (SERVER) then
	function PLUGIN:PlayerLoadedCharacter(client, character, lastChar)
		local faction = ws.faction.indices[character:GetFaction()]
		local uniqueID = "wsSalary" .. client:SteamID64()

		if (faction and faction.pay and faction.pay > 0) then
			timer.Create(uniqueID, faction.payTime or 300, 0, function()
				if (!IsValid(client)) then
					timer.Remove(uniqueID)
					return
				end

				if (hook.Run("CanPlayerEarnSalary", client, faction) == false) then return end

				local pay = hook.Run("GetSalaryAmount", client, faction) or faction.pay

				-- Only tell the player they were paid if the cash actually fit in their
				-- inventory (GiveMoney fails on a full inventory).
				if (character:GiveMoney(pay)) then
					client:NotifyLocalized("salary", ws.currency.Get(pay))
				end
			end)
		elseif (timer.Exists(uniqueID)) then
			timer.Remove(uniqueID)
		end
	end
end
