--!strict
-- MenuStand (Server Class): a class for stands that open menus when players interact with them

-- // Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- // Type aliases for deps
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

export type Opts = {
	-- args used when constructing the class
	model: Model,
	menuName: string,
	useProximityPrompt: boolean?,
	proximityPromptObjectText: string?,
	proximityPromptActionText: string?,
}

export type MenuStandAPI = {
	_opts: Opts,
	_conns: { RBXScriptConnection },

	Init: (self: MenuStandAPI) -> (),
	Destroy: (self: MenuStandAPI) -> (),
}

local MenuStand = {}
MenuStand.__index = MenuStand

-- // Internal state
local IS_SERVER = RunService:IsServer()
local _deps: Deps?

-- ========== Constructor ========== --

function MenuStand.new(deps: Deps, opts: Opts?): MenuStandAPI
	_deps = deps

	local self = setmetatable({} :: any, MenuStand) :: MenuStandAPI
	self._opts = opts or {}
	self._conns = {}

	self._menuName = self._opts.menuName
	if not self._menuName then
		error("MenuStand requires a menuName in opts")
	end

	self._useProximityPrompt = self._opts.useProximityPrompt or false
	self._proximityPromptObjectText = self._opts.proximityPromptObjectText or "Menu"
	self._proximityPromptActionText = self._opts.proximityPromptActionText or "Open"

	-- Validate the model
	self._model = self._opts.model
	if not self._model then
		error("MenuStand requires a model in opts")
	end

	self._trigger = self._model:FindFirstChild("Trigger") :: BasePart
	if not self._trigger or not self._trigger:IsA("BasePart") then
		error("MenuStand model requires a 'Trigger' BasePart child")
	end

	-- Setup proximity prompt if needed
	if self._useProximityPrompt then
		local prompt = self._trigger:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = self._proximityPromptObjectText
			prompt.ActionText = self._proximityPromptActionText
			prompt.HoldDuration = 0.2
			prompt.RequiresLineOfSight = false
			prompt.Parent = self._trigger
		end

		self._proximityPrompt = prompt
	end

	-- Client/server-specific wiring
	if RunService:IsClient() then
		-- client-only setup
		local Controllers = require(Players.LocalPlayer.PlayerScripts:WaitForChild("Controllers"))
		local MenuController = Controllers.MenuController
		if not MenuController then
			error("MenuStand client requires MenuController to be available")
		end
		self._onOpen = function(player: Player)
			MenuController:OpenMenu(self._menuName, true, true, nil)
		end
	else
		-- server-only setup
		local remote = _deps.SharedPackages.Remotes:GetRemote("RemoteEvent", "OpenMenu") :: RemoteEvent
		self._onOpen = function(player: Player)
			remote:FireClient(player, self._menuName)
		end
	end

	return self
end

-- ========== Public API ========== --

function MenuStand:OpenMenuForPlayer(player: Player)
	if self._onOpen then
		self._onOpen(player)
	end
end

-- ========== Life Cycle ========== --

function MenuStand:Init()
	if self._proximityPrompt then
		table.insert(self._conns, self._proximityPrompt.Triggered:Connect(function(player: Player)
			self:OpenMenuForPlayer(player)
		end))
	else
		-- Alternative trigger setup if not using ProximityPrompt
		local debounce: { [Player]: boolean } = {}

		table.insert(self._conns, self._trigger.Touched:Connect(function(hit: BasePart)
			local char = hit.Parent
			local human = char and char:FindFirstChildOfClass("Humanoid")
			if human and human.Health > 0 then
				local player = game.Players:GetPlayerFromCharacter(char)
				if player and not debounce[player] then
					debounce[player] = true
					task.delay(1, function()
						debounce[player] = false
					end)
					self:OpenMenuForPlayer(player)
				end
			end
		end))
	end
end

function MenuStand:Destroy()
	for _, c in self._conns do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._conns)
	_deps = nil
end

return MenuStand :: MenuStandAPI
