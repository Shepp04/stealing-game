--!strict
-- Stealing (Util)
export type StealingAPI = {}

local Stealing = {}

function Stealing.getStealableItemsByTier(items: { [string]: any }): { [number]: any }
    if not items then warn("No items provided to getStealableItemsByTier"); return {} end

    local itemsByTier: { [number]: { any } } = {}
    for itemId, itemInfo in items do
        local tier = itemInfo.tier
        if itemsByTier[tier] then
            -- Collision
            warn("Collision detected for tier:", tier, "itemId:", itemId, ". Only one item per tier is allowed.")
            continue
        end
        itemsByTier[tier] = itemInfo
    end
    return itemsByTier
end

return Stealing :: StealingAPI
