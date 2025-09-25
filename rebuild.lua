-- START OF FILE rebuild.lua (with debugging)
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
    ["MaxConcurrentRebuilds"] = 120,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
    ["EnableDebug"] = true, -- BẬT/TẮT DEBUG TẠI ĐÂY
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- ================= DEBUGGING FUNCTION =================
local function DebugLog(category, message)
    if globalEnv.TDX_Config.EnableDebug then
        print(string.format("[REBUILDER DEBUG | %s] [%s]: %s", os.date("%H:%M:%S"), category, message))
    end
end
-- ======================================================

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
if not TowerClass then
    DebugLog("CRITICAL", "Không thể load TowerClass!")
    error("Không thể load TowerClass!")
end

local function AddToRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = true end
local function RemoveFromRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                DebugLog("AUTO-SELL", string.format("Tower tại X=%.2f bị biến đổi, đang bán...", tower.SpawnCFrame.Position.X))
                pcall(function() Remotes.SellTower:FireServer(hash) end)
                task.wait(0.1)
            end
        end
    end
end)

local function GetTowerHashBySpawnX(targetX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local spawnCFrame = tower.SpawnCFrame
        if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
            if math.abs(spawnCFrame.Position.X - targetX) < 0.1 then
                return hash, tower, spawnCFrame.Position
            end
        end
    end
    return nil, nil, nil
end

local function GetTowerByAxis(axisX)
    return GetTowerHashBySpawnX(axisX)
end

local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5
    local startTime = tick()
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
    if cash.Value < amount then
        DebugLog("CASH-WAIT", string.format("Đang chờ %.0f cash (hiện có %.0f)", amount, cash.Value))
        while cash.Value < amount do
            RunService.Heartbeat:Wait()
        end
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

local function ShouldSkipTower(axisX, towerName, firstPlaceLine)
    local config = globalEnv.TDX_Config
    if config.SkipTowersAtAxis and table.find(config.SkipTowersAtAxis, axisX) then 
        DebugLog("SKIP", string.format("Bỏ qua tower tại X=%.2f do cấu hình SkipTowersAtAxis.", axisX))
        return true 
    end
    if config.SkipTowersByName and table.find(config.SkipTowersByName, towerName) then 
        DebugLog("SKIP", string.format("Bỏ qua tower '%s' tại X=%.2f do cấu hình SkipTowersByName.", towerName, axisX))
        return true 
    end
    if config.SkipTowersByLine and firstPlaceLine and table.find(config.SkipTowersByLine, firstPlaceLine) then 
        DebugLog("SKIP", string.format("Bỏ qua tower tại X=%.2f (dòng %d) do cấu hình SkipTowersByLine.", axisX, firstPlaceLine))
        return true 
    end
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

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)
    DebugLog("PLACE", string.format("Bắt đầu đặt tower '%s' tại X=%.2f.", towerName, axisValue))
    while attempts < maxAttempts do
        pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)

        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if tower then
            DebugLog("PLACE-SUCCESS", string.format("Đặt thành công '%s' tại X=%.2f sau %d lần thử.", towerName, axisValue, attempts + 1))
            RemoveFromRebuildCache(axisValue)
            return true
        end

        attempts = attempts + 1
        DebugLog("PLACE-RETRY", string.format("Thử lại đặt tower tại X=%.2f (lần %d/%d).", axisValue, attempts, maxAttempts))
        task.wait()
    end
    DebugLog("PLACE-FAIL", string.format("Đặt thất bại '%s' tại X=%.2f sau %d lần thử.", towerName, axisValue, maxAttempts))
    RemoveFromRebuildCache(axisValue)
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)
    while attempts < maxAttempts do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if not hash then
            DebugLog("UPGRADE-RETRY", string.format("Không tìm thấy tower tại X=%.2f để nâng cấp. Thử lại... (%d/%d)", axisValue, attempts + 1, maxAttempts))
            task.wait() 
            attempts = attempts + 1
            continue 
        end
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then 
            DebugLog("UPGRADE-SUCCESS", string.format("Tower tại X=%.2f đã đạt cấp tối đa cho đường %d.", axisValue, path))
            RemoveFromRebuildCache(axisValue)
            return true 
        end
        DebugLog("UPGRADE", string.format("Bắt đầu nâng cấp tower tại X=%.2f (Path %d, Level %d -> %d, Cost: %d).", axisValue, path, before, before + 1, cost))
        WaitForCash(cost)
        pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)

        local startTime = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler and t.LevelHandler:GetLevelOnPath(path) > before then 
                DebugLog("UPGRADE-SUCCESS", string.format("Nâng cấp thành công tower tại X=%.2f (Path %d, Level %d).", axisValue, path, t.LevelHandler:GetLevelOnPath(path)))
                RemoveFromRebuildCache(axisValue)
                return true 
            end
        until tick() - startTime > 3

        attempts = attempts + 1
        DebugLog("UPGRADE-RETRY", string.format("Nâng cấp chưa xác nhận tại X=%.2f. Thử lại... (%d/%d)", axisValue, attempts, maxAttempts))
        task.wait()
    end
    DebugLog("UPGRADE-FAIL", string.format("Nâng cấp thất bại tại X=%.2f sau %d lần thử.", axisValue, maxAttempts))
    RemoveFromRebuildCache(axisValue)
    return false
