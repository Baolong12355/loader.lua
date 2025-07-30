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
    ["MaxRebuildRetry"] = nil
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

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

-- Đặt lại 1 tower với retry logic
local function PlaceTowerEntry(entry)
    local vecTab = {}
    for c in tostring(entry.TowerVector):gmatch("[^,%s]+") do 
        table.insert(vecTab, tonumber(c)) 
    end
    if #vecTab ~= 3 then return false end
    
    local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
    WaitForCash(entry.TowerPlaceCost or 0)
    
    local args = {
        tonumber(entry.TowerA1), 
        entry.TowerPlaced, 
        pos, 
        tonumber(entry.Rotation or 0)
    }
    
    _G.TDX_REBUILD_RUNNING = true
    local success = pcall(function() 
        Remotes.PlaceTower:InvokeServer(unpack(args)) 
    end)
    _G.TDX_REBUILD_RUNNING = false
    
    if success then
        -- Chờ xuất hiện tower với timeout
        local startTime = tick()
        repeat 
            task.wait(0.1)
        until tick() - startTime > 3 or GetTowerByAxis(pos.X)
        
        if GetTowerByAxis(pos.X) then 
            -- Thêm delay sau khi place thành công để tránh dupe
            task.wait(globalEnv.TDX_Config.RebuildPlaceDelay or 0.3)
            return true
        end
    end
    return false
end

-- Nâng cấp tower với retry logic
local function UpgradeTowerEntry(entry)
    local axis = tonumber(entry.TowerUpgraded)
    local path = entry.UpgradePath
    local hash, tower = GetTowerByAxis(axis)
    
    if not hash or not tower then return false end
    
    local before = tower.LevelHandler:GetLevelOnPath(path)
    WaitForCash(entry.UpgradeCost or 0)
    
    _G.TDX_REBUILD_RUNNING = true
    local success = pcall(function()
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
    end)
    _G.TDX_REBUILD_RUNNING = false
    
    if success then
        -- Verify upgrade thành công
        local startTime = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axis)
            if t and t.LevelHandler:GetLevelOnPath(path) > before then 
                return true 
            end
        until tick() - startTime > 3
    end
    return false
end

-- Đổi target với retry logic
local function ChangeTargetEntry(entry)
    local axis = tonumber(entry.TowerTargetChange)
    local hash = GetTowerByAxis(axis)
    
    if not hash then return false end
    
    _G.TDX_REBUILD_RUNNING = true
    pcall(function()
        Remotes.ChangeQueryType:FireServer(hash, entry.TargetWanted)
    end)
    _G.TDX_REBUILD_RUNNING = false
    return true
end

-- Function để sử dụng moving skill
local function UseMovingSkillEntry(entry)
    local axisValue = entry.towermoving
    local skillIndex = entry.skillindex
    local location = entry.location
    
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower then return false end
    
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then return false end
    
    if not tower.AbilityHandler then return false end
    
    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    if not ability then return false end
    
    local cooldown = ability.CooldownRemaining or 0
    if cooldown > 0 then
        task.wait(cooldown + 0.1)
    end
    
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    
    _G.TDX_REBUILD_RUNNING = true
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
    
    _G.TDX_REBUILD_RUNNING = false
    return success
end

-- Worker function với fixed sequence: Place -> Upgrade -> Target -> Moving
local function RebuildTowerSequence(records)
    -- Organize records by type với thứ tự cố định
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
    
    -- Step 2: Upgrade towers (in order) - chỉ làm khi place thành công
    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerEntry(entry) then
                rebuildSuccess = false
                break
            end
            task.wait(0.1) -- Small delay between upgrades
        end
    end
    
    -- Step 3: Change targets - chỉ làm khi upgrade hoàn thành
    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetEntry(entry)
            task.wait(0.05)
        end
    end
    
    -- Step 4: Apply moving skills - CHỈ làm khi TẤT CẢ place, upgrade, target đã hoàn thành
    if rebuildSuccess and #movingRecords > 0 then
        -- Đợi thêm một chút để đảm bảo mọi thứ đã xong
        task.wait(0.2)
        
        -- Get the last moving skill for this tower
        local lastMovingRecord = movingRecords[#movingRecords]
        local entry = lastMovingRecord.entry
        UseMovingSkillEntry(entry)
        task.wait(0.1)
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
                    
                    if RebuildTowerSequence(records) then
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
        -- Reload macro record nếu có thay đổi/new data
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = tostring(#macroContent) .. "|" .. tostring(macroContent:sub(1,50))
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                -- Parse lại macro file
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
                    print("[TDX Rebuild] Đã reload record mới: ", macroPath)
                end
            end
        end
        
        -- Rebuild nếu phát hiện tower chết
        for x, records in pairs(towersByAxis) do
            if globalEnv.TDX_Config.ForceRebuildEvenIfSold or not soldAxis[x] then
                local hash, tower = GetTowerByAxis(x)
                if not hash or not tower then
                    -- Tower không tồn tại (chết HOẶC bị bán)
                    if not activeJobs[x] then -- Chưa có job rebuild
                        rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                        local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry
                        
                        if not maxRetry or rebuildAttempts[x] <= maxRetry then
                            -- Get tower type for priority
                            local towerType = nil
                            for _, record in ipairs(records) do
                                if record.entry.TowerPlaced then 
                                    towerType = record.entry.TowerPlaced
                                    break
                                end
                            end
                            
                            -- Add to queue với priority
                            activeJobs[x] = true
                            local priority = GetTowerPriority(towerType or "Unknown")
                            table.insert(jobQueue, { 
                                x = x, 
                                records = records, 
                                priority = priority,
                                deathTime = tick()
                            })
                            
                            -- Sort by priority, then by death time (older first)
                            table.sort(jobQueue, function(a, b) 
                                if a.priority == b.priority then
                                    return a.deathTime < b.deathTime
                                end
                                return a.priority < b.priority 
                            end)
                        end
                    end
                else
                    -- Tower sống, cleanup attempts
                    rebuildAttempts[x] = 0
                    if activeJobs[x] then
                        activeJobs[x] = nil
                        -- Remove from queue if exists
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
        
        task.wait() -- Luôn reload record mới mỗi 1.5 giây
    end
end)

print("[TDX Macro Rebuild with Moving Skills] Đã hoạt động!")