-- START OF FILE rebuild.lua (with SUPER debugging)
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
    ["MaxConcurrentRebuilds"] = 120,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
    ["EnableDebug"] = true,
    ["EnableSuperDebug"] = true, -- BẬT DEBUG NÂNG CAO ĐỂ TÌM LỖI NÀY
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

-- ================= DEBUGGING FUNCTIONS =================
local function DebugLog(category, message)
    if globalEnv.TDX_Config.EnableDebug then
        print(string.format("[REBUILDER DEBUG | %s] [%s]: %s", os.date("%H:%M:%S"), category, message))
    end
end
local function SuperDebugLog(category, message)
    if globalEnv.TDX_Config.EnableSuperDebug then
        print(string.format("[REBUILDER SUPER-DEBUG | %s] [%s]: %s", os.date("%H:%M:%S"), category, message))
    end
end
-- ======================================================

-- [[ ... Toàn bộ các hàm từ PlaceTowerRetry đến RebuildTowerSequence ... ]]
-- (Giữ nguyên các hàm này, không cần thay đổi)
-- Dán các hàm đó vào đây...

-- ======================================================================================
-- BẮT ĐẦU VÒNG LẶP CHÍNH VỚI DEBUG NÂNG CAO
-- ======================================================================================

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
    local lastStatusPrint = 0

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
        -- ĐỌC VÀ PHÂN TÍCH MACRO
        local macroContent = safeReadFile(macroPath)
        if not macroContent or #macroContent < 10 then
            if tick() - lastStatusPrint > 5 then
                 SuperDebugLog("MAIN-LOOP", string.format("Không tìm thấy tệp macro hoặc tệp trống tại '%s'. Đang chờ...", macroPath))
                 lastStatusPrint = tick()
            end
        else
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
                    DebugLog("MACRO", string.format("Tải thành công macro. Tìm thấy dữ liệu cho %d vị trí tower.", table.getn(towersByAxis)))
                else
                    DebugLog("MACRO-ERROR", "Lỗi khi phân tích cú pháp JSON từ tệp macro.")
                end
            end
        end

        -- LẤY DANH SÁCH TOWER HIỆN CÓ
        local existingTowersCache = {}
        local existingTowersListForDebug = {} -- Dành riêng cho SuperDebug
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                local x_coord = tower.SpawnCFrame.Position.X
                existingTowersCache[x_coord] = true
                table.insert(existingTowersListForDebug, string.format("%.2f", x_coord))
            end
        end
        
        -- IN RA TRẠNG THÁI SO SÁNH (SUPER DEBUG)
        if tick() - lastStatusPrint > 5 then
            SuperDebugLog("STATE-CHECK", "========================================")
            SuperDebugLog("STATE-CHECK", "Kiểm tra trạng thái Rebuilder:")
            SuperDebugLog("STATE-CHECK", string.format("Towers trong macro (%d): {%s}", table.getn(towersByAxis), table.concat(table.keys(towersByAxis), ", ")))
            SuperDebugLog("STATE-CHECK", string.format("Towers đang tồn tại (%d): {%s}", #existingTowersListForDebug, table.concat(existingTowersListForDebug, ", ")))
            SuperDebugLog("STATE-CHECK", string.format("Jobs đang hoạt động: %d", table.getn(activeJobs)))
            SuperDebugLog("STATE-CHECK", string.format("Jobs đang chờ trong hàng đợi: %d", #jobQueue))
            SuperDebugLog("STATE-CHECK", "========================================")
            lastStatusPrint = tick()
        end

        -- QUYẾT ĐỊNH XÂY LẠI
        local jobsAdded = false
        for x, records in pairs(towersByAxis) do
            local reasonToSkip = nil -- Biến để ghi lại lý do bỏ qua
            
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                reasonToSkip = "Đã được bán trong macro"
            elseif existingTowersCache[x] then
                reasonToSkip = "Tower đã tồn tại"
            elseif activeJobs[x] then
                reasonToSkip = "Job đã có trong hàng đợi hoặc đang chạy"
            end

            if reasonToSkip then
                -- Nếu có lý do bỏ qua và tower này đã được xóa khỏi danh sách chết, thì không cần làm gì thêm
                if deadTowerTracker.deadTowers[x] then
                     clearTowerDeath(x)
                end
                 if activeJobs[x] and reasonToSkip == "Tower đã tồn tại" then
                    activeJobs[x] = nil
                    for i = #jobQueue, 1, -1 do
                        if jobQueue[i].x == x then 
                            DebugLog("MAIN-LOOP", string.format("Tower tại X=%.2f đã tồn tại. Xóa job đang chờ khỏi hàng đợi.", x))
                            table.remove(jobQueue, i); 
                            break 
                        end
                    end
                end
            else
                -- Không có lý do để bỏ qua -> đây là tower cần xây lại
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
                        DebugLog("JOB-ADD", string.format("Phát hiện tower '%s' bị thiếu tại X=%.2f. Thêm vào hàng đợi.", towerType, x))
                        activeJobs[x] = true
                        table.insert(jobQueue, { 
                            x = x, records = records, priority = GetTowerPriority(towerType),
                            deathTime = deadTowerTracker.deadTowers[x].deathTime,
                            towerName = towerType, firstPlaceLine = firstPlaceLine
                        })
                        jobsAdded = true
                    else
                         if not activeJobs[x] then -- Chỉ log 1 lần
                            DebugLog("JOB-SKIP", string.format("Đã đạt giới hạn thử lại cho tower tại X=%.2f. Sẽ không xây lại nữa.", x))
                            activeJobs[x] = true -- Đánh dấu để không thêm lại
                         end
                    end
                end
            end
        end

        -- SẮP XẾP HÀNG ĐỢI
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