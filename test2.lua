-- START OF FILE rebuild.lua (v1.5 - Indirect Triggering & Stability - COMPLETE)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/endless.json"

-- Universal compatibility functions
local function getGlobalEnv() if getgenv then return getgenv() end if getfenv then return getfenv() end return _G end

-- Cấu hình mặc định
local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 5,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["PlaceMode"] = "Rewrite",
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
    ["ActionPacingDelay"] = 0.1, -- Độ trễ an toàn giữa các hành động
    ["EnableDebug"] = true,
    ["EnableSuperDebug"] = true, 
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
for key, value in pairs(defaultConfig) do if globalEnv.TDX_Config[key] == nil then globalEnv.TDX_Config[key] = value end end

local function DebugLog(category, message) if globalEnv.TDX_Config.EnableDebug then print(string.format("[REBUILDER DEBUG | %s] [%s]: %s", os.date("%H:%M:%S"), category, message)) end end
local function SuperDebugLog(category, message) if globalEnv.TDX_Config.EnableSuperDebug then print(string.format("[REBUILDER SUPER-DEBUG | %s] [%s]: %s", os.date("%H:%M:%S"), category, message)) end end
local function getTableKeys(tbl) local keys = {} if type(tbl) ~= "table" then return keys end for k, _ in pairs(tbl) do table.insert(keys, tostring(k)) end return keys end
local function countTableKeys(tbl) local count = 0 if type(tbl) ~= "table" then return count end for _ in pairs(tbl) do count = count + 1 end return count end
-- =================================================================

-- ================= CORE GAME MODULES ============================
-- Load một lần và lưu trữ các module quan trọng của game
local CoreModules = { IsLoaded = false }
task.spawn(function()
    pcall(function()
        local playerScripts = player:WaitForChild("PlayerScripts")
        local client = playerScripts:WaitForChild("Client")
        local gameClass = client:WaitForChild("GameClass")
        local userInterfaceHandler = client:WaitForChild("UserInterfaceHandler")

        CoreModules.TowerClass = require(gameClass:WaitForChild("TowerClass"))
        CoreModules.TowerUIHandler = require(userInterfaceHandler:WaitForChild("TowerUIHandler"))
        CoreModules.UpgradePathClass = require(userInterfaceHandler:WaitForChild("TowerUIHandler"):WaitForChild("UpgradePathClass"))
        CoreModules.BindableHandler = require(ReplicatedStorage.TDX_Shared.Common:WaitForChild("BindableHandler"))

        if CoreModules.TowerClass and CoreModules.TowerUIHandler and CoreModules.UpgradePathClass and CoreModules.BindableHandler then
            CoreModules.IsLoaded = true
            DebugLog("INIT", "Tất cả các module cốt lõi đã được load thành công!")
        else
            DebugLog("CRITICAL", "Không thể load một hoặc nhiều module cốt lõi!")
        end
    end)
end)
-- =================================================================

local function getMaxAttempts() local placeMode = globalEnv.TDX_Config.PlaceMode or "Rewrite"; if placeMode == "Ashed" then return 1 end if placeMode == "Rewrite" then return 10 end return 1 end
local function safeReadFile(path) if readfile and isfile and isfile(path) then local ok, res = pcall(readfile, path); if ok then return res end end return nil end

local function GetTowerByAxis(axisX)
    if not CoreModules.IsLoaded then return nil, nil end
    for hash, tower in pairs(CoreModules.TowerClass.GetTowers()) do
        if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
            if math.abs(tower.SpawnCFrame.Position.X - axisX) < 0.1 then return hash, tower end
        end
    end
    return nil, nil
end

