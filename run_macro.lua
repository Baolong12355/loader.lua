-- 📦 TDX Macro Runner - Rebuild Watcher (Integrated)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ⚙️ Hàm kiểm tra thiếu tower
local function IsTowerMissing(x)
    local _, tower = GetTowerByAxis(x)
    return not tower
end

-- 🧠 Gộp dữ liệu từ macro (từ dòng đầu đến maxLine)
local function BuildTowerRecords(macro, maxLine, skipList, beMode)
    local records = {}
    local skipSet = {}
    for _, name in ipairs(skipList or {}) do
        skipSet[name] = true
    end

    for i, entry in ipairs(macro) do
        if i > maxLine then break end

        local towerName = entry.TowerPlaced or entry.TowerName
        local x = nil

        if entry.TowerVector then
            local vecTab = entry.TowerVector:split(", ")
            x = tonumber(vecTab[1])
        elseif entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower then
            x = tonumber(entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower)
        end

        if x and towerName then
            local skip = false
            if skipSet[towerName] then
                if beMode and i <= maxLine then
                    skip = true
                elseif not beMode then
                    skip = true
                end
            end

            if not skip then
                records[x] = records[x] or { X = x, Actions = {} }
                table.insert(records[x].Actions, entry)
                records[x].TowerName = towerName
            end
        end
    end
    return records
end

-- 🔼 Ưu tiên theo loại tower
local priorityMap = {
    Medic = 1,
    ["Golden Mobster"] = 2,
    Mobster = 2,
    DJ = 3,
    Commander = 4
}

local function GetPriority(name)
    return priorityMap[name] or 5
end

-- 🚀 Watcher loop chính
function startRebuildWatcher(macro, maxLine, skipList, beMode)
    local towerRecords = BuildTowerRecords(macro, maxLine, skipList, beMode)

    while true do
        local rebuildList = {}
        for x, record in pairs(towerRecords) do
            if IsTowerMissing(x) then
                table.insert(rebuildList, record)
            end
        end

        table.sort(rebuildList, function(a, b)
            return GetPriority(a.TowerName) < GetPriority(b.TowerName)
        end)

        for _, record in ipairs(rebuildList) do
            for _, action in ipairs(record.Actions) do
                if action.TowerPlaced and action.TowerVector and action.TowerPlaceCost then
                    local vecTab = action.TowerVector:split(", ")
                    local pos = Vector3.new(unpack(vecTab))
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

-- 🔄 Tự động kích hoạt watcher nếu gặp "SuperFunction": "rebuild"
local function DetectRebuildEntry(macro)
    for i, entry in ipairs(macro) do
        if entry.SuperFunction == "rebuild" then
            local skip = entry.Skip or {}
            local be = entry.Be or false
            startRebuildWatcher(macro, i, skip, be)
            break
        end
    end
end

-- 📂 Load macro
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

-- Ánh xạ lại tên mode
if globalPlaceMode == "unsure" then
    globalPlaceMode = "rewrite"
elseif globalPlaceMode == "normal" then
    globalPlaceMode = "ashed"
end

if not isfile(macroPath) then
    error("Không tìm thấy macro file: " .. macroPath)
end

local success, macro = pcall(function()
    return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then
    error("Lỗi khi đọc macro")
end

-- ▶️ Chạy macro như thường lệ
for _, entry in ipairs(macro) do
    if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
        local vecTab = entry.TowerVector:split(", ")
        local pos = Vector3.new(unpack(vecTab))
        local args = {
            tonumber(entry.TowerA1),
            entry.TowerPlaced,
            pos,
            tonumber(entry.Rotation or 0)
        }
        WaitForCash(entry.TowerPlaceCost)
        PlaceTowerRetry(args, pos.X, entry.TowerPlaced)
    elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
        local axisValue = tonumber(entry.TowerUpgraded)
        UpgradeTowerRetry(axisValue, entry.UpgradePath)
    elseif entry.ChangeTarget and entry.TargetType then
        local axisValue = tonumber(entry.ChangeTarget)
        ChangeTargetRetry(axisValue, entry.TargetType)
    elseif entry.SellTower then
        local axisValue = tonumber(entry.SellTower)
        SellTowerRetry(axisValue)
    end
end

-- 🚨 Kích hoạt rebuild nếu có SuperFunction
DetectRebuildEntry(macro)

print("✅ Macro chạy hoàn tất.")