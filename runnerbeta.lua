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
    ["Macro Name"] = "e",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0,
    ["MaxConcurrentRebuilds"] = 5
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

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local success, result = pcall(function() return require(path) end)
        if success and result then return result end
        RunService.Heartbeat:Wait()
    end
    return nil
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
    local attempts = 0
    while attempts < 30 do
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
        attempts = attempts + 1
        task.wait(1)
    end
    error("Không thể tìm thấy Game UI")
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

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
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
                return true
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
            local startTime = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return true end
            until tick() - startTime > 3
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

-- NEW: Function để sử dụng moving skill
local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    
    -- Kiểm tra remote type
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then
        print("❌ Không tìm thấy TowerUseAbilityRequest remote")
        return false
    end
    
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    print(string.format("🔧 Remote type: %s, sử dụng %s", 
        TowerUseAbilityRequest.ClassName, useFireServer and "FireServer" or "InvokeServer"))
    
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if hash and tower then
            -- Kiểm tra tower có ability handler không
            if not tower.AbilityHandler then
                print(string.format("❌ Tower tại X=%.2f không có AbilityHandler", axisValue))
                return false
            end
            
            -- Kiểm tra ability tại index có tồn tại không
            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                print(string.format("❌ Tower tại X=%.2f không có skill index %d", axisValue, skillIndex))
                return false
            end
            
            -- Kiểm tra cooldown
            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then
                print(string.format("⏰ Skill %d của tower X=%.2f đang cooldown: %.2fs", skillIndex, axisValue, cooldown))
                -- Có thể chọn wait hoặc skip
                -- task.wait(cooldown + 0.1)
            end
            
            print(string.format("🔧 Tower type: %s, Skill index: %d, Hash: %s", 
                tostring(tower.Type), skillIndex, tostring(hash)))
            
            local success = false
            if location == "no_pos" then
                -- Skill không cần position (skill 3)
                success = pcall(function()
                    if useFireServer then
                        TowerUseAbilityRequest:FireServer(hash, skillIndex)
                    else
                        TowerUseAbilityRequest:InvokeServer(hash, skillIndex)
                    end
                end)
                print(string.format("✅ Sử dụng skill %d cho tower tại X=%.2f (no position)", skillIndex, axisValue))
            else
                -- Skill cần position, parse location string thành Vector3
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
                    print(string.format("✅ Sử dụng skill %d cho tower tại X=%.2f -> Vị trí: %.2f, %.2f, %.2f", 
                        skillIndex, axisValue, pos.X, pos.Y, pos.Z))
                else
                    print(string.format("❌ Không thể parse location: '%s'", location))
                end
            end
            
            if success then
                return true
            end
        else
            print(string.format("❌ Không tìm thấy tower tại X=%.2f", axisValue))
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

-- NEW: Function để kiểm tra nếu nên sử dụng moving skill
local function shouldUseMovingSkill(entry, currentWave, currentTime)
    -- Debug log
    print(string.format("🔍 Kiểm tra moving skill: Entry wave='%s' vs Current='%s', Entry time=%s vs Current='%s'", 
        tostring(entry.wave), tostring(currentWave), tostring(entry.time), tostring(currentTime)))
    
    if entry.wave and entry.wave ~= currentWave then
        print("❌ Wave không khớp")
        return false
    end
    if entry.time then
        local targetTimeStr = convertToTimeFormat(entry.time)
        print(string.format("🕐 So sánh thời gian: Target='%s' vs Current='%s'", targetTimeStr, currentTime))
        if currentTime ~= targetTimeStr then
            print("❌ Thời gian không khớp")
            return false
        end
    end
    print("✅ Điều kiện khớp, sẽ sử dụng skill")
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

