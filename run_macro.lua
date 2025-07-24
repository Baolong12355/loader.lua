-- TDX Macro Runner - Universal Compatibility
-- Hỗ trợ tất cả executor và loadstring từ GitHub

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local function safeReadFile(path)
    if readfile and typeof(readfile) == "function" then
        local success, result = pcall(readfile, path)
        return success and result or nil
    end
    return nil
end

local function safeIsFile(path)
    if isfile and typeof(isfile) == "function" then
        local success, result = pcall(isfile, path)
        return success and result or false
    end
    return false
end

local function safeWriteFile(path, content)
    if writefile and typeof(writefile) == "function" then
        local success = pcall(writefile, path, content)
        return success
    end
    return false
end

local function safeMakeFolder(path)
    if makefolder and typeof(makefolder) == "function" then
        local success = pcall(makefolder, path)
        return success
    end
    return false
end

-- Cấu hình mặc định
local defaultConfig = {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0
}

-- Khởi tạo config
local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- Hàm lấy số lần retry dựa trên PlaceMode
local function getMaxAttempts()
    local placeMode = globalEnv.TDX_Config.PlaceMode or "Ashed"
    if placeMode == "Ashed" then
        return 1  -- Không retry
    elseif placeMode == "Rewrite" then
        return 10  -- Retry 3 lần
    else
        return 1  -- Mặc định không retry nếu không rõ mode
    end
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    
    while tick() - startTime < timeout do
        local success, result = pcall(function() 
            return require(path) 
        end)
        if success and result then 
            return result 
        end
        RunService.Heartbeat:Wait()
    end
    return nil
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    
    local client = ps:FindFirstChild("Client")
    if not client then return nil end
    
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then return nil end
    
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then return nil end
    
    return SafeRequire(towerModule)
end

-- Load TowerClass
local TowerClass = LoadTowerClass()
if not TowerClass then 
    error("Không thể load TowerClass - vui lòng đảm bảo bạn đang trong game TDX")
end

-- Hàm lấy UI elements
local function getGameUI()
    local attempts = 0
    while attempts < 30 do
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
    error("Không thể tìm thấy Game UI")
end

local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

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
        if success and pos and pos.X == axisX then  -- Đã bỏ làm tròn, so sánh chính xác
            local hp = 1
            pcall(function()
                hp = tower.HealthHandler and tower.HealthHandler:GetHealth() or 1
            end)
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
    while cashStat.Value < amount do 
        task.wait() 
    end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    while attempts < maxAttempts do
        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        
        if success then
            local startTime = tick()
            repeat 
                task.wait(0.1) 
            until tick() - startTime > 3 or GetTowerByAxis(axisValue)
            
            if GetTowerByAxis(axisValue) then 
                return 
            end
        end
        
        attempts = attempts + 1
        task.wait()
    end
end

local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
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
            local startTime = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
            until tick() - startTime > 3
        end
        
        attempts = attempts + 1
        task.wait()
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = getMaxAttempts()
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
    local maxAttempts = getMaxAttempts()
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
                        
                        ChangeTargetRetry(axisValue, targetType)
                        processedEntries[i] = true
                    end
                end
            end
            
            task.wait(globalEnv.TDX_Config.TargetChangeCheckDelay)
        end
    end)
end

