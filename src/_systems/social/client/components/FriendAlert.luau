--!strict
-- FriendAlert (Component)

-- // Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SocialService = game:GetService("SocialService")

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

export type FriendAlertAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: FriendAlertAPI) -> (),
	Destroy: (self: FriendAlertAPI) -> (),
}

export type Opts = {
	rootFrame: Frame,
	messageLabel: TextLabel,
	playerIcon: ImageLabel,
	closeButton: TextButton,
	inviteButton: TextButton,
}

local FriendAlert = {}
FriendAlert.__index = FriendAlert

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function FriendAlert.new(deps: Deps, opts: Opts): FriendAlertAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, FriendAlert) :: FriendAlertAPI

	self.rootFrame = opts.rootFrame
	self.messageLabel = opts.messageLabel
	self.playerIcon = opts.playerIcon
	self.closeButton = opts.closeButton
	self.inviteButton = opts.inviteButton

	if not self.rootFrame or not self.messageLabel or not self.playerIcon or not self.closeButton or not self.inviteButton then
		error("FriendAlert: Missing required UI elements in opts")
	end

	-- Hide initially
	self:Hide()

	return self
end

-- ========== Public API ========== --

function FriendAlert:Display(friendUserId: number)
	-- Get friend's info
	local ok, result = pcall(function()
		local name = Players:GetNameFromUserIdAsync(friendUserId)
		local imageId = Players:GetUserThumbnailAsync(friendUserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		return { name = name, imageId = imageId }
	end)

	if not ok then
		warn("FriendAlert: Failed to get friend info for userId:", friendUserId)
		return
	end

	-- Update UI
	self.messageLabel.Text = string.format("%s is online!", result.name)
	self.playerIcon.Image = result.imageId

	-- Set receiver user Id for invite button
	self._receiverUserId = friendUserId

	-- Show
	self.rootFrame.Visible = true
end

function FriendAlert:Hide()
	self.rootFrame.Visible = false
end

-- ========== Internal ========== --

function FriendAlert:_internalMethod()
	-- Example
end

-- ========== Life Cycle ========== --

function FriendAlert:Init()
	if self._inited then return end
	self._inited = true

	-- // Bind signals, initialise state etc.
	table.insert(self._conns, self.closeButton.Activated:Connect(function()
		self:Hide()
	end))

	table.insert(self._conns, self.inviteButton.Activated:Connect(function()
		if not self._receiverUserId then return end

		-- Construct invite options with connection's user ID
		local inviteOptions = Instance.new("ExperienceInviteOptions")
		inviteOptions.InviteUser = self._receiverUserId

		local success, canSend = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer, self._receiverUserId)
		end)

		if not success or not canSend then
			warn("[FriendAlert] Cannot send game invite to userId:", self._receiverUserId)
			return
		end

		SocialService:PromptGameInvite(Players.LocalPlayer, inviteOptions)
	end))
end

function FriendAlert:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return FriendAlert :: FriendAlertAPI
