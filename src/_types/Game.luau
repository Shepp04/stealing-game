export type GameBroadcastState = "RoundBegin" | "RoundEnd" | "Turn" | "YourResult" | "TheirResult" | "AutoAction"
export type GameAction = "StopShuffle" | "SelectItem"
export type TurnType = "Hider" | "Shuffler" | "Chooser"
export type ItemType = "Good" | "Bad"
return {}