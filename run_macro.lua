-- TDX Macro Runner v3.0 - Loadstring Ready
-- Tương thích với loadstring từ GitHub

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- ===================== UNIVERSAL COMPATIBILITY =====================
local function getGlobalEnv()
    if getgenv then 
        return getgenv() 
    elseif getfenv then 
        return getfenv() 
    else 
        return _G 
    end
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

-- HTTP Request function với fallback
local function safeHttpGet(url)
    local httpFunctions = {
        function() return game:HttpGet(url) end,
        function() return syn and syn.request({Url = url, Method = "GET"}).Body end,
        function() return request and request({Url = url, Method = "GET"}).Body end,
        function() return http_request and http_request({Url = url, Method = "GET"}).Body end
    }
    
    for _, httpFunc in ipairs(httpFunctions) do
        local success, result = pcall(httpFunc)
        if success and result then
            return result
        end
    end
    
    error("Không thể thực hiện HTTP request - executor không hỗ trợ")
end

-- ===================== CONFIG SYSTEM =====================
local defaultConfig = {
    ["Macro Name"] = "x",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0,
    ["MaxConcurrentRebuilds"] = 5
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

-- Merge default config
for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- ===================== HELPER FUNCTIONS =====================
local function getMaxAttempts()
    local placeMode = globalEnv.TDX_Config.PlaceMode or "Ashed"
    return placeMode == "Rewrite" and 10 or 1
end

local function SafeRequire(moduleScript, timeout)
    timeout = timeout or 5
    local startTime = tick()
    
    while tick() - startTime < timeout do
        local success, result = pcall(require, moduleScript)
        if success and result then 
            return result 
        end
        RunService.Heartbeat:Wait()
    end
    
    return nil
end

local function LoadTowerClass()
    local playerScripts = player:FindFirstChild("PlayerScripts")
    if not playerScripts then return nil end
    
    local client = playerScripts:FindFirstChild("Client")
    if not client then return nil end
    
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then return nil end
    
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then return nil end
    
    return SafeRequire(towerModule)
end

-- Load TowerClass với error handling
local TowerClass = LoadTowerClass()
if not TowerClass then 
    error("Không thể load TowerClass - vui lòng đảm bảo bạn đang trong game TDX")
end

-- ===================== AUTO SELL CONVERTED TOWERS =====================
local soldConvertedX = {}

spawn(function()
    while wait(0.2) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                local spawnCFrame = tower.SpawnCFrame
                if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                    local pos = spawnCFrame.Position
                    local x = pos.X
                    if not soldConvertedX[x] then
                        pcall(function()
                            Remotes.SellTower:FireServer(hash)
                        end)
                        soldConvertedX[x] = true
                        print("Đã auto sell tower convert tại X =", x)
                    end
                end
            end
        end
    end
end)

-- ===================== TOWER MANAGEMENT FUNCTIONS =====================
local function GetTowerHashBySpawnX(targetX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local spawnCFrame = tower.SpawnCFrame
        if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
            local pos = spawnCFrame.Position
            if pos.X == targetX then
                return hash, tower, pos
            end
        end
    end
    return nil, nil, nil
end

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
        wait(1)
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
        local model = tower.Character and tower.Character:GetCharacterModel()
        if model then
            local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
            if root and not skipMap[root.Name] then
                pcall(function()
                    Remotes.SellTower:FireServer(hash)
                end)
                wait(globalEnv.TDX_Config.SellAllDelay or 0.1)
            end
        end
    end
end

local function GetTowerByAxis(axisX)
    return GetTowerHashBySpawnX(axisX)
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    
    if curLvl >= maxLvl then return nil end
    
    local success, baseCost = pcall(function() 
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1) 
    end)
    if not success then return nil end
    
    local discount = 0
    if tower.BuffHandler then
        local success2, d = pcall(function() 
            return tower.BuffHandler:GetDiscount() or 0 
        end)
        if success2 and typeof(d) == "number" then 
            discount = d 
        end
    end
    
    return math.floor(baseCost * (1 - discount))
end

local function WaitForCash(amount)
    while cashStat.Value < amount do 
        RunService.Heartbeat:Wait()
    end
end

-- ===================== TOWER ACTION FUNCTIONS =====================
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
                wait(0.1)
            until tick() - startTime > 3 or GetTowerByAxis(axisValue)
            
            if GetTowerByAxis(axisValue) then 
                return true
            end
        end
        
        attempts = attempts + 1
        wait()
    end
    
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            wait() 
            attempts = attempts + 1
            continue 
        end
        
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        
        if not cost then return true end
        
        WaitForCash(cost)
        
        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        
        if success then
            local startTime = tick()
            repeat
                wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                    return true 
                end
            until tick() - startTime > 3
        end
        
        attempts = attempts + 1
        wait()
    end
    
    return false
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
        wait(0.1)
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
            wait(0.1)
            if not GetTowerByAxis(axisValue) then 
                return true 
            end
        end
        attempts = attempts + 1
        wait()
    end
    
    return false
end

-- ===================== TARGET CHANGE MONITOR =====================
local function StartTargetChangeMonitor(targetChangeEntries, gameUI)
    spawn(function()
        while wait(globalEnv.TDX_Config.TargetChangeCheckDelay or 0.1) do
            local currentWave = tonumber(gameUI.waveText.Text:match("%d+"))
            local currentTime = gameUI.timeText.Text
            
            for _, entry in ipairs(targetChangeEntries) do
                if entry.TargetWave and entry.TargetWave == currentWave then
                    if not entry.TargetChangedAt or convertToTimeFormat(entry.TargetChangedAt) == currentTime then
                        ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetType)
                    end
                end
            end
        end
    end)
