local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/recorder_output.json"

-- Ronix compatibility function
local function getGlobalEnv()
    return getgenv and getgenv() or _G
end

-- Config
local defaultConfig = {
    MaxConcurrentRebuilds = 5,
    PriorityRebuildOrder = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ForceRebuildEvenIfSold = false,
    MaxRebuildRetry = nil,
    AutoSellConvertDelay = 0.2,
    PlaceMode = "Rewrite",
    SkipTowersAtAxis = {},
    SkipTowersByName = {"Slammer", "Toxicnator"},
    SkipTowersByLine = {},
    UseRealTimeDelays = true,
    MaxWaitTime = 5,
    FastPollingInterval = 0.03,
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- Real-time delay functions
local function preciseSleep(duration)
    if globalEnv.TDX_Config.UseRealTimeDelays then
        local endTime = tick() + duration
        while tick() < endTime do end
    else
        task.wait(duration)
    end
end

local function smartWait(condition, maxTime, pollInterval)
    maxTime = maxTime or globalEnv.TDX_Config.MaxWaitTime or 5
    pollInterval = pollInterval or globalEnv.TDX_Config.FastPollingInterval or 0.03
    
    local startTime = tick()
    while not condition() and (tick() - startTime) < maxTime do
        if globalEnv.TDX_Config.UseRealTimeDelays then
            preciseSleep(pollInterval)
        else
            task.wait(pollInterval)
        end
    end
    return condition()
end

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

-- Safe file read
local function safeReadFile(path)
    if readfile and isfile and isfile(path) then
        local ok, res = pcall(readfile, path)
        if ok then return res end
    end
    return nil
end

-- Safe require
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while (tick() - startTime) < timeout do
        local ok, mod = pcall(require, path)
        if ok and mod then return mod end
        preciseSleep(0.1)
    end
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

local TowerClass = LoadTowerClass()
if not TowerClass then error("Cannot load TowerClass!") end

-- Cache management
local function AddToRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
end

local function RemoveFromRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
end

-- Auto sell converted towers
local soldConvertedX = {}

task.spawn(function()
    while true do
        -- Cleanup tracking
        for x in pairs(soldConvertedX) do
            local hasConvertedAtX = false
            for hash, tower in pairs(TowerClass.GetTowers()) do
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
            if not hasConvertedAtX then
                soldConvertedX[x] = nil
            end
        end

        -- Check and sell converted towers
        for hash, tower in pairs(TowerClass.GetTowers()) do
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
                        preciseSleep(0.1)
                    end
                end
            end
        end

        if globalEnv.TDX_Config.UseRealTimeDelays then
            preciseSleep(0.1)
        else
            RunService.Heartbeat:Wait()
        end
    end
end)

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

local function GetTowerByAxis(axisX)
    return GetTowerHashBySpawnX(axisX)
end

local function WaitForCash(amount)
    return smartWait(function()
        return cash.Value >= amount
    end, 30)
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
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

-- Get upgrade cost
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

-- Place tower with retry
local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    AddToRebuildCache(axisValue)
    
    while attempts < maxAttempts do
        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        
        if success then
            local placed = smartWait(function()
                return GetTowerByAxis(axisValue) ~= nil
            end, 3)
            
            if placed then 
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        
        attempts = attempts + 1
        preciseSleep(0.05)
    end
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Upgrade tower with retry
local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    AddToRebuildCache(axisValue)
    
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            preciseSleep(0.05)
            attempts = attempts + 1
        else
            local before = tower.LevelHandler:GetLevelOnPath(path)
            local cost = GetCurrentUpgradeCost(tower, path)
            if not cost then 
                RemoveFromRebuildCache(axisValue)
                return true 
            end
            
            if not WaitForCash(cost) then
                RemoveFromRebuildCache(axisValue)
                return false
            end
            
            local success = pcall(function()
                Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
            end)
            
            if success then
                local upgraded = smartWait(function()
                    local _, t = GetTowerByAxis(axisValue)
                    return t and t.LevelHandler:GetLevelOnPath(path) > before
                end, 3)
                
                if upgraded then 
                    RemoveFromRebuildCache(axisValue)
                    return true 
                end
            end
            
            attempts = attempts + 1
            preciseSleep(0.05)
        end
    end
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Change target with retry
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
        preciseSleep(0.03)
    end
    RemoveFromRebuildCache(axisValue)
end

-- Check if skill exists
local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end
    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

-- Use moving skill with retry
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
            if not tower.AbilityHandler then
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then
                preciseSleep(cooldown + 0.1)
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
        preciseSleep(0.05)
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Parallel rebuild tower sequence
local function RebuildTowerSequence(records)
    local placeRecord = nil
    local upgradeRecords = {}
    local targetRecords = {}
    local movingRecords = {}

    for _, record in ipairs(records) do
        local entry = record.entry
        if entry.TowerPlaced then
            placeRecord = record
        elseif entry.TowerUpgraded then
            table.insert(upgradeRecords, record)
        elseif entry.TowerTargetChange then
            table.insert(targetRecords, record)
        elseif entry.towermoving then
            table.insert(movingRecords, record)
        end
    end

    local rebuildSuccess = true

    -- Step 1: Place tower
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
            if not WaitForCash(entry.TowerPlaceCost) then
                return false
            end
            if not PlaceTowerRetry(args, pos.X, entry.TowerPlaced) then
                rebuildSuccess = false
            end
        end
    end

    if not rebuildSuccess then
        return false
    end

    -- Step 2: Parallel processing
    local completedTasks = {}
    local totalTasks = 0

    -- Moving Skills Task
    if #movingRecords > 0 then
        totalTasks = totalTasks + 1
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            local skillReady = smartWait(function()
                return HasSkill(entry.towermoving, entry.skillindex)
            end, 10)

            if skillReady then
                UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
            end
            
            completedTasks["moving"] = true
        end)
    end

    -- Upgrades Task
    if #upgradeRecords > 0 then
        totalTasks = totalTasks + 1
        task.spawn(function()
            table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
            
            for _, record in ipairs(upgradeRecords) do
                local entry = record.entry
                if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then
                    completedTasks["upgrades"] = false
                    return
                end
                preciseSleep(0.05)
            end
            
            completedTasks["upgrades"] = true
        end)
    end

    -- Target Changes Task
    if #targetRecords > 0 then
        totalTasks = totalTasks + 1
        task.spawn(function()
            preciseSleep(0.2)
            
            for _, record in ipairs(targetRecords) do
                local entry = record.entry
                ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
                preciseSleep(0.03)
            end
            
            completedTasks["targets"] = true
        end)
    end

    -- Wait for all tasks
    if totalTasks > 0 then
        local maxWait = 30
        local waited = smartWait(function()
            local completed = 0
            for _, status in pairs(completedTasks) do
                if status == true then
                    completed = completed + 1
                elseif status == false then
                    return true
                end
            end
            return completed >= totalTasks
        end, maxWait)
        
        if completedTasks["upgrades"] == false then
            rebuildSuccess = false
        end
    end

    return rebuildSuccess
