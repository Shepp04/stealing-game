--!strict
-- MatchController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils:WaitForChild("GuiRefs"))

-- // Components
local GameHUD = require(script.Parent.Parent.Components:WaitForChild("GameHUD"))
local GameCamera = require(script.Parent.Parent.Components:WaitForChild("GameCamera"))

-- // Types (custom)
local GameTypes = require(ReplicatedStorage.Shared.Types.Game)
type GameBroadcastState = GameTypes.GameBroadcastState

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

export type MatchControllerAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Controllers: ControllerRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: MatchControllerAPI, deps: Deps) -> (),
	Start: (self: MatchControllerAPI) -> (),
	Destroy: (self: MatchControllerAPI) -> (),

	HandleGameStateUpdate: (self: MatchControllerAPI, state: GameBroadcastState, args: any) -> (),
	StartMatch: (self: MatchControllerAPI) -> (),
	EndMatch: (self: MatchControllerAPI) -> (),
}

local MatchController = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Controllers = {} :: ControllerRegistry,
} :: MatchControllerAPI

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Public API ========== --

function MatchController:HandleGameStateUpdate(kind: GameBroadcastState, ...: any)
	print("MatchController:HandleGameStateUpdate", kind, ...)

	-- ===== Match State =====
	if kind == "MatchBegin" then
		self:StartMatch()
		return
	end

	if kind == "MatchOver" then
		local winnerUserId: number = (... and (...).winnerUserId) or 0
		local winnerCameraCFrame: BasePart? = (... and (...).winnerCameraCFrame) or nil
		
		if winnerUserId == 0 then
			self._gameHUD:SetHeading("Match ended")
		elseif winnerUserId == Players.LocalPlayer.UserId then
			self._gameCamera:Focus(winnerCameraCFrame or CFrame.new(), nil, true)
			self._gameHUD:SetHeading("You won the match!")
			_deps.SharedPackages.Sounds:PlaySound("WinMatch")
		else
			self._gameCamera:Focus(winnerCameraCFrame or CFrame.new(), nil, true)
			self._gameHUD:SetHeading("Opponent won the match")
			_deps.SharedPackages.Sounds:PlaySound("LoseMatch")
		end

		self:EndMatch()
		return
	end

	if kind == "LeaveMatch" then
		_deps.SharedPackages.Sounds:PlaySound("LeaveMatch")
		self:EndMatch()
		return
	end

	-- If match isn’t running, ignore round/gameplay messages
	if not self._matchRunning then
		return
	end

	-- ===== Core HUD / Camera =====
	if kind == "Players" then
		local userId1: number = (... and (...).userId1) or 0
		local userId2: number = (... and (...).userId2) or 0
		self._playerUserIds = { userId1, userId2 }

		local player1 = Players:GetPlayerByUserId(userId1)
		local player2 = Players:GetPlayerByUserId(userId2)
		self._gameHUD:SetPlayerNames(player1 and player1.DisplayName or "Player 1", player2 and player2.DisplayName or "Player 2")
		self._gameHUD:ToggleExternalPlayerVisibility(false, { userId1, userId2 })
		return
	end

	if kind == "TurnCountdown" then
		local secondsLeft: number = (... and (...).secondsLeft) or 0
		self._gameHUD:SetSubheading("Skipping turn in " .. tostring(secondsLeft) .. "s")
		return
	end

	if kind == "Camera" then
		local cframe: CFrame = (... and (...).cframe) or CFrame.new()
		local subject: Instance? = (... and (...).subject) or nil
		local tween: boolean = (... and (...).tween) or false

		self._gameCamera:Focus(cframe, subject, tween)
		return
	end

	-- ===== Round / Gameplay =====
	if kind == "RoundBegin" then
		local payload = ...
		self:_onRoundBegin(payload)
		return
	end

	if kind == "RoundEnd" then
		local payload = ...
		self:_onRoundEnd(payload)
		return
	end

	if kind == "Score" then
		local player1Score: number = (... and (...).player1Score) or 0
		local player2Score: number = (... and (...).player2Score) or 0
		local winsToWin: number = (... and (...).winsToWin) or 0
		self._gameHUD:SetPlayerLives(winsToWin - player2Score, winsToWin - player1Score, winsToWin)
		return
	end

	if kind == "Turn" then
		local payload = ...
		self:_onTurn(payload)
		return
	end

	if kind == "Reveal" then
		local payload = ...
		self:_onReveal(payload)
		return
	end

	if kind == "ShuffleBeat" then
		local payload = ...
		self:_onShuffleBeat(payload)
		return
	end

	if kind == "BoardUpdate" then
		local payload = ...
		self:_onBoardUpdate(payload)
		return
	end

	if kind == "AutoAction" then
		local payload = ...
		self:_onAutoAction(payload)
		return
	end

	-- Unknown / not handled yet
