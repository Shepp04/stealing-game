--!strict
-- GameInput (Component)

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)

-- // Custom types
local GameTypes = require(ReplicatedStorage.Shared.Types:WaitForChild("Game"))
type GameAction = GameTypes.GameAction

type ItemObject = {
	model: Model,
	clickDetector: ClickDetector,
	isHovered: boolean,
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

export type GameInputAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: GameInputAPI) -> (),
	Destroy: (self: GameInputAPI) -> (),

	SetClickAction: (self: GameInputAPI, action: GameAction?) -> (),
	SetInputEnabled: (self: GameInputAPI, enabled: boolean) -> (),
	SetShuffleButtonVisible: (self: GameInputAPI, visible: boolean) -> (),
	SetHoverEnabled: (self: GameInputAPI, enabled: boolean) -> (),
	SetShakeEnabled: (self: GameInputAPI, enabled: boolean) -> (),
	ClearItemObjects: (self: GameInputAPI) -> (),
	CreateItemObjects: (self: GameInputAPI, itemModels: { Model }) -> { ItemObject },
	AnimateItemsIn: (self: GameInputAPI) -> (),
}

export type Opts = {
	root: ScreenGui,
	shuffleButton: { container: Instance, select: TextButton, },

	onAction: (action: GameAction, payload: { any }?) -> boolean,
}

local GameInput = {}
GameInput.__index = GameInput

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function GameInput.new(deps: Deps, opts: Opts): GameInputAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, GameInput) :: GameInputAPI

	self.onAction = opts.onAction
	if not self.onAction then
		error("GameInput requires an onAction callback")
	end

	-- // Get Gui refs
	self._root = opts.root
	self._shuffleButton = opts.shuffleButton
	if not self._root or not self._shuffleButton then
		error("GameInput requires all Gui refs to be provided")
	end

	print("GameInput created")
	
	return self
end

-- ========== Public API ========== --

function GameInput:SetClickAction(action: GameAction?)
	self._clickAction = action
end

function GameInput:SetInputEnabled(enabled: boolean)
	self._inputEnabled = enabled
	if not enabled then
		self:SetShuffleButtonVisible(false)
		self:ClearItemObjects()
	end
end

function GameInput:SetShuffleButtonVisible(visible: boolean)
	self._shuffleButton.container.Visible = visible
end

function GameInput:SetHoverEnabled(enabled: boolean)
	self._hoverEnabled = enabled
end

function GameInput:SetShakeEnabled(enabled: boolean)
	self._shakeEnabled = enabled
end

function GameInput:ClearItemObjects()
	if not self._itemObjects then return end
	for _, itemObj in pairs(self._itemObjects) do
		if itemObj.clickDetector then
			itemObj.clickDetector:Destroy()
		end
	end
	table.clear(self._itemObjects)
end

