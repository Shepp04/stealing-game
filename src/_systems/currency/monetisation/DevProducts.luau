--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type DevProductPrivate = Types.DevProductPrivate
type Handler = Types.Handler

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
    CurrencyDevProduct = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
        local value = params.value
        local currencyId = params.currencyId

        assert(typeof(value) == "number", "Invalid value for CurrencyDevProduct")
        assert(typeof(currencyId) == "string", "Invalid currencyId for CurrencyDevProduct")
        
        -- // Grant currency to player
        local CurrencyService = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Services")).Get("CurrencyService")
        if not CurrencyService then
            error("CurrencyService not found")
        end
        
        local ok, err = CurrencyService:GiveCurrency(player, currencyId, value, false)
        if not ok then
            warn("Failed to grant currency to player:", err)
            return false
        end

        return true
    end,
}

-- ========== Definitions ========== --
local defs: { devProducts: { DevProductPrivate } } = {
    devProducts = {
        CoinPack1 = {
            id = 3531894489,
            name = "Coin Pack 1",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 125, currencyId = "Cash" },
        },
        CoinPack2 = {
            id = 3531894836,
            name = "Coin Pack 2",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 500, currencyId = "Cash" },
        },
        CoinPack3 = {
            id = 3531895156,
            name = "Coin Pack 3",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 960, currencyId = "Cash" },
        },
        CoinPack4 = {
            id = 3531895546,
            name = "Coin Pack 4",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 2100, currencyId = "Cash" },
        },
        CoinPack5 = {
            id = 3531895836,
            name = "Coin Pack 5",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 4500, currencyId = "Cash" },
        },
        CoinPack6 = {
            id = 3531896224,
            name = "Coin Pack 6",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 12000, currencyId = "Cash" },
        },
	},
}

return defs