end

local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)
    DebugLog("TARGET", string.format("Bắt đầu đổi mục tiêu cho tower tại X=%.2f thành %d.", axisValue, targetType))
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.ChangeQueryType:FireServer(hash, targetType)
            end)
            DebugLog("TARGET-SUCCESS", string.format("Gửi yêu cầu đổi mục tiêu cho tower tại X=%.2f.", axisValue))
            RemoveFromRebuildCache(axisValue)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    DebugLog("TARGET-FAIL", string.format("Không tìm thấy tower tại X=%.2f để đổi mục tiêu.", axisValue))
    RemoveFromRebuildCache(axisValue)
end

local function HasSkill(axisValue, skillIndex)
    local hash, tower = WaitForTowerInitialization(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end
    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then 
        DebugLog("SKILL-FAIL", "Không tìm thấy RemoteEvent 'TowerUseAbilityRequest'.")
        return false 
    end
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    AddToRebuildCache(axisValue)
    DebugLog("SKILL", string.format("Bắt đầu sử dụng kỹ năng #%d cho tower tại X=%.2f.", skillIndex, axisValue))

    while attempts < maxAttempts do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if hash and tower then
            if not tower.AbilityHandler then
                DebugLog("SKILL-FAIL", string.format("Tower tại X=%.2f không có AbilityHandler.", axisValue))
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                DebugLog("SKILL-FAIL", string.format("Không tìm thấy kỹ năng #%d cho tower tại X=%.2f.", skillIndex, axisValue))
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then 
                DebugLog("SKILL-WAIT", string.format("Kỹ năng #%d đang hồi (%.1fs). Đang chờ...", skillIndex, cooldown))
                task.wait(cooldown + 0.1) 
            end

            local success = false
            if location == "no_pos" then
                success = pcall(function()
                    if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex)
                    else TowerUseAbilityRequest:InvokeServer(hash, skillIndex) end
                end)
            else
                local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                if x and y and z then
                    local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                    success = pcall(function()
                        if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex, pos)
                        else TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos) end
                    end)
                end
            end
            if success then
                DebugLog("SKILL-SUCCESS", string.format("Sử dụng thành công kỹ năng #%d cho tower tại X=%.2f.", skillIndex, axisValue))
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        attempts = attempts + 1
        DebugLog("SKILL-RETRY", string.format("Thử lại dùng kỹ năng tại X=%.2f (lần %d/%d).", axisValue, attempts, maxAttempts))
        task.wait(0.1)
    end
    DebugLog("SKILL-FAIL", string.format("Sử dụng kỹ năng thất bại tại X=%.2f sau %d lần thử.", axisValue, maxAttempts))
    RemoveFromRebuildCache(axisValue)
    return false
end

local function RebuildTowerSequence(records)
    local placeRecord, upgradeRecords, targetRecords, movingRecords = nil, {}, {}, {}
    for _, record in ipairs(records) do
        local entry = record.entry
        if entry.TowerPlaced then placeRecord = record
        elseif entry.TowerUpgraded then table.insert(upgradeRecords, record)
        elseif entry.TowerTargetChange then table.insert(targetRecords, record)
        elseif entry.towermoving then table.insert(movingRecords, record) end
    end

    local rebuildSuccess = true
    if placeRecord then
        local entry = placeRecord.entry
        local vecTab = {}
        for coord in entry.TowerVector:gmatch("[^,%s]+") do table.insert(vecTab, tonumber(coord)) end
        if #vecTab == 3 then
            local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
            local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
            WaitForCash(entry.TowerPlaceCost)
            if not PlaceTowerRetry(args, pos.X, entry.TowerPlaced) then
                rebuildSuccess = false
            end
        end
    else
        DebugLog("SEQUENCE-ERROR", "Không tìm thấy bản ghi 'Place' cho chuỗi xây dựng lại.")
        rebuildSuccess = false -- Không có bản ghi đặt trụ thì không thể tiếp tục
    end

    if rebuildSuccess and #movingRecords > 0 then
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry
            DebugLog("SEQUENCE-SKILL", string.format("Chờ để sử dụng kỹ năng di chuyển cho tower tại X=%.2f.", entry.towermoving))
            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end
            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end)
    end

    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then
                rebuildSuccess = false
                break
            end
            task.wait(0.1)
        end
    end

    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
            task.wait(0.05)
        end
    end

    DebugLog("SEQUENCE-COMPLETE", string.format("Chuỗi xây dựng lại hoàn tất với kết quả: %s.", tostring(rebuildSuccess)))
    return rebuildSuccess
