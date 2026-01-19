--!strict
-- SocialService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types (generated)
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps inferred from real modules
type ServiceRegistry = ServicesTypes.Registry

type DataInterface  = ServicesTypes.DataInterface
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	DataInterface: DataInterface,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type SocialServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: SocialServiceAPI, deps: Deps) -> (),
	Start: (self: SocialServiceAPI) -> (),
	Destroy: (self: SocialServiceAPI) -> (),
}

local SocialService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- // Constants
local GROUP_ID = 1234567 -- replace with actual group ID
local FALLBACK_GROUP_REWARDS: { [number]: { ({ currencyId: string, amount: number } | (player: Player) -> boolean) } } =
{
	[1] = {
		{ currencyId = "Coins", amount = 100 },
		function(player: Player)
			print("Custom reward function executed for player:", player.Name)
			return true
		end,
	}, -- [version] = { currencyRecord or custom function }
}

-- ========== Public API ========== --

function SocialService:ClaimGroupReward(player: Player, groupRewardId: number?): boolean
	-- Default groupRewardId to 1 if not provided (version)
	groupRewardId = groupRewardId or 1

	-- First, get their profile
	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile or not profile.Data or not profile.Data.Social then
		return false
	end

	-- Then, check if they have already claimed the reward
	local claimedRewards = profile.Data.Social.ClaimedGroupRewards or {}
	if claimedRewards[groupRewardId] then
		-- Already claimed
		_deps.SharedPackages.Messages:ShowMessage(player, "You have already claimed this group reward!", "Error")
		return false
	end

	-- Now, check if they are in the group
	if not player:IsInGroup(GROUP_ID) then
		_deps.SharedPackages.Messages:ShowMessage(player, "You must be in the group to claim this reward!", "Error")
		return false
	end

	-- Grant the reward (example: give in-game currency)
	local ok, err = pcall(function()
		local groupRewards = _deps.Tunables and _deps.Tunables.groupRewards or {}
		local rewardInfo = groupRewards[groupRewardId] or FALLBACK_GROUP_REWARDS[groupRewardId]
		if rewardInfo then
			for _, reward in rewardInfo do
				if typeof(reward) == "function" then
					local success = reward(player)
					if not success then
						error("Custom reward function failed for player: " .. player.Name)
					end
				elseif typeof(reward) == "table" then
					local currencyId = reward.currencyId
					local amount = reward.amount
					local success, _ = self.Services.CurrencyService:GiveCurrency(player, currencyId, amount)
					if not success then
						error("Failed to give currency reward to player: " .. player.Name)
					end
				end
			end
		end
	end)

	if not ok then
		warn("[SocialService] Failed to grant group reward:", err)
		_deps.SharedPackages.Messages:ShowMessage(player, "Failed to claim group reward. Please try again later.", "Error")
		return false
	end

	-- Mark the reward as claimed
	claimedRewards[groupRewardId] = true
	profile.Data.Social.ClaimedGroupRewards = claimedRewards

	_deps.SharedPackages.Messages:ShowMessage(player, "Group reward claimed successfully!", "Success")

	return true -- Success
end

-- ========== Life Cycle ========== --

function SocialService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Pull from tunables if available
	GROUP_ID = _deps.Tunables and _deps.Tunables.groupId or GROUP_ID
	
	-- // Register reconcile section
	_deps.DataInterface:RegisterReconcileSection("Data", "Social", {
		ClaimedGroupRewards = {},
	})

	-- // Create remotes
	self._claimGroupRewardRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "ClaimGroupReward") :: RemoteEvent
end

function SocialService:Start()
	if not self._inited or self._started then return end
	self._started = true
	
	-- // Connect remotes
	table.insert(self._conns, self._claimGroupRewardRemote.OnServerEvent:Connect(function(player: Player, groupRewardId: number?)
		self:ClaimGroupReward(player, groupRewardId)
	end))
end

function SocialService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return SocialService :: SocialServiceAPI
