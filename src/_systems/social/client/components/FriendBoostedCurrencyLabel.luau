--!strict
-- FriendBoostedCurrencyLabel (Component)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

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

export type FriendBoostedCurrencyLabelAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: FriendBoostedCurrencyLabelAPI) -> (),
	Destroy: (self: FriendBoostedCurrencyLabelAPI) -> (),
}

export type Opts = {
	textLabel: TextLabel,
	currencyId: string,
}

local FriendBoostedCurrencyLabel = {}
FriendBoostedCurrencyLabel.__index = FriendBoostedCurrencyLabel

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function FriendBoostedCurrencyLabel.new(deps: Deps, opts: Opts): FriendBoostedCurrencyLabelAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, FriendBoostedCurrencyLabel) :: FriendBoostedCurrencyLabelAPI

	self._currencyId = opts.currencyId
	self._textLabel = opts.textLabel

	-- Validate currency info
	local currencyInfo = _deps.GameData.Get("Currency", self._currencyId)
	if not currencyInfo then
		error("FriendBoostedCurrencyLabel: Invalid currencyId: " .. tostring(self._currencyId))
	end

	if currencyInfo.friendBoostMultiplier == nil then
		error("FriendBoostedCurrencyLabel: Currency does not support friend boosts: " .. tostring(self._currencyId))
	end

	self._friendBoostMultiplier = currencyInfo.friendBoostMultiplier

	return self
end

-- ========== Public API ========== --

function FriendBoostedCurrencyLabel:Update()
	-- Find how many friends are in the server
	local friendCount = 0
	for _, plr in pairs(Players:GetPlayers()) do
		if (Players.LocalPlayer:IsFriendsWith(plr.UserId)) then
			friendCount += 1
		end
	end

	-- Update label
	local boostPercent = (self._friendBoostMultiplier - 1) * friendCount * 100
	self._textLabel.Text = string.format("+%.0f%%", boostPercent)
end

-- ========== Internal ========== --

function FriendBoostedCurrencyLabel:_onPlayerAdded()
	self:Update()
end

function FriendBoostedCurrencyLabel:_onPlayerRemoving()
	self:Update()
end

-- ========== Life Cycle ========== --

function FriendBoostedCurrencyLabel:Init()
	if self._inited then return end
	self._inited = true

	-- Initial update
	self:Update()

	-- // Bind signals
	table.insert(self._conns, Players.PlayerAdded:Connect(function(...)
		self:_onPlayerAdded(...)
	end))
	table.insert(self._conns, Players.PlayerRemoving:Connect(function(...)
		self:_onPlayerRemoving(...)
	end))
end

function FriendBoostedCurrencyLabel:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
	self._textLabel.Text = ""
end

return FriendBoostedCurrencyLabel :: FriendBoostedCurrencyLabelAPI
