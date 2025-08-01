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
    ["RebuildPlaceDelay"] = 0.3,
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    -- SKIP CONFIGURATIONS
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {"Slammer", "Toxicnator"},
    ["SkipTowersByLine"] = {},
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

-- THÊM: Khởi tạo cache tower đang rebuild
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

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

-- THÊM: Hàm quản lý cache rebuild
local function AddToRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = true
end

local function RemoveFromRebuildCache(axisX)
    globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil
end

local function IsInRebuildCache(axisX)
    return globalEnv.TDX_REBUILDING_TOWERS[axisX] == true
end

-- ==== IMPROVED AUTO SELL CONVERTED TOWERS ====
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
                        
                        task.spawn(function()
                            pcall(function()
                                Remotes.SellTower:FireServer(hash)
                            end)
                        end)
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

-- Đặt lại 1 tower với retry logic
local function PlaceTowerEntry(entry)
    local vecTab = {}
    for c in tostring(entry.TowerVector):gmatch("[^,%s]+") do 
        table.insert(vecTab, tonumber(c)) 
    end
    if #vecTab ~= 3 then return false end

    local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
    local axisX = pos.X
    
    -- THÊM: Thêm vào cache rebuild
    AddToRebuildCache(axisX)
    
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
        repeat 
            task.wait(0.1)
        until tick() - startTime > 3 or GetTowerByAxis(pos.X)

        if GetTowerByAxis(pos.X) then 
            task.wait(globalEnv.TDX_Config.RebuildPlaceDelay or 0.3)
            -- THÊM: Xóa khỏi cache khi đặt thành công
            RemoveFromRebuildCache(axisX)
            return true
        end
    end
    
    -- THÊM: Xóa khỏi cache khi thất bại
    RemoveFromRebuildCache(axisX)
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

-- Nâng cấp tower với retry logic
local function UpgradeTowerEntry(entry)
    local axis = tonumber(entry.TowerUpgraded)
    local path = entry.UpgradePath
    local maxAttempts = 3
    local attempts = 0

    -- THÊM: Thêm vào cache rebuild
    AddToRebuildCache(axis)

    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axis)
        if not hash or not tower then 
            task.wait(0.1)
            attempts = attempts + 1
            continue 
        end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then 
            -- THÊM: Xóa khỏi cache khi không cần upgrade
            RemoveFromRebuildCache(axis)
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
                local _, t = GetTowerByAxis(axis)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                    -- THÊM: Xóa khỏi cache khi upgrade thành công
                    RemoveFromRebuildCache(axis)
                    return true 
                end
            until tick() - startTime > 3
        end

        attempts = attempts + 1
        task.wait(0.1)
    end
    
    -- THÊM: Xóa khỏi cache khi thất bại
    RemoveFromRebuildCache(axis)
    return false
end

-- Đổi target với retry logic
local function ChangeTargetEntry(entry)
    local axis = tonumber(entry.TowerTargetChange)
    local hash = GetTowerByAxis(axis)

    if not hash then return false end

    -- THÊM: Thêm vào cache rebuild
    AddToRebuildCache(axis)

    pcall(function()
        Remotes.ChangeQueryType:FireServer(hash, entry.TargetWanted)
    end)
    
    -- THÊM: Xóa khỏi cache sau khi thay đổi target
    RemoveFromRebuildCache(axis)
    return true
end

-- THÊM: Function để check xem skill có tồn tại không (từ runner.lua)
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

    -- THÊM: Thêm vào cache rebuild
    AddToRebuildCache(axisValue)

    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then 
        RemoveFromRebuildCache(axisValue)
        return false 
    end

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

    -- THÊM: Xóa khỏi cache sau khi sử dụng skill
    RemoveFromRebuildCache(axisValue)
    return success
end

-- SỬA: Worker function với moving skills đợi skill tồn tại (dựa trên runner.lua)
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

    -- Step 2: Apply moving skills ASAP when skills become available (từ runner.lua)
    if rebuildSuccess and #movingRecords > 0 then
        -- Start a separate task to handle moving skills
        task.spawn(function()
            -- Get the last moving skill for this tower
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry

            -- Wait for skill to become available (không có timeout)
            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end

            -- Use the skill immediately when available
            UseMovingSkillEntry(entry)
        end)
    end

    -- Step 3: Upgrade towers (in order) - Run in parallel with moving skills
    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerEntry(entry) then
                rebuildSuccess = false
                break
            end
            task.wait(0.1)
        end
    end

    -- Step 4: Change targets
    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetEntry(entry)
            task.wait(0.05)
        end
    end

    return rebuildSuccess
end

-- Hàm chính: Liên tục reload record + rebuild với worker system
task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis = {}
    local soldAxis = {}
    local rebuildAttempts = {}

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
                        end
                    else
                        rebuildAttempts[x] = 0
                    end

                    activeJobs[x] = nil
                else
                    RunService.Heartbeat:Wait()
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

        -- Rebuild nếu phát hiện tower chết
        for x, records in pairs(towersByAxis) do
            if globalEnv.TDX_Config.ForceRebuildEvenIfSold or not soldAxis[x] then
                local hash, tower = GetTowerByAxis(x)
                if not hash or not tower then
                    if not activeJobs[x] then
                        rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                        local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry

                        if not maxRetry or rebuildAttempts[x] <= maxRetry then
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

                            activeJobs[x] = true
                            local priority = GetTowerPriority(towerType or "Unknown")
                            table.insert(jobQueue, { 
                                x = x, 
                                records = records, 
                                priority = priority,
                                deathTime = tick(),
                                towerName = towerType,
                                firstPlaceLine = firstPlaceLine
                            })

                            table.sort(jobQueue, function(a, b) 
                                if a.priority == b.priority then
                                    return a.deathTime < b.deathTime
                                end
                                return a.priority < b.priority 
                            end)
                        end
                    end
                else
                    rebuildAttempts[x] = 0
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
            end
        end

        task.wait()  
    end
end)