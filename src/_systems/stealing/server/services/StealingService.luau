--!strict
-- StealingService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- // Utils
local StealingUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Stealing"))

-- // Types (generated)
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps inferred from real modules
type ServiceRegistry = ServicesTypes.Registry

type DataInterface  = ServicesTypes.DataInterface
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))
type Tunables       = { [string]: any } -- external tunables, not synced by rojo

export type Deps = {
	DataInterface: DataInterface,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
	Tunables: Tunables,
}

export type StealingServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: StealingServiceAPI, deps: Deps) -> (),
	Start: (self: StealingServiceAPI) -> (),
	Destroy: (self: StealingServiceAPI) -> (),

	GetPlayerHeldItemId: (self: StealingServiceAPI, player: Player) -> string?,
	GetHeldItemIdFromTier: (self: StealingServiceAPI, tier: number) -> string?,
	GetPlayerTier: (self: StealingServiceAPI, player: Player) -> number,
	SetPlayerHeldItemId: (self: StealingServiceAPI, player: Player,	itemId: string?) -> (),
	PerformExchange: (self: StealingServiceAPI, winner: Player, loser: Player) -> (),
	SelfUpgrade: (self: StealingServiceAPI, player: Player) -> boolean,
}

local StealingService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- // Assets
local SAMPLE_TIER_GUI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets"):WaitForChild("UI"):WaitForChild("Itemtag") :: BillboardGui
local SAMPLE_ITEM_TOOL = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Tools"):WaitForChild("SampleTool")

-- ========== Public API ========== --

-- ===== Getters and Setters ===== --
function StealingService:GetPlayerHeldItemId(player: Player, yield: boolean?): string?
	local profile = _deps.DataInterface:GetPlayerProfile(player, yield)
	if not profile then return nil end
	
	return profile.Data and profile.Data.Stealing and profile.Data.Stealing.heldItemId or nil
end

function StealingService:GetHeldItemIdFromTier(tier: number): string?
	if not _deps then return nil end

	local items = _deps.GameData.GetDataType("StealableItem").items
	local itemsByTier = StealingUtils.getStealableItemsByTier(items)
	if not itemsByTier then return nil end

	local itemInfo = itemsByTier[tier]
	return itemInfo and itemInfo.id or nil
end

function StealingService:GetPlayerTier(player: Player): number
	-- Get their held item
	local heldItemId = self:GetPlayerHeldItemId(player)
	if not heldItemId then return 0 end

	-- Get the tier from the held item
	local itemInfo = _deps.GameData.Get("StealableItem", heldItemId)
	if not itemInfo then return 0 end

	return itemInfo.tier
end

function StealingService:SetPlayerHeldItemId(player: Player, itemId: string?)
	local profile = _deps.DataInterface:GetPlayerProfile(player)
	if not profile or not profile.Data or not profile.Data.Stealing then return end

	profile.Data.Stealing.heldItemId = itemId

	if profile.Data.Stealing.seenItems == nil then
		profile.Data.Stealing.seenItems = {}
	end

	-- Register as seen (if itemId not nil, and not already seen)
	if itemId then
		if not profile.Data.Stealing.seenItems[itemId] then
			profile.Data.Stealing.seenItems[itemId] = {
				firstSeenAt = os.time(),
				timesSeen = 0,
			}
		end
		-- Increment times seen
		profile.Data.Stealing.seenItems[itemId].timesSeen += 1
	end

	-- Notify about held item change
	self:_onHeldItemChanged(player, itemId)
end

-- ===== Overhead Displays ===== --

