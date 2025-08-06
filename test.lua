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

-- Cấu hình mặc định
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    -- SKIP CONFIGURATIONS
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {"Slammer", "Toxicnator"},
    ["SkipTowersByLine"] = {},
    -- LAG OPTIMIZATION CONFIG
    ["UseRealTimeDelays"] = true, -- Sử dụng thời gian thực thay vì frame-based
    ["MaxWaitTime"] = 5, -- Timeout tối đa cho mỗi action
    ["FastPollingInterval"] = 0.03, -- Polling nhanh hơn
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- ⚡ LAG-RESISTANT WAIT FUNCTIONS
local function preciseSleep(duration)
    if globalEnv.TDX_Config.UseRealTimeDelays then
        -- Sử dụng thời gian thực thay vì frame-based
        local endTime = tick() + duration
        while tick() < endTime do
            -- Không sử dụng wait/heartbeat, chỉ check thời gian thực
            if tick() >= endTime then break end
        end
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
if not TowerClass then error("Không thể load TowerClass!") end

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

-- ==== AUTO SELL CONVERTED TOWERS - REBUILD ====
local soldConvertedX = {}

task.spawn(function()
    while true do
        -- Cleanup: Xóa tracking cho X positions không còn có converted towers
        for x in pairs(soldConvertedX) do
            local hasConvertedAtX = false

            -- Check xem có tower nào converted tại X này không
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

            -- Nếu không có converted tower nào tại X này, xóa khỏi tracking
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

                    -- Sell nếu chưa tracking X này
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

        -- ⚡ Sử dụng real-time interval thay vì Heartbeat
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
    end, 30) -- Max 30 giây chờ tiền
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

    -- Skip theo axis X
    if config.SkipTowersAtAxis then
        for _, skipAxis in ipairs(config.SkipTowersAtAxis) do
            if axisX == skipAxis then
                return true
            end
        end
    end

    -- Skip theo tên tower
    if config.SkipTowersByName then
        for _, skipName in ipairs(config.SkipTowersByName) do
            if towerName == skipName then
                return true
            end
        end
    end

    -- Skip theo line number
    if config.SkipTowersByLine and firstPlaceLine then
        for _, skipLine in ipairs(config.SkipTowersByLine) do
            if firstPlaceLine == skipLine then
                return true
            end
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

-- ⚡ LAG-OPTIMIZED: Đặt tower với retry logic
local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    AddToRebuildCache(axisValue)
    
    while attempts < maxAttempts do
        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        
        if success then
            -- ⚡ Sử dụng smartWait thay vì polling thủ công
            local placed = smartWait(function()
                return GetTowerByAxis(axisValue) ~= nil
            end, 3)
            
            if placed then 
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        
        attempts = attempts + 1
        preciseSleep(0.05) -- Ngắn hơn và chính xác hơn
    end
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- ⚡ LAG-OPTIMIZED: Nâng cấp tower với retry logic
local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    AddToRebuildCache(axisValue)
    
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            preciseSleep(0.05) -- Chờ ngắn hơn
            attempts = attempts + 1
            continue 
        end
        
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
            -- ⚡ Sử dụng smartWait cho upgrade confirmation
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
    
    RemoveFromRebuildCache(axisValue)
    return false
end

-- ⚡ LAG-OPTIMIZED: Đổi target với retry logic
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
        preciseSleep(0.03) -- Nhanh hơn nhiều
    end
    RemoveFromRebuildCache(axisValue)
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

-- ⚡ LAG-OPTIMIZED: Function để sử dụng moving skill
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
                -- ⚡ Chờ cooldown chính xác hơn
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

-- Worker function được tối ưu theo runner system
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

    -- Step 2: Apply moving skills ASAP when skills become available
    if rebuildSuccess and #movingRecords > 0 then
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            -- ⚡ Wait for skill với timeout thay vì vòng lặp vô hạn
            local skillReady = smartWait(function()
                return HasSkill(entry.towermoving, entry.skillindex)
            end, 10) -- Max 10 giây chờ skill

            if skillReady then
                UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
            end
        end)
    end

    -- Step 3: Upgrade towers (in order) - Run in parallel with moving skills
    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then
                rebuildSuccess = false
                break
            end
            preciseSleep(0.05) -- Ngắn hơn nhiều
        end
    end

    -- Step 4: Change targets
    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
            preciseSleep(0.03) -- Siêu nhanh
        end
    end

    return rebuildSuccess
end

-- ⚡ LAG-OPTIMIZED: Hệ thống chính 
task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis = {}
    local soldAxis = {}
    local rebuildAttempts = {}

    -- Tracking system cho towers đã chết
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

    -- Worker system
    local jobQueue = {}
    local activeJobs = {}

    -- Worker function
    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records
                    local towerName = job.towerName
                    local firstPlaceLine = job.firstPlaceLine

                    -- Kiểm tra skip trước khi rebuild
                    if not ShouldSkipTower(x, towerName, firstPlaceLine) then
                        if RebuildTowerSequence(records) then
                            rebuildAttempts[x] = 0
                            clearTowerDeath(x)
                        end
                    else
                        rebuildAttempts[x] = 0
                        clearTowerDeath(x)
                    end

                    activeJobs[x] = nil
                else
                    -- ⚡ Sử dụng precise sleep thay vì Heartbeat
                    preciseSleep(0.1)
                end
            end
        end)
    end

    -- Khởi tạo workers
    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do
        RebuildWorker()
    end

    while true do
        -- Reload macro record nếu có thay đổi
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
                if ok and type(macro) == "table" then
                    towersByAxis = {}
                    soldAxis = {}
                    for i, entry 