-- TDX Macro Runner - Compatible với Executor và GitHub
-- Tương thích với mọi executor phổ biến

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Compatibility layer cho các executor khác nhau
local function getGlobalEnv()
    return getgenv and getgenv() or _G
end

local function safeRequire(module)
    local success, result = pcall(function() return require(module) end)
    return success and result or nil
end

local function safeReadFile(path)
    if readfile then
        return readfile(path)
    else
        warn("readfile không khả dụng - vui lòng sử dụng executor hỗ trợ file system")
        return nil
    end
end

local function safeIsFile(path)
    if isfile then
        return isfile(path)
    else
        return false
    end
end

-- Cấu hình mặc định
local defaultConfig = {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "Ashed",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil, -- nil = infinite
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["CheDoDebug"] = false,
    ["RebuildPriority"] = true,
    ["RebuildCheckInterval"] = 0.05,
    ["MacroStepDelay"] = 0.1
}

-- Khởi tạo config với compatibility
local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

-- Merge với config mặc định
for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

local function debugPrint(...)
    if globalEnv.TDX_Config.CheDoDebug then
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
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then 
        warn("PlayerScripts không tìm thấy")
        return nil 
    end
    
    local client = ps:FindFirstChild("Client")
    if not client then 
        warn("Client không tìm thấy") 
        return nil 
    end
    
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then 
        warn("GameClass không tìm thấy") 
        return nil 
    end
    
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then 
        warn("TowerClass module không tìm thấy") 
        return nil 
    end
    
    return SafeRequire(towerModule)
end

-- Tải TowerClass với error handling
local TowerClass = LoadTowerClass()
if not TowerClass then 
    error("Không thể load TowerClass - vui lòng đảm bảo bạn đang trong game TDX")
end

-- Hàm lấy UI elements
local function getGameUI()
    local attempts = 0
    while attempts < 30 do -- Tối đa 30 giây
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                local waveFrame = gameInfoBar:FindFirstChild("Wave")
                local timeFrame = gameInfoBar:FindFirstChild("TimeLeft")
                
                if waveFrame and timeFrame then
                    local waveText = waveFrame:FindFirstChild("WaveText")
                    local timeText = timeFrame:FindFirstChild("TimeLeftText")
                    
                    if waveText and timeText then
                        return {
                            waveText = waveText,
                            timeText = timeText
                        }
                    end
                end
            end
        end
        attempts = attempts + 1
        task.wait(1)
    end
    error("Không thể tìm thấy Game UI - đảm bảo bạn đang trong trận đấu")
end

-- Chuyển số thành chuỗi thời gian
local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

-- Hàm xác định độ ưu tiên
local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

-- Hàm SellAll
local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then
        for _, name in ipairs(skipList) do
            skipMap[name] = true
        end
    end

    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, model = pcall(function()
            return tower.Character and tower.Character:GetCharacterModel()
        end)
        
        if success and model then
            local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
            if root and not skipMap[root.Name] then
                pcall(function()
                    Remotes.SellTower:FireServer(hash)
                end)
                task.wait(globalEnv.TDX_Config.SellAllDelay or 0.1)
            end
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
    local maxAttempts = 10
    local attempts = 0
    
    while attempts < maxAttempts do
        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        
        if success then
            local t0 = tick()
            repeat 
                task.wait(0.1) 
            until tick() - t0 > 3 or GetTowerByAxis(axisValue)
            
            if GetTowerByAxis(axisValue) then 
                return 
            end
        end
        
        attempts = attempts + 1
        task.wait()
    end
    
    warn("Không thể đặt tower sau", maxAttempts, "lần thử")
end

local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = 10
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            task.wait() 
            attempts = attempts + 1
            continue 
        end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end

        WaitForCash(cost)
        
        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        
        if success then
            local t0 = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
            until tick() - t0 > 3
        end
        
        attempts = attempts + 1
        task.wait()
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = 5
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.ChangeQueryType:FireServer(hash, targetType)
            end)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
end

local function SellTowerRetry(axisValue)
    local maxAttempts = 5
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.SellTower:FireServer(hash)
            end)
            task.wait(0.1)
            if not GetTowerByAxis(axisValue) then return true end
        end
        attempts = attempts + 1
        task.wait()
    end
    return false
end

-- Hàm kiểm tra điều kiện target change
local function shouldChangeTarget(entry, currentWave, currentTime)
    if entry.TargetWave and entry.TargetWave ~= currentWave then
        return false
    end
    
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
    
    task.spawn(function()
        while true do
            local success, currentWave, currentTime = pcall(function()
                return gameUI.waveText.Text, gameUI.timeText.Text
            end)
            
            if success then
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
            end
            
            task.wait(globalEnv.TDX_Config.TargetChangeCheckDelay)
        end
    end)
