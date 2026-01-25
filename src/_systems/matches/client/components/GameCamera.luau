--!strict
-- GameCamera (Component)

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

export type GameCameraAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: GameCameraAPI) -> (),
	Destroy: (self: GameCameraAPI) -> (),
}

export type Opts = {}

local GameCamera = {}
GameCamera.__index = GameCamera

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function GameCamera.new(deps: Deps, opts: Opts): GameCameraAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, GameCamera) :: GameCameraAPI

	self.player = Players.LocalPlayer
	self.currentCamera = workspace.CurrentCamera :: Camera

	return self
end

-- ========== Public API ========== --

function GameCamera:Focus(cframe: CFrame, subject: Instance?, tween: boolean?)
	self.currentCamera.CameraType = Enum.CameraType.Scriptable
	if tween then
		local tweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(self.currentCamera, tweenInfo, { CFrame = cframe })
		tween:Play()
	else
		self.currentCamera.CFrame = cframe
	end

	if subject then
		self.currentCamera.CameraSubject = subject
	end
end

function GameCamera:Reset(tween: boolean?)
	local char = self.player and self.player.Character
	local human = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if human and root then
		self:Focus(root.CFrame, human, tween)
		self.currentCamera.CameraType = Enum.CameraType.Custom
	end
end

-- ========== Internal ========== --

function GameCamera:_internalMethod()
	-- Example
end

-- ========== Life Cycle ========== --

function GameCamera:Init()
	if self._inited then return end
	self._inited = true

	-- // Bind signals, initialise state etc.
end

function GameCamera:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return GameCamera :: GameCameraAPI
