-- TDX Macro Runner (Không sai số - ánh xạ spawn pos động, executor/loadstring ready)
-- Chỉ rebuild tower bị convert sell, không rebuild tower bị bán tay. So sánh pos tuyệt đối (==), không dùng sai số.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = player:WaitForChild("PlayerGui")

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end
local function safeReadFile(path)
    if readfile and typeof(readfile) == "function" then
        local ok, res = pcall(readfile, path)
        return ok and res or nil
    end
    return nil
end
local function safeIsFile(path)
    if isfile and typeof(isfile) == "function" then
        local ok, res = pcall(isfile, path)
        return ok and res or false
    end
    return false
end
local function safeWriteFile(path, content)
    if writefile and typeof(writefile) == "function" then
        local ok = pcall(writefile, path, content)
        return ok
    end
    return false
end

local defaultConfig = {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0,
    ["MaxConcurrentRebuilds"] = 5,
    ["UseSpawnPositions"] = true,
    ["AutoSellConverted"] = true,
    ["ConvertedCheckInterval"] = 1,
    ["SpawnPositionTolerance"] = 0
}
local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
for k,v in pairs(defaultConfig) do
    if globalEnv.TDX_Config[k] == nil then globalEnv.TDX_Config[k] = v end
end

local function getMaxAttempts()
    return (globalEnv.TDX_Config.PlaceMode == "Rewrite" and 10) or 1
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local start = tick()
    while tick()-start < timeout do
        local ok, mod = pcall(function() return require(path) end)
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
assert(TowerClass, "Không thể load TowerClass. Vào map TDX rồi chạy lại.")

-- So sánh pos tuyệt đối (==)
local function vec3eq(a, b)
    return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

local function getTowerBySpawnPos(spawnPos)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local ok, cframe = pcall(function() return tower.SpawnCFrame end)
        local pos = (ok and cframe and typeof(cframe)=="CFrame") and cframe.Position or nil
        if pos and vec3eq(pos, spawnPos) then
            return tower, hash
        end
    end
    return nil, nil
end

local soldPositions = {}          -- [tostring(Vector3)] = true (bán tay/macro sell)
local convertedSoldPositions = {} -- [tostring(Vector3)] = true (convert sell)

local ConvertedTowerManager = {}
ConvertedTowerManager.__index = ConvertedTowerManager
function ConvertedTowerManager.new()
    local self = setmetatable({}, ConvertedTowerManager)
    self.convertedTowers = {}
    self.isActive = false
    return self
end
function ConvertedTowerManager:start()
    if self.isActive then return end
    self.isActive = true
    task.spawn(function()
        while self.isActive do
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local isConverted = false
                pcall(function() isConverted = tower.Converted == true end)
                if isConverted and not self.convertedTowers[hash] then
                    self.convertedTowers[hash] = true
                    local pos = tower.SpawnCFrame and tower.SpawnCFrame.Position
                    if pos then
                        local key = tostring(pos)
                        convertedSoldPositions[key] = true
                    end
                    if globalEnv.TDX_Config.AutoSellConverted then
                        pcall(function() Remotes.SellTower:FireServer(hash) end)
                    end
                elseif not isConverted and self.convertedTowers[hash] then
                    self.convertedTowers[hash] = nil
                end
            end
            task.wait(globalEnv.TDX_Config.ConvertedCheckInterval)
        end
    end)
end
local convertedManager = ConvertedTowerManager.new()

local function WaitForCash(amount)
    while cashStat.Value < amount do RunService.Heartbeat:Wait() end
end

local function PlaceTowerRetry(args, pos, towerName)
    local maxAttempts = getMaxAttempts()
    for attempt = 1, maxAttempts do
        local ok = pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
        if ok then
            local start = tick()
            repeat task.wait(0.1) until tick()-start > 3 or getTowerBySpawnPos(pos)
            if getTowerBySpawnPos(pos) then return true end
        end
        task.wait()
    end
    return false
end