function StealingService:RefreshHeldItemCharacterDisplay(player: Player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end

	-- == Clear current == --
	-- Clear display model
	local existingDisplay = char:FindFirstChild("_StealableItemDisplay")
	if existingDisplay then
		existingDisplay:Destroy()
	end
	-- Clear overhead gui
	local existingGui = char:FindFirstChild("_StealableItemDisplayGui")
	if existingGui then
		existingGui:Destroy()
	end

	-- Get their held item
	local heldItemId = self:GetPlayerHeldItemId(player, true)
	if not heldItemId or not _deps.GameData.Get("StealableItem", heldItemId) then
		return
	end

	local heldItemInfo = _deps.GameData.Get("StealableItem", heldItemId) :: any

	-- // Overhead Gui implementation
	local gui = char:FindFirstChild("_StealableItemDisplayGui") :: BillboardGui?
	if not gui then
		gui = SAMPLE_TIER_GUI:Clone() :: BillboardGui
		gui.Name = "_StealableItemDisplayGui"
		gui.Adornee = head
		gui.Parent = char
	end

	gui.Frame.ItemName.Text = heldItemInfo.name -- .. " (" .. heldItemInfo.tier .. ")"
	if heldItemInfo.textData then
		gui.Frame.ItemName.TextColor3 = heldItemInfo.textData.primaryColor or Color3.fromRGB(255, 255, 255)
	end

	-- // Physical model implementation
	local yOffset = 2.5
	local model = StealingUtils.getStealableItemModelFromPath(heldItemInfo.modelPath or {}):Clone() :: Model
	model.Name = "_StealableItemDisplay"
	model:PivotTo(head.CFrame * CFrame.new(0, yOffset, 0))

	-- Create handle
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.CFrame = model:GetPivot()
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Parent = model
	
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = false
			d.Massless = true
	
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = d
			weld.Part1 = handle
			weld.Parent = d
		end
	end

	-- Create an attachment to align to head
	local headAttach = head:FindFirstChild("_StealableItemDisplayAttach") :: Attachment?
	if not headAttach then
		headAttach = Instance.new("Attachment")
		headAttach.Name = "_StealableItemDisplayAttach"
		headAttach.Position = Vector3.new(0, yOffset, 0)
		headAttach.Parent = head
	end

	local modelAttach = Instance.new("Attachment")
	modelAttach.Name = "StealableItemModelAttach"
	modelAttach.Parent = handle

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = modelAttach
	alignPosition.Attachment1 = headAttach
	alignPosition.RigidityEnabled = false
	alignPosition.ReactionForceEnabled = true
	alignPosition.ApplyAtCenterOfMass = true
	alignPosition.Responsiveness = 50
	alignPosition.Parent = model

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = modelAttach
	alignOrientation.Attachment1 = headAttach
	alignOrientation.RigidityEnabled = false
	alignOrientation.Parent = model

	model.Parent = char
end

-- ===== Tools ===== --

function StealingService:RefreshHeldItemTool(player: Player)
	-- == Clear current == --
	-- Remove tool from player
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, v in backpack:GetChildren() do
			if CollectionService:HasTag(v, "_StealableItemTool") then
				v:Destroy()
			end
		end
	end
			
	local char = player.Character
	if char then
		for _, v in char:GetChildren() do
			if CollectionService:HasTag(v, "_StealableItemTool") then
				v:Destroy()
			end
		end
	end
	
	local heldItemId = self:GetPlayerHeldItemId(player, true)
	if not heldItemId then
		return
	end

	-- Get item info
	local heldItemInfo = _deps.GameData.Get("StealableItem", heldItemId)
	if not heldItemInfo then
		warn("[StealingService] Invalid heldItemId passed to GiveItemTool:", heldItemId)
		return
	end

	-- Create tool
	local tool = SAMPLE_ITEM_TOOL:Clone()
	tool.Name = heldItemInfo.name
	CollectionService:AddTag(tool, "_StealableItemTool")

	local model = StealingUtils.getStealableItemModelFromPath(heldItemInfo.modelPath or {}):Clone() :: Model
	model.Parent = tool

	-- Create handle
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Parent = tool
	end
	handle.CFrame = model:GetPivot()
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = false
			d.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = d
			weld.Part1 = handle
			weld.Parent = d
		end
	end

	tool.Parent = player:WaitForChild("Backpack")
end

-- ===== Game Logic ===== --

function StealingService:PerformExchange(winner: Player, loser: Player)
	-- Get winner and loser tiers
	local winnerTier = self:GetPlayerTier(winner)
	local loserTier = self:GetPlayerTier(loser)

	-- ItemIds to send to client display
	local winnerOldHeldItemId: string = self:GetPlayerHeldItemId(winner)
	local winnerNewHeldItemId: string = winnerOldHeldItemId -- set to old as default
	local loserOldHeldItemId: string = self:GetPlayerHeldItemId(loser)
	local loserNewHeldItemId: string = loserOldHeldItemId -- set to old as default

	-- Currency info to send to client display
	local earnedCurrencyAmount: number
	local earnedCurrencyId: string

	-- Winner logic
	if winnerTier < loserTier then
		-- Winner gets loser's item
		local loserItemId = self:GetPlayerHeldItemId(loser)
		self:SetPlayerHeldItemId(winner, loserItemId)
		winnerNewHeldItemId = loserItemId

		-- No currency
	elseif winnerTier == loserTier then
		-- Winner gets next tier item (if exists)
		local targetTier = winnerTier + 1
		local itemId = self:GetHeldItemIdFromTier(targetTier)
		if itemId then
			self:SetPlayerHeldItemId(winner, itemId)
			winnerNewHeldItemId = itemId

			-- No currency
		else
			-- No higher tier item, do nothing or give reward
			warn("[StealingService] No higher tier item for tier:", targetTier)

			-- Give currency
			local currencyId = _deps.Tunables.winCurrencyAmount or "Cash"
			local amount = _deps.Tunables.winCurrencyAmount or 15
			local success, breakdown = self.Services.CurrencyService:GiveCurrency(
				winner, currencyId, amount, true
			)
			if success then
				earnedCurrencyId = currencyId
				earnedCurrencyAmount = breakdown and breakdown.Total or amount
			end
		end
	else
		-- Winner already has higher tier, do nothing or give reward
		warn("[StealingService] Winner already has higher tier:", winnerTier, "vs loser tier:", loserTier)

		-- Give currency
		local currencyId = _deps.Tunables.winCurrencyAmount or "Cash"
		local amount = _deps.Tunables.winCurrencyAmount or 15
		local success, breakdown = self.Services.CurrencyService:GiveCurrency(
			winner, currencyId, amount, true
		)
		if success then
			earnedCurrencyId = currencyId
			earnedCurrencyAmount = breakdown and breakdown.Total or amount
		end
	end

	-- Loser logic: reset to initial item
	local baseHeldItemId = self:GetHeldItemIdFromTier(0)
	self:SetPlayerHeldItemId(loser, baseHeldItemId)
	loserNewHeldItemId = baseHeldItemId

	-- Display info on the clients
	self._stealResultRemote:FireClient(winner, {
		opponentUserId = loser.UserId,
		success = true,
		opponentOldHeldItemId = loserOldHeldItemId,
		opponentNewHeldItemId = loserNewHeldItemId,
		oldHeldItemId = winnerOldHeldItemId,
		newHeldItemId = winnerNewHeldItemId,
		earnedCurrencyAmount = earnedCurrencyAmount,
		earnedCurrencyId = earnedCurrencyId,
	})
	self._stealResultRemote:FireClient(loser, {
		opponentUserId = winner.UserId,
		success = false,
		opponentOldHeldItemId = winnerOldHeldItemId,
		opponentNewHeldItemId = winnerNewHeldItemId,
		oldHeldItemId = loserOldHeldItemId,
		newHeldItemId = loserNewHeldItemId,
		earnedCurrencyAmount = earnedCurrencyAmount,
		earnedCurrencyId = earnedCurrencyId,
	})
end

function StealingService:SelfUpgrade(player: Player): boolean
	-- Get player's current tier
	local currentTier = self:GetPlayerTier(player)

	-- Determine next tier item
	local targetTier = currentTier + 1
	local itemId = self:GetHeldItemIdFromTier(targetTier)
	if not itemId then
		-- No higher tier item
		return false
	end

	-- Get item info
	local itemInfo = _deps.GameData.Get("StealableItem", itemId)
	if not itemInfo or not itemInfo.currencyData then
		warn("[StealingService] Invalid item info or missing currency data for itemId:", itemId)
		return false
	end

	-- Check if player can afford
	local canAfford = self.Services.CurrencyService:CanAfford(player, itemInfo.currencyData.buyCurrencyId, itemInfo.currencyData.buyPrice, true)
	if not canAfford then
		return false
	end

	-- Spend currency
	local success = self.Services.CurrencyService:SpendCurrency(player, itemInfo.currencyData.buyCurrencyId, itemInfo.currencyData.buyPrice)
	if not success then
		return false
	end

	-- Set player's held item to next tier item
	self:SetPlayerHeldItemId(player, itemId)
	return true
end

-- ========== Internal ========== --

function StealingService:_onHeldItemChanged(player: Player, newItemId: string?)
	-- Signal to nametag system etc. to display above player's head
	self:RefreshHeldItemCharacterDisplay(player)
	self:RefreshHeldItemTool(player, newItemId)
end

-- ========== Player Life Cycle ========== --

function StealingService:_onCharacterAdded(player: Player, char: Model)
	local head = char:WaitForChild("Head") :: BasePart
	local human = char:WaitForChild("Humanoid") :: Humanoid
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart

	self:RefreshHeldItemCharacterDisplay(player)
	self:RefreshHeldItemTool(player)
end

function StealingService:_onPlayerAdded(player: Player)
	local char = player.Character or player.CharacterAdded:Wait()
	self:_onCharacterAdded(player, char)

	player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(player, character)
	end)
