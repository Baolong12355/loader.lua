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

-- FPS Monitor System
local FPSMonitor = {
    frameTimeHistory = {},
    historySize = 30, -- Monitor last 30 frames
    lastFrameTime = tick(),
    currentFPS = 60,
    fpsUpdateInterval = 0.5, -- Update FPS every 0.5 seconds
    lastFPSUpdate = 0,
    lagThreshold = 30 -- FPS threshold for switching to individual processing
}

function FPSMonitor:Init()
    -- Initialize frame time history
    for i = 1, self.historySize do
        self.frameTimeHistory[i] = 1/60 -- Default to 60 FPS
    end
    
    RunService.Heartbeat:Connect(function()
        self:UpdateFrameTime()
    end)
end

function FPSMonitor:UpdateFrameTime()
    local currentTime = tick()
    local frameTime = currentTime - self.lastFrameTime
    self.lastFrameTime = currentTime
    
    -- Add new frame time to history
    table.remove(self.frameTimeHistory, 1)
    table.insert(self.frameTimeHistory, frameTime)
    
    -- Update FPS calculation periodically
    if currentTime - self.lastFPSUpdate >= self.fpsUpdateInterval then
        self:CalculateAverageFPS()
        self.lastFPSUpdate = currentTime
    end
end

function FPSMonitor:CalculateAverageFPS()
    local totalFrameTime = 0
    for _, frameTime in ipairs(self.frameTimeHistory) do
        totalFrameTime = totalFrameTime + frameTime
    end
    local avgFrameTime = totalFrameTime / #self.frameTimeHistory
    self.currentFPS = math.floor(1 / avgFrameTime)
end

function FPSMonitor:GetCurrentFPS()
    return self.currentFPS
end

function FPSMonitor:ShouldUseBatchProcessing()
    return self.currentFPS < self.lagThreshold
end

-- Initialize FPS Monitor
FPSMonitor:Init()

-- Cấu hình mặc định với thêm FPS-based settings
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    -- FPS-BASED CONFIGURATIONS
    ["FPSBasedFallback"] = true,        -- Enable FPS-based fallback
    ["FPSThreshold"] = 30,              -- FPS threshold for fallback
    ["FPSMonitoringEnabled"] = true,    -- Enable FPS monitoring
    -- BATCH PROCESSING CONFIGURATIONS
    ["BatchProcessingEnabled"] = true,
    ["InstantBatchMode"] = true,
    ["MaxBatchSize"] = 20,
    ["BatchCollectionTime"] = 0.1,
    ["ParallelProcessing"] = true,
    ["BatchPrewarmEnabled"] = false,
    -- INDIVIDUAL PROCESSING CONFIGURATIONS
    ["IndividualProcessingDelay"] = 0.1, -- Delay between individual tower processing
    ["MaxIndividualConcurrent"] = 3,     -- Max concurrent individual rebuilds
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

-- Update FPS threshold from config
if globalEnv.TDX_Config.FPSThreshold then
    FPSMonitor.lagThreshold = globalEnv.TDX_Config.FPSThreshold
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

-- Utility functions
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

-- Đặt tower với retry logic từ runner system
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

-- Nâng cấp tower với retry logic từ runner system
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

-- Đổi target với retry logic từ runner system
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

-- Function để check xem skill có tồn tại không
local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end

    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

-- Function để sử dụng moving skill với retry logic từ runner system
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
                return true
            end
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

-- ==== INDIVIDUAL PROCESSING SYSTEM (Fallback Method) ====
local IndividualProcessor = {
    activeRebuilds = {},
    rebuildQueue = {},
    maxConcurrent = 3
}