local function WaitForTowerInitialization(axisX, timeout) timeout = timeout or 5; local startTime = tick(); while tick() - startTime < timeout do local hash, tower = GetTowerByAxis(axisX); if hash and tower and tower.LevelHandler then return hash, tower end; task.wait() end; return nil, nil end
local function WaitForCash(amount) if cash.Value < amount then DebugLog("CASH-WAIT", string.format("Đang chờ %.0f cash (hiện có %.0f)", amount, cash.Value)); while cash.Value < amount do RunService.Heartbeat:Wait() end end end
local function GetTowerPriority(towerName) for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do if towerName == name then return priority end end return math.huge end
local function ShouldSkipTower(axisX, towerName, firstPlaceLine) local config = globalEnv.TDX_Config; if config.SkipTowersAtAxis and table.find(config.SkipTowersAtAxis, axisX) then DebugLog("SKIP", string.format("Bỏ qua tower tại X=%.2f do cấu hình SkipTowersAtAxis.", axisX)); return true end; if config.SkipTowersByName and table.find(config.SkipTowersByName, towerName) then DebugLog("SKIP", string.format("Bỏ qua tower '%s' tại X=%.2f do cấu hình SkipTowersByName.", towerName, axisX)); return true end; if config.SkipTowersByLine and firstPlaceLine and table.find(config.SkipTowersByLine, firstPlaceLine) then DebugLog("SKIP", string.format("Bỏ qua tower tại X=%.2f (dòng %d) do cấu hình SkipTowersByLine.", axisX, firstPlaceLine)); return true end; return false end
local function GetCurrentUpgradeCost(tower, path) if not tower or not tower.LevelHandler then return nil end; local maxLvl = tower.LevelHandler:GetMaxLevel(); local curLvl = tower.LevelHandler:GetLevelOnPath(path); if curLvl >= maxLvl then return nil end; local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end); if not ok then return nil end; local disc = 0; pcall(function() disc = tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end); return math.floor(baseCost * (1 - disc)) end

-- =================================================================
-- ACTION FUNCTIONS (INDIRECT TRIGGERING)
-- =================================================================

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    for attempts = 1, maxAttempts do
        DebugLog("PLACE", string.format("Thử đặt '%s' tại X=%.2f [Lần %d/%d]", towerName, axisValue, attempts, maxAttempts))
        pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if tower then
            DebugLog("PLACE-SUCCESS", string.format("Đặt thành công '%s'.", towerName))
            return true
        end
        task.wait()
    end
    DebugLog("PLACE-FAIL", string.format("Đặt thất bại '%s'.", towerName))
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    if not CoreModules.IsLoaded then return false end
    
    local maxAttempts = getMaxAttempts()
    for attempts = 1, maxAttempts do
        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if not tower then
            DebugLog("UPGRADE-ERROR", string.format("Không tìm thấy tower tại X=%.2f (Lần %d/%d)", axisValue, attempts + 1, maxAttempts))
            task.wait(0.5)
            goto continue
        end

        local levelBefore = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then
            DebugLog("UPGRADE-DONE", string.format("Tower tại X=%.2f đã max level (Path %d).", axisValue, path))
            return true
        end

        DebugLog("UPGRADE-ATTEMPT", string.format("Trigger nâng cấp tại X=%.2f (Path %d, Lvl %d->%d) [Lần %d/%d]", axisValue, path, levelBefore, levelBefore + 1, attempts + 1, maxAttempts))
        WaitForCash(cost)
        
        local hotkeyEvent = CoreModules.BindableHandler.GetEvent("HotkeyUpgradeTower")
        CoreModules.TowerUIHandler.Show(tower) -- "Chọn" tower để game biết nâng cấp tower nào
        hotkeyEvent:Fire(path, false) -- path, maxUpgradeFlag = false
        CoreModules.TowerUIHandler.Hide() -- Bỏ chọn
        
        local confirmationTimeout = 5
        local startTime = tick()
        while tick() - startTime < confirmationTimeout do
            local _, currentTower = GetTowerByAxis(axisValue)
            if currentTower and currentTower.LevelHandler and currentTower.LevelHandler:GetLevelOnPath(path) > levelBefore then
                DebugLog("UPGRADE-SUCCESS", string.format("Xác nhận nâng cấp thành công tại X=%.2f.", axisValue))
                return true
            end
            task.wait(0.1)
        end
        
        DebugLog("UPGRADE-RETRY", string.format("Không xác nhận được nâng cấp tại X=%.2f. Thử lại...", axisValue))
        task.wait(0.2)
        ::continue::
    end

    DebugLog("UPGRADE-FAIL", string.format("Nâng cấp thất bại hoàn toàn tại X=%.2f.", axisValue))
    return false
end

local function ChangeTargetRetry(axisValue, targetType)
    if not CoreModules.IsLoaded then return end
    
    local maxAttempts = getMaxAttempts()
    for attempts = 1, maxAttempts do
        local _, tower = GetTowerByAxis(axisValue)
        if tower then
            DebugLog("TARGET", string.format("Trigger đổi mục tiêu tại X=%.2f thành %d.", axisValue, targetType))
            local success, err = pcall(tower.SetQueryTypeIndex, tower, targetType)
            if success then
                 DebugLog("TARGET-SUCCESS", "Gửi yêu cầu đổi mục tiêu thành công.")
                 return
            else
                DebugLog("TARGET-ERROR", "Lỗi khi gọi SetQueryTypeIndex: " .. tostring(err))
            end
        end
        task.wait(0.1)
    end
    DebugLog("TARGET-FAIL", string.format("Không tìm thấy tower tại X=%.2f để đổi mục tiêu.", axisValue))
