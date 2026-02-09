--!strict
-- ProductShop (Component)

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- // Utils
local GuiRefs = require(script.Parent.Parent.Utils.GuiRefs)
local CurrencyUtils = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Currency"))

-- // Custom types

-- // Type aliases for deps inferred from real modules
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

export type ProductShopAPI = {
	_inited: boolean,
	_conns: { RBXScriptConnection },

	Init: (self: ProductShopAPI) -> (),
	Destroy: (self: ProductShopAPI) -> (),
}

export type Opts = {
	root: ScreenGui,
	container: Frame,
}

local ProductShop = {}
ProductShop.__index = ProductShop

-- // Internal state
local _deps: Deps? = nil

-- // Constants
local PRODUCT_HOVER_SOUND_ID = 8578195318

-- ========== Constructor ========== --

function ProductShop.new(deps: Deps, opts: Opts): ProductShopAPI
	if not _deps then
		_deps = deps
	end

	local self = setmetatable({ _inited = false, _conns = {} } :: any, ProductShop) :: ProductShopAPI
	self.opts = opts

	-- // Gui paths
	self._root = self.opts.root
	self._container = self.opts.container

	self._currencyItemFrame = GuiRefs.Get(self._container, { "Categories", "Currency", "Items" })

	self._sampleCurrencyProductButton = GuiRefs.Get(self._currencyItemFrame, { "SampleCurrencyProductButton" })
	self._sampleCurrencyProductButton.Parent = nil

	return self
end

-- ========== Public API ========== --

function ProductShop:PublicMethod()
	-- Example
end

-- ========== Internal ========== --

function ProductShop:_setupProducts(catalog: { devProducts: { [string]: any }, gamepasses: { [string]: any } })
	local devProducts = catalog.devProducts

	-- Set up currency products first
	local currencyProductNames: { string } = { }
	for productName, productInfo in devProducts do
		if productInfo.category == "Currency" then
			-- Check that this product is for sale
			if productInfo.priceInRobux == nil then
				continue
			end
			table.insert(currencyProductNames, productName)
		end
	end

	-- Sort by amount, then by currency
	table.sort(currencyProductNames, function(a: string, b: string)
		local aInfo = devProducts[a]
		local bInfo = devProducts[b]
		
		local aCurrencyId = aInfo.params.currencyId or ""
		local bCurrencyId = bInfo.params.currencyId or ""
		if aCurrencyId ~= bCurrencyId then
			return aCurrencyId < bCurrencyId
		end

		local aValue = aInfo.params and aInfo.params.value or 0
		local bValue = bInfo.params and bInfo.params.value or 0
		return aValue < bValue
	end)

	-- Create a frame for each product
	for i, productName in currencyProductNames do
		local productInfo = devProducts[productName]
		local currencyId = productInfo.params and productInfo.params.currencyId
		local value = productInfo.params and productInfo.params.value
		if not currencyId or not value then
			warn("[ProductShop] Currency product", productName, "does not have currencyId and value params")
			continue
		end

		local button = self._sampleCurrencyProductButton:Clone()
		local text = "$" .. CurrencyUtils.GetCurrencyText(currencyId, value, false)

		button.Name = productName
		button.Button.ProductInfo.DisplayName.Text = text --productInfo.DisplayName
		button.Button.Price.Text = productInfo.priceInRobux .. "R$"
		button.Button.ProductInfo.Icon.Image = "rbxassetid://" .. (productInfo.iconImageAssetId or "")
		button.Parent = self._currencyItemFrame

		local background = button.Button:FindFirstChild("Background") :: Frame?
		if background then
			background.BackgroundTransparency = 1 - ((i - 1) / (#currencyProductNames - 1)) * 0.9
		end

		button.Select.MouseButton1Click:Connect(function()
			_deps.Monetisation.PromptSale(productName)
		end)

		button.Select.MouseEnter:Connect(function()
			_deps.SharedPackages.Sounds:PlaySound(PRODUCT_HOVER_SOUND_ID)
		end)
	end
end

-- ========== Life Cycle ========== --

function ProductShop:Init()
	if self._inited then return end
	self._inited = true

	-- // Setup products
	local catalog = _deps.Monetisation.GetCatalog()
	if not catalog then
		warn("[ProductShop] Failed to get catalog")
		return
	end
	print(catalog)
	self:_setupProducts(catalog)
end

function ProductShop:Destroy()
	-- Cleanup
	for _, c in pairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._inited = false
end

return ProductShop :: ProductShopAPI
