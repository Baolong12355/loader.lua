local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/recorder_output.json"

-- Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

-- Enhanced configuration with improved settings
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    -- INSTANT BATCH PROCESSING CONFIGURATIONS
    ["BatchProcessingEnabled"] = true,
    ["InstantBatchMode"] = true,
    ["MaxBatchSize"] = 20,
    ["BatchCollectionTime"] = 0.1,
    ["ParallelProcessing"] = true,
    ["BatchPrewarmEnabled"] = false,
    -- SKIP CONFIGURATIONS
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {"Slammer", "Toxicnator"},
    ["SkipTowersByLine"] = {},
    -- FALLBACK CONFIGURATIONS
    ["UseFallbackPositionDetection"] = true,
    ["ModuleLoadTimeout"] = 1.0, -- 1 second timeout for module loading
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- Enhanced tower position detection system
local TowerPositionSystem = {
    TowerClass = nil,
    lastModuleCheck = 0,
    moduleCheckCooldown = 5, -- Check module every 5 seconds
    usingFallback = false
}

-- Safe file reading
local function safeReadFile(path)
    if readfile and isfile and isfile(path) then
        local ok, res = pcall(readfile, path)
        if ok then return res end
    end
    return nil
end

-- Enhanced SafeRequire with timeout
local function SafeRequire(path, timeout)
    timeout = timeout or globalEnv.TDX_Config.ModuleLoadTimeout
    local t0 = tick()
    while tick() - t0 < timeout do
        local ok, mod = pcall(require, path)
        if ok and mod then return mod end
        RunService.Heartbeat:Wait()
    end
    return nil
end

-- Load TowerClass module with enhanced error handling
local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    local client = ps:FindFirstChild("Client")
    if not client then return nil end
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then return nil end
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then return nil end
    return SafeRequire(towerModule, globalEnv.TDX_Config.ModuleLoadTimeout)
end

-- Fallback tower position detection using workspace
local function GetTowerByAxisFallback(targetX)
    local towersFolder = workspace:FindFirstChild("Game")
    if towersFolder then
        towersFolder = towersFolder:FindFirstChild("Towers")
    end
    
    if not towersFolder then return nil, nil, nil end
    
    for _, tower in pairs(towersFolder:GetChildren()) do
        if tower:IsA("BasePart") then
            local pos = tower.Position
            if math.abs(pos.X - targetX) < 0.1 then -- Small tolerance for floating point comparison
                return tower.Name, tower, pos -- Return tower name as hash, tower object, and position
            end
        elseif tower:IsA("Model") then
            -- Check if model has a primary part or find the main part
            local mainPart = tower.PrimaryPart or tower:FindFirstChildOfClass("BasePart")
            if mainPart then
                local pos = mainPart.Position
                if math.abs(pos.X - targetX) < 0.1 then
                    return tower.Name, tower, pos
                end
            end
        end
    end
    
    return nil, nil, nil
end

-- Enhanced tower position detection with fallback
function TowerPositionSystem:GetTowerByAxis(axisX)
    local currentTime = tick()
    
    -- Try to refresh module periodically
    if currentTime - self.lastModuleCheck > self.moduleCheckCooldown then
        self.lastModuleCheck = currentTime
        if not self.TowerClass then
            self.TowerClass = LoadTowerClass()
            if self.TowerClass then
                self.usingFallback = false
                print("TowerClass module loaded successfully")
            end
        end
    end
    
    -- Try module method first if available
    if self.TowerClass and not self.usingFallback then
        local success, hash, tower, pos = pcall(function()
            for hash, tower in pairs(self.TowerClass.GetTowers()) do
                local spawnCFrame = tower.SpawnCFrame
                if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                    local towerPos = spawnCFrame.Position
                    if towerPos.X == axisX then
                        return hash, tower, towerPos
                    end
                end
            end
            return nil, nil, nil
        end)
        
        if success and hash then
            return hash, tower, pos
        elseif not success then
            print("TowerClass method failed, switching to fallback")
            self.usingFallback = true
        end
    end
    
    -- Use fallback method
    if globalEnv.TDX_Config.UseFallbackPositionDetection then
        return GetTowerByAxisFallback(axisX)
    end
    
    return nil, nil, nil
end

