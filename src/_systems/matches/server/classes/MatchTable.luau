--!strict
-- MatchTable (Server Class)

-- // Roblox Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Types
local GameTypes = require(ReplicatedStorage.Shared.Types:WaitForChild("Game"))
type GameContext = GameTypes.GameContext
type GameBroadcastState = GameTypes.GameBroadcastState
type GameAction = GameTypes.GameAction

type MatchStatus = "Waiting" | "Starting" | "Running"

export type TableState = {
	players: { Player },
	playerSet: { [Player]: boolean },
	isActive: boolean,
	scores: { [number]: number }, -- userId -> score
	status: MatchStatus,
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
	tableInstance: Instance,
	gameClass: GameAPI,
	minPlayers: number?,
	maxPlayers: number?,
}

export type MatchTableAPI = {
	_opts: Opts,
	_conns: { RBXScriptConnection },
	_debugId: string,

	gameClass: GameAPI,

	state: TableState,
	components: {
		tableInstance: Instance?,
		messageGui: BillboardGui?,
		cameraCFrames: { [string]: CFrame }?,
		winnerCFrame: CFrame?,
	},

	Init: (self: MatchTableAPI) -> (),
	Destroy: (self: MatchTableAPI) -> (),

	UpdateMessage: (self: MatchTableAPI, message: string) -> (),
	HasPlayer: (self: MatchTableAPI, player: Player) -> boolean,
	Join: (self: MatchTableAPI, player: Player) -> boolean,
	Leave: (self: MatchTableAPI, player: Player) -> (),
	StartGame: (self: MatchTableAPI) -> (),
	EndGame: (self: MatchTableAPI, winner: Player?) -> (),
	Reset: (self: MatchTableAPI) -> (),
}

local MatchTable = {}
MatchTable.__index = MatchTable

-- // Class-level variables
MatchTable.ActiveTables = {} :: { [string]: MatchTableAPI }

-- // Internal state
local _deps: Deps?

-- // Constants
local Assets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets")
local LEAVE_MATCH_GUI = Assets:WaitForChild("UI"):WaitForChild("LeaveMatchGui") :: ScreenGui

local COUNTDOWN = 5
local COINS_PER_MATCH_WIN = 10

-- // Animations
local WINNER_DANCE_ANIMATION_IDS : {[number]: string} = {
	[1] = "rbxassetid://121509216343037",
	[2] = "rbxassetid://83630821231909",
}

-- ========== Helpers =========== --

local function getBestOf(): number
	local v = _deps and _deps.Tunables and _deps.Tunables.bestOf
	if typeof(v) == "number" then
		-- allow only 1 or 3 for MVP
		if v == 1 or v == 3 then
			return v
		end
	end
	return 3
end

local function requiredWins(bestOf: number): number
	-- bestOf=1 -> 1, bestOf=3 -> 2
	return math.floor(bestOf / 2) + 1
end

local function freeFromTable(player: Player, playerSlots: { [number]: Folder })
	for _, folder in playerSlots do
		if folder:GetAttribute("OccupantUserId") == player.UserId then
			folder:SetAttribute("OccupantUserId", nil)
		end
	end
	-- Reset player walkspeed
	local char = player.Character
	local human = char and char:FindFirstChildWhichIsA("Humanoid")
	if human then
		human.WalkSpeed = _deps and _deps.Tunables and _deps.Tunables.defaultWalkSpeed or 16
	end
end

local function toggleLeaveGui(player: Player, state: boolean)
	local PlayerGui = player:FindFirstChild("PlayerGui")
	if not PlayerGui then return end

	for _, v in PlayerGui:GetChildren() do
		if v.Name == "_LeaveMatchGui" and v:IsA("ScreenGui") then
			v:Destroy()
		end
	end

	if state then
		local gui = LEAVE_MATCH_GUI:Clone()
		gui.Name = "_LeaveMatchGui"
		gui.Parent = PlayerGui
	end
end

-- ========== Constructor ========== --