function GameInput:CreateItemObjects(itemModels: { Model }): { ItemObject }
	print("[GameInput] CreateItemObjects - creating", #itemModels, "item objects", itemModels)
	-- Clear existing
	self:ClearItemObjects()

	-- Create new
	self._itemObjects = {}
	for _, itemModel in pairs(itemModels) do
		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = 32

		local itemObject = {
			model = itemModel,
			visualModel = itemModel:FindFirstChild("Visual") :: Model?,
			clickDetector = clickDetector,
			isHovered = false,
		}
		
		-- // Handle clicks and hover
		clickDetector.MouseHoverEnter:Connect(function(player: Player)
			if player ~= Players.LocalPlayer then return end

			if self._hoverEnabled then
				self:_onItemHoverEnter(itemObject, player)
			end
			if self._shakeEnabled then
				self:_onItemShake(itemObject, player)
			end
		end)

		clickDetector.MouseHoverLeave:Connect(function(player: Player)
			if player ~= Players.LocalPlayer then return end
			self:_onItemHoverLeave(itemObject, player)
		end)

		clickDetector.MouseClick:Connect(function(player: Player)
			if player ~= Players.LocalPlayer then return end
			self:_onItemClicked(itemObject, player)
		end)

		clickDetector.Parent = itemModel
		self._itemObjects[itemModel] = itemObject
		print(clickDetector)
	end

	return self._itemObjects
end

function GameInput:AnimateItemsIn()
	-- == Temporarily disable == --
	if true then return end
	
	if not self._itemObjects then return end
	for _, itemObj in pairs(self._itemObjects) do
		local model = itemObj.model
		local visualModel = itemObj.visualModel
		if not visualModel then continue end

		-- Drop in
		local startCFrame = model:GetPivot() * CFrame.new(0, 2, 0)
		visualModel:PivotTo(startCFrame)

		task.spawn(function()
			for i = 0, 1, 0.05 do
				local t = i * i * (3 - 2 * i) -- smoothstep
				local targetCFrame = model:GetPivot()
				local interpCFrame = startCFrame:Lerp(targetCFrame, t)
				visualModel:PivotTo(interpCFrame)
				task.wait()
			end
			_deps.SharedPackages.Sounds:PlaySound("ItemLand", visualModel:GetPivot().Position)
			visualModel:PivotTo(model:GetPivot())
		end)
		task.wait(0.1)
	end
end

-- ========== Internal ========== --

function GameInput:_onItemShake(itemObject: ItemObject, player: Player)
	-- Shake the item slightly to indicate hover
	local itemModel = itemObject.model
	local visualModel = itemObject.visualModel
	if not visualModel then return end

	for i = 1, 5 do
		local t = tick()
		local offset = Vector3.new(
			math.noise(t * 10, 0, 0) * (math.pi / 6),
			0,
			math.noise(0, t * 10, 0) * (math.pi / 6)
		)
		visualModel:PivotTo(itemModel:GetPivot() * CFrame.Angles(offset.X, offset.Y, offset.Z))
		task.wait(0.05)
	end
	visualModel:PivotTo(itemModel:GetPivot())
end

function GameInput:_onItemHoverEnter(itemObject: ItemObject, player: Player)
	if itemObject.isHovered then return end
	itemObject.isHovered = true
	
	-- Move the item up slightly to indicate hover
	local itemModel = itemObject.model
	local visualModel = itemObject.visualModel
	if not visualModel then return end

	for i = 0, 1, 0.05 do
		visualModel:PivotTo(itemModel:GetPivot() * CFrame.new(0, 0.05 * 0.25, 0))
		task.wait()
	end
end

function GameInput:_onItemHoverLeave(itemObject: ItemObject, player: Player)
	if not itemObject.isHovered then return end
	
	-- Move the item up slightly to indicate hover
	local itemModel = itemObject.model
	local visualModel = itemObject.visualModel
	if not visualModel then return end

	for i = 0, 1, 0.05 do
		visualModel:PivotTo(itemModel:GetPivot() * CFrame.new(0, -0.05 * 0.25, 0))
		task.wait()
	end
	itemObject.isHovered = false
end

function GameInput:_onItemClicked(itemObject: ItemObject, player: Player)
	if not self._inputEnabled then warn("Input is disabled") return end
	if not self._clickAction then warn("No click action set") return end
	
	local posIndex = itemObject.model:GetAttribute("PosIndex")
	if typeof(posIndex) ~= "number" then warn("Invalid PosIndex attribute") return end
	self.onAction(self._clickAction, { posIndex = posIndex })
end

function GameInput:_onShuffleButtonDown()
	-- Stop shuffle on the server
	if self.onAction then
		self.onAction("StartShuffle", {})
	end
end

function GameInput:_onShuffleButtonUp()
	-- Stop shuffle on the server
	if self.onAction then
		self.onAction("StopShuffle", {})
	end
end

-- ========== Life Cycle ========== --

function GameInput:Init()
	if self._inited then return end
	self._inited = true

	-- // Bind signals, initialise state etc.
	table.insert(self._conns, self._shuffleButton.select.MouseButton1Down:Connect(function()
		print("Shuffle button down")
		self:_onShuffleButtonDown()
	end))

	table.insert(self._conns, self._shuffleButton.select.MouseButton1Up:Connect(function()
		print("Shuffle button up")
		self:_onShuffleButtonUp()
	end))
end

function GameInput:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return GameInput :: GameInputAPI
