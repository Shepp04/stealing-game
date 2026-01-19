--!strict
-- TransitionController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Components
local SpotlightComponent = require(script.Parent.Parent.Components:WaitForChild("Spotlight"))

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

export type TransitionControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: TransitionControllerAPI, deps: Deps) -> (),
	Start: (self: TransitionControllerAPI) -> (),
	Destroy: (self: TransitionControllerAPI) -> (),
}

local TransitionController = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Controllers = {} :: ControllerRegistry,
} :: TransitionControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Life Cycle ========== --

function TransitionController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Create a spotlight component
	self._spotlight = SpotlightComponent.new()
	
	-- // Get remotes
	self._transitionRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "Transition") :: RemoteEvent
end

function TransitionController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Connect remotes
	table.insert(self._conns, self._transitionRemote.OnClientEvent:Connect(function(...)
		self._spotlight:Transition(...)
	end))
end

function TransitionController:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return TransitionController :: TransitionControllerAPI