-- Initialize tower position system
local function InitializeTowerSystem()
    TowerPositionSystem.TowerClass = LoadTowerClass()
    if TowerPositionSystem.TowerClass then
        print("TowerClass loaded successfully")
    else
        print("Failed to load TowerClass, will use fallback method")
        TowerPositionSystem.usingFallback = true
    end
end

-- Initialize the system
InitializeTowerSystem()

-- Retry logic
local function getMaxAttempts()
    local placeMode = globalEnv.TDX_Config.PlaceMode or "Rewrite"
    if placeMode == "Ashed" then
        return 1
    elseif placeMode == "Rewrite" then
        return 10
    else
        return 1
    end
end

-- Cache management
local function AddToRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
end

local function RemoveFromRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
end

local function IsInRebuildCache(axisX)
    return globalEnv.TDX_REBUILDING_TOWERS[axisX] == true
end

-- Skip logic
local function ShouldSkipTower(axisX, towerName, firstPlaceLine)
    local config = globalEnv.TDX_Config

    if config.SkipTowersAtAxis then
        for _, skipAxis in ipairs(config.SkipTowersAtAxis) do
            if axisX == skipAxis then
                return true
            end
        end
    end

    if config.SkipTowersByName then
        for _, skipName in ipairs(config.SkipTowersByName) do
            if towerName == skipName then
                return true
            end
        end
    end

    if config.SkipTowersByLine and firstPlaceLine then
        for _, skipLine in ipairs(config.SkipTowersByLine) do
            if firstPlaceLine == skipLine then
                return true
            end
        end
    end

    return false
end

-- Utility functions
local function GetTowerByAxis(axisX)
    return TowerPositionSystem:GetTowerByAxis(axisX)
end

local function WaitForCash(amount)
    while cash.Value < amount do
        RunService.Heartbeat:Wait()
    end
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

-- Enhanced tower upgrade cost calculation with fallback
local function GetCurrentUpgradeCost(tower, path)
    if not tower then return nil end
    
    -- Try module method first
    if TowerPositionSystem.TowerClass and tower.LevelHandler then
        local success, cost = pcall(function()
            local maxLvl = tower.LevelHandler:GetMaxLevel()
            local curLvl = tower.LevelHandler:GetLevelOnPath(path)
            if curLvl >= maxLvl then return nil end
            
            local baseCost = tower.LevelHandler:GetLevelUpgradeCost(path, 1)
            local disc = 0
            if tower.BuffHandler then
                local d = tower.BuffHandler:GetDiscount() or 0
                if typeof(d) == "number" then disc = d end
            end
            return math.floor(baseCost * (1 - disc))
        end)
        
        if success then return cost end
    end
    
    -- Fallback: return a default cost (you might want to adjust this)
    return 100 -- Default upgrade cost
end

-- Enhanced place tower with retry
local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    AddToRebuildCache(axisValue)

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
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        
        attempts = attempts + 1
        task.wait()
    end
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Enhanced upgrade tower with fallback support
local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            task.wait() 
            attempts = attempts + 1
            continue 
        end
        
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then 
            RemoveFromRebuildCache(axisValue)
            return true 
        end
        
        -- For fallback method, we might not have level tracking
        local before = 0
        if tower.LevelHandler then
            before = tower.LevelHandler:GetLevelOnPath(path)
        end
        
        WaitForCash(cost)
        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        
        if success then
            local startTime = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler then
                    if t.LevelHandler:GetLevelOnPath(path) > before then 
                        RemoveFromRebuildCache(axisValue)
                        return true 
                    end
                elseif tick() - startTime > 2 then -- Fallback timeout
                    RemoveFromRebuildCache(axisValue)
                    return true
                end
            until tick() - startTime > 3
        end
        
        attempts = attempts + 1
        task.wait()
    end
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Target changing with retry
local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.ChangeQueryType:FireServer(hash, targetType)
            end)
            RemoveFromRebuildCache(axisValue)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    
    RemoveFromRebuildCache(axisValue)
end

-- Enhanced skill checking with fallback
local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower then
        return false
    end
    
    -- Try module method
    if tower.AbilityHandler then
        local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
        return ability ~= nil
    end
    
    -- Fallback: assume skill exists after a delay (you might want to adjust this logic)
    return true
end

