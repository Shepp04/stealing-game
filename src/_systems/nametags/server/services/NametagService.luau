--!strict

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- // Assets
local UIAssets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UI")
local SampleNametag = UIAssets:WaitForChild("Nametag")

export type Deps = {
    DataInterface: {
        GetPlayerProfile: (player: Player, yield: boolean?) -> any,
        RegisterReconcileSection: (sectionType: "Info" | "Data", sectionName: string, template: {}) -> boolean,
    },
    SharedPackages: any,
    GameData: any,
    Monetisation: any,
    Config: any,
}

export type NametagService = {
    _inited: boolean,
    _started: boolean,
    _conns: { RBXScriptConnection },

    Init: (self: NametagService, deps: Deps) -> (),
    Start: (self: NametagService) -> (),
    Destroy: (self: NametagService) -> (),
}

local NametagService = {
    _inited = false,
    _started = false,
    _conns = {},
    Priority = 50, -- start early
    Services = nil :: any -- auto-filled by bootstrapper
}

-- // Private State
local _deps: Deps?

-- ========== Public API ========== --
function NametagService:Update(player: Player, char: Model?)
    -- Use the provided character model or Find the player's character
    local char = char or player.Character
    local nametag = char and char:FindFirstChild("_Nametag") :: BillboardGui
    if not nametag then
        -- Create a new nametag if it doesn't exist
        nametag = SampleNametag:Clone()
        nametag.Name = "_Nametag"
        nametag.Parent = char
        nametag.Adornee = char:FindFirstChild("Head")
    end

    -- Set display name
    local playerNameLabel = nametag:FindFirstChild("Frame"):FindFirstChild("PlayerName") :: TextLabel
    if playerNameLabel then
        local nameText = player.DisplayName

        -- Add country flag if available
        local SocialUtilModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):FindFirstChild("Social")
        if SocialUtilModule then
            local SocialUtil = require(SocialUtilModule)
            local _, _, countryFlag = SocialUtil.GetCountryCodeNameAndFlagForPlayer(player)
            if countryFlag then
                nameText = countryFlag .. " " .. nameText
            end
        end

        playerNameLabel.Text = nameText
    end
end

-- ========== Internal ========== --

function NametagService:_onCharacterAdded(player: Player, char: Model)
    local human = char:WaitForChild("Humanoid") :: Humanoid
    human.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

    local head = char:WaitForChild("Head") :: BasePart
    local root = char:WaitForChild("HumanoidRootPart") :: BasePart

    -- Update their nametag
    self:Update(player)
end

function NametagService:_onPlayerAdded(player: Player)
    local char = player.Character or player.CharacterAdded:Wait()
    self:_onCharacterAdded(player, char)

    player.CharacterAdded:Connect(function(...)
        self:_onCharacterAdded(player, ...)
    end)
end

-- ========== Life Cycle ========== --
function NametagService:Init(deps: Deps)
    if self._inited then return end
    self._inited = true
    _deps = deps

    self._conns = {}
end

function NametagService:Start()
    if not self._inited or self._started then return end
    self._started = true

    -- // Example: connect remotes
    for _, plr in Players:GetPlayers() do
        self:_onPlayerAdded(plr)
    end
    table.insert(self._conns, Players.PlayerAdded:Connect(function(...)
        self:_onPlayerAdded(...)
    end))
end

function NametagService:Destroy()
    for _, c in self._conns do c:Disconnect() end
    table.clear(self._conns)
    _deps = nil
    self._started = false
    self._inited = false
end

return NametagService