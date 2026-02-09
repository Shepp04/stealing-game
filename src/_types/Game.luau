export type GameBroadcastState =
	"MatchBegin"
	| "MatchOver"
	| "LeaveMatch"
	| "RoundBegin"
	| "RoundEnd"
	| "Players"
	| "Camera"
	| "ClearMessages"
	| "Message"       -- generic heading/subheading (payload: heading?: string, subheading?: string)
	| "Turn"
	| "TurnCountdown"
	| "YourResult"
	| "TheirResult"
	| "AutoAction"
	| "Reveal"        -- chooser sees bomb/safe mask (no lunch)
	| "ItemAttacked"  -- players see a cursor over the attacked item
	| "ShuffleBeat"   -- broadcast pairs so client can animate
	| "BoardUpdate"   -- a cup got removed / board shrank

export type GameAction =
	"SetWinningItem"      -- players choose where they hid lunch (setup)
	| "SelectItem"   -- chooser picks a cup (gameplay)
	| "StartShuffle"
	| "StopShuffle"

export type TurnType = "Setup" | "Shuffle" | "Choose"
export type ItemContent = "Win" | "Lose" | "Empty"

export type GameContext = {
 	tableInstance: Instance,
	getPlayers: () -> { Player },

	send: (player: Player, kind: GameBroadcastState, { any }?) -> (),
	broadcast: (kind: GameBroadcastState, ...any) -> (),
}

return {}