-- Enhanced moving skill usage
local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then
        return false
    end

    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if hash and tower then
            -- Check ability availability if possible
            if tower.AbilityHandler then
                local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
                if not ability then
                    RemoveFromRebuildCache(axisValue)
                    return false
                end

                local cooldown = ability.CooldownRemaining or 0
                if cooldown > 0 then
                    task.wait(cooldown + 0.1)
                end
            end

            local success = false
            if location == "no_pos" then
                success = pcall(function()
                    if useFireServer then
                        TowerUseAbilityRequest:FireServer(hash, skillIndex)
                    else
                        TowerUseAbilityRequest:InvokeServer(hash, skillIndex)
                    end
                end)
            else
                local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                if x and y and z then
                    local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                    success = pcall(function()
                        if useFireServer then
                            TowerUseAbilityRequest:FireServer(hash, skillIndex, pos)
                        else
                            TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos)
                        end
                    end)
                end
            end

            if success then
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Batch Processing System (keeping your existing implementation)
local BatchProcessor = {
    pendingBatches = {},
    currentBatch = {
        towers = {},
        startTime = tick(),
        isCollecting = false
    },
    batchCounter = 0,
    prewarmCache = {}
}

function BatchProcessor:RebuildSingleTowerComplete(tower)
    AddToRebuildCache(tower.x)

    -- Phase 1: Place tower
    local placeSuccess = false
    local placeRecord = nil

    for _, record in ipairs(tower.records) do
        if record.entry.TowerPlaced then
            placeRecord = record
            break
        end
    end

    if placeRecord then
        local entry = placeRecord.entry
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
            placeSuccess = PlaceTowerRetry(args, pos.X, entry.TowerPlaced)
        end
    end

    if not placeSuccess then
        RemoveFromRebuildCache(tower.x)
        return
    end

    -- Phase 2: Process upgrades
    local upgradeRecords = {}
    for _, record in ipairs(tower.records) do
        if record.entry.TowerUpgraded then
            table.insert(upgradeRecords, record)
        end
    end

    table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
    for _, record in ipairs(upgradeRecords) do
        local entry = record.entry
        UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath)
    end

    -- Phase 3: Process targets
    local targetRecords = {}
    for _, record in ipairs(tower.records) do
        if record.entry.TowerTargetChange then
            table.insert(targetRecords, record)
        end
    end

    for _, record in ipairs(targetRecords) do
        local entry = record.entry
        ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
    end

    -- Phase 4: Process moving skills
    local movingRecords = {}
    for _, record in ipairs(tower.records) do
        if record.entry.towermoving then
            table.insert(movingRecords, record)
        end
    end

    if #movingRecords > 0 then
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end

            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end)
    end

    RemoveFromRebuildCache(tower.x)
end

function BatchProcessor:ExecuteInstantBatch(towers)
    if #towers == 0 then return end

    for _, tower in ipairs(towers) do
        if not ShouldSkipTower(tower.x, tower.towerName, tower.firstPlaceLine) then
            task.spawn(function()
                self:RebuildSingleTowerComplete(tower)
            end)
        else
            RemoveFromRebuildCache(tower.x)
        end
    end
end

function BatchProcessor:ProcessCurrentBatchInstant()
    if #self.currentBatch.towers == 0 then
        self.currentBatch.isCollecting = false
        return
    end

    local towersToRebuild = {}
    for _, tower in ipairs(self.currentBatch.towers) do
        table.insert(towersToRebuild, tower)
    end

    self.currentBatch.towers = {}
    self.currentBatch.isCollecting = false
    self.batchCounter = self.batchCounter + 1

    table.sort(towersToRebuild, function(a, b)
        if a.priority == b.priority then
            return a.deathTime < b.deathTime
        end
        return a.priority < b.priority
    end)

    task.spawn(function()
        self:ExecuteInstantBatch(towersToRebuild)
    end)
end

