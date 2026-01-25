--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type DevProductPrivate = Types.DevProductPrivate
type Handler = Types.Handler

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
  ["ExampleHandler"] = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
    -- Example handler
    print("Player " .. player.Name .. " purchased dev product " .. tostring(productId))
    return true
  end,
}

-- ========== Definitions ========== --
local defs: { devProducts: { [string]: DevProductPrivate } } = {
  devProducts = {
    
  },
}

return defs