end

function MatchController:StartMatch()
	-- Show the HUD
	if self._gameHUD then
		self._gameHUD:SetVisible(true)
	end

	self._matchRunning = true
end

function MatchController:EndMatch()
	self._matchRunning = false

	-- Hide the HUD
	if self._gameHUD then
		self._gameHUD:SetVisible(false)
		self._gameHUD:ToggleExternalPlayerVisibility(true)
		self._gameHUD:SetPlayerLives(0, 0)
		self._gameHUD:SetHeading(nil)
		self._gameHUD:SetSubheading(nil)
		self._gameHUD:SetPlayerNames(nil, nil)
	end

	-- Reset camera
	if self._gameCamera then
		self._gameCamera:Reset(false)
	end
end

-- ========== Internal ========== --

-- ===== Round Handlers ===== --
function MatchController:_onRoundBegin(payload: any)
	self._roundRunning = true
	self._gameHUD:SetHeading("Round start!")
	self._gameHUD:SetSubheading(nil)

	-- Optional: reset lives display if you use it per round
	-- self._gameHUD:SetPlayerLives(2, 2)

	-- payload might include: numItems, userIds, tableInstance, etc.
	-- Keep generic: just store if provided
	if typeof(payload) == "table" then
		-- If server sends userIds in RoundBegin, capture
		if payload.userIds then
			self._playerUserIds = payload.userIds
		end
	end
end

function MatchController:_onRoundEnd(payload: any)
	self._roundRunning = false

	local winnerUserId = payload and payload.winnerUserId
	if winnerUserId == nil then
		self._gameHUD:SetHeading("Round ended")
		return
	end

	if winnerUserId == self._localUserId then
		self._gameHUD:SetHeading("You won the round!")
		_deps.SharedPackages.Sounds:PlaySound("WinRound")
	else
		self._gameHUD:SetHeading("You lost the round!")
		_deps.SharedPackages.Sounds:PlaySound("LoseRound")
	end
end

-- ===== Turn / Phase ===== --
function MatchController:_onTurn(payload: any)
	-- payload example:
	-- { phase = "Setup" | "Shuffle" | "Choose", attackerUserId=?, defenderUserId=? }
	if typeof(payload) ~= "table" then return end

	self._currentPhase = payload.phase
	self._attackerUserId = payload.attackerUserId
	self._defenderUserId = payload.defenderUserId

	if payload.phase == "Setup" then
		self._gameHUD:SetHeading("Hide your winning item")
		self._gameHUD:SetSubheading("Pick an item position")
	elseif payload.phase == "Shuffle" then
		-- If local player is attacker, this is the “watch + memorise” moment
		if self._attackerUserId == self._localUserId then
			self._gameHUD:SetHeading("Memorise the losing items!")
			self._gameHUD:SetSubheading("They will shuffle…")
		else
			self._gameHUD:SetHeading("Shuffling…")
			self._gameHUD:SetSubheading(nil)
		end
	elseif payload.phase == "Choose" then
		if self._attackerUserId == self._localUserId then
			self._gameHUD:SetHeading("Pick an item!")
			self._gameHUD:SetSubheading("Find the winning item")
		else
			self._gameHUD:SetHeading("Opponent is choosing…")
			self._gameHUD:SetSubheading(nil)
		end
	end
end

-- ===== Reveal / Shuffle / Board Updates ===== --
function MatchController:_onReveal(payload: any)
	-- payload expected:
	-- { defenderUserId=number, losingItemMask={ [i]=boolean }, revealSeconds=number }
	if typeof(payload) ~= "table" then return end
	self._revealActive = true
	self._lastReveal = payload

	-- STUB: apply highlight on the defender board items based on mask
	-- You’ll implement the visuals later (e.g. item:SetAttribute("IsLosing", true) + client glow)
	-- Example:
	-- self:_setBoardMaskVisuals(payload.defenderUserId, payload.losingItemMask, true)

	local revealSeconds = payload.revealSeconds or 1.25
	task.delay(revealSeconds, function()
		-- Turn token not tracked clientside; just guard match running
		if not self._matchRunning then return end
		self._revealActive = false
		-- self:_setBoardMaskVisuals(payload.defenderUserId, payload.losingItemMask, false)
	end)
end