end

task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis, soldAxis, rebuildAttempts = {}, {}, {}
    local deadTowerTracker = { deadTowers = {}, nextDeathId = 1 }
    local function recordTowerDeath(x)
        if not deadTowerTracker.deadTowers[x] then
            deadTowerTracker.deadTowers[x] = { deathTime = tick(), deathId = deadTowerTracker.nextDeathId }
            deadTowerTracker.nextDeathId = deadTowerTracker.nextDeathId + 1
        end
    end
    local function clearTowerDeath(x) deadTowerTracker.deadTowers[x] = nil end
    local jobQueue, activeJobs = {}, {}

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    DebugLog("WORKER", string.format("Worker bắt đầu xử lý job cho tower '%s' tại X=%.2f.", job.towerName, job.x))
                    if not ShouldSkipTower(job.x, job.towerName, job.firstPlaceLine) then
                        if RebuildTowerSequence(job.records) then
                            rebuildAttempts[job.x] = 0
                            clearTowerDeath(job.x)
                        end
                    else
                        rebuildAttempts[job.x] = 0
                        clearTowerDeath(job.x)
                    end
                    activeJobs[job.x] = nil
                    DebugLog("WORKER", string.format("Worker hoàn thành job cho X=%.2f.", job.x))
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    DebugLog("INIT", string.format("Khởi tạo %d workers.", globalEnv.TDX_Config.MaxConcurrentRebuilds))
    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do RebuildWorker() end

    while true do
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = #macroContent .. "|" .. macroContent:sub(1, 50)
            if macroHash ~= lastMacroHash then
                DebugLog("MACRO", "Phát hiện thay đổi trong tệp macro. Đang tải lại...")
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
                            towersByAxis[x] = towersByAxis[x] or {}
                            table.insert(towersByAxis[x], {line = i, entry = entry})
                        end
                    end
                    DebugLog("MACRO", string.format("Tải thành công macro. Tìm thấy dữ liệu cho %d vị trí tower.", #towersByAxis))
                else
                    DebugLog("MACRO-ERROR", "Lỗi khi phân tích cú pháp JSON từ tệp macro.")
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
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                -- Bỏ qua vì tower đã được bán trong macro
            elseif not existingTowersCache[x] then
                if not activeJobs[x] then
                    recordTowerDeath(x)
                    local towerType, firstPlaceLine = nil, nil
                    for _, record in ipairs(records) do
                        if record.entry.TowerPlaced then 
                            towerType = record.entry.TowerPlaced
                            firstPlaceLine = record.line
                            break
                        end
                    end
                    if towerType then
                        rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                        local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry
                        if not maxRetry or rebuildAttempts[x] <= maxRetry then
                            DebugLog("MAIN-LOOP", string.format("Phát hiện tower '%s' bị thiếu tại X=%.2f. Thêm vào hàng đợi xây dựng lại.", towerType, x))
                            activeJobs[x] = true
                            table.insert(jobQueue, { 
                                x = x, records = records, priority = GetTowerPriority(towerType),
                                deathTime = deadTowerTracker.deadTowers[x].deathTime,
                                towerName = towerType, firstPlaceLine = firstPlaceLine
                            })
                            jobsAdded = true
                        else
                            DebugLog("MAIN-LOOP", string.format("Đã đạt giới hạn thử lại cho tower tại X=%.2f. Sẽ không xây lại nữa.", x))
                        end
                    end
                end
            else
                clearTowerDeath(x)
                if activeJobs[x] then
                    activeJobs[x] = nil
                    for i = #jobQueue, 1, -1 do
                        if jobQueue[i].x == x then 
                            DebugLog("MAIN-LOOP", string.format("Tower tại X=%.2f đã tồn tại. Xóa job đang chờ khỏi hàng đợi.", x))
                            table.remove(jobQueue, i); 
                            break 
                        end
                    end
                end
            end
        end

        if jobsAdded and #jobQueue > 1 then
            DebugLog("QUEUE", "Sắp xếp lại hàng đợi theo độ ưu tiên và thời gian bị phá hủy.")
            table.sort(jobQueue, function(a, b) 
                if a.priority == b.priority then return a.deathTime < b.deathTime end
                return a.priority < b.priority 
            end)
        end

        RunService.Heartbeat:Wait()
    end
end)