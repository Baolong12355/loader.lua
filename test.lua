local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/recorder_output.json"
local debugLogPath = "tdx/debug/rebuilder_debug.log"

-- Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

-- Debug logging system
local DebugLogger = {
    logBuffer = {},
    maxBufferSize = 1000,
    lastFlushTime = tick()
}

function DebugLogger:Log(level, message, data)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logEntry = string.format("[%s] [%s] %s", timestamp, level, message)
    
    if data then
        logEntry = logEntry .. " | Data: " .. HttpService:JSONEncode(data)
    end
    
    table.insert(self.logBuffer, logEntry)
    
    -- Auto flush if buffer is full or every 30 seconds
    if #self.logBuffer >= self.maxBufferSize or tick() - self.lastFlushTime > 30 then
        self:FlushLogs()
    end
end

function DebugLogger:FlushLogs()
    if #self.logBuffer == 0 then return end
    
    local success = pcall(function()
        local existingContent = ""
        if isfile and isfile(debugLogPath) and readfile then
            existingContent = readfile(debugLogPath) or ""
        end
        
        local newContent = existingContent .. table.concat(self.logBuffer, "\n") .. "\n"
        
        if writefile then
            writefile(debugLogPath, newContent)
        end
    end)
    
    if success then
        self.logBuffer = {}
        self.lastFlushTime = tick()
    end
end

function DebugLogger:Error(message, data)
    self:Log("ERROR", message, data)
end

function DebugLogger:Warning(message, data)
    self:Log("WARN", message, data)
end

function DebugLogger:Info(message, data)
    self:Log("INFO", message, data)
end

function DebugLogger:Debug(message, data)
    self:Log("DEBUG", message, data)
end

-- Cấu hình mặc định với thêm Instant Batch Processing
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 10,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Ashed",
    -- INSTANT BATCH PROCESSING CONFIGURATIONS
    ["BatchProcessingEnabled"] = true,
    ["InstantBatchMode"] = true,       -- Xử lý ngay lập tức không chờ đợi
    ["MaxBatchSize"] = 100,             -- Tăng số tower tối đa trong một batch
    ["BatchCollectionTime"] = 0.1,     -- Thời gian thu thập tối thiểu
    ["ParallelProcessing"] = true,     -- Xử lý song song hoàn toàn
    ["BatchPrewarmEnabled"] = false,   -- Tắt pre-warm để tăng tốc
    -- SKIP CONFIGURATIONS
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {"Slammer", "Toxicnator"},
    ["SkipTowersByLine"] = {},
    -- FALLBACK CONFIGURATIONS
    ["UseFallbackPositioning"] = true,
    ["FallbackTimeout"] = 1.0,        -- Thời gian chờ trước khi dùng fallback
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

DebugLogger:Info("TDX Rebuilder initialized", globalEnv.TDX_Config)

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

-- Lấy TowerClass với fallback
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = tick()
    while tick() - t0 < timeout do
        local ok, mod = pcall(require, path)
        if ok and mod then 
            DebugLogger:Debug("Successfully loaded module", {path = tostring(path)})
            return mod 
        end
        RunService.Heartbeat:Wait()
    end
    DebugLogger:Error("Failed to load module after timeout", {path = tostring(path), timeout = timeout})
    return nil
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then 
        DebugLogger:Error("PlayerScripts not found")
        return nil 
    end
    local client = ps:FindFirstChild("Client")
    if not client then 
        DebugLogger:Error("Client not found in PlayerScripts")
        return nil 
    end
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then 
        DebugLogger:Error("GameClass not found in Client")
        return nil 
    end
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then 
        DebugLogger:Error("TowerClass module not found in GameClass")
        return nil 
    end
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then 
    DebugLogger:Error("Failed to load TowerClass - script will exit")
    error("Không thể load TowerClass!") 
end

-- Hàm quản lý cache rebuild
local function AddToRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
    DebugLogger:Debug("Added to rebuild cache", {axisX = axisX})
end

local function RemoveFromRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
    DebugLogger:Debug("Removed from rebuild cache", {axisX = axisX})
end

local function IsInRebuildCache(axisX)
    return globalEnv.TDX_REBUILDING_TOWERS[axisX] == true
end

-- ==================== POSITION DETECTION WITH FALLBACK ====================