-- Rebuild một tower hoàn chỉnh theo cách individual (legacy method)
function IndividualProcessor:RebuildSingleTowerIndividual(tower)
    -- Kiểm tra concurrent limit
    if #self.activeRebuilds >= self.maxConcurrent then
        table.insert(self.rebuildQueue, tower)
        return
    end

    -- Thêm vào active rebuilds
    table.insert(self.activeRebuilds, tower.x)
    
    task.spawn(function()
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

        -- Nếu place thất bại, dừng lại và cleanup
        if not placeSuccess then
            self:RemoveFromActiveRebuilds(tower.x)
            RemoveFromRebuildCache(tower.x)
            return
        end

        -- Delay để tránh spam
        task.wait(globalEnv.TDX_Config.IndividualProcessingDelay or 0.1)

        -- Phase 2: Process upgrades tuần tự
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
            task.wait(0.05) -- Small delay between upgrades
        end

        -- Phase 3: Process targets tuần tự
        local targetRecords = {}
        for _, record in ipairs(tower.records) do
            if record.entry.TowerTargetChange then
                table.insert(targetRecords, record)
            end
        end

        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
            task.wait(0.05)
        end

        -- Phase 4: Process moving skills
        local movingRecords = {}
        for _, record in ipairs(tower.records) do
            if record.entry.towermoving then
                table.insert(movingRecords, record)
            end
        end

        if #movingRecords > 0 then
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            -- Wait for skill availability
            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end

            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end

        -- Cleanup
        self:RemoveFromActiveRebuilds(tower.x)
        RemoveFromRebuildCache(tower.x)

        -- Process queued towers
        self:ProcessQueue()
    end)
end

function IndividualProcessor:RemoveFromActiveRebuilds(x)
    for i, activeX in ipairs(self.activeRebuilds) do
        if activeX == x then
            table.remove(self.activeRebuilds, i)
            break
        end
    end
end

function IndividualProcessor:ProcessQueue()
    if #self.rebuildQueue > 0 and #self.activeRebuilds < self.maxConcurrent then
        local tower = table.remove(self.rebuildQueue, 1)
        self:RebuildSingleTowerIndividual(tower)
    end
end

function IndividualProcessor:AddTowerToIndividual(x, records, towerName, firstPlaceLine, priority, deathTime)
    if ShouldSkipTower(x, towerName, firstPlaceLine) then
        return
    end

    local tower = {
        x = x,
        records = records,
        towerName = towerName,
        firstPlaceLine = firstPlaceLine,
        priority = priority,
        deathTime = deathTime
    }

    self:RebuildSingleTowerIndividual(tower)
end

-- Update max concurrent from config
IndividualProcessor.maxConcurrent = globalEnv.TDX_Config.MaxIndividualConcurrent or 3

-- ==== BATCH PROCESSING SYSTEM (Optimized Method) ====
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

-- Rebuild hoàn chỉnh một tower (tất cả phases) - Batch method
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

    -- Phase 2: Process upgrades ngay lập tức
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

    -- Phase 3: Process targets ngay lập tức
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

    -- Phase 4: Process moving skills song song
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

-- Xử lý batch song song hoàn toàn
function BatchProcessor:ExecuteInstantBatch(towers)
    if #towers == 0 then return end

    local allTasks = {}

    for _, tower in ipairs(towers) do
        if not ShouldSkipTower(tower.x, tower.towerName, tower.firstPlaceLine) then
            local task = task.spawn(function()
                self:RebuildSingleTowerComplete(tower)
            end)
            table.insert(allTasks, {task = task, x = tower.x})
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

-- ==== PROCESSING MODE CONTROLLER ====
local ProcessingController = {
    currentMode = "batch", -- "batch" hoặc "individual"
    lastModeSwitch = 0,
    modeStickiness = 2 -- Giữ mode trong 2 giây trước khi cho phép switch
}

function ProcessingController:DetermineOptimalMode()
    local currentTime = tick()
    
    -- Không switch mode quá thường xuyên
    if currentTime - self.lastModeSwitch < self.modeStickiness then
        return self.currentMode
    end

    -- Kiểm tra FPS-based fallback
    if globalEnv.TDX_Config.FPSBasedFallback and globalEnv.TDX_Config.FPSMonitoringEnabled then
        if not FPSMonitor:ShouldUseBatchProcessing() then
            -- FPS cao (≥30), chuyển về individual processing
            if self.currentMode ~= "individual" then
                print("[TDX Rebuild] Switching to Individual Processing (FPS: " .. FPSMonitor:GetCurrentFPS() .. ")")
                self.currentMode = "individual"
                self.lastModeSwitch = currentTime
            end
            return "individual"
        else
            -- FPS thấp (<30), dùng batch processing
            if self.currentMode ~= "batch" then
                print("[TDX Rebuild] Switching to Batch Processing (FPS: " .. FPSMonitor:GetCurrentFPS() .. ")")
                self.currentMode = "batch"
                self.lastModeSwitch = currentTime
            end
            return "batch"
        end
    end

    return self.currentMode