local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local rebuildAttempts = {}
    local soldPositions = {}
    local config = globalEnv.TDX_Config
    
    task.spawn(function()
        while true do
            if next(towerRecords) then
                local rebuildFound = false
                local rebuildQueue = {}
                
                for x, records in pairs(towerRecords) do
                    local hash, tower = GetTowerByAxis(x)
                    if not hash or not tower then
                        local towerType = nil
                        local firstPlaceRecord = nil
                        
                        for _, record in ipairs(records) do
                            if record.entry.TowerPlaced then 
                                towerType = record.entry.TowerPlaced
                                firstPlaceRecord = record
                                break
                            end
                        end
                        
                        if not towerType then continue end
                        
                        local skipRule = skipTypesMap[towerType]
                        if skipRule then
                            if skipRule.beOnly and firstPlaceRecord.line < skipRule.fromLine then
                                continue
                            elseif not skipRule.beOnly then
                                continue
                            end
                        end
                        
                        if soldPositions[x] and not config.ForceRebuildEvenIfSold then
                            continue
                        end
                        
                        rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                        local maxRetry = config.MaxRebuildRetry
                        if maxRetry and rebuildAttempts[x] > maxRetry then
                            continue
                        end
                        
                        local priority = GetTowerPriority(towerType)
                        table.insert(rebuildQueue, {
                            x = x,
                            records = records,
                            priority = priority,
                            towerType = towerType,
                            attempts = rebuildAttempts[x]
                        })
                    end
                end
                
                table.sort(rebuildQueue, function(a, b)
                    if a.priority == b.priority then
                        return a.x < b.x
                    end
                    return a.priority < b.priority
                end)
                
                for _, rebuildItem in ipairs(rebuildQueue) do
                    local x = rebuildItem.x
                    local records = rebuildItem.records
                    
                    local rebuildSuccess = true
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
                                
                                local placedHash = GetTowerByAxis(pos.X)
                                if not placedHash then
                                    rebuildSuccess = false
                                    break
                                end
                            end
                            
                        elseif action.TowerUpgraded then
                            UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                            
                        elseif action.ChangeTarget then
                            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                            
                        elseif action.SellTower then
                            local sellSuccess = SellTowerRetry(tonumber(action.SellTower))
                            if sellSuccess then
                                soldPositions[tonumber(action.SellTower)] = true
                            end
                        end
                        
                        task.wait(0.05)
                    end
                    
                    if rebuildSuccess then
                        rebuildAttempts[x] = 0
                    end
                    
                    rebuildFound = true
                    break
                end
                
                if not rebuildFound then
                    task.wait(config.RebuildCheckInterval * 2)
                else
                    task.wait(config.RebuildCheckInterval)
                end
            else
                task.wait(0.1)
            end
        end
    end)
end

local function RunMacroRunner()
    local config = globalEnv.TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/" .. macroName .. ".json"

    if not safeIsFile(macroPath) then 
        error("Không tìm thấy file macro: " .. macroPath)
    end

    local macroContent = safeReadFile(macroPath)
    if not macroContent then
        error("Không thể đọc file macro")
    end

    local ok, macro = pcall(function() 
        return HttpService:JSONDecode(macroContent) 
    end)
    
    if not ok or type(macro) ~= "table" then 
        error("Lỗi parse macro file")
    end

    local gameUI = getGameUI()
    local towerRecords = {}
    local skipTypesMap = {}
    local targetChangeEntries = {}
    local rebuildSystemActive = false

    for i, entry in ipairs(macro) do
        if entry.TowerTargetChange then
            table.insert(targetChangeEntries, entry)
        end
    end

    if #targetChangeEntries > 0 then
        StartTargetChangeMonitor(targetChangeEntries, gameUI)
    end
    
    for i, entry in ipairs(macro) do
        if entry.SuperFunction == "sell_all" then
            SellAllTowers(entry.Skip)
            
        elseif entry.SuperFunction == "rebuild" then
            if not rebuildSystemActive then
                for _, skip in ipairs(entry.Skip or {}) do
                    skipTypesMap[skip] = { beOnly = entry.Be == true, fromLine = i }
                end
                
                StartRebuildSystem(entry, towerRecords, skipTypesMap)
                rebuildSystemActive = true
            end
            
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
                
                WaitForCash(entry.TowerPlaceCost)
                PlaceTowerRetry(args, pos.X, entry.TowerPlaced)
                
                towerRecords[pos.X] = towerRecords[pos.X] or {}
                table.insert(towerRecords[pos.X], { line = i, entry = entry })
            end
            
        elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
            local axis = tonumber(entry.TowerUpgraded)
            UpgradeTowerRetry(axis, entry.UpgradePath)
            
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
            
        elseif entry.ChangeTarget and entry.TargetType then
            local axis = tonumber(entry.ChangeTarget)
            ChangeTargetRetry(axis, entry.TargetType)
            
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
            
        elseif entry.SellTower then
            local axis = tonumber(entry.SellTower)
            SellTowerRetry(axis)
            
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        end
        
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
end

local success, err = pcall(RunMacroRunner)
if not success then
    error("Lỗi Macro Runner: " .. tostring(err))
end