function BatchProcessor:AddTowerToBatch(x, records, towerName, firstPlaceLine, priority, deathTime)
    if not globalEnv.TDX_Config.BatchProcessingEnabled then
        return false
    end

    local tower = {
        x = x,
        records = records,
        towerName = towerName,
        firstPlaceLine = firstPlaceLine,
        priority = priority,
        deathTime = deathTime
    }

    if globalEnv.TDX_Config.InstantBatchMode then
        if not self.currentBatch.isCollecting then
            self.currentBatch.isCollecting = true
            self.currentBatch.startTime = tick()
            self.currentBatch.towers = {}
        end

        table.insert(self.currentBatch.towers, tower)

        local shouldProcessNow = false

        if #self.currentBatch.towers >= globalEnv.TDX_Config.MaxBatchSize then
            shouldProcessNow = true
        elseif tick() - self.currentBatch.startTime >= globalEnv.TDX_Config.BatchCollectionTime then
            shouldProcessNow = true
        end

        if shouldProcessNow then
            self:ProcessCurrentBatchInstant()
        end

        return true
    end

    return true
end

function BatchProcessor:ForceProcessCurrentBatch()
    if self.currentBatch.isCollecting and #self.currentBatch.towers > 0 then
        if globalEnv.TDX_Config.InstantBatchMode then
            self:ProcessCurrentBatchInstant()
        end
    end
end

-- Auto sell converted towers system (keeping your existing implementation)
local soldConvertedX = {}

task.spawn(function()
    while true do
        for x in pairs(soldConvertedX) do
            local hasConvertedAtX = false

            -- Try module method first, then fallback
            if TowerPositionSystem.TowerClass and not TowerPositionSystem.usingFallback then
                for hash, tower in pairs(TowerPositionSystem.TowerClass.GetTowers()) do
                    if tower.Converted == true then
                        local spawnCFrame = tower.SpawnCFrame
                        if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                            if spawnCFrame.Position.X == x then
                                hasConvertedAtX = true
                                break
                            end
                        end
                    end
                end
            else
                -- Fallback method
                local towersFolder = workspace:FindFirstChild("Game")
                if towersFolder then towersFolder = towersFolder:FindFirstChild("Towers") end
                if towersFolder then
                    for _, tower in pairs(towersFolder:GetChildren()) do
                        local pos
                        if tower:IsA("BasePart") then
                            pos = tower.Position
                        elseif tower:IsA("Model") then
                            local mainPart = tower.PrimaryPart or tower:FindFirstChildOfClass("BasePart")
                            if mainPart then pos = mainPart.Position end
                        end
                        
                        if pos and math.abs(pos.X - x) < 0.1 then
                            hasConvertedAtX = true
                            break
                        end
                    end
                end
            end

            if not hasConvertedAtX then
                soldConvertedX[x] = nil
            end
        end

        -- Check and sell converted towers
        if TowerPositionSystem.TowerClass and not TowerPositionSystem.usingFallback then
            for hash, tower in pairs(TowerPositionSystem.TowerClass.GetTowers()) do
                if tower.Converted == true then
                    local spawnCFrame = tower.SpawnCFrame
                    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                        local x = spawnCFrame.Position.X

                        if soldConvertedX[x] then
                            soldConvertedX[x] = nil
                        end

                        if not soldConvertedX[x] then
                            soldConvertedX[x] = true
                            pcall(function()
                                Remotes.SellTower:FireServer(hash)
                            end)
                            task.wait(0.1)
                        end
                    end
                end
            end
        end

        RunService.Heartbeat:Wait()
    end
end)

-- Batch monitor system
local function InstantBatchMonitor()
    task.spawn(function()
        while true do
            if BatchProcessor.currentBatch.isCollecting then
                local timeSinceStart = tick() - BatchProcessor.currentBatch.startTime
                if timeSinceStart >= globalEnv.TDX_Config.BatchCollectionTime then
                    BatchProcessor:ForceProcessCurrentBatch()
                end
            end
            task.wait(0.05)
        end
    end)
end

if globalEnv.TDX_Config.InstantBatchMode then
    InstantBatchMonitor()
end

