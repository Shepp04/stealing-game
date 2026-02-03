--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Data
local GameData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local CurrencyUtil = {}

function CurrencyUtil.GetCurrencyText(currencyId: string, amount: number, useCurrencyName: boolean?): string
	local currencyInfo = GameData.Get("Currency", currencyId)
	if not currencyInfo then
		return tostring(math.floor(amount))
	end

	if not useCurrencyName then
		return (currencyInfo.symbol or "") .. tostring(math.floor(amount))
	else
		return tostring(math.floor(amount)) .. " " .. currencyInfo.name
	end
end

return CurrencyUtil