--!strict
-- Server/Packages/FriendReferrals.lua
-- Usage: FriendReferrals:Init({ Currency = CurrencyService })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

-- // Datastores
local INVITEE_DS = DataStoreService:GetDataStore("Referral_Invitee_v1")
local REFERRER_DS = DataStoreService:GetDataStore("Referral_Referrer_v1")

-- // Packages
local Packages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"))

-- // Remotes
local Remotes = Packages.Remotes
local ReferralRewardReceived = Remotes:GetRemote("RemoteEvent", "ReferralRewardReceived") :: RemoteEvent

local Referrals = {}

-- Injected dependencies
type Deps = { Currency: any, DataInterface: any, Tunables: any, }
local deps: Deps?

-- // Assets
local Assets = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Assets")
local ReferralRewardGui = Assets:WaitForChild("UI"):WaitForChild("ReferralReward")

-- // Constants
local REFERRAL_CAP = 3                      -- max paid referrals per inviter
local INVITER_REWARD_CURRENCY_ID = "Cash"
local INVITER_REWARD_AMOUNT = 250

local INVITEE_REWARD_CURRENCY_ID = "Cash"
local INVITEE_REWARD_AMOUNT = 0            -- optional; set to 0 to disable

-- Helpers
local function invKey(uid: number): string return ("inv:%d"):format(uid) end
local function refKey(uid: number): string return ("ref:%d"):format(uid) end

local function giveCurrency(p: Player?, id: string, amt: number)
	if amt <= 0 then return true end
	if not p then return false end
	if not (deps or not deps.DataInterface) then
		warn("[SERVER | FriendReferrals] DataInterface dependency missing")
		return false
	end
	if not deps or not deps.Currency then
		warn("[SERVER | FriendReferrals] Currency dependency missing")
		return false
	end
	
	-- Wait for profile
	local profile = deps.DataInterface:GetPlayerProfile(p, true)
	if not (profile) then return false end
	
	local ok = deps.Currency:GiveCurrency(p, id, amt, false, true)
	if (ok) then
		ReferralRewardReceived:FireClient(p, {
			CurrencyID = INVITER_REWARD_CURRENCY_ID, Amount = INVITER_REWARD_AMOUNT
		})
		return true
	end
	return false
end

-- Pay any pending invitees for this referrer (up to CAP). Only runs when referrer is online.
local function processReferrerPayouts(referrer: Player)
	local uid = referrer.UserId
	local toPayList: {string} = {}
	local errMsg: string? = nil

	-- Choose which invitees to mark paid
	local ok, newData = pcall(function()
		return REFERRER_DS:UpdateAsync(refKey(uid), function(old)
			local data = old or { invitees = {}, paid = {} }
			local paidCount = 0
			for _, v in pairs(data.paid) do if v then paidCount += 1 end end
			local remaining = REFERRAL_CAP - paidCount
			if remaining <= 0 then return data end

			-- Pick unpaid invitees up to remaining
			local picked = 0
			for inviteeId, _ in pairs(data.invitees) do
				if not data.paid[inviteeId] then
					data.paid[inviteeId] = true
					table.insert(toPayList, inviteeId)
					picked += 1
					if picked >= remaining then break end
				end
			end
			return data
		end)
	end)
	if not ok then
		warn(("[FriendReferrals] REF UpdateAsync failed for %d: %s"):format(uid, tostring(newData)))
		return
	end

	-- Grant once per invitee
	local total = INVITER_REWARD_AMOUNT * #toPayList
	if #toPayList > 0 then
		print("Granting Referral Reward to", referrer)
		local granted = giveCurrency(referrer, INVITER_REWARD_CURRENCY_ID, total)
		if not granted then
			-- Rollback paid flags so we’ll try again later
			local _ok = pcall(function()
				REFERRER_DS:UpdateAsync(refKey(uid), function(old)
					local data = old or { invitees = {}, paid = {} }
					for _, inviteeId in ipairs(toPayList) do
						data.paid[inviteeId] = nil -- mark unpaid again
					end
					return data
				end)
			end)
			if not _ok then
				warn("[FriendReferrals] Failed to rollback paid flags after grant failure")
			end
		end
	end