-- Fallback position detection using workspace.Game.Towers
local function GetTowerPositionFromWorkspace(targetX)
    local towersFolder = workspace:FindFirstChild("Game")
    if towersFolder then
        towersFolder = towersFolder:FindFirstChild("Towers")
        if towersFolder then
            for _, towerPart in ipairs(towersFolder:GetChildren()) do
                if towerPart:IsA("BasePart") then
                    local pos = towerPart.Position
                    if math.abs(pos.X - targetX) < 0.1 then -- Small tolerance for floating point comparison
                        DebugLogger:Debug("Found tower position via workspace fallback", {
                            targetX = targetX, 
                            foundPos = {x = pos.X, y = pos.Y, z = pos.Z},
                            towerName = towerPart.Name
                        })
                        return towerPart, pos
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Enhanced tower detection with fallback
local function GetTowerHashBySpawnX(targetX, useTimeout)
    local startTime = tick()
    local timeout = useTimeout and globalEnv.TDX_Config.FallbackTimeout or 0
    
    -- Primary method: TowerClass.GetTowers()
    while true do
        local towers = TowerClass.GetTowers()
        if towers then
            for hash, tower in pairs(towers) do
                local spawnCFrame = tower.SpawnCFrame
                if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                    local pos = spawnCFrame.Position
                    if math.abs(pos.X - targetX) < 0.1 then
                        DebugLogger:Debug("Found tower via TowerClass", {
                            targetX = targetX, 
                            hash = hash, 
                            pos = {x = pos.X, y = pos.Y, z = pos.Z}
                        })
                        return hash, tower, pos
                    end
                end
            end
        end
        
        -- Check timeout for fallback
        if timeout > 0 and tick() - startTime >= timeout then
            break
        elseif timeout == 0 then
            break
        end
        
        RunService.Heartbeat:Wait()
    end
    
    -- Fallback method: workspace.Game.Towers
    if globalEnv.TDX_Config.UseFallbackPositioning then
        DebugLogger:Warning("Primary tower detection failed, using fallback", {targetX = targetX})
        local towerPart, pos = GetTowerPositionFromWorkspace(targetX)
        if towerPart and pos then
            -- Try to get hash from TowerClass using the found position
            local towers = TowerClass.GetTowers()
            if towers then
                for hash, tower in pairs(towers) do
                    local spawnCFrame = tower.SpawnCFrame
                    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                        local towerPos = spawnCFrame.Position
                        if (towerPos - pos).Magnitude < 1.0 then -- Close enough match
                            DebugLogger:Info("Successfully matched fallback position to TowerClass", {
                                targetX = targetX,
                                hash = hash,
                                fallbackPos = {x = pos.X, y = pos.Y, z = pos.Z},
                                towerPos = {x = towerPos.X, y = towerPos.Y, z = towerPos.Z}
                            })
                            return hash, tower, pos
                        end
                    end
                end
            end
            
            DebugLogger:Warning("Found tower via fallback but couldn't match to TowerClass", {
                targetX = targetX,
                fallbackPos = {x = pos.X, y = pos.Y, z = pos.Z}
            })
        else
            DebugLogger:Error("Fallback position detection also failed", {targetX = targetX})
        end
    end
    
    return nil, nil, nil
end

local function GetTowerByAxis(axisX, useTimeout)
    return GetTowerHashBySpawnX(axisX, useTimeout)
end

-- ==================== SKIP LOGIC ====================
local function ShouldSkipTower(axisX, towerName, firstPlaceLine)
    local config = globalEnv.TDX_Config

    -- Skip theo axis X
    if config.SkipTowersAtAxis then
        for _, skipAxis in ipairs(config.SkipTowersAtAxis) do
            if axisX == skipAxis then
                DebugLogger:Info("Skipping tower by axis", {axisX = axisX})
                return true
            end
        end
    end

    -- Skip theo tên tower
    if config.SkipTowersByName then
        for _, skipName in ipairs(config.SkipTowersByName) do
            if towerName == skipName then
                DebugLogger:Info("Skipping tower by name", {towerName = towerName, axisX = axisX})
                return true
            end
        end
    end

    -- Skip theo line number
    if config.SkipTowersByLine and firstPlaceLine then
        for _, skipLine in ipairs(config.SkipTowersByLine) do
            if firstPlaceLine == skipLine then
                DebugLogger:Info("Skipping tower by line", {line = firstPlaceLine, axisX = axisX})
                return true
            end
        end
    end

    return false
