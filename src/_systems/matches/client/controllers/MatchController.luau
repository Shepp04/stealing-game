--!strict
-- MatchController (Controller) — client controller discovered by Controllers registry.

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils:WaitForChild("GuiRefs"))

-- // Components
local GameHUD = require(script.Parent.Parent.Components:WaitForChild("GameHUD"))
local GameCamera = require(script.Parent.Parent.Components:WaitForChild("GameCamera"))
local GameInput = require(script.Parent.Parent.Components:WaitForChild("GameInput"))

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
		local tableInstance: Model? = (... and (...).tableInstance) or nil
		self:StartMatch(tableInstance)
		return
	end

	if kind == "MatchOver" then
		local winnerUserId: number = (... and (...).winnerUserId) or 0
		local winnerCameraCFrame: BasePart? = (... and (...).winnerCameraCFrame) or nil
		
		if winnerUserId == 0 then
			self._gameHUD:SetHeading("Match ended", Color3.fromRGB(255, 255, 255))
		elseif winnerUserId == Players.LocalPlayer.UserId then
			self._gameCamera:Focus(winnerCameraCFrame or CFrame.new(), nil, true)
			self._gameHUD:SetHeading("You won the match!", Color3.fromRGB(0, 255, 0))
			self._gameHUD:SetSubheading(nil)
			_deps.SharedPackages.Sounds:PlaySound("WinMatch")
		else
			self._gameCamera:Focus(winnerCameraCFrame or CFrame.new(), nil, true)
			self._gameHUD:SetHeading("Opponent won the match", Color3.fromRGB(255, 0, 0))
			_deps.SharedPackages.Sounds:PlaySound("LoseMatch")
			_deps.SharedPackages.Sounds:PlaySound("Angry")
		end

		task.wait(5.0)
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
		self._gameHUD:SetSubheading("Skipping pick in " .. tostring(secondsLeft) .. "s")
		return
	end

	if kind == "Camera" then
		local cframe: CFrame = (... and (...).cframe) or CFrame.new()
		local subject: Instance? = (... and (...).subject) or nil
		local tween: boolean = (... and (...).tween) or false

		self._gameCamera:Focus(cframe, subject, tween)
		return
	end

	if kind == "ClearMessages" then
		self._gameHUD:SetHeading(nil)
		self._gameHUD:SetSubheading(nil)
		return
	end

	if kind == "Message" then
		local payload = ...
		if typeof(payload) == "table" then
			self._gameHUD:SetHeading(payload.heading)
			self._gameHUD:SetSubheading(payload.subheading)
		end
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

	if kind == "YourResult" then
		self:_destroyDefenderWinningMarker()
		local result: string = (... and (...).result) or "Empty"
		if result == "Win" then
			self._gameHUD:SetHeading("STEAL!", Color3.fromRGB(0, 255, 0))
			self._gameHUD:SetSubheading(nil)
		elseif result == "Lose" then
			_deps.SharedPackages.Sounds:PlaySound("Scream")
			self._gameHUD:SetHeading("BOMB!", Color3.fromRGB(255, 0, 0))
			self._gameHUD:SetSubheading(nil)
		else
			self._gameHUD:SetHeading("EMPTY!", Color3.fromRGB(0, 255, 0))
			self._gameHUD:SetSubheading("1 cup has been removed")
		end
	end

	if kind == "TheirResult" then
		self:_destroyDefenderWinningMarker()
		local result: string = (... and (...).result) or "Empty"
		if result == "Win" then
			self._gameHUD:SetHeading("STOLEN!", Color3.fromRGB(255, 0, 0))
			self._gameHUD:SetSubheading(nil)
		elseif result == "Lose" then
			self._gameHUD:SetHeading("BOMB!", Color3.fromRGB(0, 255, 0))
			self._gameHUD:SetSubheading(nil)
		else
			self._gameHUD:SetHeading("EMPTY!", Color3.fromRGB(0, 255, 0))
			self._gameHUD:SetSubheading("1 cup has been removed")
		end
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

function MatchController:StartMatch(tableInstance: Model?)
	-- Show the HUD
	if self._gameHUD then
		self._gameHUD:SetVisible(true)
	end

	-- Enabled game input
	if self._gameInput then
		self._gameInput:SetInputEnabled(true)
	end

	-- Store table instance for later use
	self._tableInstance = tableInstance
	self._matchRunning = true