end

-- Grant invitee reward exactly once
local function maybeGrantInviteeReward(invitee: Player, referrerId: number)
	local inviteeId = invitee.UserId

	local ok, _ = pcall(function()
		return INVITEE_DS:UpdateAsync(invKey(inviteeId), function(old)
			local data = old or { referredBy = 0, inviteeRewardGranted = false }
			-- First referrer wins; ignore changes later
			if data.referredBy == 0 then
				data.referredBy = referrerId
			end
			if data.inviteeRewardGranted then
				return data
			end
			data.inviteeRewardGranted = true
			return data
		end)
	end)
	if not ok then
		warn(("[FriendReferrals] INV UpdateAsync failed for invitee %d"):format(inviteeId))
		return
	end

	-- Actually pay invitee (optional)
	if INVITEE_REWARD_AMOUNT > 0 then
		giveCurrency(invitee, INVITEE_REWARD_CURRENCY_ID, INVITEE_REWARD_AMOUNT)
	end
end

-- Record this invitee under the referrer and try to pay if referrer online
local function recordReferral(referrerId: number, inviteeId: number)
	local ok, _ = pcall(function()
		return REFERRER_DS:UpdateAsync(refKey(referrerId), function(old)
			local data = old or { invitees = {}, paid = {} }
			-- only record first time for this invitee
			local key = tostring(inviteeId)
			data.invitees[key] = data.invitees[key] or true
			-- do not mark paid here (we do that when the referrer is online)
			return data
		end)
	end)
	if not ok then
		warn(("[FriendReferrals] REF UpdateAsync failed while recording referral %d -> %d"):format(referrerId, inviteeId))
		return
	end

	-- If referrer is online now, process pending payouts immediately
	local refPlr = Players:GetPlayerByUserId(referrerId)
	if refPlr then
		processReferrerPayouts(refPlr)
	end
end

-- Per-join entry point
local function onPlayerAdded(p: Player)
	-- Give them a referral reward Gui
	local PlayerGui = p:WaitForChild("PlayerGui")
	local gui = ReferralRewardGui:Clone()
	gui.Parent = PlayerGui
	
	local joinData = p:GetJoinData() or {} :: {ReferredByPlayerId: string}
	local referrerId = tonumber(joinData.ReferredByPlayerId) or 0
	if referrerId == 0 or referrerId == p.UserId then
		return -- no referrer or self‑referral (ignore)
	end

	-- Ensure we only grant the invitee reward once and lock in first referrer
	maybeGrantInviteeReward(p, referrerId)

	-- Record referral under referrer and (if online) try to pay
	recordReferral(referrerId, p.UserId)
end

-- When a referrer joins, try to pay any pending invitees up to CAP
local function onReferrerAdded(p: Player)
	processReferrerPayouts(p)
end

function Referrals:Init(injected: Deps)
	deps = injected

    if deps.Tunables then
        REFERRAL_CAP = deps.Tunables.referralCap or REFERRAL_CAP
        INVITER_REWARD_CURRENCY_ID = deps.Tunables.inviterRewardCurrencyId or INVITER_REWARD_CURRENCY_ID
        INVITER_REWARD_AMOUNT = deps.Tunables.inviterRewardAmount or INVITER_REWARD_AMOUNT

        INVITEE_REWARD_CURRENCY_ID = deps.Tunables.inviteeCurrencyId or INVITEE_REWARD_CURRENCY_ID
        INVITEE_REWARD_AMOUNT = deps.Tunables.inviteeRewardAmount or INVITEE_REWARD_AMOUNT
    end

	-- Pay pending for referrers on join
	Players.PlayerAdded:Connect(function(plr)
		onPlayerAdded(plr)     -- handles invitee path
		onReferrerAdded(plr)   -- handles referrer path
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		onPlayerAdded(plr)
		onReferrerAdded(plr)
	end
end

return Referrals