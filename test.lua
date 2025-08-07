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

-- Cấu hình mặc định với logic sửa lỗi
local defaultConfig = {
    ["RebuildPlaceDelay"] = 0.1,
    ["MaxConcurrentRebuilds"] = 10,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false, -- SỬA: Mặc định false để tránh lỗi
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.1,
    ["ParallelUpgrades"] = true,
    ["UpgradeDelay"] = 0.05,
    ["PlaceTimeout"] = 2,
    ["UpgradeTimeout"] = 2,
    ["RebuildDetectionInterval"] = 0,
    ["SoldTowerTrackingEnabled"] = true, -- MỚI: Cho phép tắt tracking sold towers
    -- SKIP CONFIGURATIONS
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

-- THÊM: Khởi tạo cache với sold tower tracking được tối ưu
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}
globalEnv.TDX_REBUILD_LOCKS = globalEnv.TDX_REBUILD_LOCKS or {}
globalEnv.TDX_SOLD_TOWERS = globalEnv.TDX_SOLD_TOWERS or {} -- MỚI: Track towers đã sell

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- Đọc file an toàn
local function safeReadFile(path)
    if readfile and isfile and isfile(path) then
        local ok, res = pcall(readfile, path)
        if ok then return res end
    end
    return nil
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
if not TowerClass then error("Không thể load TowerClass!") end

-- MỚI: Thread-safe lock system với sold tower support
local function AcquireRebuildLock(axisX)
    if globalEnv.TDX_REBUILD_LOCKS[axisX] then
        return false -- Already locked
    end
    globalEnv.TDX_REBUILD_LOCKS[axisX] = true
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
    return true
end

local function ReleaseRebuildLock(axisX)
    globalEnv.TDX_REBUILD_LOCKS[axisX] = nil
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
end

local function IsRebuildLocked(axisX)
    return globalEnv.TDX_REBUILD_LOCKS[axisX] == true
end

-- MỚI: Sold tower tracking functions
local function MarkTowerAsSold(axisX)
    globalEnv.TDX_SOLD_TOWERS[axisX] = {
        soldTime = tick(),
        confirmed = true
    }
end

local function IsTowerSold(axisX)
    return globalEnv.TDX_SOLD_TOWERS[axisX] and globalEnv.TDX_SOLD_TOWERS[axisX].confirmed
end

local function ClearSoldTowerMark(axisX)
    globalEnv.TDX_SOLD_TOWERS[axisX] = nil
end

-- MỚI: Tower sell detection system
local lastKnownTowers = {}

local function UpdateTowerTracking()
    local currentTowers = {}
    
    -- Get current towers
    for hash, tower in pairs(TowerClass.GetTowers()) do
        if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
            local x = tower.SpawnCFrame.Position.X
            currentTowers[x] = {
                hash = hash,
                tower = tower,
                exists = true
            }
        end
    end
    
    -- Check for towers that disappeared (potentially sold)
    for x, oldTowerData in pairs(lastKnownTowers) do
        if not currentTowers[x] then
            -- Tower disappeared - could be death or sell
            -- We'll mark as potentially sold, but not confirmed until we detect actual sell command
            if not IsTowerSold(x) then
                -- Tower died naturally, not sold
                -- Allow rebuild if not in sold list
            end
        end
    end
    
    -- Update tracking
    lastKnownTowers = currentTowers
end

-- ==== IMPROVED AUTO SELL CONVERTED TOWERS ====
local soldConvertedX = {}

task.spawn(function()
    while true do
        -- Update tower tracking for sell detection
        if globalEnv.TDX_Config.SoldTowerTrackingEnabled then
            UpdateTowerTracking()
        end
        
        -- Handle converted towers
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                local spawnCFrame = tower.SpawnCFrame
                if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                    local pos = spawnCFrame.Position
                    local x = pos.X

                    if soldConvertedX[x] then
                        soldConvertedX[x] = nil
                    end

                    if not soldConvertedX[x] then
                        pcall(function()
                            Remotes.SellTower:FireServer(hash)
                        end)
                        soldConvertedX[x] = true
                        -- MỚI: Mark as sold to prevent rebuild
                        MarkTowerAsSold(x)
                        task.wait(globalEnv.TDX_Config.AutoSellConvertDelay)
                    end
                end
            end
        end
        RunService.Heartbeat:Wait()
    end
end)

