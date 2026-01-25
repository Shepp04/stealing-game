--!strict
-- StealingService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local Players = game:GetService("Players")
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

export type StealingServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: StealingServiceAPI, deps: Deps) -> (),
	Start: (self: StealingServiceAPI) -> (),
	Destroy: (self: StealingServiceAPI) -> (),
}

local StealingService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- // Assets
local Assets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets")
local SAMPLE_TIER_GUI = Assets:WaitForChild("UI"):WaitForChild("TierGui")

-- ========== Public API ========== --

function StealingService:GetPlayerTier(player: Player): number?
	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile then return nil end

	local stealingData = profile.Data.Stealing
	return stealingData.currentTier
end

function StealingService:SetPlayerTier(player: Player, tier: number)
	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile then return end

	local stealingData = profile.Data.Stealing
	stealingData.currentTier = tier

	if tier > 0 then
		print("[StealingService] Set player", player.UserId, "to tier", tier)
	else
		print("[StealingService]", player.UserId, " lost their tier!")
	end

	-- Update the player's overhead Gui
	self:UpdatePlayerTierGui(player)
end

function StealingService:ExchangeTiers(winner: Player, loser: Player)
	-- Get both player's tiers
	local winnerTier = self:GetPlayerTier(winner) or 0
	local loserTier = self:GetPlayerTier(loser) or 0

	-- Exchange tiers
	if winnerTier < loserTier then
		-- Only exchange if winner has lower tier than loser
		self:SetPlayerTier(winner, loserTier)
	elseif winnerTier == loserTier then
		-- If tiers are equal, increment winner's tier by 1
		self:SetPlayerTier(winner, winnerTier + 1)
	else
		-- Winner already has higher tier, give cash reward instead
	end

	-- Reset the loser's tier to 0
	self:SetPlayerTier(loser, 0)
end

function StealingService:UpdatePlayerTierGui(player: Player)
	local tier = self:GetPlayerTier(player) or 0
	local char = player.Character
	local gui = char and char:FindFirstChild("_CurrentTier") :: BillboardGui?
	if gui then
		local frame = gui:FindFirstChild("Frame") :: Frame?
		local tierLabel = frame and frame:FindFirstChild("CurrentTier") :: TextLabel?
		if tierLabel then
			if tier > 0 then
				tierLabel.Text = tostring(tier)
			else
				tierLabel.Text = "0"
			end
		end
	end
end

-- ========== Player Life Cycle ========== --

function StealingService:OnCharacterAdded(player: Player, char: Model)
	-- Create or update the overhead Gui
	local gui = char:FindFirstChild("_CurrentTier") :: BillboardGui?
	if not gui then
		gui = SAMPLE_TIER_GUI:Clone()
		gui.Name = "_CurrentTier"
		gui.Adornee = char:FindFirstChild("Head") :: BasePart
		gui.Parent = char
	end
	self:UpdatePlayerTierGui(player)
end

function StealingService:OnPlayerAdded(player: Player)
	self._playerConns = self._playerConns or {}
	self._playerConns[player.UserId] = {}

	local char = player.Character or player.CharacterAdded:Wait()
	self:OnCharacterAdded(player, char)
	table.insert(self._playerConns[player.UserId], player.CharacterAdded:Connect(function(character: Model)
		self:OnCharacterAdded(player, character)
	end))
end

function StealingService:OnPlayerRemoving(player: Player)
	if self._playerConns and self._playerConns[player.UserId] then
		for _, conn in self._playerConns[player.UserId] do
			pcall(function() conn:Disconnect() end)
		end
		self._playerConns[player.UserId] = nil
	end
end

-- ========== Life Cycle ========== --

function StealingService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Example: get/create remotes
end

function StealingService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Register reconcile section
	_deps.DataInterface:RegisterReconcileSection("Data", "Stealing", {
		currentTier = nil :: number?,
	})

	-- // Connect player life cycle
	for _, plr in Players:GetPlayers() do
		self:OnPlayerAdded(plr)
	end
	table.insert(self._conns, Players.PlayerAdded:Connect(function(player: Player)
		self:OnPlayerAdded(player)
	end))

	table.insert(self._conns, Players.PlayerRemoving:Connect(function(player: Player)
		self:OnPlayerRemoving(player)
	end))
end

function StealingService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return StealingService :: StealingServiceAPI
