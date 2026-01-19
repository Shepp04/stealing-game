--!strict
-- CurrencyService (Service) — lifecycle-first singleton discovered by Services registry.

-- // Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- // Utils
local CurrencyUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Currency"))

-- // Custom Types
export type CurrencyBreakdown = {
	Base: number,
	Total: number,
	FriendBoost: number,
	RebirthBoost: number,
	GamepassBoost: number,
}

-- // Types (generated)
local ServicesTypes = require(ReplicatedStorage.Shared.Types.Services)

-- // Type aliases for deps inferred from real modules
type ServiceRegistry = ServicesTypes.Registry

type DataInterface  = ServicesTypes.DataInterface
type SharedPackages = typeof(require(ReplicatedStorage.Shared.Packages))
type GameData       = typeof(require(ReplicatedStorage.Shared.GameData))
type Monetisation   = typeof(require(ReplicatedStorage.Shared.Monetisation))
type Config         = typeof(require(ReplicatedStorage.Shared.Config))

export type Deps = {
	DataInterface: DataInterface,
	SharedPackages: SharedPackages,
	GameData: GameData,
	Monetisation: Monetisation,
	Config: Config,
}

export type CurrencyServiceAPI = {
	_inited: boolean,
	_started: boolean,
	_conns: { RBXScriptConnection },
	Priority: number?,
	Services: ServiceRegistry, -- optional backref to the registry, filled by bootstrapper

	Init: (self: CurrencyServiceAPI, deps: Deps) -> (),
	Start: (self: CurrencyServiceAPI) -> (),
	Destroy: (self: CurrencyServiceAPI) -> (),

	CanAfford: (self: CurrencyServiceAPI, player: Player, currencyId: string, amount: number, promptUser: boolean?) -> boolean,
	GiveCurrency: (self: CurrencyServiceAPI, player: Player, currencyId: string, amount: number, useMultipliers: boolean?, showDrops: boolean?) -> (boolean, CurrencyBreakdown),
	SpendCurrency: (self: CurrencyServiceAPI, player: Player, currencyId: string, amount: number) -> boolean,
	SetCurrency: (self: CurrencyServiceAPI, player: Player, currencyId: string, amount: number) -> boolean,
	GetCurrencyMultiplier: (self: CurrencyServiceAPI, player: Player, currencyId: string) -> (number, { [string]: number }),
	SetMultiplier: (self: CurrencyServiceAPI, player: Player, multiplierId: string, currencyId: string, multiplier: number, duration: number?) -> boolean,
}

local CurrencyService = {
	_inited = false,
	_started = false,
	_conns = {},
	Priority = 50, -- higher -> starts earlier
	Services = {} :: ServiceRegistry,
}

-- Private captured deps for intellisense-friendly access
local _deps: Deps?

-- ========== Public API ========== --

--[[
    :CanAfford()
	Returns whether the player can afford a currency amount.

	@param player Player
	@param currencyId string
	@param amount number
	@param promptUser? boolean — If true, shows a UI message on insufficient funds.
	@return boolean
]]
function CurrencyService:CanAfford(player: Player, currencyId: string, amount: number, promptUser: boolean?): boolean
	local profile = self:_getPlayerProfile(player)
	if not profile then return false end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return false end

	local balance = currencyInfo.Get(profile)
	if typeof(balance) ~= "number" then
		warn("[Currency] Could not read balance for", currencyId)
		return false
	end

	if balance < amount then
		if promptUser and _deps.SharedPackages and _deps.SharedPackages.Messages then
			local missing = amount - balance
			local currencyText = CurrencyUtils.GetCurrencyText(currencyId, missing, true)
			local text = "You need " .. currencyText .. "!"
			_deps.SharedPackages.Messages:ShowMessage(player, text, "Error")
		end
		return false
	end

	return true
end