end

-- ===================== REBUILD SYSTEM =====================
local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local config = globalEnv.TDX_Config
    local rebuildAttempts = {}
    local soldPositions = {}
    local jobQueue = {}
    local activeJobs = {}

    -- Worker function
    local function RebuildWorker()
        spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records

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
                                if not PlaceTowerRetry(args, pos.X, action.TowerPlaced) then
                                    rebuildSuccess = false
                                    break
                                end
                            end

                        elseif action.TowerUpgraded then
                            if not UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath) then
                                rebuildSuccess = false
                                break
                            end

                        elseif action.ChangeTarget then
                            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)

                        elseif action.SellTower then
                            if SellTowerRetry(tonumber(action.SellTower)) then
                                soldPositions[tonumber(action.SellTower)] = true
                            end
                        end
                    end

                    if rebuildSuccess then
                        rebuildAttempts[x] = 0
                    end

                    activeJobs[x] = nil
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    -- Start workers
    for i = 1, config.MaxConcurrentRebuilds do
        RebuildWorker()
    end

    -- Main rebuild detection loop
    spawn(function()
        while true do
            if next(towerRecords) then
                for x, records in pairs(towerRecords) do
                    local hash, tower = GetTowerByAxis(x)

                    if not hash or not tower then
                        if not activeJobs[x] then
                            if soldPositions[x] and not config.ForceRebuildEvenIfSold then
                                continue
                            end

                            local towerType = nil
                            local firstPlaceRecord = nil

                            for _, record in ipairs(records) do
                                if record.entry.TowerPlaced then 
                                    towerType = record.entry.TowerPlaced
                                    firstPlaceRecord = record
                                    break
                                end
                            end

                            if towerType then
                                local skipRule = skipTypesMap[towerType]
                                local shouldSkip = false

                                if skipRule then
                                    if skipRule.beOnly and firstPlaceRecord.line < skipRule.fromLine then
                                        shouldSkip = true
                                    elseif not skipRule.beOnly then
                                        shouldSkip = true
                                    end
                                end

                                if not shouldSkip then
                                    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                                    local maxRetry = config.MaxRebuildRetry

                                    if not maxRetry or rebuildAttempts[x] <= maxRetry then
                                        activeJobs[x] = true
                                        local priority = GetTowerPriority(towerType)
                                        
                                        table.insert(jobQueue, { 
                                            x = x, 
                                            records = records, 
                                            priority = priority,
                                            deathTime = tick()
                                        })

                                        -- Sort by priority
                                        table.sort(jobQueue, function(a, b) 
                                            if a.priority == b.priority then
                                                return a.deathTime < b.deathTime
                                            end
                                            return a.priority < b.priority 
                                        end)
                                    end
                                end
                            end
                        end
                    else
                        if activeJobs[x] then
                            activeJobs[x] = nil
                            for i = #jobQueue, 1, -1 do
                                if jobQueue[i].x == x then
                                    table.remove(jobQueue, i)
                                    break
                                end
                            end
                        end
                    end
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- ===================== MAIN MACRO RUNNER =====================
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

    local success, macro = pcall(function() 
        return HttpService:JSONDecode(macroContent) 
    end)

    if not success or type(macro) ~= "table" then 
        error("Lỗi parse macro file")
    end

    local gameUI = getGameUI()
    local towerRecords = {}
    local skipTypesMap = {}
    local targetChangeEntries = {}
    local rebuildSystemActive = false

    -- Collect target change entries
    for i, entry in ipairs(macro) do
        if entry.TowerTargetChange then
            table.insert(targetChangeEntries, entry)
        end
    end

    -- Start target change monitor
    if #targetChangeEntries > 0 then
        StartTargetChangeMonitor(targetChangeEntries, gameUI)
    end

    -- Execute macro
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

        wait(config.MacroStepDelay)
    end
end

-- ===================== EXECUTION =====================
print("TDX Macro Runner v3.0 đã được tải thành công!")
print("Executor environment: " .. (getgenv and "Advanced" or "Basic"))

local success, err = pcall(RunMacroRunner)
if not success then
    error("Lỗi Macro Runner: " .. tostring(err))
end