# InputUtil

Utility module for managing Roblox's Input Action System with contexts, actions, and bindings.

## Overview

InputUtil provides a programmatic interface for creating and managing InputContexts, InputActions, and InputBindings at runtime. It follows Roblox best practices by supporting multiple enabled contexts with priority-based input handling.

## Key Features

- Dynamic creation of InputContext, InputAction, and InputBinding instances
- Support for multiple simultaneously enabled contexts with priority management
- Automatic cleanup of all input objects and connections
- Type-safe API with comprehensive type definitions

## Usage Example

```lua
local InputUtil = require(ReplicatedStorage.Client.Utils.InputUtil)

-- Create a gameplay context
local playContext = InputUtil:GetInputContext("PlayContext")
InputUtil:SetContextPriority("PlayContext", 1)
InputUtil:SetContextEnabled("PlayContext", true)

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

## API Reference

### Context Management

#### `SetContextEnabled(contextName: string, enabled: boolean)`
Enables or disables an InputContext. Multiple contexts can be enabled simultaneously. Use Priority and Sink properties to control which context's actions take precedence.

#### `SetContextPriority(contextName: string, priority: number)`
Sets the priority of an InputContext. Higher priority contexts process input first (default is 0).

### Action Callbacks

#### `SetActionCallback(actionName: string, contextName: string, callback: (state: any) -> ())`
Connects a callback function to an InputAction's StateChanged event. Overwrites existing callbacks.

#### `RemoveActionCallback(actionName: string, contextName: string)`
Disconnects and removes the callback function from an InputAction.

### Getters

#### `GetInputContext(contextName: string) -> InputContextRecord`
Retrieves or creates an InputContext. Contexts are created disabled by default.

#### `GetInputAction(actionName: string, contextName: string, actionOpts?: InputActionOpts) -> InputActionRecord`
Retrieves or creates an InputAction within a specified context.

**Options:**
- `Type: Enum.InputActionType` - Action type (Bool, Direction1D, Direction2D, Direction3D, ViewportPosition)

#### `GetInputBinding(bindingName: string, actionName: string, contextName: string, bindingOpts?: InputBindingOpts) -> InputBinding`
Retrieves or creates an InputBinding for a specific action.

**Options:**
- `KeyCode: Enum.KeyCode` - Keyboard/gamepad key
- `UIButton: GuiButton` - Touch screen button

### Cleanup

#### `Cleanup()`
Destroys all InputContexts, InputActions, InputBindings, and disconnects all callbacks. Should be called when the input system is no longer needed.

## Best Practices

### Multiple Context Management
- Use higher `Priority` values for contexts that should process input first
- Set `context.instance.Sink = true` to prevent lower-priority contexts from receiving input
- Common pattern: PlayContext (priority 1) for gameplay, MenuContext (priority 2) for UI overlays

### Cross-Platform Support
Create separate bindings for each input type:
```lua
-- Keyboard
InputUtil:GetInputBinding("Keyboard", "Sprint", "PlayContext", {
    KeyCode = Enum.KeyCode.LeftShift
})

-- Gamepad
InputUtil:GetInputBinding("Gamepad", "Sprint", "PlayContext", {
    KeyCode = Enum.KeyCode.ButtonY
})

-- Touch
InputUtil:GetInputBinding("Touch", "Sprint", "PlayContext", {
    UIButton = sprintButton
})
```

### Context Lifecycle
```lua
-- Setup
InputUtil:SetContextPriority("PlayContext", 1)
InputUtil:SetContextEnabled("PlayContext", true)

-- Switch to menu
InputUtil:SetContextPriority("MenuContext", 2)
InputUtil:SetContextEnabled("MenuContext", true)
InputUtil:SetContextEnabled("PlayContext", false) -- Optional: disable gameplay

-- Return to gameplay
InputUtil:SetContextEnabled("MenuContext", false)
InputUtil:SetContextEnabled("PlayContext", true)
```

## Types

```lua
type InputBindingOpts = {
    KeyCode: Enum.KeyCode?,
    UIButton: GuiButton?,
}

type InputActionOpts = {
    Type: Enum.InputActionType?,
}

type InputActionRecord = {
    instance: InputAction,
    callbackConn: RBXScriptConnection?,
    bindings: { [string]: InputBinding },
}

type InputContextRecord = {
    instance: InputContext,
    actions: { [string]: InputActionRecord },
}
```