end

function ProcessingController:ProcessTower(x, records, towerName, firstPlaceLine, priority, deathTime)
    local mode = self:DetermineOptimalMode()
    
    if mode == "individual" then
        -- Sử dụng Individual Processing
        IndividualProcessor:AddTowerToIndividual(x, records, towerName, firstPlaceLine, priority, deathTime)
    else
        -- Sử dụng Batch Processing
        local addedToBatch = BatchProcessor:AddTowerToBatch(x, records, towerName, firstPlaceLine, priority, deathTime)
        if not addedToBatch then
            -- Fallback to individual nếu batch thất bại
            IndividualProcessor:AddTowerToIndividual(x, records, towerName, firstPlaceLine, priority, deathTime)
        end
    end
end

-- ==== AUTO SELL CONVERTED TOWERS - REBUILD ====
local soldConvertedX = {}

task.spawn(function()
    while true do
        -- Cleanup: Xóa tracking cho X positions không còn có converted towers
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
                        -- Đã từng sell tower converted tại X này
                        -- Nhưng bây giờ lại có tower converted → nghĩa là tower mới bị convert
                        -- Reset cache và sell tower mới này
                        soldConvertedX[x] = nil
                    end

                    -- Sell nếu chưa tracking X này
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

        RunService.Heartbeat:Wait()
    end
end)

-- Batch Monitor System
local function BatchMonitor()
    task.spawn(function()
        while true do
            -- Monitor và force process batch nếu cần
            if BatchProcessor.currentBatch.isCollecting then
                local timeSinceStart = tick() - BatchProcessor.currentBatch.startTime
                if timeSinceStart >= globalEnv.TDX_Config.BatchCollectionTime then
                    BatchProcessor:ForceProcessCurrentBatch()
                end
            end
            
            -- Process queued individual towers
            IndividualProcessor:ProcessQueue()
            
            task.wait(0.05) -- Check thường xuyên
        end
    end)
end

-- Initialize monitoring systems
if globalEnv.TDX_Config.InstantBatchMode or globalEnv.TDX_Config.FPSBasedFallback then
    BatchMonitor()
end

-- FPS Monitoring Display (Optional)
task.spawn(function()
    if not globalEnv.TDX_Config.FPSMonitoringEnabled then return end
    
    while true do
        task.wait(5) -- Display FPS every 5 seconds
        local currentFPS = FPSMonitor:GetCurrentFPS()
        local currentMode = ProcessingController.currentMode
        print(string.format("[TDX Rebuild] FPS: %d | Mode: %s | Active Rebuilds: %d | Batch Towers: %d", 
            currentFPS, 
            currentMode:upper(), 
            #IndividualProcessor.activeRebuilds,
            #BatchProcessor.currentBatch.towers
        ))
    end
end)

-- Hệ thống chính được tối ưu hóa với FPS-Based Fallback
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

        -- Producer với Dynamic Processing Mode Selection
        for x, records in pairs(towersByAxis) do
            local shouldProcessTower = true

            -- Check ForceRebuildEvenIfSold logic
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                shouldProcessTower = false
            end

            if shouldProcessTower then
                local hash, tower = GetTowerByAxis(x)

                if not hash or not tower then
                    -- Tower không tồn tại (chết HOẶC bị bán)
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
                                -- Sử dụng ProcessingController để chọn method tối ưu
                                local priority = GetTowerPriority(towerType)
                                local deathTime = deadTowerTracker.deadTowers[x] and deadTowerTracker.deadTowers[x].deathTime or tick()

                                ProcessingController:ProcessTower(
                                    x, records, towerType, firstPlaceLine, priority, deathTime
                                )
                            end
                        end
                    end
                else
                    -- Tower sống, cleanup
                    clearTowerDeath(x)
                    rebuildAttempts[x] = nil -- Reset rebuild attempts khi tower sống lại
                end
            end
        end

        RunService.Heartbeat:Wait()
    end
end)