end

-- Utility functions
local function WaitForCash(amount)
    if cash.Value < amount then
        DebugLogger:Debug("Waiting for cash", {current = cash.Value, needed = amount})
        while cash.Value < amount do
            RunService.Heartbeat:Wait()
        end
        DebugLogger:Debug("Cash requirement met", {current = cash.Value, needed = amount})
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

-- Đặt tower với retry logic và debug logging
local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    DebugLogger:Info("Starting tower placement", {
        axisValue = axisValue, 
        towerName = towerName, 
        maxAttempts = maxAttempts,
        args = args
    })

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        attempts = attempts + 1
        DebugLogger:Debug("Tower placement attempt", {
            attempt = attempts, 
            maxAttempts = maxAttempts, 
            axisValue = axisValue
        })

        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        
        if success then
            local startTime = tick()
            repeat 
                task.wait(0.1)
            until tick() - startTime > 3 or GetTowerByAxis(axisValue, false)
            
            local hash, tower = GetTowerByAxis(axisValue, false)
            if hash and tower then 
                DebugLogger:Info("Tower placement successful", {
                    axisValue = axisValue, 
                    towerName = towerName, 
                    attempts = attempts,
                    hash = hash
                })
                RemoveFromRebuildCache(axisValue)
                return true
            else
                DebugLogger:Warning("Tower placement remote succeeded but tower not found", {
                    axisValue = axisValue, 
                    attempt = attempts
                })
            end
        else
            DebugLogger:Warning("Tower placement remote failed", {
                axisValue = axisValue, 
                attempt = attempts
            })
        end
        
        task.wait()
    end
    
    DebugLogger:Error("Tower placement failed after all attempts", {
        axisValue = axisValue, 
        towerName = towerName, 
        totalAttempts = attempts
    })
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Nâng cấp tower với retry logic và debug logging
local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    DebugLogger:Info("Starting tower upgrade", {
        axisValue = axisValue, 
        path = path, 
        maxAttempts = maxAttempts
    })

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        attempts = attempts + 1
        local hash, tower = GetTowerByAxis(axisValue, false)
        if not hash then 
            DebugLogger:Warning("Tower not found for upgrade", {
                axisValue = axisValue, 
                attempt = attempts
            })
            task.wait() 
            continue 
        end
        
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then 
            DebugLogger:Debug("Tower already at max level", {
                axisValue = axisValue, 
                path = path, 
                currentLevel = before
            })
            RemoveFromRebuildCache(axisValue)
            return true 
        end
        
        DebugLogger:Debug("Upgrading tower", {
            axisValue = axisValue, 
            path = path, 
            cost = cost, 
            currentLevel = before,
            attempt = attempts
        })
        
        WaitForCash(cost)
        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        
        if success then
            local startTime = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue, false)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                    DebugLogger:Info("Tower upgrade successful", {
                        axisValue = axisValue, 
                        path = path, 
                        fromLevel = before, 
                        toLevel = t.LevelHandler:GetLevelOnPath(path),
                        attempts = attempts
                    })
                    RemoveFromRebuildCache(axisValue)
                    return true 
                end
            until tick() - startTime > 3
            
            DebugLogger:Warning("Tower upgrade remote succeeded but level didn't change", {
                axisValue = axisValue, 
                path = path, 
                attempt = attempts
            })
        else
            DebugLogger:Warning("Tower upgrade remote failed", {
                axisValue = axisValue, 
                path = path, 
                attempt = attempts
            })
        end
        
        task.wait()
    end
    
    DebugLogger:Error("Tower upgrade failed after all attempts", {
        axisValue = axisValue, 
        path = path, 
        totalAttempts = attempts
    })
    RemoveFromRebuildCache(axisValue)
    return false
end

