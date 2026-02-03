--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Stealing (Util)
export type StealingAPI = {}

-- // Constants
local STEALABLE_ITEM_MODELS_FOLDER = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("StealableItems") :: Folder

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

function Stealing.getStealableItemModelFromPath(modelPath: { string }): Model?
    local curInstance = STEALABLE_ITEM_MODELS_FOLDER
	for _, loc in pairs(modelPath) do
		curInstance = curInstance:FindFirstChild(loc)
		if not curInstance then
			warn("[StealingService] Could not find model part at path:", table.concat(modelPath, " -> "))
			return nil
		end
	end
    return curInstance
end

return Stealing :: StealingAPI
