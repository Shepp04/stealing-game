--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type DevProductPrivate = Types.DevProductPrivate
type Handler = Types.Handler

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
  ["KeepIt"] = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
    -- Find the last item they lost
    local profile = deps.DataInterface:GetPlayerProfile(player)
    if not profile then
      warn("[DevProduct | KeepIt] Unable to find profile for", player)
      return false
    end

    if not profile.Data or not profile.Data.Stealing then
      return false
    end

    local lastItemLost = profile.Data.Stealing.lastItemLost
    local itemId = lastItemLost and lastItemLost.itemId
    local timestamp = lastItemLost and lastItemLost.timestamp

    if not itemId or not timestamp then
      warn("[DevProduct | KeepIt]", player, "has not lost an item yet!")
      return false
    end

    -- Check that they aren't already this item
    if profile.Data.Stealing.heldItemId == itemId then
      warn("[DevProduct | KeepIt]", player, "still has heldItemId =", itemId)
      return false
    end

    -- Check time since losing the item
    local now = os.clock()
    if (now - timestamp) > 600 then
      warn("[DevProduct | KeepIt]", player, "lost the item over 10 mins ago!")
      return false
    end

    -- Check that the item exists
    local stealableItemInfo = deps.GameData.Get("StealableItem", itemId)
    if not stealableItemInfo then
      warn("[DevProduct | KeepIt] No stealable item found with id:", itemId)
    end

    -- Give them this item back
    local StealingService = deps.Services.StealingService
    StealingService:SetPlayerHeldItemId(player, itemId)

    -- Clear their last item lost
    profile.Data.Stealing.lastItemLost = nil

    return true
  end,
}

-- ========== Definitions ========== --
local defs: { devProducts: { [string]: DevProductPrivate } } = {
  devProducts = {
    ["KeepIt"] = {
      id = 3531897082,
      name = "KEEP IT",
      category = "Gameplay",
      description = nil, -- hydrated later
      priceInRobux = nil, -- hydrated later
      iconImageAssetId = nil, -- hydrated later
      handler = Handlers.KeepIt,
      params = { },
    }
  },
}

return defs