-- Đổi target với retry logic và debug logging
local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    DebugLogger:Info("Starting target change", {
        axisValue = axisValue, 
        targetType = targetType, 
        maxAttempts = maxAttempts
    })

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        attempts = attempts + 1
        local hash = GetTowerByAxis(axisValue, false)
        if hash then
            local success = pcall(function()
                Remotes.ChangeQueryType:FireServer(hash, targetType)
            end)
            
            if success then
                DebugLogger:Info("Target change successful", {
                    axisValue = axisValue, 
                    targetType = targetType, 
                    attempts = attempts
                })
            else
                DebugLogger:Warning("Target change remote failed", {
                    axisValue = axisValue, 
                    targetType = targetType, 
                    attempt = attempts
                })
            end
            
            RemoveFromRebuildCache(axisValue)
            return
        else
            DebugLogger:Warning("Tower not found for target change", {
                axisValue = axisValue, 
                attempt = attempts
            })
        end
        
        task.wait(0.1)
    end
    
    DebugLogger:Error("Target change failed after all attempts", {
        axisValue = axisValue, 
        targetType = targetType, 
        totalAttempts = attempts
    })
    RemoveFromRebuildCache(axisValue)
end

-- Function để check xem skill có tồn tại không
local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue, false)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end

    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

-- Function để sử dụng moving skill với retry logic và debug logging
local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0

    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then
        DebugLogger:Error("TowerUseAbilityRequest remote not found")
        return false
    end

    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

    DebugLogger:Info("Starting moving skill usage", {
        axisValue = axisValue, 
        skillIndex = skillIndex, 
        location = location, 
        maxAttempts = maxAttempts,
        useFireServer = useFireServer
    })

    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        attempts = attempts + 1
        local hash, tower = GetTowerByAxis(axisValue, false)
        if hash and tower then
            if not tower.AbilityHandler then
                DebugLogger:Error("Tower has no AbilityHandler", {axisValue = axisValue})
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                DebugLogger:Error("Skill not found", {axisValue = axisValue, skillIndex = skillIndex})
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then
                DebugLogger:Debug("Waiting for skill cooldown", {
                    axisValue = axisValue, 
                    skillIndex = skillIndex, 
                    cooldown = cooldown
                })
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
                else
                    DebugLogger:Error("Invalid location format", {location = location})
                end
            end

            if success then
                DebugLogger:Info("Moving skill usage successful", {
                    axisValue = axisValue, 
                    skillIndex = skillIndex, 
                    location = location, 
                    attempts = attempts
                })
                RemoveFromRebuildCache(axisValue)
                return true
            else
                DebugLogger:Warning("Moving skill remote failed", {
                    axisValue = axisValue, 
                    skillIndex = skillIndex, 
                    attempt = attempts
                })
            end
        else
            DebugLogger:Warning("Tower not found for moving skill", {
                axisValue = axisValue, 
                attempt = attempts
            })
        end
        
        task.wait(0.1)
    end
    
    DebugLogger:Error("Moving skill usage failed after all attempts", {
        axisValue = axisValue, 
        skillIndex = skillIndex, 
        location = location, 
        totalAttempts = attempts
    })
    RemoveFromRebuildCache(axisValue)
    return false
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

