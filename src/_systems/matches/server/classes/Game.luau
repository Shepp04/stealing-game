--!strict
-- Game (Server Class)

-- // Roblox Services
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
local GameTypes = require(ReplicatedStorage.Shared.Types.Game)
type GameBroadcastState = GameTypes.GameBroadcastState
type GameAction = GameTypes.GameAction
type TurnType = GameTypes.TurnType
type ItemType = GameTypes.ItemType

export type GameContext = {
 	tableInstance: Instance,
	numItems: number,
	shuffleSpeed: number?,

	getPlayers: () -> { Player },
	send: (player: Player, kind: GameBroadcastState, ...any) -> (),
	broadcast: (kind: GameBroadcastState, ...any) -> (),
}

export type GameState = {
	-- Define game state properties here
	turnUserId: number?,
	turnType: TurnType?,
	numItems: number,
	shuffleSpeed: number?,
	timeoutSeconds: number,

	userItems: { [number]: { instance: Instance, position: number, type: ItemType } }, -- userId -> item instances
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
}

export type GameAPI = {
	_opts: Opts,
	_conns: { RBXScriptConnection },

	ctx: GameContext,
	gameState: GameState,

	Init: (self: GameAPI) -> (),
	Destroy: (self: GameAPI) -> (),

	Start: (self: GameAPI, ctx: GameContext) -> (),
	EndMatch: (self: GameAPI) -> (),
	HandleAction: (self: GameAPI, player: Player, name: string, payload: any) -> (),

	GetTurn: (self: GameAPI) -> (number?, TurnType?),
	GetOpponentUserId: (self: GameAPI, userId: number) -> number?,
	SetTurn: (self: GameAPI, userId: number, turnType: TurnType) -> (),

	-- Game Logic
	SetSpecialItem: (self: GameAPI, player: Player, itemIndex: number) -> boolean,
	StartShuffle: (self: GameAPI, player: Player) -> boolean,
	StopShuffle: (self: GameAPI, player: Player) -> boolean,
	SelectItem: (self: GameAPI, player: Player, itemIndex: number) -> boolean,
}

local Game = {}
Game.__index = Game

-- // Internal state
local _deps: Deps?

-- ========== Constructor ========== --

function Game.new(deps: Deps, opts: Opts): GameAPI
	_deps = deps

	local self = setmetatable({} :: any, Game) :: GameAPI
	self._opts = opts
	self._conns = {}

	self._onGameEnd = opts.onGameEnd
	self.ctx = opts.ctx

	-- Get remotes
	self._gameStateRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "GameState") :: RemoteEvent
	self._gameActionRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "GameAction") :: RemoteEvent
	
	-- Initialise state
	self.gameState = {
		turnUserId = nil,
		numItems = self.ctx.numItems,
		shuffleSpeed = self.ctx.shuffleSpeed or 0.5,
		timeoutSeconds = 30,
		userItems = {},
	} :: GameState

	return self
end

-- ========== Public API ========== --

function Game:GetTurn(): (number?, TurnType?)
	return self.gameState.turnUserId, self.gameState.turnType
end

function Game:GetOpponentUserId(userId: number): number?
	for otherUserId, _ in self.gameState.userItems do
		if otherUserId ~= userId then
			return otherUserId
		end
	end
	return nil
end

