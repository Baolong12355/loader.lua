local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Cấu hình
getgenv().TDX_Config = getgenv().TDX_Config or {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "Ashed",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil, -- nil = infinite
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"}, -- Danh sách ưu tiên
    ["TargetChangeCheckDelay"] = 0.1, -- Delay kiểm tra target change
    ["CheDoDebug"] = true, -- Debug mode
    ["RebuildPriority"] = true, -- Ưu tiên rebuild hơn macro
    ["RebuildCheckInterval"] = 0.05, -- Tần suất kiểm tra rebuild
    ["MacroStepDelay"] = 0.1 -- Delay giữa các bước macro
}

local function debugPrint(...)
    if getgenv().TDX_Config.CheDoDebug then
        print("[MACRO-RUNNER]", ...)
    end
end

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
if not TowerClass then return end

-- Hàm lấy UI elements
local function getGameUI()
    while true do
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                return {
                    waveText = gameInfoBar.Wave.WaveText,
                    timeText = gameInfoBar.TimeLeft.TimeLeftText
                }
            end
        end
        task.wait(1)
    end
end

-- Chuyển số thành chuỗi thời gian (ví dụ: 235 -> "02:35")
local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

-- Hàm xác định độ ưu tiên
local function GetTowerPriority(towerName)
    for priority, name in ipairs(getgenv().TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge -- Mức ưu tiên thấp nhất nếu không có trong danh sách
end

-- Hàm SellAll hoàn chỉnh
local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then
        for _, name in ipairs(skipList) do
            skipMap[name] = true
        end
    end

    for hash, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if root and not skipMap[root.Name] then
            Remotes.SellTower:FireServer(hash)
            task.wait(getgenv().TDX_Config.SellAllDelay or 0.1)
        end
    end
end

local function GetTowerByAxis(axisX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, pos, name = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            return root and root.Position, model and (root and root.Name or model.Name)
        end)
        if success and pos and pos.X == axisX then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return hash, tower, name or "(NoName)"
            end
        end
    end
    return nil, nil, nil
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
        task.wait(0.1)
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

-- Hàm kiểm tra điều kiện target change
local function shouldChangeTarget(entry, currentWave, currentTime)
    -- Kiểm tra theo wave nếu có
    if entry.TargetWave and entry.TargetWave ~= currentWave then
        return false
    end
    
    -- Kiểm tra theo thời gian nếu có
    if entry.TargetChangedAt then
        local targetTimeStr = convertToTimeFormat(entry.TargetChangedAt)
        if currentTime ~= targetTimeStr then
            return false
        end
    end
    
    return true
end

-- Hệ thống Target Change Monitor
local function StartTargetChangeMonitor(targetChangeEntries, gameUI)
    local processedEntries = {}
    
    while true do
        local currentWave = gameUI.waveText.Text
        local currentTime = gameUI.timeText.Text
        
        for i, entry in ipairs(targetChangeEntries) do
            if not processedEntries[i] and shouldChangeTarget(entry, currentWave, currentTime) then
                local axisValue = entry.TowerTargetChange
                local targetType = entry.TargetWanted
                
                debugPrint("Đang thay đổi target cho tower tại X:", axisValue, "Target:", targetType, "Wave:", currentWave, "Time:", currentTime)
                
                ChangeTargetRetry(axisValue, targetType)
                processedEntries[i] = true
                
                debugPrint("Đã thay đổi target thành công!")
            end
        end
        
        task.wait(getgenv().TDX_Config.TargetChangeCheckDelay)
    end
end

-- Hệ thống Priority Rebuild với ưu tiên cao
local function GetHighestPriorityRebuild(towerRecords, skipTypesMap, rebuildLine)
    local highestPriority = math.huge
    local bestRebuild = nil
    
    for x, records in pairs(towerRecords) do
        local _, tower = GetTowerByAxis(x)
        if not tower then -- Tower bị mất/bán
            local towerType
            for _, record in ipairs(records) do
                if record.entry.TowerPlaced then 
                    towerType = record.entry.TowerPlaced 
                    break
                end
            end
            
            -- Kiểm tra skip rules
            local skipRule = skipTypesMap[towerType]
            if skipRule then
                if skipRule.beOnly and records[1].line < skipRule.fromLine then
                    goto continue
                elseif not skipRule.beOnly then
                    goto continue
                end
            end
            
            local priority = GetTowerPriority(towerType)
            if priority < highestPriority then
                highestPriority = priority
                bestRebuild = {
                    x = x,
                    records = records,
                    priority = priority,
                    towerType = towerType
                }
            end
        end
        ::continue::
    end
    
    return bestRebuild
end

local function ExecuteRebuildActions(rebuild)
    debugPrint("🔥 URGENT REBUILD:", rebuild.towerType, "tại X:", rebuild.x, "Priority:", rebuild.priority)
    
    for _, record in ipairs(rebuild.records) do
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
            debugPrint("  ➤ Placing:", action.TowerPlaced)
            WaitForCash(action.TowerPlaceCost)
            PlaceTowerRetry(args, pos.X, action.TowerPlaced)
        elseif action.TowerUpgraded then
            debugPrint("  ➤ Upgrading path:", action.UpgradePath)
            UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
        elseif action.ChangeTarget then
            debugPrint("  ➤ Changing target to:", action.TargetType)
            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
        elseif action.SellTower then
            debugPrint("  ➤ Selling tower")
            SellTowerRetry(tonumber(action.SellTower))
        end
        task.wait(0.03) -- Rất nhanh cho rebuild
    end
    
    debugPrint("✅ Hoàn thành rebuild:", rebuild.towerType)
end
-- Cơ chế rebuild với ưu tiên (Legacy - backup)
local function StartPriorityRebuildWatcher(towerRecords, rebuildLine, skipTypesMap)
    local soldPositions = {}
    local rebuildAttempts = {}

    while true do
        -- Chỉ chạy khi không có rebuild priority
        if not getgenv().TDX_Config.RebuildPriority then
            -- Sắp xếp các tháp cần rebuild theo độ ưu tiên
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

            -- Sắp xếp theo độ ưu tiên
            table.sort(rebuildQueue, function(a, b)
                if a.priority == b.priority then
                    return a.x < b.x
                end
                return a.priority < b.priority
            end)

            -- Thực hiện rebuild theo thứ tự ưu tiên
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
                    task.wait(0.05)
                end
            end
        end

        task.wait(0.1)
    end
end)
    end
