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

	if currencyInfo.symbol == "" or currencyInfo.symbol == nil or useCurrencyName then
		return tostring(math.floor(amount)) .. " " .. currencyInfo.name
	else
		return currencyInfo.symbol .. tostring(math.floor(amount))
	end
end

return CurrencyUtil