end

local function HasSkill(axisValue, skillIndex) if not CoreModules.IsLoaded then return false end; local hash, tower = WaitForTowerInitialization(axisValue); if not hash or not tower or not tower.AbilityHandler then return false end; local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex); return ability ~= nil end
local function UseMovingSkillRetry(axisValue, skillIndex, location) if not CoreModules.IsLoaded then return false end; local maxAttempts = getMaxAttempts(); local attempts = 0; local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest"); if not TowerUseAbilityRequest then DebugLog("SKILL-FAIL", "Không tìm thấy 'TowerUseAbilityRequest'."); return false end; local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent"); DebugLog("SKILL", string.format("Bắt đầu dùng kỹ năng #%d cho tower tại X=%.2f.", skillIndex, axisValue)); while attempts < maxAttempts do local hash, tower = WaitForTowerInitialization(axisValue); if hash and tower then local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex); if not ability then DebugLog("SKILL-FAIL", "Không tìm thấy kỹ năng."); return false end; local cooldown = ability.CooldownRemaining or 0; if cooldown > 0 then DebugLog("SKILL-WAIT", string.format("Kỹ năng hồi trong %.1fs.", cooldown)); task.wait(cooldown + 0.1) end; local success = false; if location == "no_pos" then success = pcall(function() if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex) else TowerUseAbilityRequest:InvokeServer(hash, skillIndex) end end) else local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)"); if x and y and z then local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)); success = pcall(function() if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex, pos) else TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos) end end) end end; if success then DebugLog("SKILL-SUCCESS", "Dùng kỹ năng thành công."); return true end end; attempts = attempts + 1; task.wait(0.1) end; DebugLog("SKILL-FAIL", "Dùng kỹ năng thất bại."); return false end

local function RebuildTowerSequence(records)
    local placeRecord, upgradeRecords, targetRecords, movingRecords = nil, {}, {}, {}
    for _, record in ipairs(records) do local entry = record.entry; if entry.TowerPlaced then placeRecord = record elseif entry.TowerUpgraded then table.insert(upgradeRecords, record) elseif entry.TowerTargetChange then table.insert(targetRecords, record) elseif entry.towermoving then table.insert(movingRecords, record) end end

    local rebuildSuccess = true
    if placeRecord then
        local entry = placeRecord.entry
        local vecTab = {}; for coord in entry.TowerVector:gmatch("[^,%s]+") do table.insert(vecTab, tonumber(coord)) end
        if #vecTab == 3 then local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3]); local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}; WaitForCash(entry.TowerPlaceCost); if not PlaceTowerRetry(args, pos.X, entry.TowerPlaced) then rebuildSuccess = false end
        else DebugLog("SEQUENCE-ERROR", "Vector vị trí không hợp lệ."); rebuildSuccess = false end
    else DebugLog("SEQUENCE-ERROR", "Không tìm thấy bản ghi 'Place'."); rebuildSuccess = false end

    if rebuildSuccess and #movingRecords > 0 then task.spawn(function() local entry = movingRecords[#movingRecords].entry; DebugLog("SEQUENCE-SKILL", "Chờ dùng kỹ năng di chuyển."); while not HasSkill(entry.towermoving, entry.skillindex) do RunService.Heartbeat:Wait() end; UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location) end) end

    if rebuildSuccess then table.sort(upgradeRecords, function(a, b) return a.line < b.line end); for _, record in ipairs(upgradeRecords) do local entry = record.entry; if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then rebuildSuccess = false; break end; task.wait(globalEnv.TDX_Config.ActionPacingDelay) end end

    if rebuildSuccess then for _, record in ipairs(targetRecords) do local entry = record.entry; ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted); task.wait(globalEnv.TDX_Config.ActionPacingDelay) end end

    DebugLog("SEQUENCE-COMPLETE", string.format("Chuỗi xây dựng lại hoàn tất: %s.", tostring(rebuildSuccess)))
    return rebuildSuccess
end

