local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/recorder_output.json"

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

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

local function safeReadFile(path)
    if readfile and isfile and isfile(path) then
        local ok, res = pcall(readfile, path)
        if ok then return res end
    end
    return nil
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = tick()
    while tick() - t0 < timeout do
        local ok, mod = pcall(require, path)
        if ok and mod then return mod end
        RunService.Heartbeat:Wait()
    end
    return nil
end

local TowerClassModule = player:FindFirstChild("PlayerScripts"):FindFirstChild("Client"):FindFirstChild("GameClass"):FindFirstChild("TowerClass")
local TowerClass = TowerClassModule and SafeRequire(TowerClassModule)

if not TowerClass then
    return
end

local function AddToRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
end

local function RemoveFromRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
end

local activeTowersTable = nil
local function fetchActiveTowerTable()
    if activeTowersTable then return activeTowersTable end
    for i = 1, 10 do
        local name, value = debug.getupvalue(TowerClass.GetTower, i)
        if type(value) == "table" then
            local firstKey, firstTower = next(value)
            if (firstTower and type(firstTower) == "table" and firstTower.SpawnCFrame and firstTower.Hash) or not firstKey then
                activeTowersTable = value
                return value
            end
        end
    end
    activeTowersTable = TowerClass.GetTowers()
    return activeTowersTable
end

task.spawn(function()
    local soldConvertedX = {}
    while true do
        local allTowers = fetchActiveTowerTable()
        if allTowers then
            for x in pairs(soldConvertedX) do
                local hasConvertedAtX = false
                for hash, tower in pairs(allTowers) do
                    if tower.Converted == true then
                        local spawnCFrame = tower.SpawnCFrame
                        if spawnCFrame and typeof(spawnCFrame) == "CFrame" and spawnCFrame.Position.X == x then
                            hasConvertedAtX = true
                            break
                        end
                    end
                end
                if not hasConvertedAtX then
                    soldConvertedX[x] = nil
                end
            end

            for hash, tower in pairs(allTowers) do
                if tower.Converted == true then
                    local spawnCFrame = tower.SpawnCFrame
                    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                        local x = spawnCFrame.Position.X
                        if not soldConvertedX[x] then
                            soldConvertedX[x] = true
                            pcall(Remotes.SellTower.FireServer, Remotes.SellTower, hash)
                        end
                    end
                end
            end
        end
        RunService.Heartbeat:Wait()
    end
end)

local function GetTowerByAxis(axisX)
    local allTowers = fetchActiveTowerTable()
    if allTowers then
        for hash, tower in pairs(allTowers) do
            local spawnCFrame = tower.SpawnCFrame
            if spawnCFrame and typeof(spawnCFrame) == "CFrame" and spawnCFrame.Position.X == axisX then
                return hash, tower
            end
        end
    end
    return nil, nil
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

local function ShouldSkipTower(axisX, towerName, firstPlaceLine)
    local config = globalEnv.TDX_Config
    if config.SkipTowersAtAxis then
        for _, skipAxis in ipairs(config.SkipTowersAtAxis) do if axisX == skipAxis then return true end end
    end
    if config.SkipTowersByName then
        for _, skipName in ipairs(config.SkipTowersByName) do if towerName == skipName then return true end end
    end
    if config.SkipTowersByLine and firstPlaceLine then
        for _, skipLine in ipairs(config.SkipTowersByLine) do if firstPlaceLine == skipLine then return true end end
    end
    return false
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    if tower.LevelHandler:GetLevelOnPath(path) >= tower.LevelHandler:GetMaxLevel() then return nil end
    local ok, baseCost = pcall(tower.LevelHandler.GetLevelUpgradeCost, tower.LevelHandler, path, 1)
    if not ok then return nil end
    local disc = 0
    local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

local function PlaceTowerRetry(args, axisValue)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)
    while attempts < maxAttempts do
        local success = pcall(Remotes.PlaceTower.InvokeServer, Remotes.PlaceTower, unpack(args))
        if success then
            local startTime = tick()
            repeat RunService.Heartbeat:Wait() until tick() - startTime > 3 or GetTowerByAxis(axisValue)
            if GetTowerByAxis(axisValue) then
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        attempts = attempts + 1
        RunService.Heartbeat:Wait()
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

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
        local beforeLevel = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then
            RemoveFromRebuildCache(axisValue)
            return true
        end
        WaitForCash(cost)
        local success = pcall(Remotes.TowerUpgradeRequest.FireServer, Remotes.TowerUpgradeRequest, hash, path, 1)
        if success then
            local startTime = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > beforeLevel then
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

local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(Remotes.ChangeQueryType.FireServer, Remotes.ChangeQueryType, hash, targetType)
            RemoveFromRebuildCache(axisValue)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
end

local function HasSkill(axisValue, skillIndex)
    local _, tower = GetTowerByAxis(axisValue)
    if not tower or not tower.AbilityHandler then return false end
    return tower.AbilityHandler:GetAbilityFromIndex(skillIndex) ~= nil
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then return false end
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    AddToRebuildCache(axisValue)
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if hash and tower and tower.AbilityHandler then
            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                RemoveFromRebuildCache(axisValue)
                return false
            end
            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then task.wait(cooldown + 0.1) end
            local success = false
            if location == "no_pos" then
                success = pcall(function()
                    if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex)
                    else TowerUseAbilityRequest:InvokeServer(hash, skillIndex) end
                end)
            else
                local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                if x and y and z then
                    local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                    success = pcall(function()
                        if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex, pos)
                        else TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos) end
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