-- MỚI: Hook into sell commands to track manual sells
local originalFireServer = nil
local originalInvokeServer = nil

local function setupSellTracking()
    if not hookfunction then return end
    
    -- Hook FireServer để detect sell commands
    pcall(function()
        if not originalFireServer then
            originalFireServer = hookfunction(game.ReplicatedStorage.Remotes.SellTower.FireServer, function(self, hash, ...)
                -- Track tower being sold
                if hash then
                    for towerHash, tower in pairs(TowerClass.GetTowers()) do
                        if towerHash == hash and tower.SpawnCFrame then
                            local x = tower.SpawnCFrame.Position.X
                            MarkTowerAsSold(x)
                            break
                        end
                    end
                end
                return originalFireServer(self, hash, ...)
            end)
        end
    end)
end

-- Setup sell tracking nếu có hookfunction
if hookfunction then
    setupSellTracking()
end

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

-- ==================== SKIP LOGIC ====================
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

-- MỚI: Improved should rebuild logic
local function ShouldRebuildTower(axisX)
    local config = globalEnv.TDX_Config
    
    -- Check if tower was sold
    if IsTowerSold(axisX) then
        if config.ForceRebuildEvenIfSold then
            -- Force rebuild even if sold - clear the sold mark
            ClearSoldTowerMark(axisX)
            return true
        else
            -- Don't rebuild sold towers
            return false
        end
    end
    
    -- Tower died naturally, allow rebuild
    return true
end

-- Optimized place tower với timeout
local function PlaceTowerEntry(entry)
    local vecTab = {}
    for c in tostring(entry.TowerVector):gmatch("[^,%s]+") do 
        table.insert(vecTab, tonumber(c)) 
    end
    if #vecTab ~= 3 then return false end

    local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
    local axisX = pos.X

    WaitForCash(entry.TowerPlaceCost or 0)

    local args = {
        tonumber(entry.TowerA1), 
        entry.TowerPlaced, 
        pos, 
        tonumber(entry.Rotation or 0)
    }

    local success = pcall(function() 
        Remotes.PlaceTower:InvokeServer(unpack(args)) 
    end)

    if success then
        local startTime = tick()
        local timeout = globalEnv.TDX_Config.PlaceTimeout or 2
        repeat 
            RunService.Heartbeat:Wait()
        until tick() - startTime > timeout or GetTowerByAxis(pos.X)

        if GetTowerByAxis(pos.X) then 
            -- MỚI: Clear sold mark when tower is successfully placed
            ClearSoldTowerMark(axisX)
            task.wait(globalEnv.TDX_Config.RebuildPlaceDelay)
            return true
        end
    end

    return false
end

-- Function để lấy cost upgrade hiện tại
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

-- Optimized upgrade tower với timeout
local function UpgradeTowerEntry(entry)
    local axis = tonumber(entry.TowerUpgraded)
    local path = entry.UpgradePath
    local maxAttempts = 3
    local attempts = 0
    local timeout = globalEnv.TDX_Config.UpgradeTimeout or 2

    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axis)
        if not hash or not tower then 
            RunService.Heartbeat:Wait()
            attempts = attempts + 1
            continue 
        end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then 
            return true 
        end

        WaitForCash(cost)

        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)

        if success then
            local startTime = tick()
            repeat
                RunService.Heartbeat:Wait()
                local _, t = GetTowerByAxis(axis)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                    return true 
                end
            until tick() - startTime > timeout
        end

        attempts = attempts + 1
        RunService.Heartbeat:Wait()
    end

    return false
end

-- Đổi target với retry logic
local function ChangeTargetEntry(entry)
    local axis = tonumber(entry.TowerTargetChange)
    local hash = GetTowerByAxis(axis)

    if not hash then return false end

    pcall(function()
        Remotes.ChangeQueryType:FireServer(hash, entry.TargetWanted)
    end)

    return true
