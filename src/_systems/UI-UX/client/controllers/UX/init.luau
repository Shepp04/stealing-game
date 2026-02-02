--!strict
--[[
	UX Bootstrapper
	Requires, stores, and initialises all ModuleScripts under this script.
]]

--// Types
export type UX = {
	_inited: boolean,
	_started: boolean,
	_modules: { [string]: { name: string, module: any } },
	
	Init: (self: UX) -> (),
	Start: (self: UX) -> (),
	Destroy: (self: UX) -> (),
}

local UX = {} :: UX
UX._modules = {}

-- ========== Life Cycle ========== --
function UX:Init()
	if self._inited then return end
	self._inited = true
	
	-- Require all child modules without initialising them
	for _, moduleScript in script:GetChildren() do
		if moduleScript:IsA("ModuleScript") then
			local ok, result = pcall(require, moduleScript)
			if ok then
				self._modules[moduleScript.Name] = { name = moduleScript.Name, module = result }
				-- print(`[UI-UX] Loaded '{moduleScript.Name}' module`)
			else
				warn(`[UI-UX] Failed to load '{moduleScript.Name}': {result}`)
			end
		end
	end
end

-- Start all required modules
function UX:Start()
	if not self._inited or self._started then return end
	self._started = true
	
	for _, moduleWrapper in self._modules do
		if moduleWrapper.module.Init then
			local ok, err = pcall(function() moduleWrapper.module:Init() end)
			if not ok then
				warn(`[UX] Failed to start module {moduleWrapper.name}: {err}`)
			else
				-- print(`[UX] Started module {moduleWrapper.name}`)
			end
		end
	end
end

function UX:Destroy()
	if not self._inited then return end
	self._inited = false
	self._started = false
	
	for _, moduleWrapper in self._modules do
		if moduleWrapper.module.Destroy then
			moduleWrapper.module:Destroy()
		end
	end
end

return UX