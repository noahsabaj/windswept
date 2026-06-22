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
				if (IsValid(client)) then
					if (hook.Run("CanPlayerEarnSalary", client, faction) != false) then
						local pay = hook.Run("GetSalaryAmount", client, faction) or faction.pay

						character:GiveMoney(pay)
						client:NotifyLocalized("salary", ws.currency.Get(pay))
					end
				else
					timer.Remove(uniqueID)
				end
			end)
		elseif (timer.Exists(uniqueID)) then
			timer.Remove(uniqueID)
		end
	end
end