end

-- Function để check xem skill có tồn tại không
local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end

    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

local function UseMovingSkillEntry(entry)
    local axisValue = entry.towermoving
    local skillIndex = entry.skillindex
    local location = entry.location

    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower then return false end

    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then 
        return false 
    end

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

    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
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

    return success
end

-- Parallel upgrade system
local function ParallelUpgradeSystem(upgradeRecords, axisX)
    if not globalEnv.TDX_Config.ParallelUpgrades then
        -- Fallback to sequential upgrades
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerEntry(entry) then
                return false
            end
            task.wait(globalEnv.TDX_Config.UpgradeDelay)
        end
        return true
    end

    -- Parallel upgrades with path separation
    local pathUpgrades = {[1] = {}, [2] = {}}
    
    for _, record in ipairs(upgradeRecords) do
        local entry = record.entry
        local path = entry.UpgradePath
        if path == 1 or path == 2 then
            table.insert(pathUpgrades[path], {record = record, entry = entry})
        end
    end

    -- Sort each path by line number
    for path = 1, 2 do
        table.sort(pathUpgrades[path], function(a, b) 
            return a.record.line < b.record.line 
        end)
    end

    -- Spawn parallel upgrade tasks for each path
    local upgradeResults = {}
    local upgradeTasks = {}

    for path = 1, 2 do
        if #pathUpgrades[path] > 0 then
            local task_handle = task.spawn(function()
                local pathSuccess = true
                for _, upgradeData in ipairs(pathUpgrades[path]) do
                    if not UpgradeTowerEntry(upgradeData.entry) then
                        pathSuccess = false
                        break
                    end
                    task.wait(globalEnv.TDX_Config.UpgradeDelay)
                end
                upgradeResults[path] = pathSuccess
            end)
            table.insert(upgradeTasks, task_handle)
        else
            upgradeResults[path] = true -- No upgrades for this path = success
        end
    end

    -- Wait for all upgrade tasks to complete
    local maxWaitTime = 10 -- Maximum wait time for upgrades
    local startTime = tick()
    while (not upgradeResults[1] and not upgradeResults[2]) and (tick() - startTime < maxWaitTime) do
        RunService.Heartbeat:Wait()
    end

    -- Check if both paths succeeded
    local success = (upgradeResults[1] ~= false) and (upgradeResults[2] ~= false)
    return success
end

-- Optimized rebuild sequence với parallel processing
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
        if not PlaceTowerEntry(entry) then
            rebuildSuccess = false
        end
    end

    -- Step 2: Apply moving skills ASAP when skills become available
    if rebuildSuccess and #movingRecords > 0 then
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end

            UseMovingSkillEntry(entry)
        end)
    end

    -- Step 3: Parallel upgrades
    if rebuildSuccess and #upgradeRecords > 0 then
        local axisX = placeRecord and tonumber(placeRecord.entry.TowerVector:match("^([%d%-%.]+),")) or 0
        rebuildSuccess = ParallelUpgradeSystem(upgradeRecords, axisX)
    end

    -- Step 4: Change targets
    if rebuildSuccess and #targetRecords > 0 then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetEntry(entry)
            task.wait(0.02) -- Minimal delay
        end
    end

    return rebuildSuccess
end

-- Fast parallel worker system
local function CreateRebuildWorker(workerId)
    task.spawn(function()
        while true do
            -- Check for available jobs in the global queue
            local job = nil
            
            -- Thread-safe job retrieval
            pcall(function()
                if globalEnv.TDX_REBUILD_QUEUE and #globalEnv.TDX_REBUILD_QUEUE > 0 then
                    job = table.remove(globalEnv.TDX_REBUILD_QUEUE, 1)
                end
            end)
            
            if job then
                local x = job.x
                local records = job.records
                local towerName = job.towerName
                local firstPlaceLine = job.firstPlaceLine

                -- Try to acquire lock
                if AcquireRebuildLock(x) then
                    -- Check if we should skip this tower
                    if not ShouldSkipTower(x, towerName, firstPlaceLine) then
                        local success = RebuildTowerSequence(records)
                        if success then
                            -- Reset retry counter on success
                            globalEnv.TDX_REBUILD_ATTEMPTS = globalEnv.TDX_REBUILD_ATTEMPTS or {}
                            globalEnv.TDX_REBUILD_ATTEMPTS[x] = 0
                        end
                    end
                    
                    -- Always release lock
                    ReleaseRebuildLock(x)
                end
            else
                -- No jobs available, wait briefly
                RunService.Heartbeat:Wait()
            end
        end
    end)
