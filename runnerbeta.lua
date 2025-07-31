local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

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

local function safeWriteFile(path, content)
    if writefile and typeof(writefile) == "function" then
        local success = pcall(writefile, path, content)
        return success
    end
    return false
end

local function safeMakeFolder(path)
    if makefolder and typeof(makefolder) == "function" then
        local success = pcall(makefolder, path)
        return success
    end
    return false
end

-- Cấu hình mặc định
local defaultConfig = {
    ["Macro Name"] = "i",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = true,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0.1,
    ["MaxConcurrentRebuilds"] = 5,
    ["RebuildPlaceDelay"] = 0.3
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

local function getMaxAttempts()
    local placeMode = globalEnv.TDX_Config.PlaceMode or "Ashed"
    if placeMode == "Ashed" then
        return 1
    elseif placeMode == "Rewrite" then
        return 10
    else
        return 1
    end
end

local function SafeRequire(path)
    while true do
        local success, result = pcall(function() return require(path) end)
        if success and result then return result end
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
if not TowerClass then 
    error("Không thể load TowerClass - vui lòng đảm bảo bạn đang trong game TDX")
end

-- ==== TÍCH HỢP AUTO SELL CONVERT + REBUILD ====
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

local function getGameUI()
    while true do
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                local waveFrame = gameInfoBar:FindFirstChild("Wave")
                local timeFrame = gameInfoBar:FindFirstChild("TimeLeft")
                if waveFrame and timeFrame then
                    local waveText = waveFrame:FindFirstChild("WaveText")
                    local timeText = timeFrame:FindFirstChild("TimeLeftText")
                    if waveText and timeText then
                        return {
                            waveText = waveText,
                            timeText = timeText
                        }
                    end
                end
            end
        end
        task.wait(1)
    end
end

local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then
        for _, name in ipairs(skipList) do
            skipMap[name] = true
        end
    end
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        if model then
            local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
            if root and not skipMap[root.Name] then
                pcall(function()
                    Remotes.SellTower:FireServer(hash)
                end)
                task.wait(globalEnv.TDX_Config.SellAllDelay or 0.1)
            end
        end
    end
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

-- Function để kiểm tra skill có sẵn không
local function CheckSkillAvailable(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end
    
    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

-- Function để đợi skill xuất hiện
local function WaitForSkillToAppear(axisValue, skillIndex)
    while true do
        if CheckSkillAvailable(axisValue, skillIndex) then
            return true
        end
        RunService.Heartbeat:Wait()
    end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    while attempts < maxAttempts do
        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        if success then
            while true do
                if GetTowerByAxis(axisValue) then 
                    return true
                end
                task.wait(0.1)
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
            while true do
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return true end
                task.wait(0.1)
            end
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
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
end

-- Function để sử dụng moving skill
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
                while true do
                    local _, updatedTower = GetTowerByAxis(axisValue)
                    if updatedTower and updatedTower.AbilityHandler then
                        local updatedAbility = updatedTower.AbilityHandler:GetAbilityFromIndex(skillIndex)
                        if updatedAbility and (updatedAbility.CooldownRemaining or 0) <= 0 then
                            break
                        end
                    end
                    task.wait(0.1)
                end
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

local function SellTowerRetry(axisValue)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.SellTower:FireServer(hash)
            end)
            task.wait(0.1)
            if not GetTowerByAxis(axisValue) then return true end
        end
        attempts = attempts + 1
        task.wait()
    end
    return false
end

local function shouldChangeTarget(entry, currentWave, currentTime)
    if entry.TargetWave and entry.TargetWave ~= currentWave then
        return false
    end
    if entry.TargetChangedAt then
        local targetTimeStr = convertToTimeFormat(entry.TargetChangedAt)
        if currentTime ~= targetTimeStr then
            return false
        end
    end
    return true
end

-- Function để kiểm tra nếu nên sử dụng moving skill
local function shouldUseMovingSkill(entry, currentWave, currentTime)
    if entry.wave and entry.wave ~= currentWave then
        return false
    end
    if entry.time then
        local targetTimeStr = convertToTimeFormat(entry.time)
        if currentTime ~= targetTimeStr then
            return false
        end
    end
    return true
end

local function StartTargetChangeMonitor(targetChangeEntries, gameUI)
    local processedEntries = {}

    task.spawn(function()
        while true do
            local success, currentWave, currentTime = pcall(function()
                return gameUI.waveText.Text, gameUI.timeText.Text
            end)

            if success then
                for i, entry in ipairs(targetChangeEntries) do
                    if not processedEntries[i] and shouldChangeTarget(entry, currentWave, currentTime) then
                        local axisValue = entry.TowerTargetChange
                        local targetType = entry.TargetWanted

                        ChangeTargetRetry(axisValue, targetType)
                        processedEntries[i] = true
                    end
                end
            end

            task.wait(globalEnv.TDX_Config.TargetChangeCheckDelay)
        end
    end)
end

-- Function để monitor moving skills
local function StartMovingSkillMonitor(movingSkillEntries, gameUI)
    local processedEntries = {}

    task.spawn(function()
        while true do
            local success, currentWave, currentTime = pcall(function()
                return gameUI.waveText.Text, gameUI.timeText.Text
            end)

            if success then
                for i, entry in ipairs(movingSkillEntries) do
                    if not processedEntries[i] and shouldUseMovingSkill(entry, currentWave, currentTime) then
                        local axisValue = entry.towermoving
                        local skillIndex = entry.skillindex
                        local location = entry.location

                        if UseMovingSkillRetry(axisValue, skillIndex, location) then
                            processedEntries[i] = true
                        end
                    end
                end
            end

            task.wait(globalEnv.TDX_Config.TargetChangeCheckDelay)
        end
    end)
end

local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local config = globalEnv.TDX_Config
    local rebuildAttempts = {}
    local soldPositions = {}

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

    -- Worker system với fixed sequence
    local jobQueue = {}
    local activeJobs = {}

    -- Worker function - Fixed rebuild sequence: Place -> Upgrade -> Target hoàn thành -> Đợi skill -> Moving
    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records

                    -- Organize records by type với thứ tự cố định
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
                                task.wait(config.RebuildPlaceDelay or 0.5)
                            else
                                rebuildSuccess = false
                            end
                        end
                    end

                    -- Step 2: Upgrade towers (in order)
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

                    -- Step 4: Đợi skills xuất hiện và apply moving ski