--[[
    :GiveCurrency()
	Adds currency to a player.

	@param player Player
	@param currencyId string
	@param amount number — Clamped to ≥ 0
	@param useMultipliers boolean — If true, applies GetCurrencyMultiplier()
	@param showDrops boolean — Reserved for VFX/FX hooks (not used here)
	@return (boolean, CurrencyBreakdown) — success, breakdown of amount given
]]
function CurrencyService:GiveCurrency(player: Player, currencyId: string, amount: number, useMultipliers: boolean?, showDrops: boolean?): (boolean, CurrencyBreakdown)
	local profile = self:_getPlayerProfile(player)
	if not profile then 
		return false, { Base = 0, Total = 0, FriendBoost = 0, RebirthBoost = 0, GamepassBoost = 0 }
	end
	
	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then 
		return false, { Base = 0, Total = 0, FriendBoost = 0, RebirthBoost = 0, GamepassBoost = 0 }
	end
	
	amount = math.clamp(amount, 0, math.huge)
	local breakdown = self:_calculateBreakdown(player, currencyId, amount, useMultipliers or false)
	
	-- Round up to integer if your economy is integer-based
	local totalAmount = math.ceil(breakdown.Total)
	currencyInfo.Update(player, profile, totalAmount)
	
	if currencyInfo.useLeaderstats then
		self:_updateLeaderstat(player, currencyId, currencyInfo.Get(profile))
	end

	-- If show drops is true, show on the client
	if showDrops then
		self._dropCurrencyRemote:FireClient(player, currencyId, totalAmount)
	end

	return true, breakdown
end

--[[
    :SpendCurrency()
	Spends currency from a player if affordable (prompts on failure if requested).

	@param player Player
	@param currencyId string
	@param amount number
	@return boolean
]]
function CurrencyService:SpendCurrency(player: Player, currencyId: string, amount: number): boolean
	local profile = self:_getPlayerProfile(player)
	if not profile then return false end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return false end

	if not self:CanAfford(player, currencyId, amount, true) then
		return false
	end

	amount = math.clamp(amount, 0, math.huge)
	currencyInfo.Update(player, profile, -amount)

	if currencyInfo.useLeaderstats then
		self:_updateLeaderstat(player, currencyId, currencyInfo.Get(profile))
	end

	return true
end

--[[
    :SetCurrency()
	Sets a player's currency to an absolute value.

	@param player Player
	@param currencyId string
	@param amount number
	@return boolean
]]
function CurrencyService:SetCurrency(player: Player, currencyId: string, amount: number): boolean
	local profile = self:_getPlayerProfile(player)
	if not profile then return false end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return false end

	currencyInfo.Set(player, profile, math.ceil(amount))

	if currencyInfo.useLeaderstats then
		self:_updateLeaderstat(player, currencyId, currencyInfo.Get(profile))
	end

	return true
end

--[[
    :GetCurrencyMultiplier()
	Calculates the combined multiplier for a currency for the given player.

	Includes:
	- Friend boosts (neighbors in server who are Roblox friends)
	- Temporary/permanent boosts saved in profile.Info.Multipliers
	- Rebirth multiplier

	@param player Player
	@param currencyId string
	@return (number >= 1.0, multipliersUsed: { [string]: number })
]]
function CurrencyService:GetCurrencyMultiplier(player: Player, currencyId: string): (number, { [string]: number })
	local profile = self:_getPlayerProfile(player, true)
	if not profile then return 1.0, {} end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return 1.0, {} end

	local totalBonus = 0.0
	local multipliersUsed: { [string]: number } = {}

	-- Friend boost
	local friendBoost = self:GetFriendsBoost(player, currencyId)
	if friendBoost > 1.0 then
		totalBonus += friendBoost - 1.0
		multipliersUsed["FriendsBoost"] = friendBoost - 1.0
	end

	-- Multipliers (temp/permanent) saved in profile.Info.Multipliers
	if profile.Info and profile.Info.Multipliers then
		for _, entry in profile.Info.Multipliers do
			if entry.CurrencyId == currencyId then
				local bonusIncrease = entry.Value - 1
				totalBonus += bonusIncrease

				multipliersUsed[entry.CurrencyId] = multipliersUsed[entry.CurrencyId] or 0
				multipliersUsed[entry.CurrencyId] += bonusIncrease
			end
		end
	end

	-- Rebirth multiplier (example)
	if profile.Data and profile.Data.Stats and profile.Data.Stats.Rebirths and profile.Data.Stats.Rebirths > 1 then
		local rebirthMult = currencyInfo.rebirthMultiplier or 1.25
		local bonusIncrease = (profile.Data.Stats.Rebirths - 1) * rebirthMult
		totalBonus += bonusIncrease
		multipliersUsed["Rebirths"] = bonusIncrease
	end

	return math.max(1.0, 1.0 + totalBonus), multipliersUsed
end

