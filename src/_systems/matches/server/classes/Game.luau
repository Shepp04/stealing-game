--!strict
-- Game (Server Class)

-- // Roblox Services
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
local GameTypes = require(ReplicatedStorage.Shared.Types.Game)
type GameContext = GameTypes.GameContext
type GameBroadcastState = GameTypes.GameBroadcastState
type GameAction = GameTypes.GameAction
type TurnType = GameTypes.TurnType
type ItemContent = GameTypes.ItemContent

type ItemState = {
	instance: Model,
	posIndex: number,
	content: ItemContent,
}

type BoardState = {
	ownerUserId: number,
	items: { ItemState },
	positions: { CFrame }, -- static slot transforms
	winningItemChosen: boolean,
}

export type GameState = {
	phase: TurnType,
	timeoutSeconds: number,

	attackerUserId: number?, -- chooser
	defenderUserId: number?, -- whose board is being attacked (also shuffler by default)
	activeBoardUserId: number?,

	boards: { [number]: BoardState },

	-- shuffle settings per current turn
	shuffleBeats: number,
	beatDuration: number,
}

local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps
type ServiceRegistry = ServicesTypes.Registry

type ReplicatedData = typeof(require(ReplicatedStorage.Shared.Packages.ReplicatedData))
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	ReplicatedData: ReplicatedData,
	Services: ServiceRegistry,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type Opts = {
	-- args used when constructing the class
	onGameEnd: ((winner: Player?) -> ()),
	ctx: GameContext,
	tunables: Tunables?, -- optional overrides per round/table
}

export type GameAPI = {
	ctx: GameContext,
	gameState: GameState,

	Start: (self: GameAPI) -> (),
	Destroy: (self: GameAPI) -> (),
	HandleAction: (self: GameAPI, player: Player, action: GameAction, payload: { any }?) -> (),
}

local Game = {}
Game.__index = Game

-- // Internal state
local _deps: Deps?

-- // Constants
local SAMPLE_ITEM_MODEL = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Items"):WaitForChild("SampleItem") :: Model
local EXPLODE_ANIMATION = Instance.new("Animation"); EXPLODE_ANIMATION.AnimationId = "rbxassetid://126527283467855"

-- ========== Helpers ========== --

