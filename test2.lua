--- START OF FILE rebuild.lua (FINAL VERSION - All Updates Included) ---

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/endless.json"

-- Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

-- Cấu hình mặc định
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster", "XWM Turret"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = 5, -- Giới hạn số lần thử lại để tránh vòng lặp vô tận
    ["PlaceMode"] = "Rewrite",
    ["VerificationDelay"] = 1.5, -- Thời gian chờ (giây) trước khi luồng kiểm tra chạy
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
    if placeMode == "Ashed" then return 1 end
    if placeMode == "Rewrite" then return 10 end
    return 1
end

local function safeReadFile(path)
    if readfile and isfile and isfile(path) then
        local ok, res = pcall(readfile, path)
        if ok then return res end
    end
    return nil
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5; local t0 = tick()
    while tick() - t0 < timeout do
        local ok, mod = pcall(require, path)
        if ok and mod then return mod end
        RunService.Heartbeat:Wait()
    end
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    local client = ps:FindFirstChild("Client"); if not client then return nil end
    local gameClass = client:FindFirstChild("GameClass"); if not gameClass then return nil end
    local towerModule = gameClass:FindFirstChild("TowerClass"); if not towerModule then return nil end
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then error("Không thể load TowerClass!") end

local function AddToRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = true end
local function RemoveFromRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                pcall(function() Remotes.SellTower:FireServer(hash) end); task.wait(0.1)
            end
        end
    end
end)

-- CẬP NHẬT: Đảm bảo sử dụng so sánh tuyệt đối theo yêu cầu
local function GetTowerByAxis(targetX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local spawnCFrame = tower.SpawnCFrame
        if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
            if spawnCFrame.Position.X == targetX then
                return hash, tower
            end
        end
    end
    return nil, nil
end

-- CẬP NHẬT: Hàm chờ mới để đảm bảo tower đã sẵn sàng
local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5; local startTime = tick()
    while tick() - startTime < timeout do
        local hash, tower = GetTowerByAxis(axisX)
        if hash and tower and tower.LevelHandler then
            return hash, tower
        end
        task.wait()
    end
    return nil, nil
end

local function WaitForCash(amount)
    while cash.Value < amount do RunService.Heartbeat:Wait() end
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then return priority end
    end
    return math.huge
end

local function ShouldSkipTower(axisX, towerName, firstPlaceLine)
    local config = globalEnv.TDX_Config
    if config.SkipTowersAtAxis and table.find(config.SkipTowersAtAxis, axisX) then return true end
    if config.SkipTowersByName and table.find(config.SkipTowersByName, towerName) then return true end
    if config.SkipTowersByLine and firstPlaceLine and table.find(config.SkipTowersByLine, firstPlaceLine) then return true end
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
    pcall(function() disc = tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    return math.floor(baseCost * (1 - disc))
end

-- === CÁC HÀM THỰC THI HÀNH ĐỘNG (EXECUTION) ===

local function PlaceTower(args, axisValue)
    for i = 1, getMaxAttempts() do
        pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if tower then return true end
        task.wait()
    end
    return false
end

local function UpgradeTower(axisValue, path)
    for i = 1, getMaxAttempts() do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if not hash then task.wait(); continue end
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return true end -- Max level
        WaitForCash(cost)
        pcall(function() Remotes.TowerUpgradeRequest:FireServer(hash, path, 1) end)
        local startTime = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler and t.LevelHandler:GetLevelOnPath(path) > before then return true end
        until tick() - startTime > 3
        task.wait()
    end
    return false
end

local function ChangeTarget(axisValue, targetType)
    local hash = GetTowerByAxis(axisValue)
    if hash then pcall(function() Remotes.ChangeQueryType:FireServer(hash, targetType) end) end
end

local function UseMovingSkill(axisValue, skillIndex, location)
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then return false end
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    local hash, tower = WaitForTowerInitialization(axisValue)
    if hash and tower and tower.AbilityHandler then
        local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
        if not ability then return false end
        local cooldown = ability.CooldownRemaining or 0
        if cooldown > 0 then task.wait(cooldown + 0.1) end
        if location == "no_pos" then
            pcall(function()
                if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex) else TowerUseAbilityRequest:InvokeServer(hash, skillIndex) end
            end)
        else
            local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
            if x and y and z then
                local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                pcall(function()
                    if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex, pos) else TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos) end
                end)
            end
        end
    end
end


