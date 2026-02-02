--!strict
-- StealableItem (GameData type)

export type DataEntry = {
	id: string?,
	tier: number,
	name: string,
	icon: string,
	rarity: string,

	modelPath: { string }?,

	textData: {
		primaryColor: Color3,
		secondaryColor: Color3,
	}?,

	currencyData: {
		buyPrice: number,
		buyCurrencyId: string,
	}?
}

type DataTypeDict = {
	name: string,
	public_field_whitelist: { [string]: boolean },
	items: { [string]: DataEntry }
}

local DATA_TYPE_NAME = "StealableItem"
local PUBLIC_FIELD_WHITELIST = {
	["id"] = true,
	["tier"] = true,
	["name"] = true,
	["icon"] = true,
	["rarity"] = true,
	["modelPath"] = true,
	["textData"] = true,
	["currencyData"] = true,
}
local DATA: { [string]: DataEntry } = {
	["bread"] = {
		tier = 0,
		name = "Bread",
		icon = nil,
		rarity = "Common",
		modelPath = { "Bread" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(245, 222, 179),
			secondaryColor = Color3.fromRGB(210, 180, 140),
		},
		currencyData = {
			buyPrice = 0,
			buyCurrencyId = "Cash",
		},
	},

	["pizza"] = {
		tier = 1,
		name = "Pizza",
		icon = nil,
		rarity = "Common",
		modelPath = { "Pizza" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(245, 222, 179),
			secondaryColor = Color3.fromRGB(210, 180, 140),
		},
		currencyData = {
			buyPrice = 0, -- 100,
			buyCurrencyId = "Cash",
		},
	},

	["burger"] = {
		tier = 2,
		name = "Burger",
		icon = nil,
		rarity = "Common",
		modelPath = { "Burger" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(245, 222, 179),
			secondaryColor = Color3.fromRGB(210, 180, 140),
		},
		currencyData = {
			buyPrice = 350,
			buyCurrencyId = "Cash",
		},
	},
}

local DataTypeDict: DataTypeDict = {
	name = DATA_TYPE_NAME,
	public_field_whitelist = PUBLIC_FIELD_WHITELIST,
	items = DATA,
}

do
	-- Assign Ids to items
	for itemId, itemInfo in DATA do
		itemInfo.id = itemId
	end
end

return DataTypeDict