-- =================================================================
-- MAIN LOOP
-- =================================================================
task.spawn(function()
    repeat task.wait() until CoreModules.IsLoaded
    
    local lastMacroHash = ""
    local towersByAxis, soldAxis, rebuildAttempts = {}, {}, {}
    local deadTowerTracker = { deadTowers = {}, nextDeathId = 1 }
    local function recordTowerDeath(x) if not deadTowerTracker.deadTowers[x] then deadTowerTracker.deadTowers[x] = { deathTime = tick(), deathId = deadTowerTracker.nextDeathId }; deadTowerTracker.nextDeathId = deadTowerTracker.nextDeathId + 1 end end
    local function clearTowerDeath(x) deadTowerTracker.deadTowers[x] = nil end
    local jobQueue, activeJobs = {}, {}
    local lastStatusPrint = 0

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    DebugLog("WORKER", string.format("Worker xử lý job cho '%s' tại X=%.2f.", job.towerName, job.x))
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
                DebugLog("MACRO", "Phát hiện thay đổi macro. Đang tải lại...")
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
                    DebugLog("MACRO", string.format("Tải thành công. Tìm thấy dữ liệu cho %d vị trí.", countTableKeys(towersByAxis)))
                else
                    DebugLog("MACRO-ERROR", "Lỗi phân tích cú pháp JSON.")
                end
            end
        end

        local existingTowersCache = {}
        local existingTowersListForDebug = {}
        for hash, tower in pairs(CoreModules.TowerClass.GetTowers()) do
            if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                local x_coord = tower.SpawnCFrame.Position.X; existingTowersCache[x_coord] = true; table.insert(existingTowersListForDebug, string.format("%.2f", x_coord))
            end
        end
        
        if tick() - lastStatusPrint > 5 then
            SuperDebugLog("STATE-CHECK", "========================================")
            SuperDebugLog("STATE-CHECK", string.format("Towers trong macro (%d): {%s}", countTableKeys(towersByAxis), table.concat(getTableKeys(towersByAxis), ", ")))
            SuperDebugLog("STATE-CHECK", string.format("Towers đang tồn tại (%d): {%s}", #existingTowersListForDebug, table.concat(existingTowersListForDebug, ", ")))
            SuperDebugLog("STATE-CHECK", string.format("Jobs đang hoạt động: %d | Jobs đang chờ: %d", countTableKeys(activeJobs), #jobQueue))
            SuperDebugLog("STATE-CHECK", "========================================")
            lastStatusPrint = tick()
        end

        local jobsAdded = false
        for x, records in pairs(towersByAxis) do
            local reasonToSkip = nil
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then reasonToSkip = "Đã được bán trong macro"
            elseif existingTowersCache[x] then reasonToSkip = "Tower đã tồn tại"
            elseif activeJobs[x] then reasonToSkip = "Job đã có trong hàng đợi hoặc đang chạy" end

            if reasonToSkip then
                if deadTowerTracker.deadTowers[x] then clearTowerDeath(x) end
                if activeJobs[x] and reasonToSkip == "Tower đã tồn tại" then activeJobs[x] = nil; for i = #jobQueue, 1, -1 do if jobQueue[i].x == x then DebugLog("MAIN-LOOP", string.format("Tower tại X=%.2f đã tồn tại. Xóa job.", x)); table.remove(jobQueue, i); break end end end
            else
                recordTowerDeath(x)
                local towerType, firstPlaceLine = nil, nil; for _, record in ipairs(records) do if record.entry.TowerPlaced then towerType = record.entry.TowerPlaced; firstPlaceLine = record.line; break end end
                if towerType then
                    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                    local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry
                    if not maxRetry or rebuildAttempts[x] <= maxRetry then
                        DebugLog("JOB-ADD", string.format("Phát hiện '%s' bị thiếu tại X=%.2f. Thêm vào hàng đợi.", towerType, x))
                        activeJobs[x] = true
                        table.insert(jobQueue, { x = x, records = records, priority = GetTowerPriority(towerType), deathTime = deadTowerTracker.deadTowers[x].deathTime, towerName = towerType, firstPlaceLine = firstPlaceLine})
                        jobsAdded = true
                    else
                         if not activeJobs[x] then DebugLog("JOB-SKIP", string.format("Đã đạt giới hạn thử lại cho X=%.2f.", x)); activeJobs[x] = true end
                    end
                end
            end
        end

        if jobsAdded and #jobQueue > 1 then
            DebugLog("QUEUE", "Sắp xếp lại hàng đợi.")
            table.sort(jobQueue, function(a, b) if a.priority == b.priority then return a.deathTime < b.deathTime end return a.priority < b.priority end)
        end

        RunService.Heartbeat:Wait()
    end
end)