--!strict
-- SocialController (Controller)
-- Tags to use: FriendInviteButton (GuiButton), FriendBoostedCurrencyLabel (TextLabel)

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local CollectionService = game:GetService("CollectionService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local StarterGui = game:GetService("StarterGui")
local LocalizationService = game:GetService("LocalizationService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)

-- // Components
local FriendBoostedCurrencyLabel = require(script.Parent.Parent.Components.FriendBoostedCurrencyLabel)
local FriendAlertComponent = require(script.Parent.Parent.Components.FriendAlert)

-- // Assets
local Assets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets")
local GroupRewardGuiTemplate = Assets:WaitForChild("UI"):WaitForChild("GroupRewardGui") :: ScreenGui

-- // Types (generated)
local ControllersTypes = require(ReplicatedStorage.Shared.Types.Controllers)

-- // Type aliases for deps inferred from real modules
type ControllerRegistry = ControllersTypes.Registry

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

export type SocialControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: SocialControllerAPI, deps: Deps) -> (),
	Start: (self: SocialControllerAPI) -> (),
	Destroy: (self: SocialControllerAPI) -> (),

	PromptGameFavourite: (self: SocialControllerAPI) -> (),
	PromptNotificationOptIn: (self: SocialControllerAPI) -> (),
	AttemptShowFriendAlert: (self: SocialControllerAPI) -> boolean,
	Toast: (self: SocialControllerAPI, title: string, text: string) -> (),
}

local SocialController = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Controllers = {} :: ControllerRegistry,
} :: SocialControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?
local _friendBoostedCurrencyLabels: { FriendBoostedCurrencyLabel.FriendBoostedCurrencyLabelAPI } = {}
local _friendInviteButtons: { GuiButton } = {}

-- // Constants
local AUTO_SEND_FRIEND_ALERTS: boolean = false -- Whether to automatically show friend alerts periodically

-- ========== Public API ========== --

function SocialController:PromptGameFavourite()
	AvatarEditorService:PromptSetFavorite(game.PlaceId, 1, true)
end

function SocialController:PromptNotificationOptIn()
	-- Check that they can opt in
	local success, canPrompt = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if not success or not canPrompt then
		warn("[SocialController] Player is unable to opt in to notifications")
		return
	end

	-- Prompt opt in
	local success, errorMessage = pcall(function()
		ExperienceNotificationService:PromptOptIn()
	end)
	if not success then
		warn("[SocialController] Failed to prompt notification opt-in:", errorMessage)
	end
end

function SocialController:AttemptShowFriendAlert(): boolean
	local friendUserId = self:_findRecommendedFriend()
	if friendUserId then
		self:_showFriendAlert(friendUserId)
		return true -- Success
	end
	return false -- No friend to show
end

function SocialController:Toast(title: string, text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 3,
		})
	end)
end

-- ========== Internal ========== --

-- === UI and Model Setup === --
function SocialController:_setupFriendBoostLabel(label: TextLabel)
	-- Check this label isn't already been setup
	if _friendBoostedCurrencyLabels[label] then
		return _friendBoostedCurrencyLabels[label]
	end

	-- Check for currency Id
	local currencyId = label:GetAttribute("CurrencyId")
	if not currencyId then
		warn("[SocialController] FriendBoostedCurrencyLabel is missing CurrencyId attribute")
		return
	end

	-- Validate currency info
	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then
		warn("[SocialController] FriendBoostedCurrencyLabel has invalid CurrencyId:", currencyId)
		return
	end

	local friendBoostedCurrencyLabel = FriendBoostedCurrencyLabel.new(_deps, {
		textLabel = label,
		currencyId = currencyId,
	})
	_friendBoostedCurrencyLabels[label] = friendBoostedCurrencyLabel
	return friendBoostedCurrencyLabel
end

function SocialController:_setupFriendInviteButton(button: GuiButton)
	-- Check this button isn't already been setup
	if _friendInviteButtons[button] then
		return _friendInviteButtons[button]
	end

	table.insert(self._conns, button.MouseButton1Down:Connect(function()
		-- Open the friend invite dialog
		local canInvite, err = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		if not canInvite then
			warn("[SocialController] Failed to check if can send game invite:", err)
			return
		end
		SocialService:PromptGameInvite(Players.LocalPlayer)
	end))

	_friendInviteButtons[button] = button
	return button
end

function SocialController:_setupGroupRewardStand(stand: Model)
	-- Run in separate thread in case the model isn't loaded due to StreamingEnabled
	task.spawn(function()
		local trigger = stand:WaitForChild("Trigger") :: BasePart
		local proximityPrompt = trigger:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
		if proximityPrompt then
			proximityPrompt.Triggered:Connect(function(player: Player)
				if not player or player ~= Players.LocalPlayer then
					return
				end

				-- Show the group reward menu
				self.Controllers.MenuController:OpenMenu("GroupReward", true, true, 60)
			end)
		else
			local debounce = false
			trigger.Touched:Connect(function(hit: BasePart)
				if debounce then return end
				debounce = true
				task.delay(1, function() debounce = false end)

				local char = hit.Parent
				if not char then return end

				local player = Players:GetPlayerFromCharacter(char)
				if not player or player ~= Players.LocalPlayer then
					return
				end

				-- Show the group reward menu
				self.Controllers.MenuController:OpenMenu("GroupReward", true, true, 60)
			end)
		end
	end)
end

