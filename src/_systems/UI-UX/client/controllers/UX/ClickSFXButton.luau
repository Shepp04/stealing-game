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
local CLICK_SOUND_IDS: { string | number } = { "UIClick01" }

-- ========== Public API ========== --
function GuiComponent:Create(button: GuiButton): nil
	-- Prevent re-application
	if appliedInstances[button] then
		return
	end
	appliedInstances[button] = true

	-- Choose a random click sound
	local clickSoundId = CLICK_SOUND_IDS[math.random(1, #CLICK_SOUND_IDS)]

	button.MouseButton1Click:Connect(function()
		-- Play click sound
		SharedPackages.Sounds:PlaySound(clickSoundId)
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