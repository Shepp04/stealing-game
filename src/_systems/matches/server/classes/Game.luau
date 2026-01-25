--!strict
-- Game (Server Class)

-- // Roblox Services
local ContextActionService = game:GetService("ContextActionService")
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
	HandleAction: (self: GameAPI, player: Player, action: GameAction, payload: any) -> (),
}

local Game = {}
Game.__index = Game

-- // Internal state
local _deps: Deps?

-- // Constants
local SAMPLE_ITEM_MODEL = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Items"):WaitForChild("SampleItem") :: Model

-- ========== Helpers ========== --

local function clampInt(x: number, lo: number, hi: number): number
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

-- ========== Constructor ========== --

function Game.new(deps: Deps, opts: Opts): GameAPI
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

	return (self :: any) :: GameAPI
end

-- ========== Public API ========== --

function Game:Start()
	local players = self.ctx.getPlayers()
	assert(#players == 2, "Game expects exactly 2 players")

	-- Spawn boards for each player
	for seatIndex, plr in ipairs(players) do
		self:_spawnBoardForPlayer(plr, seatIndex)
	end

	-- Broadcast round begin
	self.ctx.broadcast("RoundBegin", {
		userIds = { userId1 = players[1].UserId, userId2 = players[2].UserId },
	})

	-- Setup phase: both choose winning item simultaneously (timeout auto)
	self.gameState.phase = "Setup"
	self:_nextTurnToken()
	self.ctx.broadcast("Turn", { phase = "Setup" })

	local setupSeconds = self:_t("setupTimeout", 12)
	self:_armTurnTimeout(setupSeconds, function()
		-- auto-pick winning item for anyone who hasn't chosen
		for _, plr in ipairs(players) do
			local board = self.gameState.boards[plr.UserId]
			if board and not board.winningItemChosen then
				self:_autoSetWinningItem(plr.UserId)
			else
				warn("No board found for player ", plr.Name)
			end
		end
		-- if both chosen now, start the duel loop
		self:_tryBeginDuel()
	end)

	-- Optional: tell clients to show “Pick where to hide winning item”
	for _, plr in ipairs(players) do
		self.ctx.send(plr, "AutoAction", { kind = "PromptSetWinningItem" })
	end
end

-- ===== Actions ===== --

function Game:HandleAction(player: Player, action: GameAction, payload: any)
	if self._dead then return end

	if action == "SetWinningItem" then
		if self.gameState.phase ~= "Setup" then return end
		local itemIndex = payload.itemIndex :: number
		self:_setWinningItem(player.UserId, itemIndex)
		self:_tryBeginDuel()
		return
	end

	if action == "SelectItem" then
		if self.gameState.phase ~= "Choose" then return end
		if player.UserId ~= self.gameState.attackerUserId then return end
		local itemIndex = payload.itemIndex :: number
		self:_resolvePick(player.UserId, itemIndex)
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

function Game:_tryBeginDuel()
	print("Trying to begin duel...")
	local players = self.ctx.getPlayers()
	local b1 = self.gameState.boards[players[1].UserId]
	local b2 = self.gameState.boards[players[2].UserId]
	if not b1 or not b2 then warn("Missing boards for players") return end
	if not b1.winningItemChosen or not b2.winningItemChosen then warn("Winning items not chosen yet") return end

	-- Assign contents once both winning items are chosen
	self:_assignBoardContents(players[1].UserId)
	self:_assignBoardContents(players[2].UserId)

	-- Choose starting attacker randomly (or seat 1 for now)
	local startIdx = (self:_t("randomFirst", true) and math.random(1, 2)) or 1
	local attacker = players[startIdx]
	local defender = players[3 - startIdx]

	self:_beginTurn(attacker.UserId, defender.UserId)
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
	board.items[winningItemIndex].content = "WinningItem"

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
		board.items[idx].content = "LosingItem"
	end

	-- remaining are empty safe (already Empty)
end

-- ===== Turn Loop ===== --

function Game:_beginTurn(attackerUserId: number, defenderUserId: number)
	print("Beginning turn: attacker=", attackerUserId, " defender=", defenderUserId)
	self.gameState.attackerUserId = attackerUserId
	self.gameState.defenderUserId = defenderUserId
	self.gameState.activeBoardUserId = defenderUserId

	-- Phase: Reveal to attacker (losing item mask of defender board)
	self.gameState.phase = "Shuffle"
	self:_nextTurnToken()

	self.ctx.broadcast("Turn", {
		phase = "Shuffle",
		attackerUserId = attackerUserId,
		defenderUserId = defenderUserId,
	})

	self:_revealLosingItemMask(attackerUserId, defenderUserId)

	-- Now scramble (auto for MVP; later you can replace this with manual driver)
	self:_runAutoScramble(defenderUserId, function()
		-- After scramble, attacker chooses
		self:_beginChoose(attackerUserId)
	end)
end

function Game:_beginChoose(attackerUserId: number)
	if self._dead then return end
	self.gameState.phase = "Choose"
	self:_nextTurnToken()

	self.ctx.broadcast("Turn", { phase = "Choose", attackerUserId = attackerUserId })

	local chooseSeconds = self:_t("chooseTimeout", 8)
	self:_armTurnTimeout(chooseSeconds, function()
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

	if item.content == "LosingItem" then
		-- attacker loses, defender wins round
		local winner = Players:GetPlayerByUserId(defenderUserId)
		self:_endRound(winner)
		return
	end

	if item.content == "WinningItem" then
		-- attacker wins round
		local winner = Players:GetPlayerByUserId(attackerUserId)
		self:_endRound(winner)
		return
	end

	-- Empty safe: remove this item and swap roles
	self:_removeItem(defenderUserId, itemIndex)

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
		mask[i] = (item.content == "LosingItem") -- true if losing item, false otherwise
	end

	local attacker = Players:GetPlayerByUserId(attackerUserId)
	if attacker then
		self.ctx.send(attacker, "Reveal", {
			defenderUserId = defenderUserId,
			losingItemMask = mask,
			revealSeconds = self:_t("revealSeconds", 1.25),
		})
	end
end

-- Pluggable: swap this method later to manual shuffle driver
function Game:_runAutoScramble(defenderUserId: number, onDone: () -> ())
	local board = self.gameState.boards[defenderUserId]
	if not board then onDone(); return end

	local n = #board.items
	local baseBeats = self:_t("shuffleBeats", 4)
	local beatDuration = self:_t("beatDuration", 0.45)

	-- Simple escalation as board shrinks
	local beats = clampInt(baseBeats + (6 - n), 2, 8)

	self.gameState.shuffleBeats = beats
	self.gameState.beatDuration = beatDuration

	-- Run beats sequentially
	local token = self:_nextTurnToken()
	task.spawn(function()
		for _ = 1, beats do
			if self._dead or self._turnToken ~= token then return end

			local pairs = self:_makeDisjointSwapPairs(#board.items)
			-- broadcast for client animation
			self.ctx.broadcast("ShuffleBeat", {
				defenderUserId = defenderUserId,
				pairs = pairs,
				beatDuration = beatDuration,
			})

			-- apply swap on server (instant or after duration; instant is OK for MVP)
			self:_applySwapPairs(defenderUserId, pairs)

			task.wait(beatDuration)
		end

		if self._dead or self._turnToken ~= token then return end
		onDone()
	end)
end

function Game:_makeDisjointSwapPairs(n: number): { {a: number, b: number} }
	-- Returns disjoint swap pairs covering ~half the items.
	-- Example for n=6 -> 3 pairs; n=5 -> 2 pairs
	local idxs = {}
	for i = 1, n do idxs[i] = i end
	for i = n, 2, -1 do
		local j = math.random(1, i)
		idxs[i], idxs[j] = idxs[j], idxs[i]
	end

	local pairs = {}
	local i = 1
	while i < n do
		table.insert(pairs, { a = idxs[i], b = idxs[i + 1] })
		i += 2
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
				local duration = self.gameState.beatDuration * 0.8
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

	self.ctx.broadcast("BoardUpdate", {
		boardUserId = boardUserId,
		numItems = #board.items,
	})
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
	local spacing = self:_t("itemSpacing", 3)

	local positions = {}
	for i = 1, numItems do
		positions[i] = spawnPart.CFrame * CFrame.new(0, 0, (i - 1) * spacing)
	end

	local items = {}
	for i = 1, numItems do
		local m = SAMPLE_ITEM_MODEL:Clone()
		m.Name = ("Item_%d"):format(i)
		m.Parent = itemsFolder
		m:PivotTo(positions[i])
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

function Game:_armTurnTimeout(seconds: number, onTimeout: () -> ())
	local token = self._turnToken
	task.spawn(function()
		local remaining = seconds
		while remaining > 0 do
			task.wait(1)
			remaining -= 1
			if self._dead or self._turnToken ~= token then
				return
			end
			if remaining <= 5 then
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