end

-- Main system
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

    local jobQueue = {}
    local activeJobs = {}
    local maxConcurrentJobs = globalEnv.TDX_Config.MaxConcurrentRebuilds

    local function ParallelRebuildWorker(workerId)
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records
                    local towerName = job.towerName
                    local firstPlaceLine = job.firstPlaceLine

                    if not ShouldSkipTower(x, towerName, firstPlaceLine) then
                        local success = RebuildTowerSequence(records)
                        
                        if success then
                            rebuildAttempts[x] = 0
                            clearTowerDeath(x)
                        end
                    else
                        rebuildAttempts[x] = 0
                        clearTowerDeath(x)
                    end

                    activeJobs[x] = nil
                else
                    preciseSleep(0.1)
                end
            end
        end)
    end

    -- Initialize workers
    for i = 1, maxConcurrentJobs do
        ParallelRebuildWorker(i)
    end

    while true do
        -- Reload macro
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

        -- Producer
        for x, records in pairs(towersByAxis) do
            local shouldProcessTower = true
            
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                shouldProcessTower = false
            end
            
            if shouldProcessTower then
                local hash, tower = GetTowerByAxis(x)
                
                if not hash or not tower then
                    if not activeJobs[x] then
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
                                    activeJobs[x] = true
                                    local priority = GetTowerPriority(towerType)
                                    table.insert(jobQueue, { 
                                        x = x, 
                                        records = records, 
                                        priority = priority,
                                        deathTime = deadTowerTracker.deadTowers[x] and deadTowerTracker.deadTowers[x].deathTime or tick(),
                                        towerName = towerType,
                                        firstPlaceLine = firstPlaceLine
                                    })

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
                    clearTowerDeath(x)
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

        preciseSleep(0.1)
    end
end)