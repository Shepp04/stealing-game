--!strict

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- // Constants
local TAG = "CloseButton"

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
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Check this button is a button and is a descendant of the player gui
	if not button:IsDescendantOf(PlayerGui) then
		return
	end
	if not button:IsA("GuiButton") then
		warn(TAG, "Error: '" .. button:GetFullName() .. "' is not a GuiButton")
		return
	end

	-- Prevent re-application
	if appliedInstances[button] then
		return
	end
	appliedInstances[button] = true

	-- Find the menu frame
	local menuFrame = button
	while menuFrame:IsDescendantOf(PlayerGui) do
		if menuFrame.Parent and menuFrame.Parent.Name == "Menus" then
			break
		end
		if menuFrame.Parent and menuFrame.Parent:IsA("ScreenGui") then
			break
		end
		menuFrame = menuFrame.Parent
		task.wait()
	end

	if not menuFrame:IsDescendantOf(PlayerGui) then
		warn(TAG, "Error: '" .. button:GetFullName() .. "' is not a descendant of a 'Menus' CanvasGroup container")
		return
	end

	local menuName = menuFrame.Name
	button.MouseButton1Click:Connect(function()
		MenuController:CloseMenu(menuName)
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