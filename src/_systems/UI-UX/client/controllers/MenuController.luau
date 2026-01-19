--!strict

-- // Services
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

export type Deps = {
	ReplicatedData: ReplicatedData,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type MenuControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: MenuControllerAPI, deps: Deps) -> (),
	Start: (self: MenuControllerAPI) -> (),
	Destroy: (self: MenuControllerAPI) -> (),
}

local MenuController = {
	_inited = false,
	_started = false,
	_conns = {} :: {RBXScriptConnection},
	--
	_menuBlur = nil :: BlurEffect?,
	_menus = {} :: { [Frame | CanvasGroup]: boolean },
} :: MenuControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- // Tween Styles
local TWEEN_STYLES = {
	-- No tween
	[0] = {
		In = function(menu: Frame | CanvasGroup, duration: number?)
			-- No tween
			menu.Visible = true
		end,
		Out = function(menu: Frame | CanvasGroup, duration: number?)
			-- No tween
			menu.Visible = false
		end,
	},
	
	-- Slide from bottom
	[1] = {
		In = function(menu: Frame | CanvasGroup, duration: number?)
			-- Slide in from bottom
			menu.Position = UDim2.new(0, 0, 1, 0)
			menu.Visible = true
			TweenService:Create(
				menu,
				TweenInfo.new(duration or 0.50, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0, 0, 0, 0) }
			):Play()
		end,
		Out = function(menu: Frame | CanvasGroup, duration: number?)
			-- Slide out to bottom
			TweenService:Create(
				menu,
				TweenInfo.new(duration or 0.50, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0, 0, 1, 0) }
			):Play()
			task.delay(duration or 0.50, function()
				if menu.Position.Y.Scale >= 1 then
					menu.Visible = false
				end
			end)
		end,
	},

	-- Grow/Shrink
	[2] = {
		In = function(menu: Frame | CanvasGroup, duration: number?)
			-- Pulse in
			menu.Size = UDim2.new(0, 0, 0, 0)
			menu.AnchorPoint = Vector2.new(0.5, 0.5)
			menu.Position = UDim2.new(0.5, 0, 0.5, 0)
			menu.Visible = true
			TweenService:Create(
				menu,
				TweenInfo.new(duration or 0.50, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.new(1, 0, 1, 0) }
			):Play()
		end,
		Out = function(menu: Frame | CanvasGroup, duration: number?)
			-- Pulse out
			menu.AnchorPoint = Vector2.new(0.5, 0.5)
			menu.Position = UDim2.new(0.5, 0, 0.5, 0)
			TweenService:Create(
				menu,
				TweenInfo.new(duration or 0.50, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{ Size = UDim2.new(0, 0, 0, 0) }
			):Play()
			task.delay(duration or 0.50, function()
				if menu.Size.X.Scale <= 0 and menu.Size.Y.Scale <= 0 then
					menu.Visible = false
				end
			end)
		end,
	},

	-- Pulse
	[3] = {
		In = function(menu: Frame | CanvasGroup, duration: number?)
			-- Pulse in
			menu.Size = UDim2.new(1, 0, 1, 0)
			menu.AnchorPoint = Vector2.new(0.5, 0.5)
			menu.Position = UDim2.new(0.5, 0, 0.5, 0)
			menu.Visible = true
			TweenService:Create(
				menu,
				TweenInfo.new(duration or 0.50, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, true),
				{ Size = UDim2.new(1.1, 0, 1.1, 0) }
			):Play()
		end,
		Out = function(menu: Frame | CanvasGroup, duration: number?)
			-- Pulse out
			menu.AnchorPoint = Vector2.new(0.5, 0.5)
			menu.Position = UDim2.new(0.5, 0, 0.5, 0)
			TweenService:Create(
				menu,
				TweenInfo.new(duration or 0.50, Enum.EasingStyle.Quart, Enum.EasingDirection.In, 0, true),
				{ Size = UDim2.new(0.9, 0, 0.9, 0) }
			):Play()
			task.delay((duration or 0.50) * 2, function()
				if menu.Size.X.Scale <= 0 and menu.Size.Y.Scale <= 0 then
					menu.Visible = false
				end
			end)
		end,
	},
} :: { [number]: { In: (menu: Frame | CanvasGroup, duration: number?) -> nil, Out: (menu: Frame | CanvasGroup) -> nil } }

