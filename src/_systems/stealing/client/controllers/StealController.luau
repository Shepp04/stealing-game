--!strict
-- StealController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Types (generated)
local ControllersTypes = require(ReplicatedStorage.Shared.Types.Controllers)

-- // Type aliases for deps inferred from real modules
type ControllerRegistry = ControllersTypes.Registry

type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	ReplicatedData: ReplicatedData,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type StealControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: StealControllerAPI, deps: Deps) -> (),
	Start: (self: StealControllerAPI) -> (),
	Destroy: (self: StealControllerAPI) -> (),
}

local StealController = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Controllers = {} :: ControllerRegistry,
} :: StealControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Life Cycle ========== --

function StealController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Example: get remotes / find UI elements
end

function StealController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Example: connect remotes, bind UI, start loops, etc.
	table.insert(self._conns, _deps.ReplicatedData.OnUpdate.Event:Connect(function(category: string, data: any)
		if category == "Stealing" then
			local currentTier = data.currentTier :: number?
			print("[StealController] Received updated stealing data. Current tier:", currentTier)
		end
	end))
end

function StealController:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return StealController :: StealControllerAPI
