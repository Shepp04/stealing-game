--!strict
-- HeldItemUpgradeStand (Component)

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)
local StealingUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Stealing"))
local CurrencyUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Currency"))

-- // Custom types

-- // Type aliases for deps inferred from real modules
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

export type HeldItemUpgradeStandAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: HeldItemUpgradeStandAPI) -> (),
	Destroy: (self: HeldItemUpgradeStandAPI) -> (),
}

export type Opts = {
	model: Model,
}

local HeldItemUpgradeStand = {}
HeldItemUpgradeStand.__index = HeldItemUpgradeStand

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function HeldItemUpgradeStand.new(deps: Deps, opts: Opts): HeldItemUpgradeStandAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, HeldItemUpgradeStand) :: HeldItemUpgradeStandAPI
	
	self.model = opts.model
	
	return self
end

-- ========== Helpers ========== --

function HeldItemUpgradeStand:GetHeldItemIdFromTier(tier: number): string
	-- NOTE: .GetDataType just returns the itemId: itemInfo dict on the client
	-- no items sub table!
	local items = _deps.GameData.GetDataType("StealableItem")
	local itemsByTier = StealingUtils.getStealableItemsByTier(items)
	if not itemsByTier then return nil end

	local itemInfo = itemsByTier[tier]
	return itemInfo and itemInfo.id or nil
end

-- ========== Public API ========== --

function HeldItemUpgradeStand:SetDisplay(targetTier: number)
	local heldItemId = self:GetHeldItemIdFromTier(targetTier)
	if not heldItemId or not _deps.GameData.Get("StealableItem", heldItemId) then
		-- Nothing to display e.g. max level
		self:ClearDisplay("[Max Tier]")
		return
	end

	local heldItemInfo = _deps.GameData.Get("StealableItem", heldItemId)
	if not heldItemInfo then return end

	-- Display the price
	local currencyData = heldItemInfo.currencyData
	if not currencyData then
		-- Can't be bought
		self:ClearDisplay("[N/A]")
		return
	end

	local price = currencyData.buyPrice or 0
	local currencyId = currencyData.currencyId or "Cash"
	local currencyInfo = _deps.GameData.Get("Currency", currencyId)

	self._headingLabel.Text = "UPGRADE"

	if currencyInfo and currencyInfo.icon then
		self._currencyIcon.Image = currencyInfo.icon
		self._currencyIcon.Visible = true
		self._priceLabel.Text = CurrencyUtils.GetCurrencyText(currencyId, price, false)
	else
		self._currencyIcon.Image = ""
		self._currencyIcon.Visible = false
		self._priceLabel.Text = CurrencyUtils.GetCurrencyText(currencyId, price, true)
	end
end

function HeldItemUpgradeStand:ClearDisplay(msg: string?)
	self._priceLabel.Text = ""
	self._currencyIcon.Visible = false
	self._headingLabel.Text = msg or ""
end

-- ========== Internal ========== --

function HeldItemUpgradeStand:_onTrigger()
	-- Request self upgrade
	self._selfUpgradeHeldItemRemote:FireServer()
end

-- ========== Life Cycle ========== --

function HeldItemUpgradeStand:Init()
	if self._inited then return end
	self._inited = true

	-- // Get remotes
	self._selfUpgradeHeldItemRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "SelfUpgradeHeldItem") :: RemoteEvent

	-- Validate model
	self._trigger = self.model:FindFirstChild("Trigger")

	local gui = self.model:FindFirstChildOfClass("BillboardGui")
	self._headingLabel = GuiRefs.Get(gui, { "Frame", "Heading" })
	self._priceLabel = GuiRefs.Get(gui, { "Frame", "Price", "Price" })
	self._currencyIcon = GuiRefs.Get(gui, { "Frame", "Price", "Icon" })
	
	-- Create a proximity prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.RequiresLineOfSight = false
	prompt.ActionText = "Upgrade"
	prompt.Parent = self._trigger

	-- // Bind connections
	table.insert(self._conns, prompt.Triggered:Connect(function(player: Player)
		if not player == Players.LocalPlayer then return end
		self:_onTrigger()
	end))
end

function HeldItemUpgradeStand:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return HeldItemUpgradeStand :: HeldItemUpgradeStandAPI