--[[
    :SetMultiplier()
	Sets/schedules a multiplier for a currency.

	If `duration` is provided:
	- Stores an expiry (EndTime) and removes the multiplier after `duration` seconds
	  *if* it hasn't been replaced meanwhile (by checking LastUpdate guard).

	@param player Player
	@param multiplierId string
	@param currencyId string
	@param multiplier number (e.g., 1.5 for +50%)
	@param duration? number — seconds; nil for permanent
	@return boolean
]]
function CurrencyService:SetMultiplier(player: Player, multiplierId: string, currencyId: string, multiplier: number, duration: number?): boolean
	local profile = self:_getPlayerProfile(player, true)
	if not profile then return false end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return false end

	profile.Info = profile.Info or {}
	profile.Info.Multipliers = profile.Info.Multipliers or {}

	local currentTime = os.time()
	local endTime = duration and (currentTime + duration) or nil

	profile.Info.Multipliers[multiplierId] = {
		EndTime = endTime;
		Value = multiplier;
		IsPermanent = duration == nil;
		LastUpdate = currentTime;
		CurrencyId = currencyId;
	}

	if _deps.Config.General and _deps.Config.General.devMode then
		print(("[Currency] Set multiplier '%s' for %s x%s for %s")
			:format(multiplierId, player.Name, tostring(multiplier), tostring(duration or "∞")))
	end

	if duration then
		task.delay(duration, function()
			local infoTbl = profile.Info and profile.Info.Multipliers
			local info = infoTbl and infoTbl[multiplierId]
			if info and info.LastUpdate == currentTime then
				infoTbl[multiplierId] = nil
				if _deps.Config.General and _deps.Config.General.devMode then
					print(("[Currency] Removed multiplier '%s' from %s after %ds"):format(multiplierId, player.Name, duration))
				end
			end
		end)
	end

	return true
end

--[[
	:_calculateBreakdown()
	Calculates breakdown of currency amount into base and individual multiplier contributions.

	@param player Player
	@param currencyId string
	@param baseAmount number — the base amount before multipliers
	@param useMultipliers boolean — whether to apply multipliers
	@return CurrencyBreakdown
]]
function CurrencyService:_calculateBreakdown(player: Player, currencyId: string, baseAmount: number, useMultipliers: boolean): CurrencyBreakdown
	local breakdown: CurrencyBreakdown = {
		Base = baseAmount,
		Total = baseAmount,
		FriendBoost = 0,
		RebirthBoost = 0,
		GamepassBoost = 0,
	}

	if not useMultipliers then
		return breakdown
	end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then
		return breakdown
	end

	local profile = self:_getPlayerProfile(player)
	if not profile then
		return breakdown
	end

	-- // Calculate friend boost
	local friendBoostMultiplier = self:GetFriendsBoost(player, currencyId)
	if friendBoostMultiplier > 1.0 then
		local friendBoostAmount = baseAmount * (friendBoostMultiplier - 1.0)
		breakdown.FriendBoost = friendBoostAmount
		breakdown.Total += friendBoostAmount
	end

	-- // Calculate rebirth boost
	if profile.Data and profile.Data.Stats and profile.Data.Stats.Rebirths and profile.Data.Stats.Rebirths > 0 then
		local rebirthMult = currencyInfo.rebirthMultiplier or 0.25
		local rebirthBoostAmount = baseAmount * (profile.Data.Stats.Rebirths * rebirthMult)
		breakdown.RebirthBoost = rebirthBoostAmount
		breakdown.Total += rebirthBoostAmount
	end

	-- // Calculate gamepass/other multipliers boost
	if profile.Info and profile.Info.Multipliers then
		local gamepassBoostTotal = 0
		for _, entry in profile.Info.Multipliers do
			if entry.CurrencyId == currencyId then
				local bonusIncrease = entry.Value - 1.0
				if bonusIncrease > 0 then
					gamepassBoostTotal += baseAmount * bonusIncrease
				end
			end
		end
		breakdown.GamepassBoost = gamepassBoostTotal
		breakdown.Total += gamepassBoostTotal
	end

	return breakdown
end

