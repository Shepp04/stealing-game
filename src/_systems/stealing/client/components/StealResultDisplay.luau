--!strict
-- StealResultDisplay (Component)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)

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

export type StealResultDisplayAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: StealResultDisplayAPI) -> (),
	Destroy: (self: StealResultDisplayAPI) -> (),

	SetHeading: (self: StealResultDisplayAPI, text: string?) -> (),
	SetSubheading: (self: StealResultDisplayAPI, text: string?) -> (),
	SetCloseButtonText: (self: StealResultDisplayAPI, text: string) -> (),
	SetCloseButtonColor: (self: StealResultDisplayAPI, color: Color3) -> (),
	SetRestoreButtonVisible: (self: StealResultDisplayAPI, visible: boolean) -> (),
	IsVisible: (self: StealResultDisplayAPI) -> boolean,
	SetVisible: (self: StealResultDisplayAPI, visible: boolean) -> (),
}

export type Opts = {
	root: ScreenGui,
	container: Frame,

	heading: TextLabel,
	subheading: TextLabel,

	closeButton: {
		container: Frame,
		text: TextLabel,
		select: TextButton,
	},
	restoreButton: {
		container: Frame,
		text: TextLabel,
		select: TextButton,
	},
}

local StealResultDisplay = {}
StealResultDisplay.__index = StealResultDisplay

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function StealResultDisplay.new(deps: Deps, opts: Opts): StealResultDisplayAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, StealResultDisplay) :: StealResultDisplayAPI
	
	self._opts = opts

	self.root = opts.root
	self.container = opts.container

	self._heading = opts.heading
	self._subheading = opts.subheading
	self._closeButton = opts.closeButton
	self._restoreButton = opts.restoreButton

	self._visibleToken = 0

	return self
end

-- ========== Public API ========== --

function StealResultDisplay:SetHeading(text: string?)
	self._heading.Text = text or ""
end

function StealResultDisplay:SetSubheading(text: string?)
	self._subheading.Text = text or ""
end

function StealResultDisplay:SetCloseButtonText(text: string)
	if self._closeButton and self._closeButton.text then
		self._closeButton.text.Text = text
	end
end

function StealResultDisplay:SetCloseButtonColor(color: Color3)
	if self._closeButton and self._closeButton.container then
		local button = self._closeButton.container:FindFirstChild("Button") :: Frame?
		if button then
			button.BackgroundColor3 = color
		end
	end
end

function StealResultDisplay:SetRestoreButtonVisible(visible: boolean)
	self._restoreButton.container.Visible = visible
end

function StealResultDisplay:IsVisible(): boolean
	return self._visible
end

function StealResultDisplay:SetVisible(visible: boolean)
	self.root.Enabled = visible
	self:_toggleBackpack(not visible)
	self._visible = visible

	if visible then
		self._visibleToken += 1
		local tok = self._visibleToken
		task.delay(20, function()
			if self:IsVisible() and tok == self._visibleToken then
				self:SetVisible(false)
			end
		end)
	end
end

-- ========== Internal ========== --

function StealResultDisplay:_toggleBackpack(visible: boolean)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, visible)
end

-- ========== Life Cycle ========== --

function StealResultDisplay:Init()
	if self._inited then return end
	self._inited = true

	-- // Connect button events
	table.insert(self._conns, self._closeButton.select.MouseButton1Click:Connect(function()
		-- Hide
		self:SetVisible(false)
	end))

	table.insert(self._conns, self._restoreButton.select.MouseButton1Click:Connect(function()
		_deps.Monetisation.PromptSale("KeepIt")
		task.delay(5.0, function()
			self:SetRestoreButtonVisible(false)
		end)
	end))

	-- // Hide by default
	self:SetVisible(false)
end

function StealResultDisplay:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return StealResultDisplay :: StealResultDisplayAPI
