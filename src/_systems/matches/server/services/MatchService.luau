--!strict
-- MatchService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Classes
local MatchTable = require(ServerScriptService.Server.Classes:WaitForChild("MatchTable"))
type MatchTableAPI = typeof(MatchTable.new())

local GameClass = require(ServerScriptService.Server.Classes:WaitForChild("Game"))
type GameAPI = typeof(GameClass.new())

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

export type MatchServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: MatchServiceAPI, deps: Deps) -> (),
	Start: (self: MatchServiceAPI) -> (),
	Destroy: (self: MatchServiceAPI) -> (),
}

local MatchService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Public API ========== --

function MatchService:LeaveMatch(player: Player)
	for _, t in self._matchTables do
		if t:HasPlayer(player) then
			t:Leave(player)
		end
	end
end

function MatchService:OnCharacterAdded(player: Player, char: Model)
	local human = char:WaitForChild("Humanoid") :: Humanoid
	human.Died:Connect(function()
		self:LeaveMatch(player)
	end)
end

function MatchService:OnPlayerAdded(player: Player)
	local char = player.Character or player.CharacterAdded:Wait()
	self:OnCharacterAdded(player, char)

	player.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(player, character)
	end)
end

-- ========== Internal ========== --

function MatchService:_onTutorialComplete(player: Player)
	local profile = _deps.DataInterface:GetPlayerProfile(player, true)
	if not profile then return end
	
	profile.Data.Analytics.TutorialComplete = true
end

-- ========== Life Cycle ========== --

function MatchService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Create Remotes
	self._leaveMatchRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "LeaveMatch") :: RemoteEvent
	self._tutorialCompleteRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "TutorialComplete") :: RemoteEvent

	-- // Create match table instances
	self._matchTables = {}
	for _, v in CollectionService:GetTagged("MatchTable") do
		local object = MatchTable.new(_deps, {
			tableInstance = v,
			gameClass = GameClass,
			minPlayers = 2,
			maxPlayers = 2,
		})
		table.insert(self._matchTables, object)
	end

	CollectionService:GetInstanceRemovedSignal("MatchTable"):Connect(function(model)
		local t = MatchTable.ActiveTables[model]
		if t then
			t:Destroy()
			MatchTable.ActiveTables[model] = nil
		end
	end)
end

function MatchService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Connect remotes
	table.insert(self._conns, self._leaveMatchRemote.OnServerEvent:Connect(function(...)
		self:LeaveMatch(...)
	end))
	table.insert(self._conns, self._tutorialCompleteRemote.OnServerEvent:Connect(function(...)
		self:_onTutorialComplete(...)
	end))

	-- // Init match tables
	for _, matchTable in self._matchTables do
		matchTable:Init()
	end

	-- // Connect player lifecycle
	for _, plr in Players:GetPlayers() do
		self:OnPlayerAdded(plr)
	end
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:LeaveMatch(player)
	end)
end

function MatchService:Destroy()
	-- // Destroy match tables
	for _, matchTable in self._matchTables do
		matchTable:Destroy()
	end
	table.clear(self._matchTables)

	-- // Disconnect connections
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return MatchService :: MatchServiceAPI