local function clampInt(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- ========== Constructor ========== --

function Game.new(deps: Deps, opts: Opts): GameAPI
	_deps = deps

	local self = setmetatable({}, Game) :: any
	self._deps = deps
	self._opts = opts
	self.ctx = opts.ctx
	self._onGameEnd = opts.onGameEnd

	self._tunables = table.clone(deps.Tunables or {})
	if opts.tunables then
		for k, v in pairs(opts.tunables) do
			self._tunables[k] = v
		end
	end

	self.gameState = {
		phase = "Setup",
		timeoutSeconds = self:_t("turnTimeout", 20),

		attackerUserId = nil,
		defenderUserId = nil,
		activeBoardUserId = nil,

		boards = {},

		shuffleBeats = 4,
		beatDuration = 0.45,
	} :: GameState

	self._turnToken = 0
	self._dead = false
	self._conns = {}

	-- // Validate model
	local tableInstance = self.ctx.tableInstance
	assert(tableInstance, "Game requires a table instance in context")

	local cameraCFramesFolder = tableInstance:FindFirstChild("CameraCFrames") :: Folder?
	if not cameraCFramesFolder then
		error("Game requires CameraCFrames folder in table instance")
	end

	self._cameraCFrames = {
		board1 = cameraCFramesFolder:FindFirstChild("Board1").CFrame :: CFrame,
		board2 = cameraCFramesFolder:FindFirstChild("Board2").CFrame :: CFrame,
		board1Overhead = cameraCFramesFolder:FindFirstChild("Board1Overhead").CFrame :: CFrame,
		board2Overhead = cameraCFramesFolder:FindFirstChild("Board2Overhead").CFrame :: CFrame,
		winner = cameraCFramesFolder:FindFirstChild("Winner").CFrame :: CFrame,
		matchEnd = cameraCFramesFolder:FindFirstChild("MatchEnd").CFrame :: CFrame,
	} :: { [string]: CFrame }

	return (self :: any) :: GameAPI
end

-- ========== Public API ========== --

function Game:Start(starterUserId: number?)
	local players = self.ctx.getPlayers()
	assert(#players == 2, "Game expects exactly 2 players")

	-- Spawn boards for each player
	for seatIndex, plr in ipairs(players) do
		self:_spawnBoardForPlayer(plr, seatIndex)
	end

	-- Pick attacker and defender for this round (only defender chooses hiding spot this turn)
	local attackerUserId: number
	local defenderUserId: number
	if starterUserId then
		defenderUserId = starterUserId
		for _, plr in ipairs(players) do
			if plr.UserId ~= starterUserId then
				attackerUserId = plr.UserId
				break
			end
		end
	else
		local startIdx = (self:_t("randomFirst", true) and math.random(1, 2)) or 1
		attackerUserId = players[startIdx].UserId
		defenderUserId = players[3 - startIdx].UserId
	end
	assert(attackerUserId and defenderUserId, "Failed to pick attacker and defender")

	-- Broadcast round begin
	self.ctx.broadcast("RoundBegin", {
		userIds = { userId1 = players[1].UserId, userId2 = players[2].UserId },
	})

	-- Clear initial messages
	self.ctx.broadcast("ClearMessages", {})

	-- Start turn: Setup (defender only) then shuffle/choose
	self:_beginTurn(attackerUserId, defenderUserId)
end

-- ===== Actions ===== --

function Game:HandleAction(player: Player, action: GameAction, payload: { any }?)
	if self._dead then return end

	-- ===== Debug ===== --
	print("[Game] HandleAction from player ", player.Name, " action=", action)
	-- ================= --

	if not payload then
		payload = {}
	end

	if action == "SetWinningItem" then
		if self.gameState.phase ~= "Setup" then return end
		if player.UserId ~= self.gameState.defenderUserId then return end
		local itemIndex = payload.itemIndex or 0 :: number
		self:_setWinningItem(player.UserId, itemIndex)
		self:_afterDefenderSetup()
		return
	end

	if action == "SelectItem" then
		if self.gameState.phase ~= "Choose" then return end
		if player.UserId ~= self.gameState.attackerUserId then return end
		local itemIndex = payload.itemIndex or 0 :: number
		self:_resolvePick(player.UserId, itemIndex)
		return
	end

	if action == "StartShuffle" then
		if self.gameState.phase ~= "Shuffle" then return end
		if player.UserId ~= self.gameState.defenderUserId then return end
		-- validate if shuffle is enabled for this player
		if not self._isScrambleRunning then
			self:_startScramble(player.UserId)
		end
		return
	end

	if action == "StopShuffle" then
		if self.gameState.phase ~= "Shuffle" then return end
		if player.UserId ~= self.gameState.defenderUserId then return end
		-- validate if shuffle is enabled for this player
		if self._isScrambleRunning then
			self:_endScramble(player.UserId)
		end
		return
	end

	-- Keep open for manual shuffler UX later:
	-- if action == "ShuffleInput" then
	--   validate shufflerUserId == defenderUserId
	--   apply provided pairs as a beat (or stream)
	-- end
end

-- ========== Internal ========== --

-- ===== Internal Helpers ===== --
function Game:_t(key: string, defaultValue: any): any
	local v = self._tunables[key]
	if v == nil then
		return defaultValue
	end
	return v
end

function Game:_setWinningItem(userId: number, itemIndex: number)
	print("Setting winning item for userId=", userId, " itemIndex=", itemIndex)
	local board = self.gameState.boards[userId]
	if not board or board.winningItemChosen then warn("No board found or winning item already chosen for userId=", userId) return end

	itemIndex = clampInt(itemIndex, 1, #board.items)
	-- mark winning item placeholder; actual contents assigned later
	board.winningItemChosen = true
	board._winningItemIndex = itemIndex

	self.ctx.broadcast("AutoAction", {
		kind = "SetWinningItem",
		userId = userId,
		itemIndex = itemIndex,
	})
end

function Game:_autoSetWinningItem(userId: number)
	print("Auto-setting winning item for userId=", userId)
	local board = self.gameState.boards[userId]
	if not board or board.winningItemChosen then warn("No board found or winning item already chosen for userId=", userId, board, board and board.winningItemChosen) return end
	local idx = math.random(1, #board.items)
	self:_setWinningItem(userId, idx)
end

function Game:_assignBoardContents(userId: number)
	local board = self.gameState.boards[userId]
	if not board then return end

	local n = #board.items
	local numLosingItems = clampInt(self:_t("numLosingItems", 2), 0, n - 1)
	local numEmpty = clampInt(self:_t("numEmptySafe", n - 1 - numLosingItems), 0, n - 1 - numLosingItems)
	-- 1 winning item always

	-- clear first
	for _, item in ipairs(board.items) do
		item.content = "Empty"
	end

	local winningItemIndex = board._winningItemIndex or math.random(1, n)
	board.items[winningItemIndex].content = "Win"

	-- fill losing items + empties in remaining slots
	local remaining = {}
	for i = 1, n do
		if i ~= winningItemIndex then
			table.insert(remaining, i)
		end
	end

	-- shuffle remaining
	for i = #remaining, 2, -1 do
		local j = math.random(1, i)
		remaining[i], remaining[j] = remaining[j], remaining[i]
	end

	-- losing items first
	for i = 1, numLosingItems do
		local idx = remaining[i]
		board.items[idx].content = "Lose"
	end

	-- remaining are empty safe (already Empty)
end

-- ===== Turn Loop ===== --

--[[
	_beginTurn
	Starts a turn: Setup (defender chooses hiding spot only), then after setup we reveal, shuffle, choose.
]]
function Game:_beginTurn(attackerUserId: number, defenderUserId: number)
	if self._dead then return end

	print("Beginning turn: attacker=", attackerUserId, " defender=", defenderUserId)
	self.gameState.attackerUserId = attackerUserId
	self.gameState.defenderUserId = defenderUserId
	self.gameState.activeBoardUserId = defenderUserId

	-- Setup phase: only defender chooses where to hide lunch
	self.gameState.phase = "Setup"
	local setupToken = self:_nextTurnToken()

	-- Reset defender board so they can choose hiding spot again this turn
	local defenderBoard = self.gameState.boards[defenderUserId]
	if defenderBoard then
		defenderBoard.winningItemChosen = false
		defenderBoard._winningItemIndex = nil
	end

	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == defenderUserId then
			self.ctx.send(plr, "Turn", {
				phase = "Setup",
				attackerUserId = attackerUserId,
				defenderUserId = defenderUserId,
				clickAction = "SetWinningItem",
				clickableBoardUserId = defenderUserId,
				shuffleEnabled = false,
				hoverEnabled = true,
				shakeEnabled = false,
				waitingForDefender = false,
			})
		else
			self.ctx.send(plr, "Turn", {
				phase = "Setup",
				attackerUserId = attackerUserId,
				defenderUserId = defenderUserId,
				clickAction = nil,
				clickableBoardUserId = nil,
				shuffleEnabled = false,
				hoverEnabled = false,
				shakeEnabled = false,
				waitingForDefender = true,
			})
		end
	end

	-- Attacker sees "[Defender name] is choosing where to hide..."
	local defenderPlayer = Players:GetPlayerByUserId(defenderUserId)
	local defenderDisplayName = defenderPlayer and defenderPlayer.DisplayName or "Opponent"
	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "Message", {
				heading = defenderDisplayName .. " is choosing where to hide...",
				subheading = nil,
			})
			break
		end
	end

	-- Send camera (both see defender's board area for context)
	self.ctx.broadcast("Camera", {
		cframe = self._cameraCFrames["board" .. tostring(if defenderUserId == self.ctx.getPlayers()[1].UserId then 1 else 2) .. "Overhead"],
		subject = nil,
		tween = true,
	})

	local setupSeconds = self:_t("setupTimeout", 12)
	self:_armTurnTimeout(setupSeconds, 5, function()
		if self._dead or self._turnToken ~= setupToken then return end
		local board = self.gameState.boards[defenderUserId]
		if board and not board.winningItemChosen then
			self:_autoSetWinningItem(defenderUserId)
		end
		self:_afterDefenderSetup()
	end)
end

--[[
	_afterDefenderSetup
	Called when defender has chosen (or timeout). Assigns defender board contents and starts reveal/shuffle/choose.
]]
function Game:_afterDefenderSetup()
	if self._dead then return end
	self:_nextTurnToken() -- invalidate setup timeout

	local defenderUserId = self.gameState.defenderUserId
	local attackerUserId = self.gameState.attackerUserId
	if not defenderUserId or not attackerUserId then return end

	self:_assignBoardContents(defenderUserId)

	-- Phase: Reveal to attacker (losing item mask of defender board)
	self.gameState.phase = "Shuffle"
	self:_nextTurnToken()

	-- Send camera info
	self.ctx.broadcast("Camera", {
		cframe = self._cameraCFrames["board" .. tostring(if defenderUserId == self.ctx.getPlayers()[1].UserId then 1 else 2)],
		subject = nil,
		tween = true,
	})

	-- Reveal losing item mask to attacker
	self:_revealLosingItemMask(attackerUserId, defenderUserId)
	task.wait(self:_t("revealSeconds", 1.25) + 1.5) -- wait for reveal + buffer

	-- Enable shuffle phase
	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "Turn", {
				phase = "Shuffle",
				attackerUserId = attackerUserId,
				defenderUserId = defenderUserId,

				clickAction = nil,
				clickableBoardUserId = nil,
				shuffleEnabled = false,
				hoverEnabled = false,
				shakeEnabled = true,
			})
		else
			self.ctx.send(plr, "Turn", {
				phase = "Shuffle",
				attackerUserId = attackerUserId,
				defenderUserId = defenderUserId,

				clickAction = nil,
				clickableBoardUserId = nil,
				shuffleEnabled = true,
				hoverEnabled = false,
				shakeEnabled = false,
			})
		end
	end

	-- Per-player messages: attacker sees "[Opponent] is shuffling", defender sees "Start shuffling!"
	local defenderPlayer = Players:GetPlayerByUserId(defenderUserId)
	local defenderName = defenderPlayer and defenderPlayer.DisplayName or "Opponent"
	local shuffleSeconds = self:_t("shuffleTimeout", 4.0)

	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "Message", { heading = nil, subheading = defenderName .. " is shuffling" })
		else
			self.ctx.send(plr, "Message", { heading = nil, subheading = "Start shuffling! (Auto-start in " .. tostring(shuffleSeconds) .. "s)" })
		end
	end

	-- Arm timeout: only show countdown to defender in last 2 seconds (no global "Skipping turn")
	self:_armTurnTimeout(shuffleSeconds, nil, function()
		-- auto-start scramble
		self:_startScramble(defenderUserId)
	end, function(remaining: number)
		if remaining <= 2 and remaining > 0 then
			for _, plr in ipairs(self.ctx.getPlayers()) do
				if plr.UserId == defenderUserId then
					self.ctx.send(plr, "Message", { heading = nil, subheading = "Auto-starting in " .. tostring(remaining) .. "s" })
				else
					self.ctx.send(plr, "Message", { heading = nil, subheading = defenderName .. " is shuffling" })
				end
			end
		end
	end)
end

function Game:_startScramble(defenderUserId: number)
	if self._isScrambleRunning then
		return
	end
	self._isScrambleRunning = true

	-- Placeholder if we want to separate scramble start from auto/manual driver
	self:_armTurnTimeout(self:_t("maxShuffleTime", 5), 5, function()
		-- auto-resolve scramble end
		self:_endScramble(defenderUserId)
	end)

	local board = self.gameState.boards[defenderUserId]
	if not board then return end

	local n = #board.items
	local baseBeats = self:_t("shuffleBeats", 4)
	local beatDuration = self:_t("beatDuration", 1.0)

	-- Simple escalation as board shrinks
	local beats = clampInt(baseBeats + (6 - n), 2, 8)

	self.gameState.shuffleBeats = beats
	self.gameState.beatDuration = beatDuration

	-- Run beats sequentially (exactly one swap per beat)
	local token = self:_nextTurnToken()
	for _ = 1, beats do
		if self._dead or self._turnToken ~= token or not self._isScrambleRunning then return end

		local pairs = self:_makeDisjointSwapPairs(#board.items, 1)
		-- broadcast for client animation
		self.ctx.broadcast("ShuffleBeat", {
			defenderUserId = defenderUserId,
			pairs = pairs,
			beatDuration = beatDuration,
		})

		-- apply swap on server (instant or after duration; instant is OK for MVP)
		self:_applySwapPairs(defenderUserId, pairs)

		task.wait(beatDuration)
		task.wait(0.75)
	end

	-- auto-end scramble after beats
	if self._dead or self._turnToken ~= token or not self._isScrambleRunning then
		return
	end

	self:_endScramble(defenderUserId)
end

function Game:_endScramble(defenderUserId: number)
	if not self._isScrambleRunning then
		return
	end
	
	self._isScrambleRunning = false

	local attackerUserId = self.gameState.attackerUserId
	self.ctx.broadcast("Turn", {
		phase = "Shuffle",
		attackerUserId = attackerUserId,
		defenderUserId = defenderUserId,

		clickAction = nil,
		clickableBoardUserId = nil,
		shuffleEnabled = false,
		hoverEnabled = false,
		shakeEnabled = false,
	})
	task.wait(.5)

	self:_beginChoose(attackerUserId)
end

function Game:_beginChoose(attackerUserId: number)
	if self._dead then return end
	self.gameState.phase = "Choose"
	self:_nextTurnToken()

	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "Turn", {
				phase = "Choose",
				attackerUserId = attackerUserId,
				defenderUserId = self.gameState.defenderUserId,

				clickAction = "SelectItem",
				clickableBoardUserId = self.gameState.defenderUserId,
				shuffleEnabled = false,
				hoverEnabled = false,
				shakeEnabled = true,
			})
		else
			self.ctx.send(plr, "Turn", {
				phase = "Choose",
				attackerUserId = attackerUserId,
				defenderUserId = self.gameState.defenderUserId,

				clickAction = nil,
				clickableBoardUserId = nil,
				shuffleEnabled = false,
				hoverEnabled = false,
				shakeEnabled = true,
			})
		end
	end
	
	-- Send camera info
	self.ctx.broadcast("Camera", {
		cframe = self._cameraCFrames["board" .. tostring(if attackerUserId == self.ctx.getPlayers()[1].UserId then 2 else 1)],
		subject = nil,
		tween = true,
	})

	local chooseSeconds = self:_t("chooseTimeout", 8)
	self:_armTurnTimeout(chooseSeconds, 3, function()
		-- auto pick (random live item)
		local defenderUserId = self.gameState.defenderUserId
		if not defenderUserId then return end
		local board = self.gameState.boards[defenderUserId]
		if not board or #board.items == 0 then return end
		local idx = math.random(1, #board.items)
		self:_resolvePick(attackerUserId, idx)
	end)
end

function Game:_resolvePick(attackerUserId: number, itemIndex: number)
	if self._dead then return end
	-- Invalidate choose-phase countdown so "Skipping pick in Xs" stops and timeout callback no-ops
	self:_nextTurnToken()

	local defenderUserId = self.gameState.defenderUserId
	if not defenderUserId then return end

	local board = self.gameState.boards[defenderUserId]
	if not board then return end

	itemIndex = clampInt(itemIndex, 1, #board.items)
	local item = board.items[itemIndex]
	if not item then return end

	-- Reveal to all (client can animate opening)
	self.ctx.broadcast("AutoAction", {
		kind = "RevealItem",
		defenderUserId = defenderUserId,
		itemIndex = itemIndex,
		content = item.content,
	})

	if item.content == "Lose" then
		self:_onLosingItemPicked(attackerUserId, defenderUserId, itemIndex)

		-- attacker loses, defender wins round
		local winner = Players:GetPlayerByUserId(defenderUserId)
		self:_endRound(winner)
		return
	end

	if item.content == "Win" then
		self:_onWinningItemPicked(attackerUserId, defenderUserId, itemIndex)

		-- attacker wins round
		local winner = Players:GetPlayerByUserId(attackerUserId)
		self:_endRound(winner)
		return
	end

	-- Empty safe: remove this item and swap roles
	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "YourResult", {
				result = "Safe",
			})
		else
			self.ctx.send(plr, "TheirResult", {
				result = "Safe",
			})
		end
	end

	self:_removeItem(defenderUserId, itemIndex)
	task.wait(2.0) -- wait before moving on
	
	-- Swap attacker/defender
	local newAttacker = defenderUserId
	local newDefender = attackerUserId
	self:_beginTurn(newAttacker, newDefender)
end

function Game:_endRound(winner: Player?)
	if self._dead then return end
	self._dead = true
	self:_nextTurnToken()

	self.ctx.broadcast("RoundEnd", {
		winnerUserId = if winner then winner.UserId else nil,
	})

	if self._onGameEnd then
		self._onGameEnd(winner)
	end
end

-- ===== Reveal and Shuffle ===== --
function Game:_revealLosingItemMask(attackerUserId: number, defenderUserId: number)
	local board = self.gameState.boards[defenderUserId]
	if not board then return end

	local mask = {}
	for i, item in ipairs(board.items) do
		mask[i] = (item.content == "Lose") -- true if losing item (bomb), false otherwise
	end

	local itemModels = {} :: { [number]: Model }
	for i, item in ipairs(board.items) do
		itemModels[i] = item.instance
	end

	task.wait(1.0) -- small delay before reveal

	local attacker = Players:GetPlayerByUserId(attackerUserId)
	if attacker then
		self.ctx.send(attacker, "Reveal", {
			defenderUserId = defenderUserId,
			losingItemMask = mask,
			itemModels = itemModels,
			revealSeconds = self:_t("revealSeconds", 1.25),
		})
	end
end

function Game:_onLosingItemPicked(attackerUserId: number, defenderUserId: number, itemIndex: number)
	-- Send text info to client
	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "YourResult", {
				result = "Lose",
			})
		else
			self.ctx.send(plr, "TheirResult", {
				result = "Lose",
			})
		end
	end

	-- Create an explosion effect at the attacker's character
	local attacker = Players:GetPlayerByUserId(attackerUserId)
	local attackerChar = attacker and attacker.Character
	local attackerRoot = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local attackerHuman = attackerChar and attackerChar:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if attackerRoot and attackerHuman then
		self.ctx.broadcast("Camera", {
			cframe = CFrame.new(
				attackerRoot.Position + attackerRoot.CFrame.LookVector * 5 + Vector3.new(0, 2, 0),
				attackerRoot.Position
			),
			subject = nil,
			tween = true,
		})
		task.wait(1.0)
		
		local explosion = Instance.new("Explosion")
		explosion.Position = attackerRoot.Position
		explosion.BlastPressure = 0
		explosion.BlastRadius = 5
		explosion.Parent = attackerRoot
		Debris:AddItem(explosion, 2)

		_deps.SharedPackages.Sounds:PlaySound("Explode", attackerRoot.Position)

		local animator = attackerHuman:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = attackerHuman
		end
		local animTrack = animator:LoadAnimation(EXPLODE_ANIMATION) -- explosion animation
		animTrack:Play()

		task.delay(1.5, function()
			animTrack:Stop()
		end)

		task.wait(1.5)
	end
end

function Game:_onWinningItemPicked(attackerUserId: number, defenderUserId: number, itemIndex: number)
	-- Send text info to client
	for _, plr in ipairs(self.ctx.getPlayers()) do
		if plr.UserId == attackerUserId then
			self.ctx.send(plr, "YourResult", {
				result = "Win",
			})
		else
			self.ctx.send(plr, "TheirResult", {
				result = "Win",
			})
		end
	end

	-- Create a celebratory effect at the attacker's character
	local attacker = Players:GetPlayerByUserId(attackerUserId)
	local attackerChar = attacker and attacker.Character
	local attackerRoot = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if attackerRoot then
		self.ctx.broadcast("Camera", {
			cframe = CFrame.new(
				attackerRoot.Position + attackerRoot.CFrame.LookVector * 5 + Vector3.new(0, 2, 0),
				attackerRoot.Position
			),
			subject = nil,
			tween = true,
		})
		task.wait(2.0)
	end
end

-- Pluggable: swap this method later to manual shuffle driver
function Game:_runAutoScramble(defenderUserId: number, onDone: () -> ())
	local board = self.gameState.boards[defenderUserId]
	if not board then onDone(); return end

	local n = #board.items
	local baseBeats = self:_t("shuffleBeats", 4)
	local beatDuration = self:_t("beatDuration", 1.0)

	-- Simple escalation as board shrinks
	local beats = clampInt(baseBeats + (6 - n), 2, 8)

	self.gameState.shuffleBeats = beats
	self.gameState.beatDuration = beatDuration

	-- Run beats sequentially
	local token = self:_nextTurnToken()
	task.spawn(function()
		for _ = 1, beats do
			if self._dead or self._turnToken ~= token then return end

			local pairs = self:_makeDisjointSwapPairs(#board.items, 1)
			-- broadcast for client animation
			self.ctx.broadcast("ShuffleBeat", {
				defenderUserId = defenderUserId,
				pairs = pairs,
				beatDuration = beatDuration,
			})

			-- apply swap on server (instant or after duration; instant is OK for MVP)
			self:_applySwapPairs(defenderUserId, pairs)

			task.wait(beatDuration)
			task.wait(0.75)
		end

		task.wait(self:_t("revealSeconds", 1.25)) -- wait for reveal + buffer

		if self._dead or self._turnToken ~= token then return end
		onDone()
	end)
end

--[[
	_makeDisjointSwapPairs
	Returns exactly numPairs disjoint swap pairs (each pair swaps two distinct indices).
	Used for shuffle beats; one swap per beat gives predictable, readable shuffling.

	@param n: number, number of items on board
	@param numPairs: number, number of pairs to return (e.g. 1 for one swap per beat)
	@return { {a: number, b: number} }
]]
function Game:_makeDisjointSwapPairs(n: number, numPairs: number): { {a: number, b: number} }
	if n < 2 or numPairs < 1 then
		return {}
	end

	local idxs = {}
	for i = 1, n do
		idxs[i] = i
	end
	for i = n, 2, -1 do
		local j = math.random(1, i)
		idxs[i], idxs[j] = idxs[j], idxs[i]
	end

	local pairs = {}
	for p = 1, numPairs do
		local i = (p - 1) * 2 + 1
		local j = i + 1
		if j > n then
			break
		end
		table.insert(pairs, { a = idxs[i], b = idxs[j] })
	end
	return pairs
end

function Game:_applySwapPairs(defenderUserId: number, pairs: { {a: number, b: number} })
	local board = self.gameState.boards[defenderUserId]
	if not board then return end

	for _, p in ipairs(pairs) do
		local a = board.items[p.a]
		local b = board.items[p.b]
		if a and b then
			a.posIndex, b.posIndex = b.posIndex, a.posIndex
		end
	end

	-- Reposition moved items to their slot CFrames (lerp)
	for _, item in ipairs(board.items) do
		local slotCF = board.positions[item.posIndex]
		if slotCF then
			-- Lerp to new position
			task.spawn(function()
				local startCF = item.instance:GetPivot()
				local duration = 0.3 -- self.gameState.beatDuration * 0.8
				local elapsed = 0
				while elapsed < duration do
					local alpha = elapsed / duration
					local newCF = startCF:Lerp(slotCF, alpha)
					item.instance:PivotTo(newCF)
					task.wait()
					elapsed += task.wait()
				end
				item.instance:PivotTo(slotCF)
			end)
		end
	end
end

-- ===== Board Management ===== --
function Game:_removeItem(boardUserId: number, itemIndex: number)
	local board = self.gameState.boards[boardUserId]
	if not board then return end
	local item = board.items[itemIndex]
	if not item then return end

	-- destroy instance
	if item.instance and item.instance.Parent then
		item.instance:Destroy()
	end

	table.remove(board.items, itemIndex)

	--[[
	-- Re-pack posIndex to 1..n and reposition
	for i, c in ipairs(board.items) do
		c.posIndex = i
		local slotCF = board.positions[i]
		if slotCF then
			-- Lerp to new position
			task.spawn(function()
				local startCF = c.instance:GetPivot()
				local duration = 0.3
				local elapsed = 0
				while elapsed < duration do
					local alpha = elapsed / duration
					local newCF = startCF:Lerp(slotCF, alpha)
					c.instance:PivotTo(newCF)
					task.wait()
					elapsed += task.wait()
				end
				c.instance:PivotTo(slotCF)
			end)
		end
	end
	--]]

	self.ctx.broadcast("BoardUpdate", {
		boardUserId = boardUserId,
		numItems = #board.items,
	})
end

function Game:_getItemModelClone(player: Player): Model
	-- Create a blank model
	local m = Instance.new("Model")
	local basePart = Instance.new("Part")
	basePart.Name = "BasePart"
	basePart.Size = Vector3.new(1, 1, 1)
	basePart.Transparency = 1
	basePart.Anchored = true
	basePart.CanCollide = false
	basePart.Parent = m
	m.PrimaryPart = basePart

	local visualModel = SAMPLE_ITEM_MODEL:Clone()
	visualModel.Name = "Visual"
	visualModel:PivotTo(basePart.CFrame)
	visualModel.Parent = m

	return m
end

function Game:_spawnBoardForPlayer(player: Player, seatIndex: number)
	local tableInstance = self.ctx.tableInstance
	local playerSlotsFolder = tableInstance:FindFirstChild("PlayerSlots") :: Folder?
	local playerFolder = playerSlotsFolder and playerSlotsFolder:FindFirstChild("Player" .. tostring(seatIndex)) :: Folder?
	assert(playerFolder, "Missing Player folder in table")

	local spawnPart = playerFolder:FindFirstChild("ItemSpawnPart") :: BasePart?
	assert(spawnPart, "Missing ItemSpawnPart")

	local itemsFolder = playerFolder:FindFirstChild("Items") :: Folder?
	assert(itemsFolder, "Missing Items folder")

	-- Clear folder
	for _, child in ipairs(itemsFolder:GetChildren()) do
		child:Destroy()
	end

	local numItems = clampInt(self:_t("numItems", 6), 3, 10)
	local boardSizeX = self:_t("boardSizeX", 1.0)
	local boardSizeZ = self:_t("boardSizeZ", 1.25)

	-- Form a grid layout
	local cols = math.ceil(math.sqrt(numItems * (boardSizeX / boardSizeZ)))
	local rows = math.ceil(numItems / cols)
	local spacingX = boardSizeX / rows
	local spacingZ = boardSizeZ / cols
	
	local positions = {}
	for i = 1, numItems do
		-- Centre the cframe positions around the spawnPart
		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		local offsetX = (col - (cols - 1) / 2) * spacingX
		local offsetZ = (row - (rows - 1) / 2) * spacingZ
		local cf = spawnPart.CFrame * CFrame.new(offsetZ, 0, offsetX)
		positions[i] = cf
	end

	local items = {}
	for i = 1, numItems do
		local m = self:_getItemModelClone(player)
		m.Name = ("Item_%d"):format(i)
		m:PivotTo(positions[i])
		m.Parent = itemsFolder

		m:SetAttribute("ItemIndex", i)
		m:SetAttribute("BoardUserId", player.UserId)

		table.insert(items, {
			instance = m,
			posIndex = i,
			content = "Empty",
		})
	end

	self.gameState.boards[player.UserId] = {
		ownerUserId = player.UserId,
		items = items,
		positions = positions,
		winningItemChosen = false,
	} :: any
	print("Spawned board for player ", player.Name)
end

-- ===== Turn Tokens and Timeouts ===== --
function Game:_nextTurnToken(): number
	self._turnToken += 1
	return self._turnToken
end

--[[
	_armTurnTimeout
	Arms a timeout; optionally broadcasts TurnCountdown or calls onTick(remaining) each second.
	When onTick is provided, it is called each second with remaining (no TurnCountdown broadcast).
	When onTick is nil, broadcasts TurnCountdown when remaining <= clientCountdownSeconds.
]]
function Game:_armTurnTimeout(seconds: number, clientCountdownSeconds: number, onTimeout: () -> (), onTick: ((remaining: number) -> ())?)
	local token = self._turnToken
	task.spawn(function()
		local remaining = seconds
		while remaining > 0 do
			task.wait(1)
			remaining -= 1
			if self._dead or self._turnToken ~= token then
				return
			end
			if onTick then
				onTick(remaining)
			elseif typeof(clientCountdownSeconds) == "number" and remaining <= clientCountdownSeconds then
				self.ctx.broadcast("TurnCountdown", { secondsLeft = remaining })
			end
		end
		if self._dead or self._turnToken ~= token then return end
		onTimeout()
	end)
end

-- ========== Life Cycle ========== --

function Game:Init()
	-- // Note: call :Start() instead
end

function Game:Destroy()
	self._dead = true
	self:_nextTurnToken()

	-- Cleanup items
	for _, board in pairs(self.gameState.boards) do
		for _, item in ipairs(board.items) do
			if item.instance and item.instance.Parent then
				item.instance:Destroy()
			end
		end
	end
	table.clear(self.gameState.boards)

	-- Disconnect conns
	for _, c in ipairs(self._conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._conns)
end

return Game :: GameAPI
