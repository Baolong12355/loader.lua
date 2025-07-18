-- 📦 TDX Runner & Rebuilder (Final Fixed Version)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Cấu hình
getgenv().TDX_Config = getgenv().TDX_Config or {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil, -- nil = infinite
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["RebuildCheckInterval"] = 0.25
}

-- Biến toàn cục
local macroPaused = false
local currentMacroIndex = 1
local towerRecords = {}
local skipTypesMap = {}
local rebuildLine = nil
local placedTowers = {} -- Theo dõi các tháp đã được đặt

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local success, result = pcall(function() return require(path) end)
        if success then return result end
        task.wait()
    end
    return nil
end

local function LoadTowerClass()
    local ps = player:WaitForChild("PlayerScripts")
    local client = ps:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return SafeRequire(towerModule)
end

TowerClass = TowerClass or LoadTowerClass()
if not TowerClass then 
    warn("❌ Không thể tải TowerClass")
    return 
end

-- Hàm xác định độ ưu tiên
local function GetTowerPriority(towerName)
    if not towerName then return math.huge end
    for priority, name in ipairs(getgenv().TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

-- Hàm GetTowerByAxis an toàn
local function GetTowerByAxis(axisX)
    if not placedTowers[axisX] then return nil, nil, nil end
    
    local towers = TowerClass.GetTowers()
    if not towers then return nil, nil, nil end
    
    for hash, tower in pairs(towers) do
        if tower and tower.Character then
            local success, pos, name = pcall(function()
                local model = tower.Character:GetCharacterModel()
                local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
                return root and root.Position, model and (root and root.Name or model.Name)
            end)
            if success and pos and math.floor(pos.X) == math.floor(axisX) then
                local hp = (tower.HealthHandler and tower.HealthHandler:GetHealth()) or 0
                if hp > 0 then
                    return hash, tower, name or "Unknown"
                end
            end
        end
    end
    return nil, nil, nil
end

-- Hàm kiểm tra tháp ưu tiên bị phá hủy (đã sửa)
local function CheckPriorityTowersDestroyed()
    for x, records in pairs(towerRecords) do
        if placedTowers[x] then -- Chỉ kiểm tra tháp đã được đặt
            local _, t, name = GetTowerByAxis(x)
            if not t and name and GetTowerPriority(name) <= #getgenv().TDX_Config.PriorityRebuildOrder then
                return true, x, name
            end
        end
    end
    return false
end

-- Hàm rebuild tháp cụ thể (đã sửa)
local function RebuildTower(x, records)
    local rebuildAttempts = {}
    
    local towerType
    for _, record in ipairs(records) do
        if record.entry.TowerPlaced then 
            towerType = record.entry.TowerPlaced 
            break
        end
    end
    
    -- Kiểm tra điều kiện skip
    local skipRule = towerType and skipTypesMap[towerType]
    if skipRule then
        if (skipRule.beOnly and records[1].line < skipRule.fromLine) or (not skipRule.beOnly) then
            return
        end
    end
    
    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
    if getgenv().TDX_Config.MaxRebuildRetry and rebuildAttempts[x] > getgenv().TDX_Config.MaxRebuildRetry then
        return
    end
    
    for _, record in ipairs(records) do
        local action = record.entry
        if action.TowerPlaced then
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
        elseif action.TowerUpgraded then
            UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
        elseif action.ChangeTarget then
            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
        end
        task.wait(0.1)
    end
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
    if not ok then return nil end
    local disc = 0
    local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

local function WaitForCash(amount)
    while cashStat.Value < amount do task.wait() end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        local t0 = tick()
        repeat task.wait(0.1) until tick() - t0 > 2 or GetTowerByAxis(axisValue)
        if GetTowerByAxis(axisValue) then return end
    end
end

local function UpgradeTowerRetry(axisValue, path)
    while true do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then task.wait() continue end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end

        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)

        local t0 = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
        until tick() - t0 > 2
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    while true do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            Remotes.ChangeQueryType:FireServer(hash, targetType)
            return
        end
        task.wait()
    end
end

local function SellTowerRetry(axisValue)
    while true do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            Remotes.SellTower:FireServer(hash)
            task.wait(0.1)
            if not GetTowerByAxis(axisValue) then return true end
        end
        task.wait()
    end
end

