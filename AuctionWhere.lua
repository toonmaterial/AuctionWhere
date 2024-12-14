local DB = "AuctionWhereDB"

local function computeTable(...)
	local t, ks

	if type(...) == "table" then
		t, ks = ..., { select(2, ...) }
	else
		t, ks = _G, { ... }
	end

	for _, k in ipairs(ks) do
		t[k] = t[k] or {}
		t = t[k]
	end

	return t
end

local ITEM = "ITEM"
local CHARACTER = "CHARACTER"
local CONNECTED_REALM_TO_CHARACTER = "CONNECTED_REALM_TO_CHARACTER"

local function computeRealm()
	local realms = GetAutoCompleteRealms()
	table.sort(realms)
	return realms[1] or GetNormalizedRealmName()
end

local function processBrowseResult(result)
	computeTable(DB, ITEM, result.itemKey.itemID)[computeRealm()] = { price = result.minPrice, time = time() }
end

local function processCommoditySearchResult(result)
	computeTable(DB, ITEM, result.itemID)[computeRealm()] = { price = result.unitPrice, time = time() }
end

local function processItemSearchResult(result)
	computeTable(DB, ITEM, result.itemKey.itemID)[computeRealm()] = { price = result.buyoutAmount, time = time() }
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		f:UnregisterEvent("PLAYER_ENTERING_WORLD")

		local realm = GetNormalizedRealmName()
		local player = UnitName("player") .. "-" .. realm
		local _, class = UnitClass("player")

		computeTable(DB, CHARACTER)[player] = { realm = realm, class = class }
		computeTable(DB, CONNECTED_REALM_TO_CHARACTER, realm)[player] = true
		for _, connectedRealm in ipairs(GetAutoCompleteRealms()) do
			computeTable(DB, CONNECTED_REALM_TO_CHARACTER, connectedRealm)[player] = true
		end

		local now = time()
		local sevenDays = 3 * 24 * 60 * 60

		local itemDB = computeTable(DB, ITEM)
		for itemID, db in pairs(itemDB) do
			for itemRealm, data in pairs(db) do
				if now - data.time > sevenDays then
					db[itemRealm] = nil
				end
			end

			if not next(db) then
				itemDB[itemID] = nil
			end
		end
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		for _, result in ipairs(C_AuctionHouse.GetBrowseResults()) do
			processBrowseResult(result)
		end
	end

	if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		for _, result in ipairs(...) do
			processBrowseResult(result)
		end
	end

	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		local result = C_AuctionHouse.GetCommoditySearchResultInfo(..., 1)
		if result then
			processCommoditySearchResult(result)
		end
	end

	if event == "ITEM_SEARCH_RESULTS_UPDATED" then
		local result = C_AuctionHouse.GetItemSearchResultInfo(..., 1)
		if result then
			processItemSearchResult(result)
		end
	end
end)

local function elapsed(t)
	local dt = time() - t
	if dt < 60 then return dt .. " seconds ago" end
	dt = floor(dt / 60)
	if dt < 60 then return dt .. " minutes ago" end
	dt = floor(dt / 60)
	if dt < 24 then return dt .. " hours ago" end
	dt = floor(dt / 24)
	return dt .. " days ago"
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
	local realms = GetPairsArray(computeTable(DB, ITEM, data.id))
	table.sort(realms, function(a, b) return a.value.price < b.value.price end)

	local function printPlayer(player)
		local character = computeTable(DB, CHARACTER, player)
		tooltip:AddLine(RAID_CLASS_COLORS[character.class]:WrapTextInColorCode(player))
	end

	local function printRealm(realm)
		tooltip:AddDoubleLine(
			realm.key .. " " .. WHITE_FONT_COLOR:WrapTextInColorCode(elapsed(realm.value.time)),
			WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(realm.value.price, true)))

		local players = GetKeysArray(computeTable(DB, CONNECTED_REALM_TO_CHARACTER, realm.key))
		table.sort(players)

		if IsShiftKeyDown() or #players <= 3 then
			for _, player in ipairs(players) do
				printPlayer(player)
			end
		else
			printPlayer(players[1])
			tooltip:AddLine("...")
			printPlayer(players[#players])
		end
	end

	if IsShiftKeyDown() or #realms <= 3 then
		for _, realm in ipairs(realms) do
			tooltip:AddLine(" ")
			printRealm(realm)
		end
	else
		tooltip:AddLine(" ")
		printRealm(realms[1])
		tooltip:AddLine("...")
		printRealm(realms[#realms])
	end
end)
