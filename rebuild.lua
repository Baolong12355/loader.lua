-- 📦 TDX Macro Runner - FULL DEBUG + REBUILD TRACKING (With Rebuild Watcher)

local HttpService = game:GetService("HttpService") local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- 📚 Skip & Priority local priorityMap = { Medic = 1, ["Golden Mobster"] = 2, Mobster = 2, DJ = 3, Commander = 4 } local function GetPriority(name) return priorityMap[name] or 5 end

-- 🧠 Gộp tower từ macro local function BuildTowerRecords(macro, maxLine, skipList, beMode) local records, skipSet, latestName = {}, {}, {} for _, name in ipairs(skipList or {}) do skipSet[name] = true end

for i, entry in ipairs(macro) do
    if i > maxLine then break end
    local x = nil
    if entry.TowerVector then
        local vec = entry.TowerVector:split(", ")
        x = tonumber(vec[1])
    else
        x = tonumber(entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower)
    end

    local name = entry.TowerPlaced or entry.TowerName
    if x then
        if name then latestName[x] = name end
        name = name or latestName[x] or select(3, GetTowerByAxis(x)) or "UNKNOWN"
        if skipSet[name] and (not beMode or (beMode and i <= maxLine)) then continue end
        records[x] = records[x] or { X = x, Actions = {}, TowerName = name }
        table.insert(records[x].Actions, entry)
    end
end
return records

end

-- 🚀 Rebuild Watcher chính function startRebuildWatcher(macro, maxLine, skipList, beMode) local records = BuildTowerRecords(macro, maxLine, skipList, beMode) LogDebug("[WATCHER] Bắt đầu theo dõi tower cần rebuild...")

while true do
    local rebuildList = {}
    for x, rec in pairs(records) do
        local hash = GetTowerByAxis(x)
        if not hash then
            LogDebug("🔄 Thiếu tower @X=", x, "→", rec.TowerName)
            table.insert(rebuildList, rec)
        end
    end
    table.sort(rebuildList, function(a, b)
        return GetPriority(a.TowerName) < GetPriority(b.TowerName)
    end)

    for _, rec in ipairs(rebuildList) do
        for _, action in ipairs(rec.Actions) do
            if action.TowerPlaced and action.TowerVector and action.TowerPlaceCost then
                local vec = action.TowerVector:split(", ")
                local pos = Vector3.new(unpack(vec))
                local args = {
                    tonumber(action.TowerA1),
                    action.TowerPlaced,
                    pos,
                    tonumber(action.Rotation or 0)
                }
                WaitForCash(action.TowerPlaceCost)
                PlaceTowerRetry(args, pos.X, action.TowerPlaced)
            elseif action.TowerUpgraded and action.UpgradePath and action.UpgradeCost then
                UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
            elseif action.ChangeTarget and action.TargetType then
                ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
            elseif action.SellTower then
                SellTowerRetry(tonumber(action.SellTower))
            end
        end
    end
    task.wait(2)
end

end

-- 🚨 Tự động khởi động watcher nếu có "SuperFunction": "rebuild" local function DetectRebuildEntry(macro) for i, entry in ipairs(macro) do if entry.SuperFunction == "rebuild" then local skip = entry.Skip or {} local be = entry.Be or false LogDebug("[REBUILD] Gặp dòng rebuild tại #"..i.." → skip:", table.concat(skip, ", ")) startRebuildWatcher(macro, i, skip, be) break end end end

-- 📂 Load macro và chạy local config = getgenv().TDX_Config or {} local macroName = config["Macro Name"] or "event" local macroPath = "tdx/macros/" .. macroName .. ".json" globalPlaceMode = config["PlaceMode"] or "normal" if globalPlaceMode == "unsure" then globalPlaceMode = "rewrite" elseif globalPlaceMode == "normal" then globalPlaceMode = "ashed" end if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end local ok, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end) if not ok then error("Lỗi khi đọc macro") end

for _, entry in ipairs(macro) do if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then local vec = entry.TowerVector:split(", ") local pos = Vector3.new(unpack(vec)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0) } WaitForCash(entry.TowerPlaceCost) PlaceTowerRetry(args, pos.X, entry.TowerPlaced) elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) elseif entry.ChangeTarget and entry.TargetType then ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType) elseif entry.SellTower then SellTowerRetry(tonumber(entry.SellTower)) end end

DetectRebuildEntry(macro) LogDebug("✅ Đã chạy xong macro & khởi động rebuild nếu có.")