function MatchTable.new(deps: Deps, opts: Opts?): MatchTableAPI
	_deps = deps

	local self = setmetatable({} :: any, MatchTable) :: MatchTableAPI
	self._opts = opts or {}
	self._conns = {}

	-- Generate a debug id
	self._debugId = HttpService:GenerateGUID(false)

	-- Validate table instance
	if not self:_validateTableInstance(self._opts.tableInstance) then
		error("Invalid table instance provided to MatchTable")
	end

	self._playerSlots = {} :: { [number]: Folder }
	
	local playerSlotsFolder = self._opts.tableInstance:FindFirstChild("PlayerSlots")
	if playerSlotsFolder and playerSlotsFolder:IsA("Folder") then
		for _, slot in pairs(playerSlotsFolder:GetChildren()) do
			local spawnPart = slot:FindFirstChild("SpawnPart")
			if spawnPart and spawnPart:IsA("BasePart") then
				table.insert(self._playerSlots, slot)
			end
		end
	end

	self.gameClass = self._opts.gameClass

	self.components = {
		tableInstance = self._opts.tableInstance,
		messageGui = nil,
		cameraCFrames = nil,
		winnerCFrame = nil,
	}

	self.state = {
		players = {},
		playerSet = {},
		isActive = false,
		scores = {},
		status = "Waiting",
	}

	self._bestOf = getBestOf()
	self._winsToWin = requiredWins(self._bestOf)
	self._roundIndex = 0

	self._minPlayers = self._opts.minPlayers or 2
	self._maxPlayers = self._opts.maxPlayers or 2

	-- Get remotes
	self._gameStateRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "GameState") :: RemoteEvent
	self._gameActionRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "GameAction") :: RemoteEvent

	-- Get components
	local messageGui = self.components.tableInstance:FindFirstChild("MessageGui")
	if not messageGui or not messageGui:IsA("BillboardGui") then
		warn("Table instance is missing a valid MessageGui BillboardGui")
	else
		self.components.messageGui = messageGui
	end
	
	local cameraCFramesFolder = self.components.tableInstance:FindFirstChild("CameraCFrames")
	if not cameraCFramesFolder or not cameraCFramesFolder:IsA("Folder") then
		warn("Table instance is missing a valid CameraCFrames folder")
	else
		self.components.cameraCFrames = {
			matchEnd = cameraCFramesFolder:FindFirstChild("MatchEnd").CFrame,
			winner = cameraCFramesFolder:FindFirstChild("Winner").CFrame,
			player1 = cameraCFramesFolder:FindFirstChild("Player1").CFrame,
			player2 = cameraCFramesFolder:FindFirstChild("Player2").CFrame,
		}
	end

	local winnerCFramePart = self.components.tableInstance:FindFirstChild("WinnerCFrame")
	if not winnerCFramePart or not winnerCFramePart:IsA("BasePart") then
		warn("Table instance is missing a valid WinnerCFrame part")
	else
		self.components.winnerCFrame = winnerCFramePart.CFrame
	end

	-- Add to active tables
	MatchTable.ActiveTables[self._debugId] = self

	return self
end

-- ========== Public API ========== --

function MatchTable:UpdateMessage(message: string)
	if self.components.messageGui then
		local textLabel = self.components.messageGui:FindFirstChildWhichIsA("TextLabel")
		if textLabel then
			textLabel.Text = message
		end
	end
end

function MatchTable:HasPlayer(player: Player): boolean
	return self.state.playerSet[player] ~= nil
end

function MatchTable:StartGame()
	if self.state.status ~= "Waiting" or #self.state.players < self._minPlayers then return false end
	self.state.status = "Starting"

	-- Countdown
	for t = COUNTDOWN, 1, -1 do
		self:UpdateMessage("Starting in " .. t)
		task.wait(1)
		if #self.state.players < self._minPlayers then
			self.state.status = "Waiting"
			self:_onPlayerSetChanged()
			return false
		end
	end
	
	self:UpdateMessage("")

	-- Reorder players to match table sides BEFORE game starts
	self.state.players = self:_playersOrderedByPositions()
	
	-- Remove the leave Guis and tell the players the match has begun (and initial state info)
	for _, plr in self.state.players do
		toggleLeaveGui(plr :: Player, false)
		self._gameStateRemote:FireClient(plr, "MatchBegin")
		self._gameStateRemote:FireClient(plr, "Players", { userId1 = self.state.players[1].UserId, userId2 = self.state.players[2].UserId })
	end
	
	-- Start match state + scores
	self:_startMatch()

	-- Start round 1
	self:_startNextRound()

	return true
