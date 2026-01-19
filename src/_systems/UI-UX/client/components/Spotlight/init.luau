--!strict

--[[
	Spotlight UI Component

	A client-side component that focuses the screen around a central hole,
	useful for transitions, tutorials, and cinematic effects.

	Usage:
	local spotlight = Spotlight.new()
	spotlight:Focus()
	spotlight:SetColour(Color3.new(0, 0, 0), 0.4)
	spotlight:Transition()
	spotlight:Hide()
]]

--// Type Definitions
export type Spotlight = {
	_root: ScreenGui,
	_spotlight: CanvasGroup,
	_tweens: { [string]: Tween },
	_visible: boolean,
	_debounce: boolean,

	SetColour: (self: Spotlight, colour: Color3) -> (),
	SetTransparency: (self: Spotlight, transparency: number) -> (),
	Focus: (self: Spotlight, centre: UDim2?, size: number?, moveFromCentre: boolean?) -> (),
	Transition: (self: Spotlight) -> (),
	Hide: (self: Spotlight) -> (),
	Destroy: (self: Spotlight) -> (),
}

--// Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

--// UI Source
local UI_ASSET = script:WaitForChild("SpotlightGui") :: ScreenGui

local Spotlight = {}
Spotlight.__index = Spotlight

--[[
	Creates a new Spotlight instance. Clones UI and attaches to PlayerGui.

	@return Spotlight
]]
function Spotlight.new(): Spotlight
	local self = setmetatable({}, Spotlight)

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = UI_ASSET:Clone()
	gui.Parent = playerGui
	gui.Name = "Spotlight"

	self._root = gui
	self._spotlight = gui:WaitForChild("Spotlight") :: CanvasGroup

	local hole = self._spotlight:FindFirstChild("Hole") :: ImageLabel
	assert(hole, "Spotlight hole not found in GUI")

	self._tweens = {
		Hide = TweenService:Create(
			hole,
			TweenInfo.new(0.75, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(10, 10) }
		),
	}

	self._visible = false
	self._debounce = false

	self:SetColour(Color3.fromRGB(0, 0, 0))
	self:SetTransparency(0)
	self:Hide(false)

	return self
end

--[[
	Sets the colour of the spotlight.

	@param colour Color3
]]
function Spotlight:SetColour(colour: Color3)
	for _, v in pairs(self._spotlight:GetDescendants()) do
		if v:IsA("Frame") then
			v.BackgroundColor3 = colour
		elseif v:IsA("ImageLabel") then
			v.ImageColor3 = colour
		end
	end
end

--[[
	Sets the transparency of the spotlight.

	@param transparency number
]]
function Spotlight:SetTransparency(transparency: number)
	self._spotlight.GroupTransparency = transparency or self._spotlight.GroupTransparency
end

--[[
	Focuses the spotlight to a specific screen position with a hole size.

	@param centre? UDim2 — Position to focus (default center of screen)
	@param size? number — Scale size of the hole (default 0.01)
	@param moveFromCentre? boolean — Whether to animate from center outward
]]
function Spotlight:Focus(centre: UDim2?, size: number?, moveFromCentre: boolean?)
	if self._debounce then return end
	self._debounce = true

	local hole = self._spotlight:FindFirstChild("Hole") :: ImageLabel
	if not hole then
		warn("No spotlight hole found")
		self._debounce = false
		return
	end

	centre = centre or UDim2.fromScale(0.5, 0.5)
	size = size or 0.01

	hole.Size = UDim2.fromScale(10, 10)
	hole.Position = moveFromCentre and UDim2.fromScale(0.5, 0.5) or hole.Position

	if not self._visible then
		self._spotlight.Visible = true
		self._visible = true
	end

	hole:TweenSizeAndPosition(
		UDim2.new(size, 0, size, 0),
		centre,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quart,
		1
	)

	task.delay(1, function()
		self._debounce = false
	end)
end

--[[
	Plays a full-screen spotlight transition:
	Shrinks hole, flashes background, then expands again.
]]
function Spotlight:Transition(color: Color3?)
	if self._debounce then return end
	self._debounce = true
	
	-- Set transparency to 0 and colour if provided
	if color then
		self:SetColour(color)
	end
	self:SetTransparency(0)

	local hole = self._spotlight:FindFirstChild("Hole") :: ImageLabel
	local bg = self._spotlight:FindFirstChild("Background") :: Frame

	if not hole or not bg then
		warn("Spotlight missing Hole or Background")
		self._debounce = false
		return
	end

	if not self._visible then
		self._spotlight.Visible = true
		self._visible = true
	end

	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)

	hole.Size = UDim2.fromScale(10, 10)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole:TweenSize(UDim2.fromScale(0.01, 0.01), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 1)
	task.wait(1)

	bg.Visible = true
	task.wait(1)

	bg.Visible = false
	hole:TweenSize(UDim2.fromScale(10, 10), Enum.EasingDirection.In, Enum.EasingStyle.Quart, 1)
	task.wait(1)

	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	self._debounce = false
end

--[[
	Hides the spotlight by expanding the hole and turning invisible.
]]
function Spotlight:Hide(tween: boolean?)
	self._visible = false

	if tween then
		self._tweens.Hide:Play()
		self._tweens.Hide.Completed:Wait()
	end

	self._spotlight.Visible = false
end

--[[
	Cleans up tweens and internal state (but does not remove UI).
]]
function Spotlight:Destroy()
	self._visible = false
	self._tweens = {}
end

return Spotlight