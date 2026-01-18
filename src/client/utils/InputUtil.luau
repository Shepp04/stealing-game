--!strict
--[[
	InputUtil
	Utility module for managing Roblox's Input Action System with contexts, actions, and bindings.
	
	This module provides a programmatic interface for creating and managing InputContexts, InputActions,
	and InputBindings at runtime. It follows Roblox best practices by supporting multiple enabled contexts
	with priority-based input handling.
	
	Key Features:
	- Dynamic creation of InputContext, InputAction, and InputBinding instances
	- Support for multiple simultaneously enabled contexts with priority management
	- Automatic cleanup of all input objects and connections
	- Type-safe API with comprehensive type definitions
	
	Usage Example:
	```lua
	local InputUtil = require(...)
	
	-- Create a gameplay context
	local playContext = InputUtil:GetInputContext("PlayContext")
	playContext.instance.Priority = 1
	playContext.instance.Enabled = true
	
	-- Create a sprint action
	local sprintAction = InputUtil:GetInputAction("Sprint", "PlayContext", {
		Type = Enum.InputActionType.Bool
	})
	
	-- Add keyboard binding
	InputUtil:GetInputBinding("Keyboard", "Sprint", "PlayContext", {
		KeyCode = Enum.KeyCode.LeftShift
	})
	
	-- Set callback
	InputUtil:SetActionCallback("Sprint", "PlayContext", function(state)
		print("Sprint state:", state)
	end)
	```
]]

-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
export type InputBindingOpts = {
    KeyCode: Enum.KeyCode?,
    UIButton: GuiButton?,
}

export type InputActionOpts = {
    Type: Enum.InputActionType?,
}

export type InputActionRecord = {
    instance: InputAction,
    callbackConn: RBXScriptConnection?,
    bindings: { [string]: InputBinding },
}

export type InputContextRecord = {
    instance: InputContext,
    actions: { [string]: InputActionRecord },
}

export type InputUtilAPI = {
    _inputContexts: { [string]: InputContextRecord },

    SetContextEnabled: (self: InputUtilAPI, contextName: string, enabled: boolean) -> (),
    SetContextPriority: (self: InputUtilAPI, contextName: string, priority: number) -> (),
    SetActionCallback: (self: InputUtilAPI, actionName: string, contextName: string, callback: (state: string) -> ()) -> (),
    RemoveActionCallback: (self: InputUtilAPI, actionName: string, contextName: string) -> (),
    Cleanup: (self: InputUtilAPI) -> (),

    GetInputContext: (self: InputUtilAPI, contextName: string) -> InputContextRecord,
    GetInputAction: (self: InputUtilAPI, actionName: string, contextName: string, actionOpts: InputActionOpts?) -> InputActionRecord,
    GetInputBinding: (self: InputUtilAPI, bindingName: string, actionName: string, contextName: string, bindingOpts: InputBindingOpts?) -> InputBinding,
}

-- // Util
local InputUtil = {
    _inputContexts = {},
} :: InputUtilAPI

-- // Constants
local INPUT_OBJECT_DESTINATION: Folder
do
    local inputFolder = ReplicatedStorage:FindFirstChild("InputObjects")
    if not inputFolder then
        inputFolder = Instance.new("Folder")
        inputFolder.Name = "InputObjects"
        inputFolder.Parent = ReplicatedStorage
    end
    INPUT_OBJECT_DESTINATION = inputFolder
end

-- ========== Public API ========== --

--[[
	SetContextEnabled
	Enables or disables an InputContext. Multiple contexts can be enabled simultaneously.
	Use Priority property to control which context's actions take precedence when multiple
	contexts are enabled. Use Sink property to prevent lower-priority contexts from receiving input.
	
	@param contextName: string, The name of the context to enable/disable
	@param enabled: boolean, Whether the context should be enabled
]]
function InputUtil:SetContextEnabled(contextName: string, enabled: boolean)
    local inputContextRecord = self:GetInputContext(contextName)
    inputContextRecord.instance.Enabled = enabled
end

--[[
	SetContextPriority
	Sets the priority of an InputContext. Higher priority contexts process input first.
	By default, all contexts have priority 0. When multiple contexts are enabled,
	actions in higher priority contexts will be processed before lower priority ones.
	
	@param contextName: string, The name of the context
	@param priority: number, The priority value (higher = processed first)
]]
function InputUtil:SetContextPriority(contextName: string, priority: number)
    local inputContextRecord = self:GetInputContext(contextName)
    inputContextRecord.instance.Priority = priority
end

--[[
	SetActionCallback
	Connects a callback function to an InputAction's StateChanged event.
	The callback will be invoked whenever the action's state changes (e.g., pressed/released for Bool type).
	If a callback already exists for this action, it will be disconnected and replaced.
	
	@param actionName: string, The name of the action
	@param contextName: string, The name of the context containing the action
	@param callback: (state: string) -> (), Function to call when action state changes
]]
function InputUtil:SetActionCallback(actionName: string, contextName: string, callback: (state: string) -> ())
    local inputActionRecord = self:GetInputAction(actionName, contextName)

    -- Check if already connected
    if inputActionRecord.callbackConn then
        warn("[InputUtil] SetActionCallback - Action '" .. actionName .. "' in context '" .. contextName .. "' already has a callback set. Overwriting.")
        inputActionRecord.callbackConn:Disconnect()
        inputActionRecord.callbackConn = nil
    end

    inputActionRecord.callbackConn = inputActionRecord.instance.StateChanged:Connect(function(...)
        callback(...)
    end)
