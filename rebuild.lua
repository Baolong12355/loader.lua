local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

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

-- Configuration with defaults matching main runner
local defaultConfig = {
    ["MacroRecordPath"] = "tdx/macros/recorder_output.json",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = true,
    ["MaxRebuildRetry"] = nil,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["RebuildCheckInterval"] = 0,
    ["MaxConcurrentRebuilds"] = 5,
    ["RebuildPlaceDelay"] = 0.3,
    ["MacroStepDelay"] = 0.1
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_REBUILD_Config = globalEnv.TDX_REBUILD_Config or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_REBUILD_Config[key] == nil then
        globalEnv.TDX_REBUILD_Config[key] = value
    end
end

local function getMaxAttempts()
    local placeMode = globalEnv.TDX_REBUILD_Config.PlaceMode or "Rewrite"
    if placeMode == "Ashed" then
        return 1
    elseif placeMode == "Rewrite" then
        return 10
    else
        return 1
    end
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local success, result = pcall(function() return require(path) end)
        if success and result then return result end
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

local TowerClass = LoadTowerClass()
if not TowerClass then 
    error("Không thể load TowerClass - vui lòng đảm bảo bạn đang trong game TDX")
end

-- ==== TÍCH HỢP AUTO SELL CONVERT (giống main runner) ====
local soldConvertedX = {}

task.spawn(function()
    while true do
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
                    end
                end
            end
        end
        task.wait(0.2)
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
        RunService.Heartbeat:Wait()
    end
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_REBUILD_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
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
                return true
            end
        end
        attempts = attempts + 1
        task.wait()
    end
    return false
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
        if not cost then return true end
        WaitForCash(cost)
        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        if success then
            local startTime = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return true end
            until tick() - startTime > 3
        end
        attempts = attempts + 1
        task.wait()
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
            return true
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    return false
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then
        return false
    end

    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if hash and tower then
            if not tower.AbilityHandler then
                return false
            end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                return false
            end

            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then
                task.wait(cooldown + 0.1)
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
                return true
            end
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    return false
end

-- Improved Rebuild System with advanced tracking
local function StartAdvancedRebuildSystem()
    local config = globalEnv.TDX_REBUILD_Config
    local macroPath = config.MacroRecordPath
    
    local rebuildAttempts = {}
    local soldPositions = {}
    local lastMacroHash = ""
    local towerRecords = {}

    -- Advanced tracking system
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

    -- Worker system with proper sequencing
    local jobQueue = {}
    local activeJobs = {}

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records

                    -- Organize records by type
                    local placeRecord = nil
                    local upgradeRecords = {}
                    local targetRecords = {}
                    local movingRecords = {}

                    for _, record in ipairs(records) do
                        local action = record.entry
                        if action.TowerPlaced then
                            placeRecord = record
                        elseif action.TowerUpgraded then
                            table.insert(upgradeRecords, record)
                        elseif action.TowerTargetChange then
                            table.insert(targetRecords, record)
                        elseif action.towermoving then
                            table.insert(movingRecords, record)
                        end
                    end

                    local rebuildSuccess = true

                    -- Step 1: Place tower
                    if placeRecord then
                        local action = placeRecord.entry
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
                            if PlaceTowerRetry(args, pos.X, action.TowerPlaced) then
                                task.wait(config.RebuildPlaceDelay or 0.3)
                            else
                                rebuildSuccess = false
                            end
                        end
                    end

                    -- Step 2: Upgrade towers
                    if rebuildSuccess then
                        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
                        for _, record in ipairs(upgradeRecords) do
                            local action = record.entry
                            if not UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath) then
                                rebuildSuccess = false
                                break
                            end
                            task.wait(0.1)
                        end
                    end

                    -- Step 3: Change targets
                    if rebuildSuccess then
                        for _, record in ipairs(targetRecords) do
                            local action = record.entry
                            ChangeTargetRetry(tonumber(action.TowerTargetChange), action.TargetWanted)
                            task.wait(0.05)
                        end
                    end

                    -- Step 4: Apply moving skills
                    if rebuildSuccess and #movingRecords > 0 then
                        task.wait(0.2)
                        local lastMovingRecord = movingRecords[#movingRecords]
                        local action = lastMovingRecord.entry
                        UseMovingSkillRetry(action.towermoving, action.skillindex, action.location)
                        task.wait(0.1)
                    end

                    -- Cleanup
                    if rebuildSuccess then
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

    -- Initialize workers
    for i = 1, config.MaxConcurrentRebuilds do
        RebuildWorker()
    end

    -- Main rebuild loop
    task.spawn(function()
        while true do
            -- Reload macro if changed
            if safeIsFile(macroPath) then
                local macroContent = safeReadFile(macroPath)
                if macroContent and #macroContent > 10 then
                    local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
                    if macroHash ~= lastMacroHash then
                        lastMacroHash = macroHash
                        local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
                        if ok and type(macro) == "table" then
                            towerRecords = {}
                            soldPositions = {}
                            
                            -- Process macro entries
                            for i, entry in ipairs(macro) do
                                if entry.SellTower then
                                    local x = tonumber(entry.SellTower)
                                    if x then
                                        soldPositions[x] = true
                                    end
                                elseif entry.TowerPlaced and entry.TowerVector then
                                    local vecTab = {}
                                    for coord in entry.TowerVector:gmatch("[^,%s]+") do
                                        table.insert(vecTab, tonumber(coord))
                                    end
                                    if #vecTab == 3 then
                                        local x = vecTab[1]
                                        towerRecords[x] = towerRecords[x] or {}
                                        table.insert(towerRecords[x], { line = i, entry = entry })
                                    end
                                elseif entry.TowerUpgraded then
                                    local x = tonumber(entry.TowerUpgraded)
                                    if x then
                                        towerRecords[x] = towerRecords[x] or {}
                                        table.insert(towerRecords[x], { line = i, entry = entry })
                                    end
                                elseif entry.TowerTargetChange then
                                    local x = tonumber(entry.TowerTargetChange)
                                    if x then
                                        towerRecords[x] = towerRecords[x] or {}
                                        table.insert(towerRecords[x], { line = i, entry = entry })
                                    end
                                elseif entry.towermoving then
                                    local x = entry.towermoving
                                    if x then
                                        towerRecords[x] = towerRecords[x] or {}
                                        table.insert(towerRecords[x], { line = i, entry = entry })
                                    end
                                end
                            end
                            print("[TDX Rebuild] Đã reload record mới: " .. macroPath)
                        end
                    end
                end
            end

            -- Check for dead towers and rebuild
            if next(towerRecords) then
                for x, records in pairs(towerRecords) do
                    local hash, tower = GetTowerByAxis(x)

                    if not hash or not tower then
                        -- Tower is dead
                        if not activeJobs[x] then
                            -- Check ForceRebuildEvenIfSold setting
                            if soldPositions[x] and not config.ForceRebuildEvenIfSold then
                                continue
                            end

                            recordTowerDeath(x)

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
                                rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                                local maxRetry = config.MaxRebuildRetry

                                if not maxRetry or rebuildAttempts[x] <= maxRetry then
                                    activeJobs[x] = true
                                    local priority = GetTowerPriority(towerType)
                                    table.insert(jobQueue, { 
                                        x = x, 
                                        records = records, 
                                        priority = priority,
                                        deathTime = deadTowerTracker.deadTowers[x] and deadTowerTracker.deadTowers[x].deathTime or tick()
                                    })

                                    -- Sort by priority, then by death time
                                    table.sort(jobQueue, function(a, b) 
                                       