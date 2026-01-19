--!strict

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- // Constants
local TAG = "HoverSFXButton"

-- // Types
type GuiComponent = {
	Create: (self: GuiComponent, button: GuiButton) -> (),
	Init: (self: GuiComponent) -> (),
}

-- // Component
local GuiComponent = {} :: GuiComponent

-- // Dependencies
local SharedPackages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))

-- // Internal State
local appliedInstances: { [Instance]: boolean } = {}

-- // Constants
local HOVER_SOUND_IDS: { string | number } = { "UIHover01" }

-- ========== Public API ========== --
function GuiComponent:Create(button: GuiButton): nil
	-- Prevent re-application
	if appliedInstances[button] then
		return
	end
	appliedInstances[button] = true

	-- Choose a random hover sound
	local hoverSoundId = HOVER_SOUND_IDS[math.random(1, #HOVER_SOUND_IDS)]

	button.MouseEnter:Connect(function()
		-- Play hover sound
		SharedPackages.Sounds:PlaySound(hoverSoundId)
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