end

-- Main execution
debugPrint("Đang khởi động Macro Runner...")

local config = getgenv().TDX_Config
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"

if not isfile(macroPath) then 
    debugPrint("Không tìm thấy file macro:", macroPath)
    return 
end

local ok, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end)
if not ok or type(macro) ~= "table" then 
    debugPrint("Lỗi khi đọc macro file")
    return 
end

-- Lấy UI elements
local gameUI = getGameUI()
debugPrint("Đã kết nối với GameUI")

local towerRecords, skipTypesMap = {}, {}
local targetChangeEntries = {}
local rebuildLine, watcherStarted = nil, false
local targetMonitorStarted = false

-- Hệ thống Macro Runner với Priority Rebuild
local function RunMacroWithRebuildPriority(macro, towerRecords, skipTypesMap, rebuildLine, targetChangeEntries, gameUI)
    local targetMonitorStarted = false
    
    -- Khởi động Target Monitor nếu cần
    if #targetChangeEntries > 0 then
        task.spawn(StartTargetChangeMonitor, targetChangeEntries, gameUI)
        targetMonitorStarted = true
        debugPrint("Đã khởi động Target Change Monitor")
    end
    
    debugPrint("🚀 Bắt đầu Macro với Priority Rebuild System")
    
    for i, entry in ipairs(macro) do
        -- PRIORITY CHECK: Kiểm tra rebuild trước mỗi bước macro
        if getgenv().TDX_Config.RebuildPriority and rebuildLine and i >= rebuildLine then
            while true do
                local urgentRebuild = GetHighestPriorityRebuild(towerRecords, skipTypesMap, rebuildLine)
                if urgentRebuild then
                    ExecuteRebuildActions(urgentRebuild)
                    task.wait(getgenv().TDX_Config.RebuildCheckInterval)
                else
                    break -- Không có rebuild nào cần thiết, tiếp tục macro
                end
            end
        end
        
        -- Thực hiện bước macro hiện tại
        if entry.SuperFunction == "sell_all" then
            debugPrint("📤 Thực hiện sell_all")
            SellAllTowers(entry.Skip)
        elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            local vecTab = entry.TowerVector:split(", ")
            local pos = Vector3.new(unpack(vecTab))
            local args = {
                tonumber(entry.TowerA1),
                entry.TowerPlaced,
                pos,
                tonumber(entry.Rotation or 0)
            }
            debugPrint("🏗️ Đang đặt tower:", entry.TowerPlaced, "tại", pos)
            WaitForCash(entry.TowerPlaceCost)
            PlaceTowerRetry(args, pos.X, entry.TowerPlaced)
            towerRecords[pos.X] = towerRecords[pos.X] or {}
            table.insert(towerRecords[pos.X], { line = i, entry = entry })
        elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
            local axis = tonumber(entry.TowerUpgraded)
            debugPrint("⬆️ Đang nâng cấp tower tại X:", axis, "Path:", entry.UpgradePath)
            UpgradeTowerRetry(axis, entry.UpgradePath)
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        elseif entry.ChangeTarget and entry.TargetType then
            local axis = tonumber(entry.ChangeTarget)
            debugPrint("🎯 Đang thay đổi target tại X:", axis, "Target:", entry.TargetType)
            ChangeTargetRetry(axis, entry.TargetType)
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        elseif entry.SellTower then
            local axis = tonumber(entry.SellTower)
            debugPrint("💰 Đang bán tower tại X:", axis)
            SellTowerRetry(axis)
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        elseif entry.SuperFunction == "rebuild" then
            rebuildLine = i
            debugPrint("🔧 Đã thiết lập rebuild line:", i)
            for _, skip in ipairs(entry.Skip or {}) do
                skipTypesMap[skip] = { beOnly = entry.Be == true, fromLine = i }
            end
        elseif not entry.TowerTargetChange then -- Bỏ qua TowerTargetChange entries
            debugPrint("⚠️ Entry không xác định tại line:", i)
        end
        
        -- Delay nhỏ giữa các bước macro
        task.wait(getgenv().TDX_Config.MacroStepDelay)
    end
    
    debugPrint("✅ Macro hoàn thành! Chuyển sang chế độ Rebuild Only")
    
    -- Sau khi macro hoàn thành, chỉ focus vào rebuild
    while getgenv().TDX_Config.RebuildPriority and rebuildLine do
        local urgentRebuild = GetHighestPriorityRebuild(towerRecords, skipTypesMap, rebuildLine)
        if urgentRebuild then
            ExecuteRebuildActions(urgentRebuild)
        end
        task.wait(getgenv().TDX_Config.RebuildCheckInterval)
    end
end

debugPrint("Macro Runner đã hoàn thành khởi động!")
debugPrint("- Mode:", getgenv().TDX_Config.RebuildPriority and "PRIORITY REBUILD" or "LEGACY")
debugPrint("- Target Change entries:", #targetChangeEntries)
debugPrint("- Tower records sẽ được tạo trong quá trình chạy")
debugPrint("- Rebuild enabled:", rebuildLine ~= nil)