end

function MatchTable:EndGame(winner: Player?)
	if self.state.status ~= "Running" then return false end

	for _, plr in ipairs(self.state.players) do
		self._gameStateRemote:FireClient(plr, "MatchOver", {
			winnerUserId = winner and winner.UserId or 0,
			winnerCameraCFrame = self.components.cameraCFrames.matchEnd,
		})
		if winner then
			if plr == winner then
				_deps.Services.CurrencyService:GiveCurrency(plr, "Wins", 1, false, false)
				_deps.Services.CurrencyService:GiveCurrency(plr, "Streak", 1, false, false)
				_deps.Services.CurrencyService:GiveCurrency(plr, "Coins", COINS_PER_MATCH_WIN, true, false)
			else
				_deps.Services.CurrencyService:SetCurrency(plr, "Streak", 0)
			end
		end
	end

	-- Teleport the winner and make them dance
	if (winner) then
		local char = winner.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		local human = char and char:FindFirstChild("Humanoid") :: Humanoid
		if (root and human) then
			-- Load a dance animation
			local animator = human:FindFirstChildOfClass("Animator") :: Animator
			if not (animator) then
				animator = Instance.new("Animator")
				animator.Parent = human
			end
			
			local animID = "rbxassetid://182436842" -- self:_getWinnerDanceId(winner)
			local animation = Instance.new("Animation")
			animation.AnimationId = animID
			
			-- Play music
			_deps.SharedPackages.Sounds:PlayLoopingSound("WinnerMusic", self.components.tableInstance:FindFirstChild("Trigger"), nil, true)
			
			-- Play the dance
			local animTrack = animator:LoadAnimation(animation)
			animTrack.Looped = true
			animTrack:Play()
			
			-- Record the winner's current CFrame and teleport them to the winner position
			local originalCFrame = root.CFrame
			root.CFrame = self.components.winnerCFrame
			
			task.wait(5.0)
			
			-- Fade out the music
			_deps.SharedPackages.Sounds:StopLoopingSound("WinnerMusic", true)
			
			-- Stop the dance and teleport them back
			animTrack:Stop()
			root.CFrame = originalCFrame
		end
	else
		task.wait(2.5)
	end
	
	-- Destroy the game instance
	if self.game and self.game.Destroy then
		self.game:Destroy()
	end
	self.game = nil
	
	-- Give each player a debounce so they don't join again by accident
	for _, plr in self.state.players do
		_deps.SharedPackages.Debounce:Try(plr.UserId .. "_MatchTableJoin_" .. self._debugId, 5.0, nil)
	end

	self:Reset()
	return true
end

function MatchTable:Reset()
	self.state.status = "Waiting"

	for _, plr in self.state.players do
		freeFromTable(plr, self._playerSlots)
		toggleLeaveGui(plr, false)
		self._gameStateRemote:FireClient(plr, "LeaveMatch")
		self.state.playerSet[plr] = nil
	end
	self.state.scores = {}
	self.state.players = {}
	self.state.playerSet = {}

	self:UpdateMessage("Waiting for players...")

	-- Clear all seat slots
	for _, folder in self._playerSlots do
		if folder:IsA("Folder") then
			folder:SetAttribute("OccupantUserId", nil)
		end
	end
end

