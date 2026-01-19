--!strict
-- MenuService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- // Classes
local MenuStand = require(ReplicatedStorage.Shared.Classes:WaitForChild("MenuStand"))

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

export type MenuServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: MenuServiceAPI, deps: Deps) -> (),
	Start: (self: MenuServiceAPI) -> (),
	Destroy: (self: MenuServiceAPI) -> (),

	OpenMenuForPlayer: (self: MenuServiceAPI, player: Player, menuName: string) -> (),
	CloseMenuForPlayer: (self: MenuServiceAPI, player: Player, menuName: string) -> (),
}

local MenuService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Public ========== --

function MenuService:OpenMenuForPlayer(player: Player, menuName: string)
	if not self._started or not _deps then return end
	self._openMenuRemote:FireClient(player, menuName)
end

function MenuService:CloseMenuForPlayer(player: Player, menuName: string)
	if not self._started or not _deps then return end
	self._closeMenuRemote:FireClient(player, menuName)
end

-- ========== Life Cycle ========== --

function MenuService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Example: get/create remotes
	self._openMenuRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "OpenMenu") :: RemoteEvent
	self._closeMenuRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "CloseMenu") :: RemoteEvent
end

function MenuService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Example: connect remotes, start loops, etc.

	-- Set up menu stands
	for _, standModel in CollectionService:GetTagged("MenuStand") do
		local menuName = standModel:GetAttribute("MenuName")
		local useProximityPrompt = standModel:GetAttribute("UseProximityPrompt")

		local stand = MenuStand.new(_deps, { model = standModel, menuName = menuName, useProximityPrompt = useProximityPrompt })
		stand:Init()
	end

	CollectionService:GetInstanceAddedSignal("MenuStand"):Connect(function(standModel)
		local menuName = standModel:GetAttribute("MenuName")
		local useProximityPrompt = standModel:GetAttribute("UseProximityPrompt")

		local stand = MenuStand.new(_deps, { model = standModel, menuName = menuName, useProximityPrompt = useProximityPrompt })
		stand:Init()
	end)
end

function MenuService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return MenuService :: MenuServiceAPI