end

-- ========== Life Cycle ========== --

function StealingService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Create remotes
	self._stealResultRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "StealResult") :: RemoveEvent
	self._selfUpgradeHeldItemRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "SelfUpgradeHeldItem") :: RemoteEvent

	-- // Register reconcile section
	local defaultHeldItemId = "bread" :: string?
	if not _deps.GameData.Get("StealableItem", defaultHeldItemId) then
		defaultHeldItemId = nil
	end
	self.Services.DataInterface:RegisterReconcileSection("Data", "Stealing", {
		heldItemId = defaultHeldItemId,
		seenItems = {} :: { [string]: {
			firstSeenAt: number,
			timesSeen: number,
		} },
	})
end

function StealingService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Example: connect remotes, start loops, etc.
	for _, plr in Players:GetPlayers() do
		self:_onPlayerAdded(plr)
	end

	table.insert(self._conns, Players.PlayerAdded:Connect(function(player: Player)
		self:_onPlayerAdded(player)
	end))

	local selfUpgradeDebounce = {} :: { [Player]: true }
	table.insert(self._conns, self._selfUpgradeHeldItemRemote.OnServerEvent:Connect(function(player: Player)
		if selfUpgradeDebounce[player] then return end
		selfUpgradeDebounce[player] = true
		task.delay(0.50, function()
			selfUpgradeDebounce[player] = nil
		end)

		self:SelfUpgrade(player)
	end))
end

function StealingService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return StealingService :: StealingServiceAPI