-- === Friends === --
function SocialController:_getOnlineFriends(): { any }
	local success, friends = pcall(function()
		return Players.LocalPlayer:GetFriendsOnline()
	end)
	if not success or not friends then
		warn("[SocialController] Failed to get friends list")
		return {}
	end

	--[[
    	[1] =  ▼  {
        	["DisplayName"] = "STARCODE_Dogbon",
            ["IsOnline"] = true,
            ["LastLocation"] = "Studio",
            ["LastOnline"] = "2025-12-28T23:39:26.07Z",
            ["LocationType"] = 6,
            ["UserName"] = "Dogbon62",
            ["VisitorId"] = 1230109044
        },
	]]
	
	return friends
end

function SocialController:_findRecommendedFriend(): number?
	-- Find an online friend to invite
	-- They must be online, not already in this game, and not already prompted in this session
	local onlineFriends = self:_getOnlineFriends()
	local candidates: { number } = {}
	for _, friendInfo in onlineFriends do
		local userId = friendInfo.VisitorId :: number
		local placeId = friendInfo.PlaceId :: number?

		if placeId == game.PlaceId then
			-- Already in this game
			continue
		end

		if self._alertedFriendIds and self._alertedFriendIds[userId] then
			-- Already prompted this session
			continue
		end

		table.insert(candidates, userId)
	end

	-- Choose a random candidate
	if #candidates == 0 then
		return nil
	end

	return candidates[math.random(1, #candidates)]
end


function SocialController:_showFriendAlert(friendUserId: number)
	-- Show the alert prompt
	if self._friendAlert then
		self._friendAlert:Display(friendUserId)
	end

	-- Register this friend as alerted this session
	self._alertedFriendIds = self._alertedFriendIds or {}
	self._alertedFriendIds[friendUserId] = true
end

-- ========== Life Cycle ========== --

function SocialController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps


	-- // Get remotes
	self._claimGroupRewardRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "ClaimGroupReward") :: RemoteEvent
	
	local PlayerGui = GuiRefs.GetPlayerGui(Players.LocalPlayer)
	local SocialGui = GuiRefs.GetScreenGui(PlayerGui, "SocialGui")

	-- // Give the player a group reward gui
	local GroupRewardGui = GroupRewardGuiTemplate:Clone() :: ScreenGui
	GroupRewardGui.Enabled = true
	GroupRewardGui.ResetOnSpawn = false
	GroupRewardGui.Parent = PlayerGui

	self._claimGroupRewardButton = GuiRefs.Get(GroupRewardGui, { "GroupReward", "Frame", "Container", "Bottom", "ClaimButton", "Select" }) :: GuiButton
	GroupRewardGui.GroupReward.Visible = false

	-- // Create a Friend Alert
	self._friendAlert = FriendAlertComponent.new(_deps, {
		rootFrame = GuiRefs.Get(SocialGui, { "FriendAlert" }) :: Frame,
		messageLabel = GuiRefs.Get(SocialGui, { "FriendAlert", "Message" }) :: TextLabel,
		playerIcon = GuiRefs.Get(SocialGui, { "FriendAlert", "PlayerIcon" }) :: ImageLabel,
		closeButton = GuiRefs.Get(SocialGui, { "FriendAlert", "CloseButton", "Select" }) :: GuiButton,
		inviteButton = GuiRefs.Get(SocialGui, { "FriendAlert", "InviteButton", "Select" }) :: GuiButton,
	})
end

function SocialController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- === Friend Invites === --
	-- // Connect friend invite buttons
	for _, v in CollectionService:GetTagged("FriendInviteButton") do
		local button = v :: GuiButton
		self:_setupFriendInviteButton(button)
	end

	CollectionService:GetInstanceAddedSignal("FriendInviteButton"):Connect(function(v)
		local button = v :: GuiButton
		self:_setupFriendInviteButton(button)
	end)

	-- === Friend Boosted Currency Labels === --
	-- // Connect friend boosted currency labels
	for _, v in CollectionService:GetTagged("FriendBoostedCurrencyLabel") do
		local label = v :: TextLabel
		self:_setupFriendBoostLabel(label)
	end

	CollectionService:GetInstanceAddedSignal("FriendBoostedCurrencyLabel"):Connect(function(v)
		local label = v :: TextLabel
		self:_setupFriendBoostLabel(label)
	end)

	-- === Group Rewards === --
	-- // Bind group reward claim button
	table.insert(self._conns, self._claimGroupRewardButton.MouseButton1Down:Connect(function()
		-- Attempt to claim the group reward
		self._claimGroupRewardRemote:FireServer()

		-- Close the menu
		self.Controllers.MenuController:CloseMenu("GroupReward")
	end))

	-- // Set up group reward stands
	for _, v in CollectionService:GetTagged("GroupRewardStand") do
		local stand = v :: Model
		self:_setupGroupRewardStand(stand)
	end

	CollectionService:GetInstanceAddedSignal("GroupRewardStand"):Connect(function(v)
		local stand = v :: Model
		self:_setupGroupRewardStand(stand)
	end)

	-- === Friend Alert Loop === --
	self._friendAlert:Init()

	if AUTO_SEND_FRIEND_ALERTS then
		task.spawn(function()
			task.wait(math.random(30, 60)) -- Initial delay
			while self._started do
				local success = self:AttemptShowFriendAlert()
				local delayTime = success and math.random(120, 180) or 1
				task.wait(delayTime)
			end
		end)
	end

	self:Toast("Welcome!", "Please like and favourite for more updates :)")
end

function SocialController:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return SocialController :: SocialControllerAPI