end

--[[
	RemoveActionCallback
	Disconnects and removes the callback function from an InputAction.
	Warns if the action has no callback to remove.
	
	@param actionName: string, The name of the action
	@param contextName: string, The name of the context containing the action
]]
function InputUtil:RemoveActionCallback(actionName: string, contextName: string)
    local inputActionRecord = self:GetInputAction(actionName, contextName)

    if inputActionRecord.callbackConn then
        inputActionRecord.callbackConn:Disconnect()
        inputActionRecord.callbackConn = nil
    else
        warn("[InputUtil] RemoveActionCallback - Action '" .. actionName .. "' in context '" .. contextName .. "' has no callback to remove.")
    end
end

--[[
	Cleanup
	Destroys all InputContexts, InputActions, InputBindings, and disconnects all callbacks.
	Should be called when the input system is no longer needed (e.g., on player disconnect).
]]
function InputUtil:Cleanup()
    for _, contextRecord in self._inputContexts do

        for _, actionRecord in contextRecord.actions do
            if actionRecord.callbackConn then
                actionRecord.callbackConn:Disconnect()
                actionRecord.callbackConn = nil
            end
            for _, binding in actionRecord.bindings do
                binding:Destroy()
            end
            actionRecord.instance:Destroy()
        end

        contextRecord.instance:Destroy()
    end
    self._inputContexts = {}
end

-- ========== Public Getters ========== --

--[[
	GetInputContext
	Retrieves or creates an InputContext with the given name.
	Contexts are created disabled by default - use SetContextEnabled to enable them.
	Best practice is to set Priority before enabling to manage multiple active contexts.
	
	@param contextName: string, The name of the context to get or create
	
	@return contextRecord: InputContextRecord, The context record containing the instance and actions
]]
function InputUtil:GetInputContext(contextName: string): InputContextRecord
    if self._inputContexts[contextName] then
        return self._inputContexts[contextName]
    end

    -- Create new InputContext (disabled by default)
    local inputContext = Instance.new("InputContext")
    inputContext.Name = contextName
    inputContext.Enabled = false
    inputContext.Parent = INPUT_OBJECT_DESTINATION
    self._inputContexts[contextName] = {
        instance = inputContext,
        actions = {},
    }

    return self._inputContexts[contextName]
end

--[[
	GetInputAction
	Retrieves or creates an InputAction within a specified context.
	Actions define gameplay mechanics (e.g., "Jump", "Sprint") and are mapped to hardware inputs via bindings.
	
	@param actionName: string, The name of the action
	@param contextName: string, The name of the context to contain this action
	@param actionOpts: InputActionOpts?, Optional configuration (Type: Enum.InputActionType)
	
	@return actionRecord: InputActionRecord, The action record containing the instance and bindings
]]
function InputUtil:GetInputAction(actionName: string, contextName: string, actionOpts: InputActionOpts?): InputActionRecord
    local inputContextRecord = self:GetInputContext(contextName)
    if inputContextRecord.actions[actionName] then
        return inputContextRecord.actions[actionName]
    end

    local inputAction = Instance.new("InputAction")
    inputAction.Name = actionName

    -- Set properties from opts
    actionOpts = actionOpts or {}
    if actionOpts.Type then
        inputAction.Type = actionOpts.Type
    end

    inputAction.Parent = inputContextRecord.instance
    inputContextRecord.actions[actionName] = {
        instance = inputAction,
        bindings = {},
    }
    return inputContextRecord.actions[actionName]
end

--[[
	GetInputBinding
	Retrieves or creates an InputBinding for a specific action.
	Bindings map hardware inputs (keyboard, gamepad, touch) to actions.
	For cross-platform support, create separate bindings for each input type.
	
	@param bindingName: string, The name of the binding (e.g., "KeyboardBinding", "GamepadBinding")
	@param actionName: string, The name of the action this binding triggers
	@param contextName: string, The name of the context containing the action
	@param bindingOpts: InputBindingOpts?, Optional configuration (KeyCode or UIButton)
	
	@return binding: InputBinding, The created or existing InputBinding instance
]]
function InputUtil:GetInputBinding(bindingName: string, actionName: string, contextName: string, bindingOpts: InputBindingOpts?): InputBinding
    local inputActionRecord = self:GetInputAction(actionName, contextName)
    if inputActionRecord.bindings[bindingName] then
        return inputActionRecord.bindings[bindingName]
    end

    local inputBinding = Instance.new("InputBinding")
    inputBinding.Name = bindingName

    -- Set properties from opts
    bindingOpts = bindingOpts or {}
    if bindingOpts.KeyCode then
        inputBinding.KeyCode = bindingOpts.KeyCode
    end
    if bindingOpts.UIButton then
        inputBinding.UIButton = bindingOpts.UIButton
    end

    inputBinding.Parent = inputActionRecord.instance
    inputActionRecord.bindings[bindingName] = inputBinding
    return inputActionRecord.bindings[bindingName]
end

return InputUtil :: InputUtilAPI
