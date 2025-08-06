local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

print("=== REBUILD SYSTEM STARTING ===")

local macroPath = "tdx/macros/recorder_output.json"

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

-- Cấu hình mặc định
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["PlaceMode"] = "Rewrite",
    -- SKIP CONFIGURATIONS
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {"Slammer", "Toxicnator"},
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

print("Config loaded:", globalEnv.TDX_Config)

-- Retry logic từ runner system
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

-- Lấy TowerClass
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

print("TowerClass loaded successfully")

-- Hàm quản lý cache rebuild
local function AddToRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
end

local function RemoveFromRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
end

local function IsInRebuildCache(axisX)
    return globalEnv.TDX_REBUILDING_TOWERS[axisX] == true
end

-- ==== AUTO SELL CONVERTED TOWERS ====
local soldConvertedX = {}

task.spawn(function()
    print("Auto-sell converted towers started")
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

        -- Check và sell converted towers
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
                        print("Sold converted tower at X:", x)
                        task.wait(0.1)
                    end
                end
            end
        end
        RunService.Heartbeat:Wait()
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

-- Retry functions
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
                print("Successfully placed tower:", towerName, "at X:", axisValue)
                return true
            end
        end
        attempts = attempts + 1
        print("Place attempt", attempts, "failed for", towerName, "at X:", axisValue)
        task.wait()
    end
    RemoveFromRebuildCache(axisValue)
    print("Failed to place tower:", towerName, "at X:", axisValue)
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
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then 
            RemoveFromRebuildCache(axisValue)
            return true 
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
                if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                    RemoveFromRebuildCache(axisValue)
                    print("Successfully upgraded tower at X:", axisValue, "path:", path)
                    return true 
                end
            until tick() - startTime > 3
        end
        attempts = attempts + 1
        task.wait()
    end
    RemoveFromRebuildCache(axisValue)
    print("Failed to upgrade tower at X:", axisValue, "path:", path)
    return false
end

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
            print("Changed target for tower at X:", axisValue, "to:", targetType)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
end

local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end
    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

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
                RemoveFromRebuildCache(axisValue)
                print("Used moving skill for tower at X:", axisValue)
                return true
            end
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Rebuild sequence
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
            WaitForCash(entry.TowerPlaceCost)
            if not PlaceTowerRetry(args, pos.X, entry.TowerPlaced) then
                rebuildSuccess = false
                print("Failed to place tower in rebuild sequence")
            end
        end
    end

    -- Step 2: Moving skills (asynchronous)
    if rebuildSuccess and #movingRecords > 0 then
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end

            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end)
    end

    -- Step 3: Upgrades
    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then
                rebuildSuccess = false
                print("Failed to upgrade tower in rebuild sequence")
                break
            end
            task.wait(0.1)
        end
    end

    -- Step 4: Target changes
    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
            task.wait(0.05)
        end
    end

    return rebuildSuccess
end

-- Main rebuild system
local function StartRebuildSystem()
    print("Starting rebuild system...")
    
    if not safeIsFile(macroPath) then 
        print("WARNING: Macro file not found at:", macroPath)
        return
    end
    
    local lastMacroHash = ""
    local towersByAxis = {}
    local soldAxis = {}
    local rebuildAttempts = {}

    -- Dead tower tracking
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
            print("Tower death recorded at X:", x)
        end
    end

    local function clearTowerDeath(x)
        if deadTowerTracker.deadTowers[x] then
            deadTowerTracker.deadTowers[x] = nil
            print("Tower death cleared at X:", x)
        end
    end

    -- Worker system
    local jobQueue = {}
    local activeJobs = {}

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records
                    local towerName = job.towerName
                    local firstPlaceLine = job.firstPlaceLine

                    print("Processing rebuild job for tower:", towerName, "at X:", x)

                    if not ShouldSkipTower(x, towerName, firstPlaceLine) then
                        if RebuildTowerSequence(records) then
                            rebuildAttempts[x] = 0
                            clearTowerDeath(x)
                            print("Rebuild successful for tower:", towerName, "at X:", x)
                        else
                            print("Rebuild failed for tower:", towerName, "at X:", x)
                        end
                    else
                        rebuildAttempts[x] = 0
                        clearTowerDeath(x)
                        print("Skipped tower:", towerName, "at X:", x)
                    end

                    activeJobs[x] = nil
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    -- Initialize workers
    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do
        RebuildWorker()
    end
    print("Initialized", globalEnv.TDX_Config.MaxConcurrentRebuilds, "rebuild workers")

    -- Main loop
    task.spawn(function()
        while true do
            -- Load macro file
            local macroContent = safeReadFile(macroPath)
            if macroContent and #macroContent > 10 then
                local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
                if macroHash ~= lastMacroHash then
                    lastMacroHash = macroHash
                    local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
                    if ok and type(macro) == "table" then
                        print("Loaded macro with", #macro, "entries")
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
                        
                        print("Parsed towers by axis:", #table.keys(towersByAxis or {}))
                    else
                        print("Failed to parse macro JSON")
                    end
                end
            end

            -- Check for dead towers and queue rebuilds
            for x, records in pairs(towersByAxis) do
                if globalEnv.TDX_Config.ForceRebuildEvenIfSold or not soldAxis[x] then
                    local hash, tower = GetTowerByAxis(x)
                    
                    if not hash or not tower then
                        if not activeJobs[x] then
                            if soldAxis[x] and not globalEnv.TDX_Config.ForceRebuildEvenIfSold then
                                goto continue
                            end

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
                                    
                                    print("Queued rebuild for", towerType, "at X:", x, "Priority:", priority)
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
                    ::continue::
                end
            end

            RunService.Heartbeat:Wait()
        end
    end)
end

-- Start the system
local success, err = pcall(StartRebuildSystem)
if not success then
    error("Lỗi Rebuild System: " .. tostring(err))
else
    print("=== REBUILD SYSTEM INITIALIZED SUCCESSFULLY ===")
end