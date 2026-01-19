--!strict
-- // Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // Types
local Types = require(ReplicatedStorage.Shared.Types.Monetisation)
type Handler = Types.Handler
type GamepassPrivate = Types.GamepassPrivate

-- ========== Handlers ========== --
local Handlers: { [string]: Handler } = {
    MultiplierGamepass = function(player: Player, productId: number, params: { any }?, deps: { any }?): boolean
        -- NOTE: Gamepasses are not fulfilled via receipts; handler can be used for side-effects elsewhere.
        return true
    end
}

-- ========== Definitions ========== --
local defs: { gamepasses: { GamepassPrivate } } = {
    gamepasses = {

    }
}

return defs
