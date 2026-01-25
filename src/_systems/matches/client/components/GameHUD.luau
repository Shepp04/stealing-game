--!strict
-- GameHUD (Component)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
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

export type GameHUDAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: GameHUDAPI) -> (),
	Destroy: (self: GameHUDAPI) -> (),

	ToggleExternalPlayerVisibility: (self: GameHUDAPI, state: boolean, ignoreUserIds: { number }?) -> (),
	SetHeading: (self: GameHUDAPI, text: string?) -> (),
	SetSubheading: (self: GameHUDAPI, text: string?) -> (),
	SetPlayerNames: (self: GameHUDAPI, player1Name: string?, player2Name: string?) -> (),
	SetPlayerLives: (self: GameHUDAPI, player1Lives: number, player2Lives: number) -> (),
	SetVisible: (self: GameHUDAPI, visible: boolean) -> (),
}

export type Opts = {
	root: ScreenGui,
	headingTextLabel: TextLabel,
	subheadingTextLabel: TextLabel,

	player1NameLabel: TextLabel,
	player2NameLabel: TextLabel,

	player1Lives: Frame,
	player2Lives: Frame,
}

local GameHUD = {}
GameHUD.__index = GameHUD

-- // Internal state
local _deps: Deps? = nil

-- ========== Constructor ========== --

function GameHUD.new(deps: Deps, opts: Opts): GameHUDAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, GameHUD) :: GameHUDAPI

	self._root = opts.root
	self._headingTextLabel = opts.headingTextLabel
	self._subheadingTextLabel = opts.subheadingTextLabel

	self._player1NameLabel = opts.player1NameLabel
	self._player2NameLabel = opts.player2NameLabel
	self._player1Lives = opts.player1Lives
	self._player2Lives = opts.player2Lives

	return self
end

-- ========== Public API ========== --

function GameHUD:ToggleExternalPlayerVisibility(state: boolean, ignoreUserIds: { number }?)
	-- state == false  -> hide non-round players
	-- state == true   -> show everyone again

	-- storage for connections while hiding is active
	self._visPlayerAddedConn = self._visPlayerAddedConn or nil
	self._visCharConns = self._visCharConns or {}   -- [Player] = RBXScriptConnection

	local function setCharHidden(p: Player, hidden: boolean)
		local char = p.Character
		local human = char and char:FindFirstChild("Humanoid") :: Humanoid
		if not (char and human) then return end
		for _, inst in ipairs(char:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.LocalTransparencyModifier = hidden and 1 or 0
			elseif inst:IsA("Decal") and inst.Name == "face" then
				inst.Transparency = hidden and 1 or 0
			elseif inst:IsA("BillboardGui") and inst.Name == "_Streak_Tag" then
				inst.Enabled = if hidden then false else true
			end
		end
		human.NameDisplayDistance = hidden and 0 or 100
	end

	local function trackCharacter(p: Player, hidden: boolean)
		-- apply to current character
		setCharHidden(p, hidden)
		
		-- update on respawn
		if self._visCharConns[p] then
			self._visCharConns[p]:Disconnect()
			self._visCharConns[p] = nil
		end
		if hidden then
			self._visCharConns[p] = p.CharacterAdded:Connect(function()
				setCharHidden(p, true)
			end)
		end
	end

	-- always clear previous listeners first
	if self._visPlayerAddedConn then
		self._visPlayerAddedConn:Disconnect()
		self._visPlayerAddedConn = nil
	end
	for plr, charConn in pairs(self._visCharConns) do
		charConn:Disconnect()
		self._visCharConns[plr] = nil
	end

	if state == false then
		-- make a fast lookup set of who should remain visible
		local ignoreSet: {[number]: boolean} = {}
		for _, uid in ipairs(ignoreUserIds or {}) do
			if typeof(uid) == "number" then ignoreSet[uid] = true end
		end
		ignoreSet[Players.LocalPlayer.UserId] = true

		-- hide everyone except ignored
		for _, plr in ipairs(Players:GetPlayers()) do
			if not ignoreSet[plr.UserId] then
				trackCharacter(plr, true)
			else
				trackCharacter(plr, false) -- ensure visible (in case we’re toggling while active)
			end
		end

		-- new players that join mid-round should be hidden unless ignored
		self._visPlayerAddedConn = Players.PlayerAdded:Connect(function(player: Player)
			local char = player.Character or player.CharacterAdded:Wait()
			local human = char:WaitForChild("Humanoid")
			ignoreSet[player.UserId] = false
			print(player, "joined. Setting their character visibility to", ignoreSet[player.UserId] == true)
			if ignoreSet[player.UserId] then
				trackCharacter(player, false)
			else
				trackCharacter(player, true)
			end
		end)
	else
		-- restore everyone currently in the server
		for _, plr in ipairs(Players:GetPlayers()) do
			setCharHidden(plr, false)
		end
	end
end

function GameHUD:SetHeading(text: string?)
	if text then
		self._headingTextLabel.Text = text
		self._headingTextLabel.Visible = true
	else
		self._headingTextLabel.Text = ""
		self._headingTextLabel.Visible = false
	end
end

function GameHUD:SetSubheading(text: string?)
	if text then
		self._subheadingTextLabel.Text = text
		self._subheadingTextLabel.Visible = true
	else
		self._subheadingTextLabel.Text = ""
		self._subheadingTextLabel.Visible = false
	end
end

function GameHUD:SetPlayerNames(player1Name: string?, player2Name: string?)
	self._player1NameLabel.Text = player1Name or ""
	self._player2NameLabel.Text = player2Name or ""
end

function GameHUD:SetPlayerLives(player1Lives: number, player2Lives: number, maxLives: number?)
	-- Player 1
	for _, child in pairs(self._player1Lives:GetChildren()) do
		if child:IsA("ImageLabel") then
			local i = tonumber(child.Name)
			if not i then
				warn("Invalid child name for player lives: " .. child.Name)
				continue
			end

			if maxLives and i > maxLives then
				child.Visible = false
				continue
			end
			
			local uiGradient = child:FindFirstChildOfClass("UIGradient")
			if uiGradient then
				uiGradient.Enabled = player1Lives < i
			else
				child.Visible = player1Lives >= i
			end
		end
	end

	-- Player 2
	for _, child in pairs(self._player2Lives:GetChildren()) do
		if child:IsA("ImageLabel") then
			local i = tonumber(child.Name)
			if not i then
				warn("Invalid child name for player lives: " .. child.Name)
				continue
			end

			if maxLives and i > maxLives then
				child.Visible = false
				continue
			end
			
			local uiGradient = child:FindFirstChildOfClass("UIGradient")
			if uiGradient then
				uiGradient.Enabled = player2Lives < i
			else
				child.Visible = player2Lives >= i
			end
		end
	end
end

function GameHUD:SetVisible(visible: boolean)
	self._root.Enabled = visible
end

-- ========== Internal ========== --

function GameHUD:_internalMethod()
	-- Example
end

-- ========== Life Cycle ========== --

function GameHUD:Init()
	if self._inited then return end
	self._inited = true

	-- // Clear state and hide
	self:SetHeading(nil)
	self:SetSubheading(nil)
	self:SetPlayerNames(nil, nil)
	self:SetPlayerLives(0, 0)
	self:SetVisible(false)
end

function GameHUD:Destroy()
	if not self._inited then return end
	self:SetVisible(false)

	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return GameHUD :: GameHUDAPI
