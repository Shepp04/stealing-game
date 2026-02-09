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
		winAmount: number,
		winCurrencyId: string,
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
			winAmount = 25,
			winCurrencyId = "Cash",
		},
	},

	["Ramen"] = {
		tier = 1,
		name = "Ramen",
		icon = nil,
		rarity = "Common",
		modelPath = { "Ramen" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(20, 198, 0),
			secondaryColor = Color3.fromRGB(80, 208, 16),
		},
		currencyData = {
			buyPrice = 60,
			buyCurrencyId = "Cash",
			winAmount = 35,
			winCurrencyId = "Cash",
		},
	},

	["sandwich"] = {
		tier = 2,
		name = "Sandwich",
		icon = nil,
		rarity = "Common",
		modelPath = { "Sandwich" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(239, 175, 15),
			secondaryColor = Color3.fromRGB(251, 196, 100),
		},
		currencyData = {
			buyPrice = 195,
			buyCurrencyId = "Cash",
			winAmount = 46,
			winCurrencyId = "Cash",
		},
	},

	["bloxiade"] = {
		tier = 3,
		name = "Bloxiade",
		icon = nil,
		rarity = "Common",
		modelPath = { "Bloxiade" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(159, 130, 255),
			secondaryColor = Color3.fromRGB(159, 130, 255),
		},
		currencyData = {
			buyPrice = 465,
			buyCurrencyId = "Cash",
			winAmount = 58,
			winCurrencyId = "Cash",
		},
	},

	["bloxy_cola"] = {
		tier = 4,
		name = "Bloxy Cola",
		icon = nil,
		rarity = "Common",
		modelPath = { "BloxyCola" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(153, 46, 0),
			secondaryColor = Color3.fromRGB(153, 46, 0),
		},
		currencyData = {
			buyPrice = 995,
			buyCurrencyId = "Cash",
			winAmount = 72,
			winCurrencyId = "Cash",
		},
	},

	["pizza"] = {
		tier = 5,
		name = "Pizza",
		icon = nil,
		rarity = "Common",
		modelPath = { "Pizza" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(245, 222, 179),
			secondaryColor = Color3.fromRGB(210, 180, 140),
		},
		currencyData = {
			buyPrice = 1980,
			buyCurrencyId = "Cash",
			winAmount = 108,
			winCurrencyId = "Cash",
		},
	},

	["cake_slice"] = {
		tier = 6,
		name = "Cake Slice",
		icon = nil,
		rarity = "Common",
		modelPath = { "CakeSlice" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(255, 228, 74),
			secondaryColor = Color3.fromRGB(255, 228, 74),
		},
		currencyData = {
			buyPrice = 4864,
			buyCurrencyId = "Cash",
			winAmount = 156,
			winCurrencyId = "Cash",
		},
	},

	["burger"] = {
		tier = 7,
		name = "Burger",
		icon = nil,
		rarity = "Common",
		modelPath = { "Burger" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(245, 222, 179),
			secondaryColor = Color3.fromRGB(210, 180, 140),
		},
		currencyData = {
			buyPrice = 9672,
			buyCurrencyId = "Cash",
			winAmount = 255,
			winCurrencyId = "Cash",
		},
	},

	["cake"] = {
		tier = 8,
		name = "Cake",
		icon = nil,
		rarity = "Common",
		modelPath = { "Cake" }, -- relative to STEALABLE_ITEM_MODELS_FOLDER in StealingService
		
		textData = {
			primaryColor = Color3.fromRGB(255, 255, 255),
			secondaryColor = Color3.fromRGB(242, 222, 195),
		},
		currencyData = {
			buyPrice = 19248,
			buyCurrencyId = "Cash",
			winAmount = 512,
			winCurrencyId = "Cash",
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