function MatchTable:Join(player: Player): boolean
	-- Check general debounce
	if not _deps.SharedPackages.Debounce:Try("_MatchTableJoin_" .. self._debugId, 0.25) then
		return false
	end

	-- Check player specific debounce (longer duration - triggered when they leave)
	if not _deps.SharedPackages.Debounce:Try(player.UserId .. "_MatchTableJoin_" .. self._debugId, 0.25) then
		return false
	end

	-- Check the table isn't full and that the player hasn't already joined a table
	if self.state.playerSet[player] or #self.state.players >= self._maxPlayers then
		return false
	end

	for _, t in pairs(MatchTable.ActiveTables) do
		if t:HasPlayer(player) then
			return false
		end
	end

	-- Validate character and humanoid
	local char = player.Character
	local human = char and char:FindFirstChildWhichIsA("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not root or not human or human.Health <= 0 then
		return false
	end

	-- Show leave gui
	toggleLeaveGui(player, true)

	-- Serialise seat assignments to prevent race conditions
	while self._seatLock do task.wait() end
	self._seatLock = true

	-- Assign player to a seat
	local chosenPart: BasePart? = nil
	
	for _, slot in self._playerSlots do
		local spawnPart = slot:FindFirstChild("SpawnPart")
		local occupiedValue = slot:GetAttribute("OccupantUserId")
		if spawnPart and spawnPart:IsA("BasePart") and (not occupiedValue) then
			chosenPart = spawnPart
			slot:SetAttribute("OccupantUserId", player.UserId)
			break
		end
	end

	self._seatLock = false

	if not chosenPart then
		warn("No available seat found for player:", player.Name)
		return false
	else
		print("Player", player.Name, "seated at", chosenPart.Name)
		-- Teleport player to seat and set their walkspeed to 0
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local human = char and char:FindFirstChildWhichIsA("Humanoid")
		if char and root and human then
			root.CFrame = chosenPart.CFrame
			human.WalkSpeed = 0
		end
	end

	table.insert(self.state.players, player)
	self.state.playerSet[player] = true

	self:_onPlayerSetChanged()

	-- Initialise player score
	self.state.scores[player.UserId] = 0

	return true
end

function MatchTable:Leave(player: Player): boolean
	-- Check that they are in the table
	if not self.state.playerSet[player] then return false end
	self.state.playerSet[player] = nil

	local idx = table.find(self.state.players, player)
	if idx then
		table.remove(self.state.players, idx)
	end

	self:_onPlayerSetChanged()

	-- Add debounce
	_deps.SharedPackages.Debounce:Try(player.UserId .. "_MatchTableJoin_" .. self._debugId, 2.0)

	-- Free them from their seat
	freeFromTable(player, self._playerSlots)

	-- Hide their leave gui
	toggleLeaveGui(player, false)

	-- Notify them they have left
	self._gameStateRemote:FireClient(player, "LeaveMatch")
	
	return true
end

-- ========== Internal ========== --

function MatchTable:_getWinnerDanceID(player: Player): string
	return WINNER_DANCE_ANIMATION_IDS[math.random(1, #WINNER_DANCE_ANIMATION_IDS)]
end

function MatchTable:_onPlayerSetChanged()
	self:UpdateMessage(string.format("Players: %d/%d", #self.state.players, self._maxPlayers))
	if self.state.status == "Waiting" and #self.state.players == self._maxPlayers then
		self:StartGame()
	elseif self.state.status == "Running" and #self.state.players < self._minPlayers then
		self:EndGame(nil)
	end
end

function MatchTable:_playersOrderedByPositions(): {Player}
	local slots = {} :: {[number]: Player}
	for _, plr in ipairs(self.state.players) do
		for _, slot in self._playerSlots do
			if slot:GetAttribute("OccupantUserId") == plr.UserId then
				local idx = tonumber(slot:GetAttribute("SlotIndex")) or 9999
				if not slots[idx] then slots[idx] = plr end
				break
			end
		end
	end
	-- produce ordered list 1..max players (ignore gaps)
	local ordered = {}
	for i = 1, self._maxPlayers do
		if slots[i] then table.insert(ordered, slots[i]) end
	end
	-- fallback: if something went wrong, keep original order
	if #ordered < #self.state.players then
		for _, plr in ipairs(self.state.players) do
			if not table.find(ordered, plr) then
				table.insert(ordered, plr)
			end
		end
	end
	return ordered
end

function MatchTable:_validateTableInstance(instance: Instance?): boolean
	-- Check that it is a model/folder
	if not instance then
		warn("Table instance is nil")
		return false
	end
	if not (instance:IsA("Model") or instance:IsA("Folder")) then
		warn("Table instance is not a Model or Folder")
		return false
	end

	-- Check for a trigger part
	local triggerPart = instance:FindFirstChild("Trigger")
	if not triggerPart or not triggerPart:IsA("BasePart") then
		warn("Table instance is missing a valid TriggerPart")
		return false
	end

	-- Check for player slots folder
	local playerSlotsFolder = instance:FindFirstChild("PlayerSlots")
	if not playerSlotsFolder or not playerSlotsFolder:IsA("Folder") then
		warn("Table instance is missing a valid PlayerSlots folder")
		return false
	end

	return true
end

function MatchTable:_buildCtx(): GameContext
	return {
		tableInstance = self.components.tableInstance,
		numItems = self._numItems or 5,
		shuffleSpeed = self._shuffleSpeed or 1,
		
		getPlayers = function(): {Player}
			return self.state.players
		end,
		send = function(player: Player, kind: GameBroadcastState, ...: any)
			self._gameStateRemote:FireClient(player, kind, ...)
		end,
		broadcast = function(kind: GameBroadcastState, ...: any)
			for _, plr in ipairs(self.state.players) do
				self._gameStateRemote:FireClient(plr, kind, ...)
			end
		end,
	}
end

function MatchTable:_broadcastScores()
	local p1 = self.state.players[1]
	local p2 = self.state.players[2]
	if not (p1 and p2) then return end

	for _, plr in ipairs(self.state.players) do
		self._gameStateRemote:FireClient(plr, "Score", {
			player1Score = self.state.scores[p1.UserId] or 0,
			player2Score = self.state.scores[p2.UserId] or 0,
			winsToWin = self._winsToWin,
		})
	end
end

function MatchTable:_startMatch()
	self.state.status = "Running"
	self.state.scores = {}
	self._roundIndex = 0

	for _, plr in ipairs(self.state.players) do
		self.state.scores[plr.UserId] = 0
	end

	-- Optional: broadcast initial score state (use your existing "Players" + add a "Score" state later)
	self:_broadcastScores()
end

function MatchTable:_startNextRound()
	-- Guard
	if self.state.status ~= "Running" then return end
	if self.game then
		pcall(function() self.game:Destroy() end)
		self.game = nil
	end

	self._roundIndex += 1

	local ctx = self:_buildCtx()

	self.game = self.gameClass.new(_deps, {
		ctx = ctx,
		onGameEnd = function(winner: Player?)
			self:_onRoundEnded(winner)
		end,
		tunables = {
			-- Round tunables (keep these)
			numItems = 6,
			numLosingItems = 2,
			numEmptySafe = 3,
			revealSeconds = 1.25,
			shuffleBeats = 4,
			beatDuration = 0.45,
			setupTimeout = 12,
			chooseTimeout = 8,
		},
	}) :: GameAPI

	self.game:Start()
end


function MatchTable:_onRoundEnded(winner: Player?)
	-- If someone left mid-round, EndGame(nil) may be called elsewhere; guard
	if self.state.status ~= "Running" then return end

	-- Update score
	if winner then
		self.state.scores[winner.UserId] = (self.state.scores[winner.UserId] or 0) + 1
	end

	-- Optional: broadcast score update (add state later if you want)
	self:_broadcastScores()

	-- Decide if match is over
	if winner then
		local wins = self.state.scores[winner.UserId] or 0
		if wins >= (self._winsToWin or 2) then
			self:EndGame(winner)
			return
		end
	end

	-- If no winner (draw / disconnect), end match
	if not winner then
		self:EndGame(nil)
		return
	end

	-- Start next round after a short breather
	task.delay(1.25, function()
		-- Ensure still running & still 2 players
		if self.state.status ~= "Running" then return end
		if #self.state.players < self._minPlayers then return end
		self:_startNextRound()
	end)
end

-- ========== Life Cycle ========== --

function MatchTable:Init()
	-- // Connect touch event
	local triggerPart = self.components.tableInstance:FindFirstChild("Trigger")
	if not triggerPart or not triggerPart:IsA("BasePart") then
		warn("Cannot init MatchTable; missing Trigger part")
		return
	end

	local debounce = false
	table.insert(self._conns, triggerPart.Touched:Connect(function(hit: BasePart)
		if debounce then return end
		debounce = true

		task.delay(0.25, function() debounce = false end)

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end

		self:Join(player)
	end))
end

function MatchTable:Destroy()
	-- Destroy the game instance
	if self.game and self.game.Destroy then
		pcall(function() self.game:Destroy() end)
	end

	-- Reset
	self:Reset()

	-- Disconnect connections
	for _, c in self._conns do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
end

return MatchTable :: MatchTableAPI
