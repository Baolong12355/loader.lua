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

-- Cấu hình mặc định với thêm Instant Batch Processing
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    -- INSTANT BATCH PROCESSING CONFIGURATIONS
    ["BatchProcessingEnabled"] = true,
    ["InstantBatchMode"] = true,       -- Xử lý ngay lập tức không chờ đợi
    ["MaxBatchSize"] = 20,             -- Tăng số tower tối đa trong một batch
    ["BatchCollectionTime"] = 0.1,     -- Thời gian thu thập tối thiểu
    ["ParallelProcessing"] = true,     -- Xử lý song song hoàn toàn
    ["BatchPrewarmEnabled"] = false,   -- Tắt pre-warm để tăng tốc
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

-- ==== BATCH PROCESSING SYSTEM ====
local BatchProcessor = {
    pendingBatches = {},
    currentBatch = {
        towers = {},
        startTime = tick(),
        isCollecting = false
    },
    batchCounter = 0,
    prewarmCache = {} -- Cache cho pre-warming
}

-- Thêm tower vào batch hiện tại hoặc xử lý ngay lập tức
function BatchProcessor:AddTowerToBatch(x, records, towerName, firstPlaceLine, priority, deathTime)
    if not globalEnv.TDX_Config.BatchProcessingEnabled then
        return false -- Không sử dụng batch processing
    end

    local tower = {
        x = x,
        records = records,
        towerName = towerName,
        firstPlaceLine = firstPlaceLine,
        priority = priority,
        deathTime = deathTime
    }

    -- Instant Mode: Xử lý ngay lập tức nếu bật
    if globalEnv.TDX_Config.InstantBatchMode then
        -- Thêm vào batch hiện tại
        if not self.currentBatch.isCollecting then
            self.currentBatch.isCollecting = true
            self.currentBatch.startTime = tick()
            self.currentBatch.towers = {}
        end

        table.insert(self.currentBatch.towers, tower)
        
        -- Xử lý ngay lập tức nếu đạt batch size hoặc sau 0.1s
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

    -- Legacy batch mode (giữ nguyên code cũ cho tương thích)
    -- ... existing batch logic ...
    return true
end

-- Xử lý batch ngay lập tức (Instant Mode)
function BatchProcessor:ProcessCurrentBatchInstant()
    if #self.currentBatch.towers == 0 then
        self.currentBatch.isCollecting = false
        return
    end

    -- Sao chép tất cả tower hiện tại
    local towersToRebuild = {}
    for _, tower in ipairs(self.currentBatch.towers) do
        table.insert(towersToRebuild, tower)
    end

    -- Reset batch ngay lập tức để có thể nhận tower mới
    self.currentBatch.towers = {}
    self.currentBatch.isCollecting = false
    self.batchCounter = self.batchCounter + 1

    -- Sắp xếp theo priority
    table.sort(towersToRebuild, function(a, b)
        if a.priority == b.priority then
            return a.deathTime < b.deathTime
        end
        return a.priority < b.priority
    end)

    -- Xử lý tất cả tower song song ngay lập tức
    task.spawn(function()
        self:ExecuteInstantBatch(towersToRebuild)
    end)
end

-- Xử lý batch song song hoàn toàn
function BatchProcessor:ExecuteInstantBatch(towers)
    if #towers == 0 then return end

    -- Tạo tất cả task song song ngay lập tức
    local allTasks = {}
    
    for _, tower in ipairs(towers) do
        if not ShouldSkipTower(tower.x, tower.towerName, tower.firstPlaceLine) then
            -- Mỗi tower có task riêng xử lý hoàn toàn độc lập
            local task = task.spawn(function()
                self:RebuildSingleTowerComplete(tower)
            end)
            table.insert(allTasks, {task = task, x = tower.x})
        else
            -- Clean up skipped tower
            RemoveFromRebuildCache(tower.x)
        end
    end
    
    -- Không chờ đợi - batch tiếp theo có thể bắt đầu ngay
end

-- Rebuild hoàn chỉnh một tower (tất cả phases)
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
    
    -- Nếu place thất bại, dừng lại
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
    
    -- Sort và upgrade ngay
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
            
            -- Wait for skill availability
            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end
            
            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end)
    end
    
    RemoveFromRebuildCache(tower.x)
end

-- Force process batch nếu cần (Instant Mode)
function BatchProcessor:ForceProcessCurrentBatch()
    if self.currentBatch.isCollecting and #self.currentBatch.towers > 0 then
        if globalEnv.TDX_Config.InstantBatchMode then
            self:ProcessCurrentBatchInstant()
        else
            self:ProcessCurrentBatch() -- Legacy mode
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

-- Instant Batch Worker System - Xử lý ngay lập tức
local function InstantBatchMonitor()
    task.spawn(function()
        while true do
            -- Chỉ cần monitor và force process nếu có tower chờ quá lâu
            if BatchProcessor.currentBatch.isCollecting then
                local timeSinceStart = tick() - BatchProcessor.currentBatch.startTime
                if timeSinceStart >= globalEnv.TDX_Config.BatchCollectionTime then
                    BatchProcessor:ForceProcessCurrentBatch()
                end
            end
            task.wait(0.05) -- Check thường xuyên hơn
        end
    end)
end

-- Khởi tạo Instant Batch Monitor
if globalEnv.TDX_Config.InstantBatchMode then
    InstantBatchMonitor()
else
    -- Legacy Batch Worker System
    local function BatchWorker()
        task.spawn(function()
            while true do
                if #BatchProcessor.pendingBatches > 0 then
                    local batch = table.remove(BatchProcessor.pendingBatches, 1)
                    BatchProcessor:ExecuteBatch(batch)
                else
                    -- Force process current batch nếu đã quá thời gian thu thập
                    if BatchProcessor.currentBatch.isCollecting then
                        local timeSinceStart = tick() - BatchProcessor.currentBatch.startTime
                        if timeSinceStart >= globalEnv.TDX_Config.BatchCollectionTime then
                            BatchProcessor:ForceProcessCurrentBatch()
                        end
                    end
                    task.wait(0.1)
                end
            end
        end)
    end

    -- Khởi tạo Batch Workers
    for i = 1, math.min(globalEnv.TDX_Config.MaxConcurrentRebuilds, 3) do
        BatchWorker()
    end
end

-- Hệ thống chính được tối ưu hóa với Batch Processing
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

        -- Producer với Batch Processing support
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
                    -- Check ForceRebuildEvenIfSold setting
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
                                -- Sử dụng Batch Processing hoặc fallback về individual processing
                                local priority = GetTowerPriority(towerType)
                                local deathTime = deadTowerTracker.deadTowers[x] and deadTowerTracker.deadTowers[x].deathTime or tick()
                                
                                local addedToBatch = BatchProcessor:AddTowerToBatch(
                                    x, records, towerType, firstPlaceLine, priority, deathTime
                                )
                                
                                -- Nếu không thêm được vào batch, xử lý individual (fallback)
                                if not addedToBatch then
                                    -- Fallback to individual processing (legacy code)
                                    -- Implementation sẽ giống như code gốc
                                end
                            end
                        end
                    end
                else
                    -- Tower sống, cleanup
                    clearTowerDeath(x)
                end
            end
        end

        RunService.Heartbeat:Wait()
    end
end)