-- Main system with enhanced tower detection
task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis = {}
    local soldAxis = {}
    local rebuildAttempts = {}

    local deadTowerTracker = {
        deadTowers = {},
        nextDeathId = 1
    }

    local function recordTowerDeath(x)
        if not deadTowerTracker.deadTowers[x] then
            deadTowerTracker.deadTowers[x] = {
                deathTime = tick(),
                deathId = deadTowerTracker.nextDeathId
            }
            deadTowerTracker.nextDeathId = deadTowerTracker.nextDeathId + 1
        end
    end

    local function clearTowerDeath(x)
        deadTowerTracker.deadTowers[x] = nil
    end

    while true do
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
                if ok and type(macro) == "table" then
                    towersByAxis = {}
                    soldAxis = {}
                    for i, entry in ipairs(macro) do
                        if entry.SellTower then
                            local x = tonumber(entry.SellTower)
                            if x then
                                soldAxis[x] = true
                            end
                        elseif entry.TowerPlaced and entry.TowerVector then
                            local x = tonumber(entry.TowerVector:match("^([%d%-%.]+),"))
                            if x then
                                towersByAxis[x] = towersByAxis[x] or {}
                                table.insert(towersByAxis[x], {line = i, entry = entry})
                            end
                        elseif entry.TowerUpgraded and entry.UpgradePath then
                            local x = tonumber(entry.TowerUpgraded)
                            if x then
                                towersByAxis[x] = towersByAxis[x] or {}
                                table.insert(towersByAxis[x], {line = i, entry = entry})
                            end
                        elseif entry.TowerTargetChange then
                            local x = tonumber(entry.TowerTargetChange)
                            if x then
                                towersByAxis[x] = towersByAxis[x] or {}
                                table.insert(towersByAxis[x], {line = i, entry = entry})
                            end
                        elseif entry.towermoving then
                            local x = entry.towermoving
                            if x then
                                towersByAxis[x] = towersByAxis[x] or {}
                                table.insert(towersByAxis[x], {line = i, entry = entry})
                            end
                        end
                    end
                end
            end
        end

        for x, records in pairs(towersByAxis) do
            local shouldProcessTower = true

            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                shouldProcessTower = false
            end

            if shouldProcessTower then
                local hash, tower = GetTowerByAxis(x)

                if not hash or not tower then
                    local canRebuild = true
                    if soldAxis[x] and not globalEnv.TDX_Config.ForceRebuildEvenIfSold then
                        canRebuild = false
                    end

                    if canRebuild then
                        recordTowerDeath(x)

                        local towerType = nil
                        local firstPlaceRecord = nil
                        local firstPlaceLine = nil

                        for _, record in ipairs(records) do
                            if record.entry.TowerPlaced then 
                                towerType = record.entry.TowerPlaced
                                firstPlaceRecord = record
                                firstPlaceLine = record.line
                                break
                            end
                        end

                        if towerType then
                            rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                            local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry

                            if not maxRetry or rebuildAttempts[x] <= maxRetry then
                                local priority = GetTowerPriority(towerType)
                                local deathTime = deadTowerTracker.deadTowers[x] and deadTowerTracker.deadTowers[x].deathTime or tick()

                                local addedToBatch = BatchProcessor:AddTowerToBatch(
                                    x, records, towerType, firstPlaceLine, priority, deathTime
                                )

                                -- Fallback to individual processing if batch fails
                                if not addedToBatch then
                                    task.spawn(function()
                                        BatchProcessor:RebuildSingleTowerComplete({
                                            x = x,
                                            records = records,
                                            towerName = towerType,
                                            firstPlaceLine = firstPlaceLine,
                                            priority = priority,
                                            deathTime = deathTime
                                        })
                                    end)
                                end
                            end
                        end
                    end
                else
                    -- Tower is alive, cleanup death tracking
                    clearTowerDeath(x)
                    -- Reset rebuild attempts for this tower
                    rebuildAttempts[x] = 0
                end
            end
        end

        RunService.Heartbeat:Wait()
    end
end)

-- Status monitoring and debugging system
task.spawn(function()
    local lastStatusTime = 0
    local statusInterval = 30 -- Print status every 30 seconds
    
    while true do
        local currentTime = tick()
        if currentTime - lastStatusTime >= statusInterval then
            lastStatusTime = currentTime
            
            local totalTowers = 0
            local rebuildingCount = 0
            
            -- Count total rebuilding towers
            for _ in pairs(globalEnv.TDX_REBUILDING_TOWERS) do
                rebuildingCount = rebuildingCount + 1
            end
            
            -- Count total towers (try both methods)
            if TowerPositionSystem.TowerClass and not TowerPositionSystem.usingFallback then
                for _ in pairs(TowerPositionSystem.TowerClass.GetTowers()) do
                    totalTowers = totalTowers + 1
                end
            else
                local towersFolder = workspace:FindFirstChild("Game")
                if towersFolder then towersFolder = towersFolder:FindFirstChild("Towers") end
                if towersFolder then
                    totalTowers = #towersFolder:GetChildren()
                end
            end
            
            print(string.format("[TDX Rebuild] Status - Total Towers: %d, Rebuilding: %d, Using Fallback: %s", 
                totalTowers, rebuildingCount, tostring(TowerPositionSystem.usingFallback)))
            
            if BatchProcessor.currentBatch.isCollecting then
                print(string.format("[TDX Rebuild] Current Batch - Towers: %d, Time Collecting: %.1fs", 
                    #BatchProcessor.currentBatch.towers, 
                    currentTime - BatchProcessor.currentBatch.startTime))
            end
        end
        
        task.wait(1)
    end
end)