end

-- Main execution function
local function RunMacroRunner()
    debugPrint("Đang khởi động Macro Runner...")

    local config = globalEnv.TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/" .. macroName .. ".json"

    -- Kiểm tra file macro
    if not safeIsFile(macroPath) then 
        warn("Không tìm thấy file macro:", macroPath)
        warn("Vui lòng đảm bảo file macro tồn tại hoặc executor hỗ trợ file system")
        return 
    end

    local macroContent = safeReadFile(macroPath)
    if not macroContent then
        warn("Không thể đọc file macro")
        return
    end

    local ok, macro = pcall(function() 
        return HttpService:JSONDecode(macroContent) 
    end)
    
    if not ok or type(macro) ~= "table" then 
        warn("Lỗi khi parse macro file:", ok and "Invalid JSON format" or macro)
        return 
    end

    -- Lấy UI elements
    local gameUI = getGameUI()
    debugPrint("Đã kết nối với GameUI")

    local towerRecords, skipTypesMap = {}, {}
    local targetChangeEntries = {}
    local rebuildLine = nil

    -- Collect target change entries
    for _, entry in ipairs(macro) do
        if entry.TowerTargetChange then
            table.insert(targetChangeEntries, entry)
        end
    end

    -- Khởi động Target Monitor nếu cần
    if #targetChangeEntries > 0 then
        StartTargetChangeMonitor(targetChangeEntries, gameUI)
        debugPrint("Đã khởi động Target Change Monitor với", #targetChangeEntries, "entries")
    end

    debugPrint("🚀 Bắt đầu thực thi macro")
    
    -- Main macro execution loop
    for i, entry in ipairs(macro) do
        debugPrint("Đang thực thi line", i, "of", #macro)
        
        if entry.SuperFunction == "sell_all" then
            debugPrint("📤 Thực hiện sell_all")
            SellAllTowers(entry.Skip)
            
        elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            local vecTab = {}
            for coord in entry.TowerVector:gmatch("[^,%s]+") do
                table.insert(vecTab, tonumber(coord))
            end
            
            if #vecTab == 3 then
                local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
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
            end
            
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
        end
        
        -- Delay giữa các bước macro
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
    
    debugPrint("✅ Macro hoàn thành thành công!")
    
    -- Rebuild system sau khi macro hoàn thành
    if rebuildLine and config.RebuildPriority then
        debugPrint("🔧 Bắt đầu hệ thống rebuild...")
        
        task.spawn(function()
            while true do
                for x, records in pairs(towerRecords) do
                    local _, tower = GetTowerByAxis(x)
                    if not tower then -- Tower bị mất
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
                                continue
                            elseif not skipRule.beOnly then
                                continue
                            end
                        end
                        
                        debugPrint("🔥 Rebuilding:", towerType, "tại X:", x)
                        
                        -- Thực hiện rebuild
                        for _, record in ipairs(records) do
                            local action = record.entry
                            if action.TowerPlaced then
                                local vecTab = {}
                                for coord in action.TowerVector:gmatch("[^,%s]+") do
                                    table.insert(vecTab, tonumber(coord))
                                end
                                if #vecTab == 3 then
                                    local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
                                    local args = {
                                        tonumber(action.TowerA1), 
                                        action.TowerPlaced, 
                                        pos, 
                                        tonumber(action.Rotation or 0)
                                    }
                                    WaitForCash(action.TowerPlaceCost)
                                    PlaceTowerRetry(args, pos.X, action.TowerPlaced)
                                end
                            elseif action.TowerUpgraded then
                                UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                            elseif action.ChangeTarget then
                                ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                            elseif action.SellTower then
                                SellTowerRetry(tonumber(action.SellTower))
                            end
                            task.wait(0.05)
                        end
                        
                        debugPrint("✅ Hoàn thành rebuild:", towerType)
                        break -- Rebuild một tower mỗi lần để tránh lag
                    end
                end
                
                task.wait(config.RebuildCheckInterval)
            end
        end)
    end
end

-- Khởi chạy script
local success, err = pcall(RunMacroRunner)
if not success then
    warn("Lỗi khi chạy Macro Runner:", err)
    warn("Vui lòng kiểm tra:")
    warn("1. Bạn đang trong game TDX")
    warn("2. File macro tồn tại")
    warn("3. Executor hỗ trợ đầy đủ các functions cần thiết")
end