-- ========== Internal ========== --
--[[
	Toggles the camera's Field of View.

	@param state boolean — True to apply custom FOV, false to reset.
	@param fov? number — Custom FOV to apply (default: 70).
]]
function MenuController:_toggleFOV(state: boolean, fov: number?)
	local targetFOV = state and (fov or self._defaultFOV) or self._defaultFOV

	local camera = workspace.CurrentCamera
	if not camera then return end

	TweenService:Create(
		camera,
		TweenInfo.new(self._defaultTweenDuration * 0.75, Enum.EasingStyle.Linear, state and Enum.EasingDirection.In or Enum.EasingDirection.Out),
		{ FieldOfView = targetFOV }
	):Play()
end

--[[
	Toggles menu blur effect.

	@param state boolean — True to enable blur, false to remove.
	@param blurSize? number — Custom blur size to apply (default: self._defaultBlurSize).
]]
function MenuController:_toggleBlur(state: boolean, blurSize: number?)
	if self._menuBlur.Enabled == state then return end

	self._menuBlur.Enabled = true
	local targetSize = state and (blurSize or self._defaultBlurSize) or 0
	local tween = TweenService:Create(
		self._menuBlur,
		TweenInfo.new(self._defaultTweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
	tween:Play()

	if not state then
		task.delay(self._defaultTweenDuration, function()
			if self._menuBlur.Size == 0 then
				self._menuBlur.Enabled = false
			end
		end)
	end
end

function MenuController:_registerMenu(menu: Frame | CanvasGroup)
	-- Check that this menu is a descendant of the PlayerGui
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not menu:IsDescendantOf(PlayerGui) then
		return
	end

	-- Check that a menu with this id is not already registered
	local menuId = menu.Name
	if self._menus[menuId] then
		warn(`[MenuController] Menu with id '{menuId}' is already registered.`)
		return
	end

	-- If the menu is not tagged, tag it
	if not CollectionService:HasTag(menu, "Menu") then
		CollectionService:AddTag(menu, "Menu")
	end

	-- Add to internal tracking
	self._menus[menuId] = menu
end

-- ========== Public API ========== --

function MenuController:GetMenuFromId(menuId: string): Frame | CanvasGroup?
	return self._menus[menuId]
end

function MenuController:IsMenuOpen(menuId: string): boolean
	local menu = self:GetMenuFromId(menuId)
	if not menu then return false end
	return menu.Visible
end

function MenuController:ToggleMenu(menuId: string, closeOthers: boolean?, affectBlur: boolean?, fov: boolean?)
	local menu = self:GetMenuFromId(menuId)
	if not menu then return end

	if self:IsMenuOpen(menuId) then
		self:CloseMenu(menuId, affectBlur, true)
	else
		self:OpenMenu(menuId, closeOthers or true, affectBlur or true, fov or self._defaultFOV * 1.15)
	end
end

--[[
	Animates a menu out of view and optionally disables blur/FOV.

	@param menuId string — The ID of the UI element to hide.
	@param affectBlur? boolean — Whether to disable blur (default: true).
	@param affectFOV? boolean — Whether to reset FOV (default: true).
]]
function MenuController:CloseMenu(menuId: string, affectBlur: boolean?, affectFOV: boolean?)
	local menu = self:GetMenuFromId(menuId)
	if not menu then return end
	if not menu.Visible then return end

	-- Get this menu's tween style and duration
	local menuTweenStyleId = menu:GetAttribute("MenuTweenOutStyleId")
	local menuTweenDuration = menu:GetAttribute("MenuTweenOutDuration")
	local tweenInfo = TWEEN_STYLES[menuTweenStyleId or 0]
	if tweenInfo then
		tweenInfo.Out(menu, menuTweenDuration)
	else
		-- Default to no tween
		menu.Visible = false
	end

	if affectBlur ~= false then
		self:_toggleBlur(false)
	end
	if affectFOV ~= false then
		self:_toggleFOV(false)
	end
end

--[[
	Animates a menu into view and optionally closes others, applies blur/FOV.

	@param menuId string — The ID of the menu to open.
	@param closeOthers boolean — Whether to close other tagged menus.
	@param affectBlur boolean — Whether to apply blur.
	@param fov? number — Optional custom FOV.
]]
function MenuController:OpenMenu(menuId: string, closeOthers: boolean, affectBlur: boolean, fov: number?)
	local menu = self:GetMenuFromId(menuId)
	if not menu then return end
	if menu.Visible then return end

	if closeOthers then
		for otherMenuId, otherMenu in pairs(self._menus) do
			if otherMenuId ~= menuId and otherMenu.Visible then
				self:CloseMenu(otherMenuId, false, false)
			end
		end
	end

	(menu :: Frame).Visible = true

	-- Get this menu's tween style and duration
	local menuTweenStyleId = menu:GetAttribute("MenuTweenInStyleId")
	local menuTweenDuration = menu:GetAttribute("MenuTweenInDuration")
	local tweenInfo = TWEEN_STYLES[menuTweenStyleId or 0]
	if tweenInfo then
		tweenInfo.In(menu, menuTweenDuration)
	else
		-- Default to no tween
		menu.Visible = true
	end
	
	if affectBlur then
		-- Get this menu's blur size
		local blurSize = menu:GetAttribute("MenuBlurSize")
		self:_toggleBlur(true, blurSize)
	end

	if fov then
		-- Get this menu's FOV
		local fov = menu:GetAttribute("MenuFOV")
		self:_toggleFOV(true, fov)
	end
end

--[[
	Closes all menus tagged with "Menu" using CollectionService.
]]
function MenuController:CloseMenus()
	for menuId, menuFrame in pairs(self._menus) do
		self:CloseMenu(menuFrame, false, false)
	end
end

-- ========== Life cycle ========== --
function MenuController:Init(deps: Deps, args: { defaultFOV: number?, defaulBlurSize: number?, defaultTweenDuration: number? }?)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- Set defaults
	self._defaultFOV = args and args.defaultFOV or 70
	self._defaultBlurSize = args and args.defaulBlurSize or 20
	self._defaultTweenDuration = args and args.defaultTweenDuration or 0.25

	-- Create a menu blur
	self._menuBlur = Instance.new("BlurEffect") :: BlurEffect
	self._menuBlur.Name = "MenuBlur"
	self._menuBlur.Size = 0
	self._menuBlur.Enabled = false
	self._menuBlur.Parent = game:GetService("Lighting")

	-- // Get remotes
	self._openMenuRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "OpenMenu") :: RemoteEvent
	self._closeMenuRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "CloseMenu") :: RemoteEvent
