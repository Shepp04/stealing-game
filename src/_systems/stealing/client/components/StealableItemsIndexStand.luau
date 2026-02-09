--!strict
-- StealableItemsIndexStand (Component)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)
local StealingUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Stealing"))
local CurrencyUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Currency"))

-- // Custom types
type DisplayedItem = {
	id: string,
	model: Model,
}

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

export type StealableItemsIndexStandAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: StealableItemsIndexStandAPI) -> (),
	Destroy: (self: StealableItemsIndexStandAPI) -> (),
}

export type Opts = {
	model: Model,
	base: BasePart,
	numItems: number,
}

local StealableItemsIndexStand = {}
StealableItemsIndexStand.__index = StealableItemsIndexStand

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function StealableItemsIndexStand.new(deps: Deps, opts: Opts): StealableItemsIndexStandAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, StealableItemsIndexStand) :: StealableItemsIndexStandAPI
	
	self._opts = opts
	self.model = opts.model
	self.base = opts.base
	self.numItems = opts.numItems

	self._items = {} :: { [number]: DisplayedItem }

	return self
end

-- ========== Public API ========== --

function StealableItemsIndexStand:AddItem(stealableItemId: string)
	-- Check that an unfilled position exists
	pos = nil
	for i = 1, self.numItems do
		if self._items[i] == nil then
			pos = i
			break
		end
	end

	if not pos then
		-- Stand is full
		warn(`[StealableItemsIndexStand] {self.model} is full!`)
		return
	end

	-- Get info
	local stealableItemInfo = _deps.GameData.Get("StealableItem", stealableItemId)
	if not stealableItemInfo then
		return
	end

	-- Clone the model and create a stand
	local model = StealingUtils.getStealableItemModelFromPath(stealableItemInfo.modelPath or {})
	if not model then return end
	model = model:Clone()

	local stand = Instance.new("Model")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.CFrame = model:GetPivot()
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Anchored = true

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = false
			d.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = d
			weld.Part1 = handle
			weld.Parent = d
		end
	end
	
	model:ScaleTo(1.5)
	model.Parent = stand
	handle.Parent = stand
	stand.PrimaryPart = handle

	-- Create a gui
	local indexGui, infoGui = self:_createTierGuis(stealableItemId)
	if indexGui and infoGui then
		indexGui.Adornee = handle
		indexGui.Parent = stand
		infoGui.Adornee = handle
		infoGui.Parent = stand
	end

	-- Pivot and parent the stand
	stand:PivotTo(self:_getCFrameFromIndex(pos))
	stand.Parent = self.model

	local displayedItem: DisplayedItem = {
		id = stealableItemId,
		model = stand,
	}

	self._items[pos] = displayedItem
end

-- ========== Internal ========== --

function StealableItemsIndexStand:_getCFrameFromIndex(index: number)
	-- Space equally
	local length = self.base.Size.X
	local x = (index - 1) / self.numItems
	return self.base.CFrame * CFrame.new(x * length - (length / 2), 2.5, 0)
end

function StealableItemsIndexStand:_createTierGuis(stealableItemId: string): (BillboardGui?, BillboardGui?)
	-- Get info
	local stealableItemInfo = _deps.GameData.Get("StealableItem", stealableItemId)
	if not stealableItemInfo then return end

	local indexGui = Instance.new("BillboardGui")
	indexGui.Name = "Index"
	indexGui.Size = UDim2.fromScale(2, 2)
	indexGui.AlwaysOnTop = false
	indexGui.LightInfluence = 0
	indexGui.StudsOffset = Vector3.new(0, 4.5, 0)
	indexGui.ClipsDescendants = false

	local indexLabel = Instance.new("TextLabel")
	indexLabel.Name = "ItemIndex"
	indexLabel.LayoutOrder = 0
	indexLabel.Size = UDim2.fromScale(1, 1)
	indexLabel.Font = Enum.Font.FredokaOne
	indexLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	indexLabel.TextScaled = true
	indexLabel.Text = stealableItemInfo.tier and tostring(stealableItemInfo.tier) or ""
	indexLabel.BackgroundTransparency = 1
	indexLabel.Parent = indexGui

	local infoGui = Instance.new("BillboardGui")
	infoGui.Name = "Info"
	infoGui.Size = UDim2.fromScale(3.5, 2) -- UDim2.fromScale(6.4, 2.4)
	infoGui.AlwaysOnTop = false
	infoGui.LightInfluence = 0
	infoGui.StudsOffset = Vector3.new(0, 2.5, 0)
	infoGui.ClipsDescendants = false

	local UIListLayout = Instance.new("UIListLayout")
	UIListLayout.Parent = infoGui

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.LayoutOrder = 0
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.Font = Enum.Font.BuilderSansBold
	nameLabel.TextScaled = true
	nameLabel.BackgroundTransparency = 1
	nameLabel.Parent = infoGui

	local nameUIStroke = Instance.new("UIStroke")
	nameUIStroke.Thickness = 2.5
	nameUIStroke.Parent = nameLabel

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "ItemValue"
	valueLabel.LayoutOrder = 1
	valueLabel.Size = UDim2.fromScale(1, 0.4)
	valueLabel.Font = Enum.Font.BuilderSansBold
	valueLabel.TextScaled = true
	valueLabel.BackgroundTransparency = 1
	valueLabel.Parent = infoGui

	local valueUIStroke = Instance.new("UIStroke")
	valueUIStroke.Thickness = 2.5
	valueUIStroke.Parent = valueLabel

	-- Set text
	nameLabel.Text = stealableItemInfo.name

	local itemCurrencyData = stealableItemInfo.currencyData
	if itemCurrencyData and itemCurrencyData.winAmount and itemCurrencyData.winCurrencyId then
		valueLabel.Text = "$" .. CurrencyUtils.GetCurrencyText(itemCurrencyData.winCurrencyId, itemCurrencyData.winAmount, false) .. " per win"
	else
		valueLabel.Text = "Tier " .. tostring(stealableItemInfo.tier or 0)
	end

	if stealableItemInfo.textData then
		nameLabel.TextColor3 = stealableItemInfo.textData.primaryColor or Color3.fromRGB(255, 255, 255)
		valueLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
		-- valueLabel.TextColor3 = stealableItemInfo.textData.secondaryColor or Color3.fromRGB(0, 255, 0)
	end

	return indexGui, infoGui
end

-- ========== Life Cycle ========== --

function StealableItemsIndexStand:Init()
	if self._inited then return end
	self._inited = true

	-- // Create models for each stealable item
	local items = _deps.GameData.GetDataType("StealableItem")

	-- Sort by tier
	local sortedItems = {}
	for id, info in items do
		table.insert(sortedItems, info)
	end
	table.sort(sortedItems, function(a, b)
		local aTier = a.tier or 0
		local bTier = b.tier or 0

		if aTier == bTier then
			local aPrice = a.currencyData and a.currencyData.buyPrice or 0
			local bPrice = b.currencyData and b.currencyData.buyPrice or 0
			return aPrice < bPrice
		else
			return aTier < bTier
		end
	end)
	
	for i, stealableItemInfo in sortedItems do
		self:AddItem(stealableItemInfo.id)
	end
end

function StealableItemsIndexStand:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return StealableItemsIndexStand :: StealableItemsIndexStandAPI