-- NEW: Function để monitor moving skills
local function StartMovingSkillMonitor(movingSkillEntries, gameUI)
    local processedEntries = {}
    
    print(string.format("🎯 Khởi động Moving Skill Monitor với %d entries", #movingSkillEntries))
    for i, entry in ipairs(movingSkillEntries) do
        print(string.format("   Entry %d: Tower X=%.2f, Skill=%d, Wave='%s', Time=%s, Location='%s'", 
            i, entry.towermoving, entry.skillindex, tostring(entry.wave), tostring(entry.time), entry.location))
    end

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

                        print(string.format("🚀 Thực hiện moving skill: Tower X=%.2f, Skill=%d, Location='%s'", 
                            axisValue, skillIndex, location))
                        
                        if UseMovingSkillRetry(axisValue, skillIndex, location) then
                            processedEntries[i] = true
                            print(string.format("✅ Moving skill thành công cho entry %d", i))
                        else
                            print(string.format("❌ Moving skill thất bại cho entry %d", i))
                        end
                    end
                end
            else
                print("❌ Không thể lấy thông tin wave/time từ UI")
            end

            task.wait(globalEnv.TDX_Config.TargetChangeCheckDelay)
        end
    end)
end

-- Hàm rebuild lại tower nếu bị convert auto sell
local function RebuildIfNeeded(axisX, placeArgs)
    local hash, tower = GetTowerByAxis(axisX)
    if not hash and soldConvertedX[axisX] then
        local ok = false
        for i = 1, getMaxAttempts() do
            ok = pcall(function()
                Remotes.PlaceTower:InvokeServer(unpack(placeArgs))
            end)
            if ok then
                local t1 = tick()
                repeat
                    local h = GetTowerByAxis(axisX)
                    if h then break end
                    task.wait(0.1)
                until tick() - t1 > 3
                if GetTowerByAxis(axisX) then break end
            end
            task.wait(0.1)
        end
        if ok then
            soldConvertedX[axisX] = nil
        end
    end
end

local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local config = globalEnv.TDX_Config
    local rebuildAttempts = {}
    local soldPositions = {}

    -- Tracking system cho towers đã chết (từ v19)
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

    -- Worker system (từ v20) với cải tiến
    local jobQueue = {}
    local activeJobs = {}

    -- Worker function - Optimized rebuild with moving skills support
    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local x = job.x
                    local records = job.records

                    -- NEW: Tìm moving skill cuối cùng cho tower này
                    local lastMovingSkill = nil
                    for _, record in ipairs(records) do
                        if record.entry.towermoving then
                            lastMovingSkill = record.entry
                        end
                    end

                    local rebuildSuccess = true
                    for _, record in ipairs(records) do
                        local action = record.entry

                        if action.TowerPlaced then
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
                                if not PlaceTowerRetry(args, pos.X, action.TowerPlaced) then
                                    rebuildSuccess = false
                                    break
                                end
                            end

                        elseif action.TowerUpgraded then
                            -- Đảm bảo upgrade thành công, nếu fail thì retry
                            if not UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath) then
                                rebuildSuccess = false
                                break
                            end

                        elseif action.ChangeTarget then
                            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)

                        elseif action.SellTower then
                            if SellTowerRetry(tonumber(action.SellTower)) then
                                soldPositions[tonumber(action.SellTower)] = true
                            end

                        -- NEW: Xử lý moving skill - chỉ dùng cái cuối cùng
                        elseif action.towermoving then
                            -- Chỉ thực hiện nếu đây là moving skill cuối cùng của tower này
                            if action == lastMovingSkill then
                                print(string.format("🔄 Rebuild: Sử dụng moving skill cuối cùng cho tower X=%.2f", action.towermoving))
                                UseMovingSkillRetry(action.towermoving, action.skillindex, action.location)
                                task.wait(0.2) -- Thêm delay nhỏ sau khi dùng skill
                            end
                        end
                    end

                    -- Cleanup sau khi rebuild
                    if rebuildSuccess then
                        rebuildAttempts[x] = 0
                        clearTowerDeath(x)
                    end

                    activeJobs[x] = nil
                else
                    RunService.Heartbeat:Wait() -- Sử dụng heartbeat thay vì task.wait
                end
            end
        end)
    end

    -- Khởi tạo workers
    for i = 1, config.MaxConcurrentRebuilds do
        RebuildWorker()
    end

    -- Producer - Fast detection system
    task.spawn(function()
        while true do
            if next(towerRecords) then
                for x, records in pairs(towerRecords) do
                    local hash, tower = GetTowerByAxis(x)

                    if not hash or not tower then
                        -- Tower không tồn tại (chết HOẶC bị bán)
                        if not activeJobs[x] then -- Chưa có job rebuild
                            -- Kiểm tra xem tower có bị bán không
                            if soldPositions[x] and not config.ForceRebuildEvenIfSold then
                                -- Tower đã bị bán và không force rebuild
                                continue
                            end

                            recordTowerDeath(x)

                            local towerType = nil
                            local firstPlaceRecord = nil

                            for _, record in ipairs(records) do
                                if record.entry.TowerPlaced then 
                                    towerType = record.entry.TowerPlaced
                                    firstPlaceRecord = record
                                    break
                                end
                            end

                            if towerType then
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
                                    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                                    local maxRetry = config.MaxRebuildRetry

                                    if not maxRetry or rebuildAttempts[x] <= maxRetry then
                                        -- Add to queue với priority
                                        activeJobs[x] = true
                                        local priority = GetTowerPriority(towerType)
                                        table.insert(jobQueue, { 
                                            x = x, 
                                            records = records, 
                                            priority = priority,
                                            deathTime = deadTowerTracker.deadTowers[x] and deadTowerTracker.deadTowers[x].deathTime or tick()
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
                            end
                        end
                    else
                        -- Tower sống, cleanup
                        clearTowerDeath(x)
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

            RunService.Heartbeat:Wait() -- Sử dụng heartbeat để response nhanh nhất
        end
    end)
end

local function RunMacroRunner()
    local config = globalEnv.TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/" .. macroName .. ".json"

    if not safeIsFile(macroPath) then 
        error("Không tìm thấy file macro: " .. macroPath)
    end

    local macroContent = safeReadFile(macroPath)
    if not macroContent then
        error("Không thể đọc file macro")
    end

    local ok, macro = pcall(function() 
        return HttpService:JSONDecode(macroContent) 
    end)

    if not ok or type(macro) ~= "table" then 
        error("Lỗi parse macro file")
    end

    local gameUI = getGameUI()
    local towerRecords = {}
    local skipTypesMap = {}
    local targetChangeEntries = {}
    local movingSkillEntries = {} -- NEW: Array cho moving skills
    local rebuildSystemActive = false

    -- NEW: Phân loại các entries theo loại
    for i, entry in ipairs(macro) do
        if entry.TowerTargetChange then
            table.insert(targetChangeEntries, entry)
        elseif entry.towermoving then -- NEW: Moving skill entries
            table.insert(movingSkillEntries, entry)
        end
    end

    if #targetChangeEntries > 0 then
        StartTargetChangeMonitor(targetChangeEntries, gameUI)
    end

    -- NEW: Start moving skill monitor
    if #movingSkillEntries > 0 then
        StartMovingSkillMonitor(movingSkillEntries, gameUI)
    end

    for i, entry in ipairs(macro) do
        if entry.SuperFunction == "sell_all" then
            SellAllTowers(entry.Skip)

        elseif entry.SuperFunction == "rebuild" then
            if not rebuildSystemActive then
                for _, skip in ipairs(entry.Skip or {}) do
                    skipTypesMap[skip] = { beOnly = entry.Be == true, fromLine = i }
                end

                StartRebuildSystem(entry, towerRecords, skipTypesMap)
                rebuildSystemActive = true
            end

        elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
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
                PlaceTowerRetry(args, pos.X, entry.TowerPlaced)

                towerRecords[pos.X] = towerRecords[pos.X] or {}
                table.insert(towerRecords[pos.X], { line = i, entry = entry })
            end

        elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
            local axis = tonumber(entry.TowerUpgraded)
            UpgradeTowerRetry(axis, entry.UpgradePath)

            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })

        elseif entry.ChangeTarget and entry.TargetType then
            local axis = tonumber(entry.ChangeTarget)
            ChangeTargetRetry(axis, entry.TargetType)

            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })

        elseif entry.SellTower then
            local axis = tonumber(entry.SellTower)
            SellTowerRetry(axis)

            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })

        -- NEW: Xử lý moving skill entries trong main execution
        elseif entry.towermoving and entry.skillindex and entry.location then
            -- Moving skills sẽ được xử lý bởi monitor, nhưng vẫn cần thêm vào towerRecords cho rebuild
            local axis = entry.towermoving
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        end

        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
end

local success, err = pcall(RunMacroRunner)
if not success then
    error("Lỗi Macro Runner: " .. tostring(err))
end