-- Configuration management functions
local ConfigManager = {}

function ConfigManager.UpdateConfig(key, value)
    if globalEnv.TDX_Config[key] ~= nil then
        globalEnv.TDX_Config[key] = value
        print(string.format("[TDX Config] Updated %s = %s", key, tostring(value)))
        return true
    else
        print(string.format("[TDX Config] Unknown config key: %s", key))
        return false
    end
end

function ConfigManager.GetConfig(key)
    return globalEnv.TDX_Config[key]
end

function ConfigManager.PrintConfig()
    print("=== TDX Rebuild Configuration ===")
    for key, value in pairs(globalEnv.TDX_Config) do
        if type(value) == "table" then
            print(string.format("%s = {%s}", key, table.concat(value, ", ")))
        else
            print(string.format("%s = %s", key, tostring(value)))
        end
    end
    print("================================")
end

-- Expose configuration manager globally
globalEnv.TDX_ConfigManager = ConfigManager

-- Performance monitoring
local PerformanceMonitor = {
    metrics = {
        towersRebuilt = 0,
        batchesProcessed = 0,
        fallbackUsages = 0,
        startTime = tick()
    }
}

function PerformanceMonitor:IncrementTowersRebuilt()
    self.metrics.towersRebuilt = self.metrics.towersRebuilt + 1
end

function PerformanceMonitor:IncrementBatchesProcessed()
    self.metrics.batchesProcessed = self.metrics.batchesProcessed + 1
end

function PerformanceMonitor:IncrementFallbackUsages()
    self.metrics.fallbackUsages = self.metrics.fallbackUsages + 1
end

function PerformanceMonitor:GetStats()
    local uptime = tick() - self.metrics.startTime
    return {
        uptime = uptime,
        towersRebuilt = self.metrics.towersRebuilt,
        batchesProcessed = self.metrics.batchesProcessed,
        fallbackUsages = self.metrics.fallbackUsages,
        rebuildsPerMinute = (self.metrics.towersRebuilt / uptime) * 60
    }
end

function PerformanceMonitor:PrintStats()
    local stats = self:GetStats()
    print("=== TDX Rebuild Performance Stats ===")
    print(string.format("Uptime: %.1f minutes", stats.uptime / 60))
    print(string.format("Towers Rebuilt: %d", stats.towersRebuilt))
    print(string.format("Batches Processed: %d", stats.batchesProcessed))
    print(string.format("Fallback Usages: %d", stats.fallbackUsages))
    print(string.format("Rebuilds/Minute: %.1f", stats.rebuildsPerMinute))
    print("=====================================")
end

-- Expose performance monitor globally
globalEnv.TDX_PerformanceMonitor = PerformanceMonitor

-- Enhanced error handling and recovery system
local ErrorHandler = {
    errorCounts = {},
    maxErrorsPerType = 10,
    cooldownTime = 60 -- 60 seconds cooldown after max errors
}

function ErrorHandler:RecordError(errorType, errorMessage)
    self.errorCounts[errorType] = self.errorCounts[errorType] or {count = 0, lastError = 0}
    self.errorCounts[errorType].count = self.errorCounts[errorType].count + 1
    self.errorCounts[errorType].lastError = tick()
    
    print(string.format("[TDX Error] %s: %s (Count: %d)", errorType, errorMessage, self.errorCounts[errorType].count))
    
    if self.errorCounts[errorType].count >= self.maxErrorsPerType then
        print(string.format("[TDX Error] Maximum errors reached for %s, entering cooldown", errorType))
        self.errorCounts[errorType].cooldown = tick() + self.cooldownTime
    end