-- CÆ¡ cháº¿ rebuild vá»›i Æ°u tiĂªn
local function StartPriorityRebuildWatcher(towerRecords, rebuildLine, skipTypesMap)
    local soldPositions = {}
    local rebuildAttempts = {}

    while true do
        -- Sáº¯p xáº¿p cĂ¡c thĂ¡p cáº§n rebuild theo Ä‘á»™ Æ°u tiĂªn
        local rebuildQueue = {}
        for x, records in pairs(towerRecords) do
            local _, t, name = GetTowerByAxis(x)
            if not t then
                if soldPositions[x] and not getgenv().TDX_Config.ForceRebuildEvenIfSold then
                    continue
                end

                local towerType
                for _, record in ipairs(records) do
                    if record.entry.TowerPlaced then towerType = record.entry.TowerPlaced end
                end

                local skipRule = skipTypesMap[towerType]
                if skipRule then
                    if skipRule.beOnly and records[1].line < skipRule.fromLine then
                        continue
                    elseif not skipRule.beOnly then
                        continue
                    end
                end

                rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                local maxRetry = getgenv().TDX_Config.MaxRebuildRetry
                if maxRetry and rebuildAttempts[x] > maxRetry then
                    continue
                end

                table.insert(rebuildQueue, {
                    x = x,
                    records = records,
                    priority = GetTowerPriority(towerType),
                    name = towerType or "Unknown"
                })
            end
        end

        -- Sáº¯p xáº¿p theo Ä‘á»™ Æ°u tiĂªn
        table.sort(rebuildQueue, function(a, b)
            if a.priority == b.priority then
                return a.x < b.x
            end
            return a.priority < b.priority
        end)

        -- Thá»±c hiá»‡n rebuild theo thá»© tá»± Æ°u tiĂªn
        for _, item in ipairs(rebuildQueue) do
            for _, record in ipairs(item.records) do
                local action = record.entry
                if action.TowerPlaced then
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
                elseif action.TowerUpgraded then
                    UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                elseif action.ChangeTarget then
                    ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                elseif action.SellTower then
                    SellTowerRetry(tonumber(action.SellTower))
                end
                task.wait(0.1)
            end
        end

        task.wait(0.25)
    end
end

-- Main execution
local config = getgenv().TDX_Config
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"

if not isfile(macroPath) then 
    warn("❌ Không tìm thấy file macro:", macroPath)
    return 
end

local ok, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end)
if not ok or type(macro) ~= "table" then 
    warn("❌ Lỗi đọc macro hoặc macro rỗng")
    return 
end

-- Chạy macro chính
task.spawn(function()
    while currentMacroIndex <= #macro do
        -- Kiểm tra tháp ưu tiên bị phá hủy
        local priorityDestroyed, x, name = CheckPriorityTowersDestroyed()
        if priorityDestroyed then
            macroPaused = true
            warn("⏸️ Tạm dừng macro để rebuild tháp ưu tiên:", name)
            RebuildTower(x, towerRecords[x])
            macroPaused = false
            warn("▶️ Tiếp tục macro")
        end
        
        if not macroPaused then
            local entry = macro[currentMacroIndex]
            
            if entry.SuperFunction == "sell_all" then
                SellAllTowers(entry.Skip)
            elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
                local vecTab = entry.TowerVector:split(", ")
                local pos = Vector3.new(unpack(vecTab))
                local axisX = pos.X
                local args = {
                    tonumber(entry.TowerA1),
                    entry.TowerPlaced,
                    pos,
                    tonumber(entry.Rotation or 0)
                }
                WaitForCash(entry.TowerPlaceCost)
                if PlaceTowerRetry(args, axisX, entry.TowerPlaced) then
                    placedTowers[axisX] = true
                    towerRecords[axisX] = towerRecords[axisX] or {}
                    table.insert(towerRecords[axisX], { line = currentMacroIndex, entry = entry })
                end
            -- ... (các điều kiện khác giữ nguyên) ...
            end
            
            currentMacroIndex = currentMacroIndex + 1
        end
        
        task.wait(config.RebuildCheckInterval)
    end
end)

-- Watcher cho các tháp không ưu tiên
task.spawn(function()
    while true do
        if not macroPaused then
            for x, records in pairs(towerRecords) do
                if placedTowers[x] then -- Chỉ kiểm tra tháp đã đặt
                    local _, t, name = GetTowerByAxis(x)
                    if not t and name and GetTowerPriority(name) > #getgenv().TDX_Config.PriorityRebuildOrder then
                        RebuildTower(x, records)
                    end
                end
            end
        end
        task.wait(config.RebuildCheckInterval)
    end
end)