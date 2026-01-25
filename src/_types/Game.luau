export type GameBroadcastState =
	"MatchBegin"
	| "MatchOver"
	| "LeaveMatch"
	| "RoundBegin"
	| "RoundEnd"
	| "Players"
	| "Camera"
	| "Turn"
	| "TurnCountdown"
	| "YourResult"
	| "TheirResult"
	| "AutoAction"
	| "Reveal"        -- chooser sees bomb/safe mask (no lunch)
	| "ShuffleBeat"   -- broadcast pairs so client can animate
	| "BoardUpdate"   -- a cup got removed / board shrank

export type GameAction =
	"SetLunch"      -- players choose where they hid lunch (setup)
	| "SelectCup"   -- chooser picks a cup (gameplay)
	| "ShuffleInput" -- OPTIONAL later for manual swap UX (keep open)

export type TurnType = "Setup" | "Shuffle" | "Choose"
export type ItemContent = "Win" | "Lose" | "Empty"

export type GameContext = {
 	tableInstance: Instance,
	getPlayers: () -> { Player },

	send: (player: Player, kind: GameBroadcastState, { any }?) -> (),
	broadcast: (kind: GameBroadcastState, ...any) -> (),
}

return {}