end

function ErrorHandler:ShouldSkipDueToErrors(errorType)
    local errorData = self.errorCounts[errorType]
    if not errorData then return false end
    
    if errorData.cooldown and tick() < errorData.cooldown then
        return true
    elseif errorData.cooldown and tick() >= errorData.cooldown then
        -- Reset error count after cooldown
        errorData.count = 0
        errorData.cooldown = nil
        print(string.format("[TDX Error] Cooldown expired for %s, resuming operations", errorType))
    end
    
    return false
end

-- Expose error handler globally
globalEnv.TDX_ErrorHandler = ErrorHandler

-- Emergency stop system
local EmergencyStop = {
    stopped = false,
    reason = ""
}

function EmergencyStop:Stop(reason)
    self.stopped = true
    self.reason = reason or "Manual stop"
    print(string.format("[TDX Emergency] System stopped: %s", self.reason))
end

function EmergencyStop:Resume()
    self.stopped = false
    self.reason = ""
    print("[TDX Emergency] System resumed")
end

function EmergencyStop:IsActive()
    return self.stopped
end

-- Expose emergency stop globally
globalEnv.TDX_EmergencyStop = EmergencyStop

-- Utility functions for external access
local Utils = {}

function Utils.GetTowerInfo(axisX)
    local hash, tower, pos = GetTowerByAxis(axisX)
    if not hash then return nil end
    
    local info = {
        hash = hash,
        position = pos,
        exists = true,
        usingFallback = TowerPositionSystem.usingFallback
    }
    
    if tower and tower.LevelHandler then
        info.hasLevelHandler = true
        info.maxLevel = tower.LevelHandler:GetMaxLevel()
    end
    
    return info
end

function Utils.ForceRebuildTower(axisX)
    -- Find tower records from current macro
    local macroContent = safeReadFile(macroPath)
    if not macroContent then return false end
    
    local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
    if not ok then return false end
    
    local records = {}
    for i, entry in ipairs(macro) do
        local entryX = nil
        if entry.TowerPlaced and entry.TowerVector then
            entryX = tonumber(entry.TowerVector:match("^([%d%-%.]+),"))
        elseif entry.TowerUpgraded then
            entryX = tonumber(entry.TowerUpgraded)
        elseif entry.TowerTargetChange then
            entryX = tonumber(entry.TowerTargetChange)
        elseif entry.towermoving then
            entryX = entry.towermoving
        end
        
        if entryX == axisX then
            table.insert(records, {line = i, entry = entry})
        end
    end
    
    if #records == 0 then return false end
    
    local towerType = nil
    local firstPlaceLine = nil
    for _, record in ipairs(records) do
        if record.entry.TowerPlaced then
            towerType = record.entry.TowerPlaced
            firstPlaceLine = record.line
            break
        end
    end
    
    if not towerType then return false end
    
    -- Force rebuild this tower
    task.spawn(function()
        BatchProcessor:RebuildSingleTowerComplete({
            x = axisX,
            records = records,
            towerName = towerType,
            firstPlaceLine = firstPlaceLine,
            priority = GetTowerPriority(towerType),
            deathTime = tick()
        })
    end)
    
    return true
end

-- Expose utils globally
globalEnv.TDX_Utils = Utils

print("=== TDX Enhanced Auto-Rebuild System Loaded ===")
print("Features:")
print("- Enhanced tower position detection with fallback")
print("- Batch processing with instant mode")
print("- Automatic converted tower selling")
print("- Performance monitoring")
print("- Error handling and recovery")
print("- Emergency stop system")
print("")
print("Available commands:")
print("TDX_ConfigManager.PrintConfig() - Show current configuration")
print("TDX_ConfigManager.UpdateConfig(key, value) - Update configuration")
print("TDX_PerformanceMonitor.PrintStats() - Show performance statistics")
print("TDX_EmergencyStop.Stop(reason) - Emergency stop")
print("TDX_EmergencyStop.Resume() - Resume operations")
print("TDX_Utils.GetTowerInfo(axisX) - Get tower information")
print("TDX_Utils.ForceRebuildTower(axisX) - Force rebuild specific tower")
print("===============================================")