end

function MenuController:Start()
	if self._started then return end
	self._started = true
	
	-- // Connect remotes
	table.insert(self._conns, self._openMenuRemote.OnClientEvent:Connect(function(menuId: string)
		self:OpenMenu(menuId, true, true, self._defaultFOV * 1.15)
	end))

	table.insert(self._conns, self._closeMenuRemote.OnClientEvent:Connect(function(menuId: string)
		self:CloseMenu(menuId, true, true)
	end))

	-- Register all existing menus
	for _, menu in CollectionService:GetTagged("Menu") do
		if menu:IsA("Frame") or menu:IsA("CanvasGroup") then
			self:_registerMenu(menu)
		end
	end

	-- Listen for new menus being added
	table.insert(self._conns, CollectionService:GetInstanceAddedSignal("Menu"):Connect(function(instance)
		if instance:IsA("Frame") or instance:IsA("CanvasGroup") then
			self:_registerMenu(instance)
		end
	end))

	-- Listen for menus being removed
	table.insert(self._conns, CollectionService:GetInstanceRemovedSignal("Menu"):Connect(function(instance)
		if instance:IsA("Frame") or instance:IsA("CanvasGroup") then
			local menuId = instance.Name
			self._menus[menuId] = nil
		end
	end))
end

function MenuController:Destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._inited = false
	self._started = false
end

return MenuController