--[[
	:GetFriendsBoost()
	Calculates the friends boost multiplier for a player for a given currency.

	@param player Player
	@param currencyId string
	@return number >= 1.0
]]
function CurrencyService:GetFriendsBoost(player: Player, currencyId: string): number
	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return 1.0 end

	if typeof(currencyInfo.friendBoostMultiplier) == "number" and currencyInfo.friendBoostMultiplier > 1.0 then
		local friendCount = 0
		for _, other in Players:GetPlayers() do
			if player ~= other and player:IsFriendsWith(other.UserId) then
				friendCount += 1
			end
		end
		if friendCount > 0 then
			return friendCount * (currencyInfo.friendBoostMultiplier or 0)
		end
	end

	return 1.0
end

-- ========== Internal ========== --

-- Data Management
function CurrencyService:_getPlayerProfile(player: Player, yield: boolean): any?
	local profile = _deps.DataInterface:GetPlayerProfile(player, yield)
	if not profile then
		warn("[CurrencyService] Couldn't load profile for", player)
		return nil
	end
	return profile
end

--[[
	Registers reconcile sections with your DataManager via DataInterface.

	- "Info/Multipliers": dictionary of active multipliers
	- "Data/Stats": numeric balances for each currency type

	(Adjust to match your DataManager schema.)
]]
function CurrencyService:_registerReconcileSections()
	local statsTemplate = {}
	for currencyId, currencyInfo in _deps.GameData.GetDataType("Currency").items do
		statsTemplate[currencyId] = currencyInfo.DefaultValue or 0
	end
	_deps.DataInterface:RegisterReconcileSection("Info", "Multipliers", {})
	_deps.DataInterface:RegisterReconcileSection("Data", "Stats", statsTemplate)
end

-- Leaderstats Management
function CurrencyService:_updateLeaderstat(player: Player, currencyId: string, newValue: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local currencyInfo = _deps.GameData.Get("Currency", currencyId)
	if not currencyInfo then return end

	-- Using display name for the NumberValue (match your buildLeaderstats logic)
	local statName = currencyInfo.name
	local stat = leaderstats:FindFirstChild(statName)
	if stat and stat:IsA("NumberValue") then
		stat.Value = newValue
	end
end

function CurrencyService:_buildLeaderstatsValues(profile: any): { NumberValue }
	local specified = {}
	local unspecified = {}

	for _, currencyInfo in _deps.GameData.GetDataType("Currency").items do
		if currencyInfo.useLeaderstats then
			local val = Instance.new("NumberValue")
			val.Name = currencyInfo.name
			val.Value = currencyInfo.Get(profile) or 0

			local pos = (currencyInfo :: any).leaderstatsPosition
			if typeof(pos) == "number" and pos >= 1 then
				table.insert(specified, { pos = pos, val = val })
			else
				table.insert(unspecified, { val = val })
			end
		end
	end

	table.sort(specified, function(a, b) return a.pos < b.pos end)
	table.sort(unspecified, function(a, b) return a.val.Name < b.val.Name end)

	local ordered = {}
	local seen = {}
	local dupTail = {}

	for _, entry in ipairs(specified) do
		if not seen[entry.pos] then
			seen[entry.pos] = true
			table.insert(ordered, entry.val)
		else
			table.insert(dupTail, entry.val)
		end
	end
	for _, entry in ipairs(unspecified) do
		table.insert(ordered, entry.val)
	end
	for _, v in ipairs(dupTail) do
		table.insert(ordered, v)
	end

	return ordered
end

-- // Player Management
function CurrencyService:_onPlayerAdded(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local profile = self:_getPlayerProfile(player, true)
	if not profile then return end

	for _, val in self:_buildLeaderstatsValues(profile) do
		val.Parent = leaderstats
	end
end

-- ========== Life Cycle ========== --

function CurrencyService:Init(deps: Deps)
	if self._inited then return end
	self._inited = true
	self._conns = {}
	_deps = deps

	-- // Register reconcile sections
	self:_registerReconcileSections()

	-- // Create remotes
	self._dropCurrencyRemote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "DropCurrency") :: RemoteEvent
end

function CurrencyService:Start()
	if not self._inited or self._started then return end
	self._started = true

	-- // Bind player events
	for _, plr in Players:GetPlayers() do
		self:_onPlayerAdded(plr)
	end
	self._conns.PlayerAdded = Players.PlayerAdded:Connect(function(player: Player)
		self:_onPlayerAdded(player)
	end)
end

function CurrencyService:Destroy()
	for _, conn in self._conns do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
	self._started = false
	self._inited = false
end

return CurrencyService :: CurrencyServiceAPI