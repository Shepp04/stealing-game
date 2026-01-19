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
            id = 3478507776,
            name = "Coin Pack 1",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 120, currencyId = "Coins" },
        },
        CoinPack2 = {
            id = 3478507887,
            name = "Coin Pack 2",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 960, currencyId = "Coins" },
        },
        CoinPack3 = {
            id = 3478507963,
            name = "Coin Pack 3",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 2100, currencyId = "Coins" },
        },
        CoinPack4 = {
            id = 3478508048,
            name = "Coin Pack 4",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 4500, currencyId = "Coins" },
        },
        CoinPack5 = {
            id = 3478508114,
            name = "Coin Pack 5",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 12000, currencyId = "Coins" },
        },
        CoinPack6 = {
            id = 3478508187,
            name = "Coin Pack 6",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 30000, currencyId = "Coins" },
        },
        CoinPack7 = {
            id = 3478508251,
            name = "Coin Pack 7",
            category = "Currency",
            description = nil, -- hydrated later
            priceInRobux = nil, -- hydrated later
            iconImageAssetId = nil, -- hydrated later
            handler = Handlers.CurrencyDevProduct,
            params = { value = 120000, currencyId = "Coins" },
        },
	},
}

return defs