-- Rebuild hoàn chỉnh một tower (tất cả phases)
function BatchProcessor:RebuildSingleTowerComplete(tower)
    DebugLogger:Info("Starting complete tower rebuild", {
        axisX = tower.x, 
        towerName = tower.towerName, 
        priority = tower.priority,
        recordCount = #tower.records
    })

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
        else
            DebugLogger:Error("Invalid tower vector format", {
                axisX = tower.x, 
                vector = entry.TowerVector
            })
        end
    else
        DebugLogger:Error("No place record found for tower", {axisX = tower.x})
    end

    -- Nếu place thất bại, dừng lại
    if not placeSuccess then
        DebugLogger:Error("Tower placement failed, aborting rebuild", {axisX = tower.x})
        RemoveFromRebuildCache(tower.x)
        return
    end

    DebugLogger:Info("Tower placement successful, proceeding with upgrades", {axisX = tower.x})

    -- Phase 2: Process upgrades ngay lập tức
    local upgradeRecords = {}
    for _, record in ipairs(tower.records) do
        if record.entry.TowerUpgraded then
            table.insert(upgradeRecords, record)
        end
    end

    -- Sort và upgrade ngay
    table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
    DebugLogger:Debug("Processing upgrades", {axisX = tower.x, upgradeCount = #upgradeRecords})
    
    for i, record in ipairs(upgradeRecords) do
        local entry = record.entry
        DebugLogger:Debug("Processing upgrade", {
            axisX = tower.x, 
            upgradeIndex = i, 
            path = entry.UpgradePath, 
            line = record.line
        })
        UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath)
    end

    -- Phase 3: Process targets ngay lập tức
    local targetRecords = {}
    for _, record in ipairs(tower.records) do
        if record.entry.TowerTargetChange then
            table.insert(targetRecords, record)
        end
    end

    DebugLogger:Debug("Processing target changes", {axisX = tower.x, targetCount = #targetRecords})
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
        DebugLogger:Debug("Processing moving skills", {axisX = tower.x, movingCount = #movingRecords})
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            -- Wait for skill availability
            local waitStart = tick()
            while not HasSkill(entry.towermoving, entry.skillindex) do
                if tick() - waitStart > 10 then -- 10 second timeout
                    DebugLogger:Error("Skill availability timeout", {
                        axisX = entry.towermoving, 
                        skillIndex = entry.skillindex
                    })
                    break
                end
                RunService.Heartbeat:Wait()
            end

            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end)
    end

    DebugLogger:Info("Tower rebuild completed", {axisX = tower.x, towerName = tower.towerName})
    RemoveFromRebuildCache(tower.x)
end

-- Xử lý batch song song hoàn toàn
function BatchProcessor:ExecuteInstantBatch(towers)
    if #towers == 0 then return end

    DebugLogger:Info("Executing instant batch", {
        batchSize = #towers, 
        batchCounter = self.batchCounter
    })

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
            DebugLogger:Info("Skipping tower in batch", {axisX = tower.x, towerName = tower.towerName})
            RemoveFromRebuildCache(tower.x)
        end
    end

    DebugLogger:Info("Batch execution started", {
        totalTasks = #allTasks, 
        batchCounter = self.batchCounter
    })

    -- Không chờ đợi - batch tiếp theo có thể bắt đầu ngay
end

-- Xử lý batch ngay lập tức (Instant Mode)
function BatchProcessor:ProcessCurrentBatchInstant()
    if #self.currentBatch.towers == 0 then
        self.currentBatch.isCollecting = false
        return
    end

    DebugLogger:Info("Processing current batch instant", {
        towerCount = #self.currentBatch.towers, 
        collectionTime = tick() - self.currentBatch.startTime
    })

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

    DebugLogger:Debug("Batch sorted by priority", {
        batchSize = #towersToRebuild,
        priorities = (function()
            local priorities = {}
            for _, tower in ipairs(towersToRebuild) do
                table.insert(priorities, {x = tower.x, priority = tower.priority, name = tower.towerName})
            end
            return priorities
        end)()
    })

    -- Xử lý tất cả tower song song ngay lập tức
    task.spawn(function()
        self:ExecuteInstantBatch(towersToRebuild)
    end)
end

-- Thêm tower vào batch hiện tại hoặc xử lý ngay lập tức
function BatchProcessor:AddTowerToBatch(x, records, towerName, firstPlaceLine, priority, deathTime)
    if not globalEnv.TDX_Config.BatchProcessingEnabled then
        DebugLogger:Debug("Batch processing disabled")
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

    DebugLogger:Debug("Adding tower to batch", {
        axisX = x, 
        towerName = towerName, 
        priority = priority, 
        firstPlaceLine = firstPlaceLine
    })

    -- Instant Mode: Xử lý ngay lập tức nếu bật
    if globalEnv.TDX_Config.InstantBatchMode then
        -- Thêm vào batch hiện tại
        if not self.currentBatch.isCollecting then
            self.currentBatch.isCollecting = true
            self.currentBatch.startTime = tick()
            self.currentBatch.towers = {}
            DebugLogger:Debug("Started new batch collection")
        end

        table.insert(self.currentBatch.towers, tower)

        -- Xử lý ngay lập tức nếu đạt batch size hoặc sau 0.1s
        local shouldProcessNow = false

        if #self.currentBatch.towers >= globalEnv.TDX_Config.MaxBatchSize then
            DebugLogger:Debug("Batch size limit reached", {
                currentSize = #self.currentBatch.towers, 
                maxSize = globalEnv.TDX_Config.MaxBatchSize
            })
            shouldProcessNow = true
        elseif tick() - self.currentBatch.startTime >= globalEnv.TDX_Config.BatchCollectionTime then
            DebugLogger:Debug("Batch collection time exceeded", {
                timeElapsed = tick() - self.currentBatch.startTime, 
                maxTime = globalEnv.TDX_Config.BatchCollectionTime
            })
            shouldProcessNow = true
        end

        if shouldProcessNow then
            self:ProcessCurrentBatchInstant()
        end

        return true
    end

    -- Legacy batch mode (giữ nguyên code cũ cho tương thích)
    return true
end

-- Force process batch nếu cần (Instant Mode)
function BatchProcessor:ForceProcessCurrentBatch()
    if self.currentBatch.isCollecting and #self.currentBatch.towers > 0 then
        DebugLogger:Debug("Force processing current batch", {
            towerCount = #self.currentBatch.towers
        })
        
        if globalEnv.TDX_Config.InstantBatchMode then
            self:ProcessCurrentBatchInstant()
        else
            -- Legacy mode processing would go here
        end
    end
end

-- ==== AUTO SELL CONVERTED TOWERS - REBUILD ====
local soldConvertedX = {}

task.spawn(function()
    DebugLogger:Info("Starting auto-sell converted towers system")
    
    while true do
        -- Cleanup: Xóa tracking cho X positions không còn có converted towers
        local cleanupCount = 0
        for x in pairs(soldConvertedX) do
            local hasConvertedAtX = false

            -- Check xem có tower nào converted tại X này không
            for hash, tower in pairs(TowerClass.GetTowers()) do
                if tower.Converted == true then
                    local spawnCFrame = tower.SpawnCFrame
                    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
                        if math.abs(spawnCFrame.Position.X - x) < 0.1 then
                            hasConvertedAtX = true
                            break
                        end
                    end
                end
            end

            -- Nếu không có converted tower nào tại X này, xóa khỏi tracking
            if not hasConvertedAtX then
                soldConvertedX[x] = nil
                cleanupCount = cleanupCount + 1
            end
        end

        if cleanupCount > 0 then
            DebugLogger:Debug("Cleaned up converted tower tracking", {cleanupCount = cleanupCount})
        end

        -- Check và sell converted towers
        local soldCount = 0
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
                        soldCount = soldCount + 1

                        DebugLogger:Info("Selling converted tower", {
                            axisX = x, 
                            hash = hash
                        })

                        pcall(function()
                            Remotes.SellTower:FireServer(hash)
                        end)
                        task.wait(0.1)
                    end
                end
            end
        end

        if soldCount > 0 then
            DebugLogger:Info("Sold converted towers", {count = soldCount})
        end

        RunService.Heartbeat:Wait()
    end
end)

-- Instant Batch Worker System - Xử lý ngay lập tức
local function InstantBatchMonitor()
    task.spawn(function()
        DebugLogger:Info("Starting instant batch monitor")
        
        while true do
            -- Chỉ cần monitor và force process nếu có tower chờ quá lâu
            if BatchProcessor.currentBatch.isCollecting then
                local timeSinceStart = tick() - BatchProcessor.currentBatch.startTime
                if timeSinceStart >= globalEnv.TDX_Config.BatchCollectionTime then
                    DebugLogger:Debug("Forcing batch process due to time limit", {
                        timeSinceStart = timeSinceStart, 
                        maxTime = globalEnv.TDX_Config.BatchCollectionTime
                    })
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
end

-- Auto flush debug logs periodically
task.spawn(function()
    while true do
        task.wait(30) -- Flush every 30 seconds
        DebugLogger:FlushLogs()
    end
end)

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
            DebugLogger:Debug("Recorded tower death", {
                axisX = x, 
                deathId = deadTowerTracker.deadTowers[x].deathId
            })
        end
    end

    local function clearTowerDeath(x)
        if deadTowerTracker.deadTowers[x] then
            DebugLogger:Debug("Cleared tower death record", {
                axisX = x, 
                deathId = deadTowerTracker.deadTowers[x].deathId
            })
            deadTowerTracker.deadTowers[x] = nil
        end
    end

    DebugLogger:Info("Starting main tower monitoring system")

    while true do
        -- Reload macro record nếu có thay đổi
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
            if macroHash ~= lastMacroHash then
                DebugLogger:Info("Macro file changed, reloading", {
                    oldHash = lastMacroHash, 
                    newHash = macroHash, 
                    contentLength = #macroContent
                })
                
                lastMacroHash = macroHash
                local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
                if ok and type(macro) == "table" then
                    local oldTowerCount = 0
                    for _ in pairs(towersByAxis) do oldTowerCount = oldTowerCount + 1 end
                    
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
                    
                    local newTowerCount = 0
                    for _ in pairs(towersByAxis) do newTowerCount = newTowerCount + 1 end
                    
                    DebugLogger:Info("Macro parsed successfully", {
                        totalEntries = #macro, 
                        oldTowerCount = oldTowerCount, 
                        newTowerCount = newTowerCount,
                        soldAxisCount = (function()
                            local count = 0
                            for _ in pairs(soldAxis) do count = count + 1 end
                            return count
                        end)()
                    })
                else
                    DebugLogger:Error("Failed to parse macro JSON", {macroHash = macroHash})
                end
            end
        else
            if not macroContent then
                DebugLogger:Warning("Macro file not found or unreadable", {path = macroPath})
            elseif #macroContent <= 10 then
                DebugLogger:Warning("Macro file too short", {length = #macroContent})
            end
        end

        -- Producer với Batch Processing support
        local processedTowers = 0
        local skippedTowers = 0
        local foundTowers = 0
        
        for x, records in pairs(towersByAxis) do
            local shouldProcessTower = true

            -- Check ForceRebuildEvenIfSold logic
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                shouldProcessTower = false
                skippedTowers = skippedTowers + 1
            end

            if shouldProcessTower then
                -- Use timeout for primary detection to enable fallback
                local hash, tower = GetTowerByAxis(x, true)

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

                                DebugLogger:Debug("Adding tower to rebuild queue", {
                                    axisX = x, 
                                    towerType = towerType, 
                                    priority = priority, 
                                    attempt = rebuildAttempts[x], 
                                    maxRetry = maxRetry
                                })

                                local addedToBatch = BatchProcessor:AddTowerToBatch(
                                    x, records, towerType, firstPlaceLine, priority, deathTime
                                )

                                -- Nếu không thêm được vào batch, xử lý individual (fallback)
                                if not addedToBatch then
                                    DebugLogger:Warning("Failed to add tower to batch, using individual processing", {
                                        axisX = x, 
                                        towerType = towerType
                                    })
                                    
                                    -- Individual fallback processing would go here
                                    -- This maintains compatibility if batch processing fails
                                end
                                
                                processedTowers = processedTowers + 1
                            else
                                DebugLogger:Warning("Tower exceeded max rebuild attempts", {
                                    axisX = x, 
                                    towerType = towerType, 
                                    attempts = rebuildAttempts[x], 
                                    maxRetry = maxRetry
                                })
                            end
                        else
                            DebugLogger:Error("No tower type found for axis", {
                                axisX = x, 
                                recordCount = #records
                            })
                        end
                    else
                        DebugLogger:Debug("Tower rebuild blocked by ForceRebuildEvenIfSold setting", {
                            axisX = x, 
                            soldAxis = soldAxis[x], 
                            forceRebuild = globalEnv.TDX_Config.ForceRebuildEvenIfSold
                        })
                    end
                else
                    -- Tower sống, cleanup
                    foundTowers = foundTowers + 1
                    clearTowerDeath(x)
                    
                    -- Reset rebuild attempts for living towers
                    if rebuildAttempts[x] then
                        DebugLogger:Debug("Reset rebuild attempts for living tower", {
                            axisX = x, 
                            previousAttempts = rebuildAttempts[x]
                        })
                        rebuildAttempts[x] = nil
                    end
                end
            end
        end

        -- Log periodic status if there's activity
        if processedTowers > 0 or skippedTowers > 0 or foundTowers > 0 then
            DebugLogger:Debug("Tower monitoring cycle completed", {
                foundTowers = foundTowers, 
                processedTowers = processedTowers, 
                skippedTowers = skippedTowers,
                totalTracked = (function()
                    local count = 0
                    for _ in pairs(towersByAxis) do count = count + 1 end
                    return count
                end)(),
                batchCollecting = BatchProcessor.currentBatch.isCollecting,
                currentBatchSize = #BatchProcessor.currentBatch.towers
            })
        end

        RunService.Heartbeat:Wait()
    end
end)

DebugLogger:Info("TDX Tower Rebuilder fully initialized and running")

-- Cleanup on script end
game.Players.PlayerRemoving:Connect(function(plr)
    if plr == player then
        DebugLogger:Info("Player leaving, flushing final logs")
        DebugLogger:FlushLogs()
    end
end)