function Game:SetTurn(userId: number, turnType: TurnType)
	self.gameState.turnUserId = userId
	self.gameState.turnType = turnType

	-- invalidate any existing turn timeouts
	self:_nextTurnToken()

	self.ctx.broadcast("Turn", {
		turnUserId = userId,
		turnType = turnType,
	})

	local timeoutSeconds = self.gameState.timeoutSeconds

	-- // Arm turn timeout logic
	if turnType == "Hider" then
		self:_armTurnTimeout(timeoutSeconds, function()
			-- Auto-set special item and advance
			self:_autoSetSpecialItemFor(userId)

			local player = Players:GetPlayerByUserId(userId)
			if player then
				-- Advance to Shuffler turn
				self:SetTurn(userId, "Shuffler")
			end
		end)
	end
	
	if turnType == "Shuffler" then
		-- Start shuffling immediately
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self:StartShuffle(player)
		end

		self:_armTurnTimeout(timeoutSeconds, function()
			-- Auto-stop shuffle and pass to Chooser
			local plr = Players:GetPlayerByUserId(userId)
			if plr then
				self:StopShuffle(plr)
			end
		end)
	end
	
	if turnType == "Chooser" then
		self:_armTurnTimeout(timeoutSeconds, function()
			-- Auto-select an item
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_autoSelectFor(player)
			end
		end)
	end
end

function Game:Start(players: { Player })
	--[[
		Flow:
		- Generate items for each player
		- Notify players of round begin
		- Choose starting player (shuffler)
		- Set camera targets
	]]
	-- Generate items
	for i, plr in players do
		-- Generate item slots for each player
		local playerSlotsFolder = self.ctx.tableInstance:FindFirstChild("PlayerSlots") :: Folder?
		local playerFolder = playerSlotsFolder and playerSlotsFolder:FindFirstChild("Player" .. tostring(i)) :: Folder?
		if not playerFolder then
			warn("[Game] No player folder found for player", plr.Name)
			continue
		end

		local itemSpawn = playerFolder:FindFirstChild("ItemSpawn") :: BasePart?
		if not itemSpawn then
			warn("[Game] No item spawn found for player", plr.Name)
			continue
		end

		local itemsFolder = playerFolder:FindFirstChild("Items") :: Folder?
		if not itemsFolder then
			warn("[Game] No items folder found for player", plr.Name)
			continue
		end

		self:_spawnItemsForPlayer(plr, self.gameState.numItems, itemSpawn.CFrame, itemsFolder)
	end

	-- Notify players of round begin
	self.ctx.broadcast("RoundBegin", {
		numItems = self.gameState.numItems,
		userIds = table.map(players, function(p) return p.UserId end),
		tableInstance = self.ctx.tableInstance,
	})

	-- Choose starting player (shuffler)
	local startingPlayer = players[1]
	self:SetTurn(startingPlayer.UserId, "Hider")
end

function Game:End(winner: Player?)
	-- Notify players of round end
	self.ctx.broadcast("RoundEnd", {
		winnerUserId = if winner then winner.UserId else nil,
	})

	-- Call the game end callback
	if self._onGameEnd then
		self._onGameEnd(winner)
	end
end

function Game:HandleAction(player: Player, action: GameAction, payload: any)
	-- Only the active player may act
	local turnUserId, turnType = self:GetTurn()
	if player.UserId ~= turnUserId then
		warn("Player", player.Name, "tried to perform action", action, "out of turn")
		return
	end

	-- // Hider Logic
	if turnType == "Hider" then
		if action == "SetSpecialItem" then
			local itemIndex = payload.itemIndex :: number
			local ok = self:SetSpecialItem(player, itemIndex)
		end
	end

	-- // Shuffle Logic
	if turnType == "Shuffler" then
		if action == "StopShuffle" then
			local ok = self:StopShuffle(player)
		end
	end

	-- // Choose Logic
	if turnType == "Chooser" then
		if action == "SelectItem" then
			local itemIndex = payload.itemIndex :: number
			local ok = self:SelectItem(player, itemIndex)
		end
	end
end

-- ========== Game Logic ========== --