function MatchController:_onShuffleBeat(payload: any)
	-- payload expected:
	-- { defenderUserId=number, pairs={ {a=1,b=4}, ... }, beatDuration=number }
	if typeof(payload) ~= "table" then return end

	-- STUB: animate simultaneous swaps locally for feel.
	-- You can either:
	-- (A) purely animate and trust server moved items (recommended), or
	-- (B) animate based on a client-maintained mapping.
	--
	-- For now: just play SFX + optional screen shake, and leave actual movement to server replication.
	_deps.SharedPackages.Sounds:PlaySound("ShuffleBeat")

	-- Later:
	-- self:_animateSwapPairs(payload.defenderUserId, payload.pairs, payload.beatDuration)
end

function MatchController:_onBoardUpdate(payload: any)
	-- payload: { boardUserId=number, numItems=number }
	if typeof(payload) ~= "table" then return end

	local boardUserId = payload.boardUserId
	local numItems = payload.numItems

	self._boards[boardUserId] = self._boards[boardUserId] or {}
	self._boards[boardUserId].numItems = numItems

	-- STUB: update UI (like “items left: X”) or play a sound
	_deps.SharedPackages.Sounds:PlaySound("ItemRemoved")

	-- Optional HUD hint
	if self._attackerUserId == self._localUserId then
		self._gameHUD:SetSubheading(("Items left: %d"):format(numItems))
	end
end

function MatchController:_onAutoAction(payload: any)
	-- payload example:
	-- { kind="SetWinningItem"|"SelectItem"|"RevealItem", userId=?, itemIndex=?, content=? }
	if typeof(payload) ~= "table" then return end

	-- STUB: for debugging + future UX.
	-- For example, if server auto-picked, you can show a toast:
	if payload.kind == "SetWinningItem" then
		-- only show to the player whose item was set
		if payload.userId == self._localUserId then
			self._gameHUD:SetSubheading("Auto-picked a hiding spot")
		end
	elseif payload.kind == "SelectItem" then
		if payload.userId == self._localUserId then
			self._gameHUD:SetSubheading("Auto-picked an item")
		end
	elseif payload.kind == "RevealItem" then
		-- This is where you’d animate opening + reveal feedback
	end
end

-- ========== Life Cycle ========== --

function MatchController:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Initialise state
	self._matchRunning = false

	-- Round state
	self._roundRunning = false
	self._localUserId = Players.LocalPlayer.UserId
	self._playerUserIds = {} :: { number } -- {p1, p2}
	self._currentPhase = nil :: string?
	self._attackerUserId = nil :: number?
	self._defenderUserId = nil :: number?

	-- // Board / items
	-- boards are keyed by owner userId (defender boards)
	self._boards = {} :: {
		[number]: {
			items: { Model }?, -- optional cache (if you want)
			numItems: number?,
		}
	}

	-- // Reveal state
	self._revealActive = false
	self._lastReveal = nil :: any

	-- // Get remotes
	self._gameStateRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "GameState") :: RemoteEvent
	self._gameActionRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "GameAction") :: RemoteEvent

	-- // Get Gui elements
	local PlayerGui = GuiRefs.GetPlayerGui(Players.LocalPlayer)
	local GameHUDGui = GuiRefs.GetScreenGui(PlayerGui, "GameHUD")

	-- // Create a game HUD
	self._gameHUD = GameHUD.new(_deps, {
		root = GameHUDGui,
		headingTextLabel = GuiRefs.Get(GameHUDGui, { "Heading" }) :: TextLabel,
		subheadingTextLabel = GuiRefs.Get(GameHUDGui, { "Subheading" }) :: TextLabel,
		player1NameLabel = GuiRefs.Get(GameHUDGui, { "Score", "Scores", "Player1", "PlayerName" }) :: TextLabel,
		player2NameLabel = GuiRefs.Get(GameHUDGui, { "Score", "Scores", "Player2", "PlayerName" }) :: TextLabel,
		player1Lives = GuiRefs.Get(GameHUDGui, { "Score", "Scores", "Player1", "Lives" }) :: Frame,
		player2Lives = GuiRefs.Get(GameHUDGui, { "Score", "Scores", "Player2", "Lives" }) :: Frame,
	})

	-- // Create a game camera
	self._gameCamera = GameCamera.new(_deps, {})
end

function MatchController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Init the HUD and camera
	self._gameHUD:Init()
	self._gameCamera:Init()

	-- // Setup remotes
	table.insert(self._conns, self._gameStateRemote.OnClientEvent:Connect(function(kind: GameBroadcastState, ...: any)
		self:HandleGameStateUpdate(kind, ...)
	end))
end

function MatchController:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return MatchController :: MatchControllerAPI