local function UpgradeTowerRetry(pos, path)
    local maxAttempts = getMaxAttempts()
    for attempt = 1, maxAttempts do
        local tower, hash = getTowerBySpawnPos(pos)
        if not tower then task.wait() goto continue end
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = nil
        pcall(function()
            local maxLvl = tower.LevelHandler:GetMaxLevel()
            if before < maxLvl then
                cost = tower.LevelHandler:GetLevelUpgradeCost(path, 1)
            end
        end)
        if not cost then return true end
        WaitForCash(cost)
        local ok = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        if ok then
            local start = tick()
            repeat
                task.wait(0.1)
                local t = getTowerBySpawnPos(pos)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return true end
            until tick()-start > 3
        end
        ::continue::
        task.wait()
    end
    return false
end

local function ChangeTargetRetry(pos, targetType)
    local maxAttempts = getMaxAttempts()
    for attempt = 1, maxAttempts do
        local _, hash = getTowerBySpawnPos(pos)
        if hash then
            pcall(function() Remotes.ChangeQueryType:FireServer(hash, targetType) end)
            return
        end
        task.wait(0.1)
    end
end

local function SellTowerRetry(pos)
    local maxAttempts = getMaxAttempts()
    for attempt = 1, maxAttempts do
        local _, hash = getTowerBySpawnPos(pos)
        if hash then
            pcall(function() Remotes.SellTower:FireServer(hash) end)
            task.wait(0.1)
            if not getTowerBySpawnPos(pos) then
                soldPositions[tostring(pos)] = true
                return true
            end
        end
        task.wait()
    end
    return false
end

local function GetTowerPriority(towerName)
    for p, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then return p end
    end
    return math.huge
end

