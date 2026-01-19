--!strict

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- // Constants
local TAG = "MenuButton"

-- // Types
type GuiComponent = {
	Create: (self: GuiComponent, button: Frame) -> (),
	Init: (self: GuiComponent) -> (),
}

-- // Component
local GuiComponent = {} :: GuiComponent

-- // Dependencies
local MenuController = require(script.Parent.Parent:WaitForChild("MenuController"))

-- // Internal State
local appliedInstances: { [Instance]: boolean } = {}

-- ========== Public API ========== --
function GuiComponent:Create(button: GuiButton): nil
	-- Check this button is a button
	if not button:IsA("GuiButton") then
		warn(TAG, "Error: '" .. button:GetFullName() .. "' is not a GuiButton")
		return
	end

	-- Prevent re-application
	if appliedInstances[button] then
		return
	end
	appliedInstances[button] = true

	-- Get the menu name
	local menuName = button:GetAttribute("MenuName")
	button.MouseButton1Click:Connect(function()
		MenuController:ToggleMenu(menuName, true)
	end)
end

-- ========== Life Cycle ========== --
function GuiComponent:Init()
	for _, instance in CollectionService:GetTagged(TAG) do
		GuiComponent:Create(instance)
	end

	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		GuiComponent:Create(instance)
	end)
end

return GuiComponent