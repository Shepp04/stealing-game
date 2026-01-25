--!strict
export type SoundInfo = {
    id: string,
    playbackSpeed: number?,
    rolloffMaxDistance: number?,
    volume: number?
}

export type SoundsConfig = {
    volume: number,
    sounds: { [string]: SoundInfo },
    Get: (self: SoundsConfig, name: string) -> SoundInfo?,
}

local Sounds: SoundsConfig = {
    volume = 0.50, -- [0.00, 1.00]
    sounds = {
        UIClick01 = {
			id = "rbxassetid://4499400560",
			playbackSpeed = 1.0,
			rolloffMaxDistance = 50,
			volume = 1.00, -- [0.00, 1.00]
        },
        UIHover01 = {
            id = "rbxassetid://91231770405780",
            playbackSpeed = 1.0,
            rolloffMaxDistance = 50,
            volume = 0.75, -- [0.00, 1.00]
        },

        -- Match Sounds
        JoinMatch = {
            id = "rbxassetid://773858658",
            playbackSpeed = 1.0,
            rolloffMaxDistance = 50,
            volume = 0.75, -- [0.00, 1.00]
        },

        LeaveMatch = {
            id = "rbxassetid://96334570383985",
            playbackSpeed = 2.0,
            rolloffMaxDistance = 50,
            volume = 0.75, -- [0.00, 1.00]
        },

        WinMatch = {
            id = "rbxassetid://6684542570",
            playbackSpeed = 1.0,
            rolloffMaxDistance = 50,
            volume = 1.00, -- [0.00, 1.00]
        },

        LoseMatch = {
            id = "rbxassetid://8713437441",
            playbackSpeed = 0.8,
            rolloffMaxDistance = 50,
            volume = 1.00, -- [0.00, 1.00]
        },

        WinnerMusic = {
            id = "rbxassetid://87640194214913",
            playbackSpeed = 1.0,
            rolloffMaxDistance = 50,
            volume = 0.50, -- [0.00, 1.00]
        },

        -- Gameplay
        WinRound = {
            id = "rbxassetid://8578195318",
            playbackSpeed = 1.0,
            rolloffMaxDistance = 50,
            volume = 0.75, -- [0.00, 1.00]
        },

        LoseRound = {
            id = "rbxassetid://1844442622",
            playbackSpeed = 0.8,
            rolloffMaxDistance = 50,
            volume = 0.75, -- [0.00, 1.00]
        },

        ShuffleBeat = {
            id = "rbxassetid://773858658",
            playbackSpeed = 1.2,
            rolloffMaxDistance = 50,
            volume = 0.50, -- [0.00, 1.00]
        },

        ItemRemoved = {
            id = "rbxassetid://77072623407707",
            playbackSpeed = 0.9,
            rolloffMaxDistance = 50,
            volume = 0.75, -- [0.00, 1.00]
        },
    },
    Get = function(self: SoundsConfig, name: string)
        if self.sounds[name] then
            return self.sounds[name]
        end
        warn(`[SoundConfig] No sound with name {name}`)
    end,
}

return Sounds