function Game:SetSpecialItem(player: Player, itemIndex: number): boolean
	-- Check that the turn type is Hider
	local turnUserId, turnType = self:GetTurn()
	if turnType ~= "Hider" then
		warn("Player", player.Name, "tried to set special item but the turn type is not Hider")
		return false
	end

	-- Check that it's this player's turn
	if player.UserId ~= turnUserId then
		warn("Player", player.Name, "tried to set special item out of turn")
		return false
	end

	-- Find the player's items
	local playerItems = self.gameState.userItems[player.UserId]
	if not playerItems then
		warn("No items found for player", player.Name)
		return false
	end

	-- Check if this is a valid item index
	if itemIndex < 1 or itemIndex > #playerItems then
		warn("Player", player.Name, "tried to set special item with invalid index", itemIndex)
		return false
	end

	-- Mark only the selected item as special
	for _, itemData in playerItems do
		itemData.type = "Bad" -- Reset all items to normal (Bad)
	end
	playerItems[itemIndex].type = "Good" -- Mark the item as special (Good)

	-- Advance to shuffling
	self:SetTurn(player.UserId, "Shuffler")
	return true -- Success
end

function Game:StartShuffle(player: Player): boolean
	-- Check that shuffling is allowed
	local turnUserId, turnType = self:GetTurn()
	if turnType ~= "Shuffler" then
		warn("Player", player.Name, "tried to start shuffle but the turn type is not Shuffler")
		return false
	end
	-- Check that it's this player's turn
	if player.UserId ~= turnUserId then
		warn("Player", player.Name, "tried to start shuffle out of turn")
		return false
	end

	-- Use a token-based strategy to handle shuffling
	self._shuffleToken = (self._shuffleToken or 0) + 1
	local currentToken = self._shuffleToken
	local userId = player.UserId

	task.spawn(function()
		while task.wait() do
			-- Check that the current token is still valid
			if self._shuffleToken ~= currentToken then
				break
			end
			-- Perform a shuffle action (swap two random items)
			local numItems = self.gameState.numItems
			local idx1 = math.random(1, numItems)
			local idx2 = math.random(1, numItems)
			while idx2 == idx1 do
				idx2 = math.random(1, numItems)
				task.wait(0)
			end
			self:_swapItemPositions(userId, idx1, idx2)
			task.wait(self.gameState.shuffleSpeed or 0.5)
		end
	end)

	return true
end

function Game:StopShuffle(player: Player): boolean
	-- Check that shuffling is in progress
	local turnUserId, turnType = self:GetTurn()
	if turnType ~= "Shuffler" then
		warn("Player", player.Name, "tried to stop shuffle but the turn type is not Shuffler")
		return false
	end

	-- Invalidate the current shuffle token to stop shuffling
	self._shuffleToken = nil

	-- Transition to Chooser turn
	local chooserUserId = self:GetOpponentUserId(turnUserId)
	if not chooserUserId then
		warn("No opponent found to become chooser")
		return false
	end
	self:SetTurn(chooserUserId, "Chooser")
	return true
end

function Game:SelectItem(player: Player, itemIndex: number): boolean
	-- Check that the turn type is Chooser
	local turnUserId, turnType = self:GetTurn()
	if turnType ~= "Chooser" then
		warn("Player", player.Name, "tried to select item but the turn type is not Chooser")
		return false
	end

	-- Check that it's this player's turn
	if player.UserId ~= turnUserId then
		warn("Player", player.Name, "tried to select item out of turn")
		return false
	end

	-- Find the opponent's items
	local opponentUserId = self:GetOpponentUserId(player.UserId)
	if not opponentUserId then
		warn("No opponent found for player", player.Name)
		return false
	end

	local opponentItems = self.gameState.userItems[opponentUserId]
	if not opponentItems then
		warn("No items found for opponent of player", player.Name)
		return false
	end

	-- Check if this is the special item
	local selectedItem = opponentItems[itemIndex]
	if not selectedItem then
		warn("Player", player.Name, "tried to select invalid item index", itemIndex)
		return false
	end

	if selectedItem.type == "Good" then
		-- This player wins the game (round)
		self.ctx.send(player, "YourResult", { result = "Correct" })
		local opponentPlayer = game.Players:GetPlayerByUserId(opponentUserId)
		if opponentPlayer then
			self.ctx.send(opponentPlayer, "TheirResult", { result = "Correct" })
		end

		self:End(player)
	else
		-- Chooser loses, hider wins
		self.ctx.send(player, "YourResult", { result = "Incorrect" })
		local opponentPlayer = Players:GetPlayerByUserId(opponentUserId)
		if opponentPlayer then
			self.ctx.send(opponentPlayer, "TheirResult", { result = "Incorrect" })
			self:End(opponentPlayer)
		else
			self:End(nil)
		end
	end
	return true