local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local config = globalEnv.TDX_Config
    local rebuildAttempts = {}
    local deadTowerTracker = { deadTowers = {}, nextDeathId = 1 }
    local function recordTowerDeath(posKey)
        if not deadTowerTracker.deadTowers[posKey] then
            deadTowerTracker.deadTowers[posKey] = {
                deathTime = tick(), deathId = deadTowerTracker.nextDeathId
            }
            deadTowerTracker.nextDeathId = deadTowerTracker.nextDeathId + 1
        end
    end
    local function clearTowerDeath(posKey)
        deadTowerTracker.deadTowers[posKey] = nil
    end
    local jobQueue, activeJobs = {}, {}

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local posKey, records, posVector = job.posKey, job.records, job.posVector
                    local rebuildSuccess = true
                    for _, record in ipairs(records) do
                        local action = record.entry
                        if action.TowerPlaced then
                            local vecTab = {}
                            for coord in action.TowerVector:gmatch("[^,%s]+") do table.insert(vecTab, tonumber(coord)) end
                            if #vecTab == 3 then
                                local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
                                local args = {
                                    tonumber(action.TowerA1),
                                    action.TowerPlaced,
                                    pos,
                                    tonumber(action.Rotation or 0)
                                }
                                WaitForCash(action.TowerPlaceCost)
                                if not PlaceTowerRetry(args, pos, action.TowerPlaced) then
                                    rebuildSuccess = false
                                    break
                                end
                            end
                        elseif action.TowerUpgraded then
                            if not UpgradeTowerRetry(posVector, action.UpgradePath) then
                                rebuildSuccess = false
                                break
                            end
                        elseif action.ChangeTarget then
                            ChangeTargetRetry(posVector, action.TargetType)
                        elseif action.SellTower then
                            SellTowerRetry(posVector)
                        end
                    end
                    if rebuildSuccess then
                        rebuildAttempts[posKey] = 0
                        clearTowerDeath(posKey)
                    end
                    activeJobs[posKey] = nil
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end
    for i = 1, config.MaxConcurrentRebuilds do RebuildWorker() end

    task.spawn(function()
        while true do
            if next(towerRecords) then
                for posKey, records in pairs(towerRecords) do
                    local posVector = records.posVector
                    local tower, hash = getTowerBySpawnPos(posVector)
                    if not tower or convertedManager.convertedTowers[hash] then
                        if not activeJobs[posKey] then
                            if soldPositions[posKey] and not convertedSoldPositions[posKey] and not config.ForceRebuildEvenIfSold then
                                continue
                            end
                            recordTowerDeath(posKey)
                            local towerType, firstPlaceRecord
                            for _, record in ipairs(records) do
                                if record.entry.TowerPlaced then
                                    towerType = record.entry.TowerPlaced
                                    firstPlaceRecord = record
                                    break
                                end
                            end
                            local skipRule = skipTypesMap[towerType]
                            local shouldSkip = false
                            if skipRule then
                                if skipRule.beOnly and firstPlaceRecord.line < skipRule.fromLine then
                                    shouldSkip = true
                                elseif not skipRule.beOnly then
                                    shouldSkip = true
                                end
                            end
                            if not shouldSkip then
                                rebuildAttempts[posKey] = (rebuildAttempts[posKey] or 0) + 1
                                local maxRetry = config.MaxRebuildRetry
                                if not maxRetry or rebuildAttempts[posKey] <= maxRetry then
                                    activeJobs[posKey] = true
                                    local priority = GetTowerPriority(towerType)
                                    table.insert(jobQueue, {
                                        posKey = posKey,
                                        posVector = posVector,
                                        records = records,
                                        priority = priority,
                                        deathTime = deadTowerTracker.deadTowers[posKey] and deadTowerTracker.deadTowers[posKey].deathTime or tick()
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
                    else
                        clearTowerDeath(posKey)
                        if activeJobs[posKey] then
                            activeJobs[posKey] = nil
                            for i = #jobQueue, 1, -1 do
                                if jobQueue[i].posKey == posKey then
                                    table.remove(jobQueue, i)
                                    break
                                end
                            end
                        end
                    end
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

local function RunMacroRunner()
    convertedManager:start()
    local config = globalEnv.TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/"..macroName..".json"
    assert(safeIsFile(macroPath), "Không tìm thấy file macro: "..macroPath)
    local macroContent = safeReadFile(macroPath)
    assert(macroContent, "Không thể đọc file macro")
    local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
    assert(ok and type(macro) == "table", "Lỗi parse macro file")

    local towerRecords, skipTypesMap = {}, {}
    local rebuildSystemActive = false

    for i, entry in ipairs(macro) do
        if entry.TowerPlaced or entry.TowerUpgraded or entry.ChangeTarget or entry.SellTower then
            local pos = nil
            if entry.TowerPlaced and entry.TowerVector then
                local vecTab = {}
                for coord in entry.TowerVector:gmatch("[^,%s]+") do table.insert(vecTab, tonumber(coord)) end
                if #vecTab == 3 then pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3]) end
            elseif entry.TowerUpgraded then
                pos = Vector3.new(tonumber(entry.TowerUpgraded), 0, 0)
            elseif entry.ChangeTarget then
                pos = Vector3.new(tonumber(entry.ChangeTarget), 0, 0)
            elseif entry.SellTower then
                pos = Vector3.new(tonumber(entry.SellTower), 0, 0)
            end
            if pos then
                local posKey = tostring(pos)
                towerRecords[posKey] = towerRecords[posKey] or {posVector=pos}
                table.insert(towerRecords[posKey], { entry = entry, line = i })
            end
        elseif entry.SkipType then
            skipTypesMap[entry.SkipType] = { beOnly = entry.BeOnly, fromLine = i }
        elseif entry.Start and not rebuildSystemActive then
            rebuildSystemActive = true
            StartRebuildSystem(entry, towerRecords, skipTypesMap)
        end
        task.wait(config.MacroStepDelay)
    end

    if not rebuildSystemActive then
        StartRebuildSystem(nil, towerRecords, skipTypesMap)
    end
end

local ok, err = pcall(RunMacroRunner)
if not ok then error("TDX Macro Runner error: "..tostring(err)) end