end

-- SỬA: Hàm chính với logic sold tower được sửa lỗi
task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis = {}
    
    -- Initialize global systems
    globalEnv.TDX_REBUILD_QUEUE = globalEnv.TDX_REBUILD_QUEUE or {}
    globalEnv.TDX_REBUILD_ATTEMPTS = globalEnv.TDX_REBUILD_ATTEMPTS or {}

    -- Create worker pool
    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do
        CreateRebuildWorker(i)
    end

    -- Fast macro reloading
    local function ReloadMacro()
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
                if ok and type(macro) == "table" then
                    towersByAxis = {}
                    for i, entry in ipairs(macro) do
                        if entry.TowerPlaced and entry.TowerVector then
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
    end

    -- Fast detection system với sold tower logic đã sửa
    local lastDetectionTime = 0
    
    while true do
        local currentTime = tick()
        
        -- Rate-limited macro reloading
        if currentTime - lastDetectionTime > 0.1 then -- 10 FPS detection rate
            ReloadMacro()
            lastDetectionTime = currentTime
        end

        -- Fast tower death detection với sold tower check
        for x, records in pairs(towersByAxis) do
            local hash, tower = GetTowerByAxis(x)
            if not hash or not tower then
                -- Tower is dead, check if we should rebuild
                if ShouldRebuildTower(x) and not IsRebuildLocked(x) then
                    globalEnv.TDX_REBUILD_ATTEMPTS[x] = (globalEnv.TDX_REBUILD_ATTEMPTS[x] or 0) + 1
                    local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry

                    if not maxRetry or globalEnv.TDX_REBUILD_ATTEMPTS[x] <= maxRetry then
                        local towerType = nil
                        local firstPlaceLine = nil

                        for _, record in ipairs(records) do
                            if record.entry.TowerPlaced then 
                                towerType = record.entry.TowerPlaced
                                firstPlaceLine = record.line
                                break
                            end
                        end

                        if towerType then
                            local priority = GetTowerPriority(towerType)
                            local job = { 
                                x = x, 
                                records = records, 
                                priority = priority,
                                deathTime = currentTime,
                                towerName = towerType,
                                firstPlaceLine = firstPlaceLine
                            }

                            -- Add to queue with priority sorting
                            table.insert(globalEnv.TDX_REBUILD_QUEUE, job)
                            table.sort(globalEnv.TDX_REBUILD_QUEUE, function(a, b) 
                                if a.priority == b.priority then
                                    return a.deathTime < b.deathTime
                                end
                                return a.priority < b.priority 
                            end)
                        end
                    end
                end
            else
                -- Tower is alive, reset attempts and clear sold mark if any
                globalEnv.TDX_REBUILD_ATTEMPTS[x] = 0
                ClearSoldTowerMark(x) -- Clear any lingering sold marks
                -- Remove from queue if exists
                for i = #globalEnv.TDX_REBUILD_QUEUE, 1, -1 do
                    if globalEnv.TDX_REBUILD_QUEUE[i].x == x then
                        table.remove(globalEnv.TDX_REBUILD_QUEUE, i)
                        break
                    end
                end
            end
        end

        -- High frequency heartbeat for fast detection
        RunService.Heartbeat:Wait()
    end
end)

print("✅ Fixed Rebuild System đã khởi động!")
print("🔧 Đã sửa lỗi ForceRebuildEvenIfSold")
print("📊 Sold tower tracking: " .. tostring(globalEnv.TDX_Config.SoldTowerTrackingEnabled))
print("⚡ Parallel processing: " .. tostring(globalEnv.TDX_Config.ParallelUpgrades))