local function RebuildTowerSequence(records)
    local placeRecord, lastTargetRecord, lastMovingRecord
    local upgradeRecords = {}

    for _, record in ipairs(records) do
        local entry = record.entry
        if entry.TowerPlaced then placeRecord = record
        elseif entry.TowerUpgraded then table.insert(upgradeRecords, record)
        elseif entry.TowerTargetChange then lastTargetRecord = record
        elseif entry.towermoving then lastMovingRecord = record
        end
    end
    
    local rebuildSuccess = true
    if placeRecord then
        local entry = placeRecord.entry
        local vecTab = {}
        for coord in entry.TowerVector:gmatch("[^,%s]+") do table.insert(vecTab, tonumber(coord)) end
        if #vecTab == 3 then
            local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
            local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
            WaitForCash(entry.TowerPlaceCost or 0)
            if not PlaceTowerRetry(args, pos.X) then
                rebuildSuccess = false
            end
        else
            rebuildSuccess = false
        end
    end

    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then
                rebuildSuccess = false
                break
            end
        end
    end

    if rebuildSuccess then
        task.wait(0.1)
        if lastMovingRecord then
            task.spawn(function()
                local entry = lastMovingRecord.entry
                local axisValue = tonumber(entry.towermoving)
                while not HasSkill(axisValue, entry.skillindex) do
                    RunService.Heartbeat:Wait()
                end
                UseMovingSkillRetry(axisValue, entry.skillindex, entry.location)
            end)
        end
        if lastTargetRecord then
            local entry = lastTargetRecord.entry
            ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
        end
    end

    return rebuildSuccess
end

task.spawn(function()
    local towersByAxisBlueprint = {}
    local soldTowersX = {}
    local rebuildAttempts = {}
    
    local deadTowerTracker = { deadTowers = {}, nextDeathId = 1 }

    local function recordTowerDeath(x)
        if not deadTowerTracker.deadTowers[x] then
            deadTowerTracker.deadTowers[x] = { deathTime = tick(), deathId = deadTowerTracker.nextDeathId }
            deadTowerTracker.nextDeathId = deadTowerTracker.nextDeathId + 1
        end
    end

    local function clearTowerDeath(x)
        deadTowerTracker.deadTowers[x] = nil
    end

    local jobQueue = {}
    local activeJobs = {}

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    if not ShouldSkipTower(x, job.towerName, job.firstPlaceLine) then
                        if RebuildTowerSequence(job.records) then
                            rebuildAttempts[x] = 0
                            clearTowerDeath(x)
                        end
                    else
                        rebuildAttempts[x] = 0
                        clearTowerDeath(x)
                    end
                    activeJobs[x] = nil
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end
    
    local function buildDataFromMacro()
        local content = safeReadFile(macroPath)
        if not content then return nil, nil end
        local success, allActions = pcall(HttpService.JSONDecode, HttpService, content)
        if not success then return nil, nil end
        
        local blueprint, soldList = {}, {}
        
        for i, entry in ipairs(allActions) do
            local x
            if entry.TowerPlaced then x = tonumber(entry.TowerVector:match("([^,]+)"))
            elseif entry.TowerUpgraded then x = tonumber(entry.TowerUpgraded)
            elseif entry.TowerTargetChange then x = tonumber(entry.TowerTargetChange)
            elseif entry.towermoving then x = tonumber(entry.towermoving)
            end
            if x then
                if not blueprint[x] then blueprint[x] = {} end
                table.insert(blueprint[x], {line = i, entry = entry})
            end
            if entry.SellTower then soldList[tonumber(entry.SellTower)] = true end
        end
        return blueprint, soldList
    end

    towersByAxisBlueprint, soldTowersX = buildDataFromMacro()
    if not towersByAxisBlueprint then return end
    fetchActiveTowerTable()

    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do
        RebuildWorker()
    end
    
    local TICK_RATE = 20
    local STEP = 1 / TICK_RATE
    local lastTime = os.clock()
    local accumulator = 0
    
    while true do
        local currentTime = os.clock()
        accumulator = accumulator + (currentTime - lastTime)
        lastTime = currentTime
        
        while accumulator >= STEP do
            local currentTowers = fetchActiveTowerTable()
            local activeTowersByX = {}
            if currentTowers then
                for hash, tower in pairs(currentTowers) do
                    local cf = tower.SpawnCFrame
                    if cf then activeTowersByX[cf.Position.X] = true end
                end
            end

            for x, records in pairs(towersByAxisBlueprint) do
                if not activeTowersByX[x] and not soldTowersX[x] and not activeJobs[x] then
                    recordTowerDeath(x)
                    local towerType, firstPlaceLine
                    for _, record in ipairs(records) do
                        if record.entry.TowerPlaced then 
                            towerType = record.entry.TowerPlaced
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
                                if a.priority == b.priority then return a.deathTime < b.deathTime end
                                return a.priority < b.priority 
                            end)
                        end
                    end
                end
            end
            
            accumulator = accumulator - STEP
        end
        
        RunService.Heartbeat:Wait()
    end
end)