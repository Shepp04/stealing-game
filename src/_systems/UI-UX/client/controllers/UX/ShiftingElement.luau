--!strict

-- // Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- // Constants
local TAG = "ShiftingElement"

-- // Types
type GuiComponent = {
	Init: (self: GuiComponent) -> (),
}

-- // Component
local GuiComponent = {} :: GuiComponent

-- // Render Update
local function update()
	local elements = CollectionService:GetTagged(TAG)
	if #elements == 0 then return end

	local t = tick()

	for _, element in elements do
		if not element:IsDescendantOf(game.Players) then continue end
		
		local speed = element:GetAttribute("ShiftSpeed") or 0.04

		local sizeX = element.AbsoluteSize.X
		local sizeY = element.AbsoluteSize.Y

		local shiftX = math.sin(t * speed) * (sizeX / 4)
		local shiftY = math.cos(t * speed + math.pi * 3) * (sizeY / 4)
		local pos = element.Position
		
		element.Position = UDim2.new(pos.X.Scale, shiftX, pos.Y.Scale, shiftY)
	end
end

-- ========== Life Cycle ========== --
function GuiComponent:Init()
	RunService:BindToRenderStep("ShiftUIElements", Enum.RenderPriority.Camera.Value, update)
end

return GuiComponent