-- CẬP NHẬT: Hệ thống 2 luồng Thực Thi và Kiểm Tra
task.spawn(function()
    local lastMacroHash, towersByAxis, soldAxis, rebuildAttempts = "", {}, {}, {}
    local jobQueue, verificationQueue, activeJobs = {}, {}, {}

    -- Luồng 1: Thực thi (RebuildWorker)
    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    
                    AddToRebuildCache(x)
                    
                    local placeRecord, upgradeRecords, targetRecords, movingRecords = nil, {}, {}, {}
                    for _, record in ipairs(job.records) do
                        local entry = record.entry
                        if entry.TowerPlaced then placeRecord = record
                        elseif entry.TowerUpgraded then table.insert(upgradeRecords, record)
                        elseif entry.TowerTargetChange then table.insert(targetRecords, record)
                        elseif entry.towermoving then table.insert(movingRecords, record) end
                    end

                    local rebuildSuccess = true
                    if placeRecord then
                        local entry = placeRecord.entry; local vecTab = {}
                        for coord in entry.TowerVector:gmatch("[^,%s]+") do table.insert(vecTab, tonumber(coord)) end
                        if #vecTab == 3 then
                            local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
                            local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
                            WaitForCash(entry.TowerPlaceCost)
                            if not PlaceTower(args, pos.X) then rebuildSuccess = false end
                        end
                    end

                    if rebuildSuccess then
                        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
                        for _, record in ipairs(upgradeRecords) do
                            if not UpgradeTower(tonumber(record.entry.TowerUpgraded), record.entry.UpgradePath) then
                                rebuildSuccess = false; break
                            end
                            task.wait(0.1)
                        end
                    end

                    if rebuildSuccess then
                        for _, record in ipairs(targetRecords) do
                            ChangeTarget(tonumber(record.entry.TowerTargetChange), record.entry.TargetWanted)
                            task.wait(0.05)
                        end
                    end

                    if rebuildSuccess and #movingRecords > 0 then
                        local lastMoving = movingRecords[#movingRecords].entry
                        UseMovingSkill(lastMoving.towermoving, lastMoving.skillindex, lastMoving.location)
                    end
                    
                    RemoveFromRebuildCache(x)
                    -- Đưa job vào hàng đợi kiểm tra
                    job.executionTime = tick()
                    table.insert(verificationQueue, job)
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    -- Luồng 2: Kiểm tra (VerificationWorker)
    local function VerificationWorker()
        task.spawn(function()
            while true do
                if #verificationQueue > 0 then
                    local job = verificationQueue[1]
                    if tick() - job.executionTime > globalEnv.TDX_Config.VerificationDelay then
                        table.remove(verificationQueue, 1)
                        local x = job.x
                        local _, tower = GetTowerByAxis(x)
                        
                        local targetLvlP1, targetLvlP2 = 0, 0
                        for _, record in ipairs(job.records) do
                            if record.entry.TowerUpgraded and record.entry.UpgradePath == 1 then targetLvlP1 = targetLvlP1 + 1 end
                            if record.entry.TowerUpgraded and record.entry.UpgradePath == 2 then targetLvlP2 = targetLvlP2 + 1 end
                        end
                        
                        local isVerified = false
                        if tower and tower.LevelHandler then
                           if tower.LevelHandler:GetLevelOnPath(1) == targetLvlP1 and tower.LevelHandler:GetLevelOnPath(2) == targetLvlP2 then
                               isVerified = true
                           end
                        end

                        if isVerified then
                            -- Thành công, dọn dẹp
                            rebuildAttempts[x] = nil
                            activeJobs[x] = nil
                        else
                            -- Thất bại, đưa lại vào hàng đợi chính
                            local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry
                            if not maxRetry or (rebuildAttempts[x] or 0) < maxRetry then
                                table.insert(jobQueue, 1, job) -- Đưa lên đầu hàng đợi để thử lại ngay
                            else
                                -- Đạt giới hạn thử lại, từ bỏ
                                activeJobs[x] = nil
                            end
                        end
                    else
                         RunService.Heartbeat:Wait()
                    end
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    -- Khởi tạo các workers
    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do RebuildWorker() end
    VerificationWorker() -- Chỉ cần 1 worker kiểm tra

    -- Luồng chính: Producer (Phát hiện tower chết)
    while true do
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = #macroContent .. "|" .. macroContent:sub(1, 50)
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                local ok, macro = pcall(HttpService.JSONDecode, HttpService, macroContent)
                if ok and type(macro) == "table" then
                    towersByAxis, soldAxis = {}, {}
                    for i, entry in ipairs(macro) do
                        local x = nil
                        if entry.SellTower then x = tonumber(entry.SellTower); if x then soldAxis[x] = true end
                        elseif entry.TowerPlaced and entry.TowerVector then x = tonumber(entry.TowerVector:match("^([%d%-%.]+),"))
                        elseif entry.TowerUpgraded then x = tonumber(entry.TowerUpgraded)
                        elseif entry.TowerTargetChange then x = tonumber(entry.TowerTargetChange)
                        elseif entry.towermoving then x = entry.towermoving end
                        if x then
                            towersByAxis[x] = towersByAxis[x] or {}; table.insert(towersByAxis[x], {line = i, entry = entry})
                        end
                    end
                end
            end
        end

        local existingTowersCache = {}
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                existingTowersCache[tower.SpawnCFrame.Position.X] = true
            end
        end

        local jobsAdded = false
        for x, records in pairs(towersByAxis) do
            if not activeJobs[x] and not (globalEnv.TDX_Config.ForceRebuildEvenIfSold == false and soldAxis[x]) and not existingTowersCache[x] then
                local towerType, firstPlaceLine = nil, nil
                for _, record in ipairs(records) do
                    if record.entry.TowerPlaced then
                        towerType, firstPlaceLine = record.entry.TowerPlaced, record.line; break
                    end
                end
                if towerType and not ShouldSkipTower(x, towerType, firstPlaceLine) then
                    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                    activeJobs[x] = true
                    table.insert(jobQueue, {
                        x = x, records = records, priority = GetTowerPriority(towerType),
                        deathTime = tick(), towerName = towerType, firstPlaceLine = firstPlaceLine
                    })
                    jobsAdded = true
                end
            end
        end

        if jobsAdded and #jobQueue > 1 then
            table.sort(jobQueue, function(a, b) 
                if a.priority == b.priority then return a.deathTime < b.deathTime end
                return a.priority < b.priority 
            end)
        end

        RunService.Heartbeat:Wait()
    end
end)