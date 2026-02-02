--!strict
-- StealController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils:WaitForChild("GuiRefs"))

-- // Components
local StealResultDisplay = require(script.Parent.Parent.Components:WaitForChild("StealResultDisplay"))
local HeldItemUpgradeStand = require(script.Parent.Parent.Components:WaitForChild("HeldItemUpgradeStand"))

-- // Types (custom)
type StealResult = {
	opponentUserId: number,
	success: boolean,
	opponentOldHeldItemId: string,
	opponentNewHeldItemId: string,
	oldHeldItemId: string,
	newHeldItemId: string
}

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

-- ========== Internal ========== --

function StealController:_onStealResultReceived(result: StealResult)
	-- Unpack result
	local opponentUserId = result.opponentUserId
	local success = result.success
	local opponentOldHeldItemId = result.opponentOldHeldItemId
	local opponentNewHeldItemId = result.opponentNewHeldItemId
	local oldHeldItemId = result.oldHeldItemId
	local newHeldItemId = result.newHeldItemId

	-- Get item info
	local opponentOldHeldItemInfo = _deps.GameData.Get("StealableItem", opponentOldHeldItemId)
	local oldHeldItemInfo = _deps.GameData.Get("StealableItem", oldHeldItemId)
	local newHeldItemInfo = _deps.GameData.Get("StealableItem", newHeldItemId)
	if not opponentOldHeldItemInfo or not oldHeldItemInfo or not newHeldItemInfo then
		warn("[StealController] missing item info for ids:", opponentOldHeldItemId, oldHeldItemId, newHeldItemId)
		return
	end

	if success then
		self._stealResultDisplay:SetHeading("You stole their " .. opponentOldHeldItemInfo.name)
		self._stealResultDisplay:SetCloseButtonText("Take it")
		self._stealResultDisplay:SetCloseButtonColor(Color3.fromRGB(46, 255, 0))
		self._stealResultDisplay:SetRestoreButtonVisible(false)
	else
		self._stealResultDisplay:SetHeading("They stole your " .. oldHeldItemInfo.name)
		self._stealResultDisplay:SetCloseButtonText("Ok :(")
		self._stealResultDisplay:SetCloseButtonColor(Color3.fromRGB(246, 16, 0))
		self._stealResultDisplay:SetRestoreButtonVisible(true)
	end
	self._stealResultDisplay:SetSubheading("You are now " .. newHeldItemInfo.name .. " level")

	-- Show
	self._stealResultDisplay:SetVisible(true)
end

function StealController:_onStealingDataChanged(data: { heldItemId: string, seenItems: { [string]: { firstSeenAt: number, timesSeen: number, } } })
	-- Get held item id
	local heldItemId = data.heldItemId

	-- Get tier from item
	local heldItemInfo = _deps.GameData.Get("StealableItem", heldItemId)
	local tier = heldItemInfo and heldItemInfo.tier or 0

	-- Refresh upgrade stand(s)
	if self._upgradeStands then
		for model, object in self._upgradeStands do
			object:SetDisplay(tier + 1)
		end
	end
end

-- ========== Life Cycle ========== --

function StealController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Get Gui refs
	local PlayerGui = GuiRefs.GetPlayerGui(Players.LocalPlayer)
	local StealResultGui = GuiRefs.GetScreenGui(PlayerGui, "StealResult")

	-- // Create a steal result display
	self._stealResultDisplay = StealResultDisplay.new(_deps, {
		root = StealResultGui,
		container = GuiRefs.Get(StealResultGui, { "StealResult", "Frame" }),

		heading = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Top", "Heading" }),
		subheading = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Middle", "Subheading" }),
		
		closeButton = {
			container = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Bottom", "Close" }),
			text = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Bottom", "Close", "Button", "TextLabel" }),
			select = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Bottom", "Close", "Select" }),
		},

		restoreButton = {
			container = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Bottom", "Restore" }),
			text = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Bottom", "Restore", "Button", "TextLabel" }),
			select = GuiRefs.Get(StealResultGui, { "StealResult", "Frame", "Bottom", "Restore", "Select" }),
		},
	})

	-- // Initialise upgrade stand dict
	self._upgradeStands = {}

	-- // Get remotes
	self._stealResultRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "StealResult") :: RemoteEvent
end

function StealController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Connect remotes
	table.insert(self._conns, self._stealResultRemote.OnClientEvent:Connect(function(...)
		self:_onStealResultReceived(...)
	end))

	-- // Connect listeners
	table.insert(self._conns, _deps.ReplicatedData.OnUpdate.Event:Connect(function(category: string, data: any)
		if category == "Stealing" then
			local heldItemId = data.heldItemId :: number?
			print("[StealController] Received updated stealing data. Current item:", heldItemId)
			
			self:_onStealingDataChanged(data)
		end
	end))

	-- // Init results component
	self._stealResultDisplay:Init()

	-- // Setup upgrade stand(s)
	for _, v in CollectionService:GetTagged("HeldItemUpgradeStand") do
		local object = HeldItemUpgradeStand.new(_deps, {
			model = v,
		})
		object:Init()
		self._upgradeStands[v] = object
	end

	table.insert(self._conns, CollectionService:GetInstanceAddedSignal("HeldItemUpgradeStand"):Connect(function(v: Instance)
		local object = HeldItemUpgradeStand.new(_deps, {
			model = v,
		})
		object:Init()
		self._upgradeStands[v] = object
	end))

	table.insert(self._conns, CollectionService:GetInstanceRemovedSignal("HeldItemUpgradeStand"):Connect(function(v: Instance)
		if self._upgradeStands[v] then
			self._upgradeStands[v]:Destroy()
			self._upgradeStands[v] = nil
		end
	end))

	-- Initial data read
	local stealingData = _deps.ReplicatedData:GetData("Stealing", true)
	if stealingData then
		self:_onStealingDataChanged(stealingData)
	end
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