end

function MatchController:EndMatch()
	self._matchRunning = false
	self:_destroyDefenderWinningMarker()

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

	-- Reset game input
	if self._gameInput then
		self._gameInput:SetInputEnabled(false)
		self._gameInput:ClearItemObjects()
	end
end

-- ========== Internal ========== --

-- ===== Helpers ===== --
function MatchController:_getBoardModels(boardUserId: number): { Model }
	-- find the player folder based on slot ordering, or by BoardUserId attribute
	-- simplest: scan tableInstance descendants for models with BoardUserId attr
	local models = {}
	local tableInstance = self._tableInstance -- store from RoundBegin payload
	if not tableInstance then
		warn("[MatchController] _getBoardModels: no tableInstance set")
		return models
	end

	for _, inst in ipairs(tableInstance:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("BoardUserId") == boardUserId then
			table.insert(models, inst)
		end
	end
	return models
end

function MatchController:_getItemModelByIndex(boardUserId: number, itemIndex: number): Model?
	local models = self:_getBoardModels(boardUserId)
	for _, model in ipairs(models) do
		if model:GetAttribute("ItemIndex") == itemIndex then
			return model
		end
	end
	return nil
end

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
		-- self._gameHUD:SetHeading("You won the round!", Color3.fromRGB(0, 255, 0))
		_deps.SharedPackages.Sounds:PlaySound("WinRound")
	else
		-- self._gameHUD:SetHeading("You lost the round!", Color3.fromRGB(255, 0, 0))
		_deps.SharedPackages.Sounds:PlaySound("LoseRound")
	end
end

-- ===== Turn / Phase ===== --
function MatchController:_onTurn(payload: any)
	-- payload example:
	-- { phase = "Setup" | "Shuffle" | "Choose", attackerUserId=?, defenderUserId=? }
	if typeof(payload) ~= "table" then return end

	local phase = payload.phase
	local attackerUserId = payload.attackerUserId
	local defenderUserId = payload.defenderUserId

	local shuffleEnabled = payload.shuffleEnabled or false

	local hoverEnabled = payload.hoverEnabled or false
	local shakeEnabled = payload.shakeEnabled or false

	-- Always clear first
	self._gameInput:ClearItemObjects()
	self._gameInput:SetClickAction(nil)
	self._gameInput:SetShuffleButtonVisible(false)

	self._currentPhase = phase
	self._attackerUserId = attackerUserId
	self._defenderUserId = defenderUserId

	self._gameInput:SetShuffleButtonVisible(shuffleEnabled)
	self._gameInput:SetHoverEnabled(hoverEnabled)
	self._gameInput:SetShakeEnabled(shakeEnabled)

	if phase == "Setup" then
		local waitingForDefender = payload.waitingForDefender == true

		if defenderUserId == self._localUserId then
			-- Defender: choose where to hide lunch
			self._gameInput:SetClickAction("SetWinningItem")

			local models = self:_getBoardModels(defenderUserId)
			self._gameInput:CreateItemObjects(models)
			self._gameInput:AnimateItemsIn()

			self._gameHUD:SetHeading("HIDE YOUR LUNCH!")
			self._gameHUD:SetSubheading("Tap a cup")
		elseif waitingForDefender then
			-- Attacker: message is set by server (Message broadcast with defender's display name)
			-- No need to set heading here; server sends "Message" with full text
		end
	elseif phase == "Shuffle" then
		-- If local player is attacker, this is the “watch + memorise” moment
		if self._attackerUserId == self._localUserId then
			self._gameHUD:SetHeading(nil)
			self._gameHUD:SetSubheading(nil)
		else
			self._gameHUD:SetHeading(nil)
			self._gameHUD:SetSubheading(nil)
		end
	elseif phase == "Choose" then
		if self._attackerUserId == self._localUserId then
			-- Only attacker/chooser can click defender board to select
			self._gameInput:SetClickAction("SelectItem")
			local models = self:_getBoardModels(defenderUserId)
			self._gameInput:CreateItemObjects(models)

			-- Show text
			self._gameHUD:SetHeading("CHOOSE A CUP!")
			self._gameHUD:SetSubheading(nil)
		else
			self._gameHUD:SetHeading(nil)
			self._gameHUD:SetSubheading("Opponent is choosing a cup...")
		end
	end
end

-- ===== Reveal / Shuffle / Board Updates ===== --
function MatchController:_onReveal(payload: any)
	-- payload expected:
	-- { defenderUserId=number, losingItemMask={ [i]=boolean }, itemModels={ [i]=Model }, revealSeconds=number }
	if typeof(payload) ~= "table" then return end
	self._revealActive = true
	self._lastReveal = payload

	local losingItemMask = payload.losingItemMask
	if typeof(losingItemMask) ~= "table" then
		losingItemMask = {}
	end

	for itemIndex, isLosing in losingItemMask do
		task.spawn(function()
			self._gameHUD:RevealItemMask(
				payload.itemModels[itemIndex],
				isLosing and "Lose" or "Empty",
				payload.revealSeconds or 1.25
			)
		end)
	end

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
		self._gameHUD:SetSubheading("1 cup was removed")
	end
end

function MatchController:_destroyDefenderWinningMarker()
	local gui = self._defenderWinningMarkerGui
	self._defenderWinningMarkerGui = nil
	if not gui or not gui.Parent then return end

	local canvasGroup = gui:FindFirstChild("Content") :: CanvasGroup?
	if canvasGroup then
		local fadeOut = TweenService:Create(canvasGroup, TweenInfo.new(0.3), { GroupTransparency = 1 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if gui.Parent then
				gui:Destroy()
			end
		end)
	else
		gui:Destroy()
	end
end

function MatchController:_onAutoAction(payload: any)
	-- payload example:
	-- { kind="SetWinningItem"|"SelectItem"|"RevealItem", userId=?, itemIndex=?, content=? }
	if typeof(payload) ~= "table" then return end

	if payload.kind == "SetWinningItem" then
		if payload.userId == self._localUserId then
			self:_destroyDefenderWinningMarker()
			local itemModel = self:_getItemModelByIndex(self._localUserId, payload.itemIndex)
			if itemModel then
				local attachPart = itemModel.PrimaryPart or itemModel:FindFirstChildWhichIsA("BasePart")
				if attachPart then
					local gui = Instance.new("BillboardGui")
					gui.Name = "_DefenderWinningMarker"
					gui.Adornee = attachPart
					gui.Size = UDim2.fromScale(0.8, 0.8)
					gui.StudsOffset = Vector3.new(0, 0, 0)
					gui.AlwaysOnTop = true
					gui.Parent = itemModel

					local canvasGroup = Instance.new("CanvasGroup")
					canvasGroup.Name = "Content"
					canvasGroup.BackgroundTransparency = 1
					canvasGroup.Size = UDim2.fromScale(1, 1)
					canvasGroup.GroupTransparency = 1
					canvasGroup.Parent = gui

					local label = Instance.new("TextLabel")
					label.Size = UDim2.fromScale(1, 1)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.Highway
					label.TextScaled = true
					label.Text = "X"
					label.TextColor3 = Color3.fromRGB(255, 255, 255)
					label.Parent = canvasGroup

					local stroke = Instance.new("UIStroke")
					stroke.Thickness = 2
					stroke.Color = Color3.new(0.2, 0.2, 0.2)
					stroke.Parent = label

					self._defenderWinningMarkerGui = gui
					-- Fade in
					TweenService:Create(canvasGroup, TweenInfo.new(0.35), { GroupTransparency = 0 }):Play()
				end
			end
		end
	elseif payload.kind == "SelectItem" then
		if payload.userId == self._localUserId then
			-- self._gameHUD:SetSubheading("Auto-picked an item")
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

	-- // Defender winning-item marker (BillboardGui "X"), destroyed when result is shown
	self._defenderWinningMarkerGui = nil :: Instance?

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

	-- // Create a game input handler
	self._gameInput = GameInput.new(_deps, {
		root = GameHUDGui,
		shuffleButton = {
			container = GuiRefs.Get(GameHUDGui, { "Actions", "Shuffle" }) :: Frame,
			select = GuiRefs.Get(GameHUDGui, { "Actions", "Shuffle", "Select" }) :: TextButton,
		},
		onAction = function(action: GameTypes.GameAction, payload: { any }?)
			-- Forward to server
			print("GameInput action:", action, payload)
			self._gameActionRemote:FireServer(action, payload or {})
			return true
		end,
	})
end

function MatchController:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Init the HUD and camera
	self._gameHUD:Init()
	self._gameCamera:Init()
	self._gameInput:Init()

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
