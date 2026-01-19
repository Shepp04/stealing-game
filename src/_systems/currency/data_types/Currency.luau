
--!strict
-- Currency (GameData type)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Assets
local Assets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets")
local ModelsFolder = Assets:WaitForChild("Models")

-- // Types
local DataTypes = require(ReplicatedStorage.Shared.Types.Data)

type PlayerProfile = DataTypes.PlayerProfile

type Collectable = {
	name: string,
	value: number,
	model: Model,
	soundId: number,
}

export type DataEntry = {
	name: string,
	symbol: string?,
	icon: string?,
	collectSoundId: number?,
	spendSoundId: number?,
	defaultValue: number?,
	earnedPromptEnabled: boolean?,
	rebirthMultiplier: number?,
	useLeaderstats: boolean,
	leaderstatsPosition: number?,
	friendBoostMultiplier: number?,
	collectables: { Collectable }?,

	Get: (profile: PlayerProfile) -> number,
	Set: (player: Player, profile: PlayerProfile, amount: number) -> (),
	Update: (player: Player, profile: PlayerProfile, amount: number) -> (),
}

type DataTypeDict = {
	name: string,
	public_field_whitelist: { [string]: boolean },
	items: { [string]: DataEntry },

	GetCurrencyText: (self: DataTypeDict, currencyId: string, amount: number, useCurrencyName: boolean?) -> string
}

local DATA_TYPE_NAME = "Currency"
local PUBLIC_FIELD_WHITELIST = {
	name = true, symbol = true, icon = true, collectSoundId = true, spendSoundId = true, defaultValue = true, rebirthMultiplier = true,
	useLeaderstats = true, useFriendsBoost = true, friendBoostMultiplier = true, leaderstatsPosition = true, collectables = true,
	Get = false, Set = false, Update = false,
}
local DATA: { [string]: DataEntry } = {
	Cash = {
		name = "Cash",
		symbol = "$",
		icon = "rbxassetid://106727718665166",
		collectSoundId = 7112275565,
		spendSoundId = 81816893340749,
		defaultValue = 0,
		earnedPromptEnabled = true,
		rebirthMultiplier = nil,
		useLeaderstats = true,
		useFriendsBoost = true,
		leaderstatsPosition = 3,
		friendBoostMultiplier = 1.1,
		collectables = nil,

		Get = function(profile: PlayerProfile): number
			return profile.Data.Stats and profile.Data.Stats.Cash or 0
		end,

		Set = function(player: Player, profile: PlayerProfile, amount: number)
			if profile.Data.Stats then
				profile.Data.Stats.Cash = amount
			end
		end,
		
		Update = function(player: Player, profile: PlayerProfile, amount: number)
			if profile.Data.Stats and profile.Data.Stats.Cash then
				profile.Data.Stats.Cash += amount
			end
		end,
	},

	Kills = {
		name = "Kills",
		symbol = nil,
		icon = "rbxassetid://106134811949520",
		collectSoundId = nil,
		spendSoundId = nil,
		defaultValue = 0,
		earnedPromptEnabled = false,
		rebirthMultiplier = nil,
		useLeaderstats = true,
		leaderstatsPosition = 1,
		friendBoostMultiplier = nil,
		collectables = nil,

		Get = function(profile: PlayerProfile): number
			return profile.Data.Stats and profile.Data.Stats.Kills or 0
		end,

		Set = function(player: Player, profile: PlayerProfile, amount: number)
			if profile.Data.Stats then
				profile.Data.Stats.Kills = amount
			end
		end,

		Update = function(player: Player, profile: PlayerProfile, amount: number)
			if profile.Data.Stats and profile.Data.Stats.Kills then
				profile.Data.Stats.Kills += amount
			end
		end,
	},
}

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

return DataTypeDict