end

function Game:_autoSetSpecialItemFor(userId: number)
	local items = self.gameState.userItems[userId]
	if not items or #items == 0 then return end
	local idx = math.random(1, #items)

	-- Mark only selected as Good
	for _, itemData in items do
		itemData.type = "Bad"
	end
	items[idx].type = "Good"

	-- Broadcast
	self.ctx.broadcast("AutoAction", {
		kind = "SetSpecialItem",
		userId = userId,
		itemIndex = idx,
	})
end

function Game:_autoSelectFor(player: Player)
	local opponentUserId = self:GetOpponentUserId(player.UserId)
	if not opponentUserId then return end

	local opponentItems = self.gameState.userItems[opponentUserId]
	if not opponentItems or #opponentItems == 0 then return end

	local idx = math.random(1, #opponentItems)

	self.ctx.broadcast("AutoAction", {
		kind = "SelectItem",
		userId = player.UserId,
		itemIndex = idx,
	})

	self:SelectItem(player, idx)
end

function Game:_spawnItemsForPlayer(player: Player, numItems: number, cf: CFrame, parent: Instance)
	-- TODO: get the item skins from player data
	local sampleModel = workspace.SampleItem

	-- Clear old
	if self.gameState.userItems[player.UserId] then
		for _, itemData in self.gameState.userItems[player.UserId] do
			itemData.instance:Destroy()
		end
		self.gameState.userItems[player.UserId] = {}
	end

	-- Spawn an arrangement of items
	local spawnedItems = {}
	for i = 1, numItems do
		local itemInstance = sampleModel:Clone() :: Model
		itemInstance.Name = "Item_" .. tostring(i)
		itemInstance:PivotTo(cf * CFrame.new(0, 0, (i - 1) * 3))
		itemInstance.Parent = parent
		table.insert(spawnedItems, { instance = itemInstance, position = i })
	end
	self.gameState.userItems[player.UserId] = spawnedItems
end

function Game:_swapItemPositions(userId: number, idx1: number, idx2: number)
	local items = self.gameState.userItems[userId]
	if not items then
		warn("No items found for player", userId)
		return
	end

	local item1 = items[idx1]
	local item2 = items[idx2]
	if not item1 or not item2 then
		warn("Invalid item indices for player", userId, idx1, idx2)
		return
	end

	-- Swap positions
	local tempPos = item1.position
	item1.position = item2.position
	item2.position = tempPos

	-- Update instance positions (simple swap along Z axis for example)
	local cf1 = item1.instance:GetPivot()
	local cf2 = item2.instance:GetPivot()
	item1.instance:PivotTo(cf2)
	item2.instance:PivotTo(cf1)
end

-- ========== Internal ========== --

function Game:_nextTurnToken(): number
	self._turnToken = (self._turnToken or 0) + 1
	return self._turnToken
end

function Game:_armTurnTimeout(seconds: number, onTimeout: () -> ())
	local token = self:_nextTurnToken()
	task.delay(seconds, function()
		-- if token changed, turn advanced or game destroyed
		if self._turnToken ~= token then return end
		onTimeout()
	end)
end

-- ========== Life Cycle ========== --

function Game:Init()
	-- // Note: call :Start() instead
end

function Game:Destroy()
	-- // Clean up resources
	for _, itemData in self.gameState.userItems do
		for _, item in itemData do
			item.instance:Destroy()
		end
	end
	table.clear(self.gameState.userItems)

	-- Disconnect all connections
	for _, c in self._conns do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
end

return Game :: GameAPI
