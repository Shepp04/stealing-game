--!strict
-- MonetisationController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils:WaitForChild("GuiRefs"))

-- // Components
local ProductShop = require(script.Parent.Parent.Components:WaitForChild("ProductShop"))
-- local StarterPack = require(script.Parent.Parent.Components:WaitForChild("StarterPack"))

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

export type MonetisationControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: MonetisationControllerAPI, deps: Deps) -> (),
	Start: (self: MonetisationControllerAPI) -> (),
	Destroy: (self: MonetisationControllerAPI) -> (),
}

local MonetisationController = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Controllers = {} :: ControllerRegistry,
} :: MonetisationControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Life Cycle ========== --

function MonetisationController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Get Gui elements
	local PlayerGui = GuiRefs.GetPlayerGui(Players.LocalPlayer)
	local ProductShopGui = GuiRefs.GetScreenGui(PlayerGui, "ProductShop")

	-- // Create components
	self._productShop = ProductShop.new(_deps, {
		root = ProductShopGui,
		container = GuiRefs.Get(ProductShopGui, { "ProductShop", "Frame" }),
	})
	-- self._starterPack = StarterPack.new(_deps, { saleDuration = 24*60*60 })
end

function MonetisationController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Init components
	self._productShop:Init()
	-- self._starterPack:Init()
end

function MonetisationController:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return MonetisationController :: MonetisationControllerAPI
