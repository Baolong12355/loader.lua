--- START OF FILE rebuild.lua (Invisible UI Upgrade Logic) ---

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
    ["MaxRebuildRetry"] = 9999,
    ["PlaceMode"] = "Rewrite",
    ["VerificationDelay"] = 1.5,
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

-- Tải các module cần thiết
local TowerClass, UpgradePathClass
pcall(function()
    local PlayerScripts = player:WaitForChild("PlayerScripts")
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    TowerClass = SafeRequire(gameClass:WaitForChild("TowerClass"))
    
    local uiHandler = client:WaitForChild("UserInterfaceHandler")
    local towerUIHandler = uiHandler:WaitForChild("TowerUIHandler")
    UpgradePathClass = SafeRequire(towerUIHandler:WaitForChild("UpgradePathClass"))
end)

if not TowerClass or not UpgradePathClass then
    error("Không thể load TowerClass hoặc UpgradePathClass!")
end

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

local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5; local startTime = tick()
    while tick() - startTime < timeout do
        local hash, tower = GetTowerByAxis(axisX)
        if hash and tower and tower.LevelHandler then return hash, tower end
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

-- CẬP NHẬT: Hàm nâng cấp "tàng hình" không hiện UI
local function UpgradeTower(axisValue, path)
    local hash, tower = WaitForTowerInitialization(axisValue, 5)
    if not hash then return false end

    -- Lấy đối tượng nút nâng cấp từ module UI
    local pathButton = (path == 1 and UpgradePathClass.Path1Button) or (path == 2 and UpgradePathClass.Path2Button)
    if not pathButton then return false end
    
    local beforeLevel = tower.LevelHandler:GetLevelOnPath(path)
    
    -- Kiểm tra xem có thể nâng cấp không
    if beforeLevel >= tower.LevelHandler:GetMaxLevel() then return true end

    -- BƯỚC 1: "Nạp" dữ liệu của tower vào module UI một cách âm thầm
    -- Hàm Update này chỉ cập nhật dữ liệu nội bộ của nút, không làm nó hiện lên
    pathButton:Update(tower)
    
    -- BƯỚC 2: Trigger hành động bấm nút sau khi nó đã có dữ liệu đúng
    pathButton:UpgradePressed(false) -- false nghĩa là không phải max upgrade

    -- BƯỚC 3: Chờ xác nhận nâng cấp thành công
    local success = false
    local startTime = tick()
    repeat
        task.wait(0.1)
        local _, currentTower = GetTowerByAxis(axisValue)
        if currentTower and currentTower.LevelHandler and currentTower.LevelHandler:GetLevelOnPath(path) > beforeLevel then
            success = true
            break
        end
    until tick() - startTime > 2
    
    return success
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

-- Hệ thống 2 luồng Thực Thi và Kiểm Tra
task.spawn(function()
    local lastMacroHash, towersByAxis, soldAxis, rebuildAttempts = "", {}, {}, {}
    local jobQueue, verificationQueue, activeJobs = {}, {}, {}

    local function RebuildWorker()
        task.spawn(function()
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local placeRecord, upgradeRecords, targetRecords, movingRecords = nil, {}, {}, {}
                    for _, r in ipairs(job.records) do
                        if r.entry.TowerPlaced then placeRecord = r
                        elseif r.entry.TowerUpgraded then table.insert(upgradeRecords, r)
                        elseif r.entry.TowerTargetChange then table.insert(targetRecords, r)
                        elseif r.entry.towermoving then table.insert(movingRecords, r) end
                    end

                    AddToRebuildCache(job.x)
                    local success = true
                    if placeRecord then
                        local e = placeRecord.entry; local v = {}; for c in e.TowerVector:gmatch("[^,%s]+") do table.insert(v, tonumber(c)) end
                        if #v == 3 then
                            local p = Vector3.new(v[1], v[2], v[3])
                            local a = {tonumber(e.TowerA1), e.TowerPlaced, p, tonumber(e.Rotation or 0)}
                            WaitForCash(e.TowerPlaceCost); if not PlaceTower(a, p.X) then success = false end
                        end
                    end
                    if success then
                        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
                        for _, r in ipairs(upgradeRecords) do
                            if not UpgradeTower(tonumber(r.entry.TowerUpgraded), r.entry.UpgradePath) then success = false; break end
                        end
                    end
                    if success then
                        for _, r in ipairs(targetRecords) do ChangeTarget(tonumber(r.entry.TowerTargetChange), r.entry.TargetWanted); task.wait(0.05) end
                        if #movingRecords > 0 then UseMovingSkill(movingRecords[#movingRecords].entry.towermoving, movingRecords[#movingRecords].entry.skillindex, movingRecords[#movingRecords].entry.location) end
                    end
                    RemoveFromRebuildCache(job.x)
                    job.executionTime = tick()
                    table.insert(verificationQueue, job)
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    local function VerificationWorker()
        task.spawn(function()
            while true do
                if #verificationQueue > 0 and tick() - verificationQueue[1].executionTime > globalEnv.TDX_Config.VerificationDelay then
                    local job = table.remove(verificationQueue, 1)
                    local _, tower = GetTowerByAxis(job.x)
                    local targetLvlP1, targetLvlP2 = 0, 0
                    for _, r in ipairs(job.records) do
                        if r.entry.TowerUpgraded and r.entry.UpgradePath == 1 then targetLvlP1 = targetLvlP1 + 1 end
                        if r.entry.TowerUpgraded and r.entry.UpgradePath == 2 then targetLvlP2 = targetLvlP2 + 1 end
                    end
                    if tower and tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(1) == targetLvlP1 and tower.LevelHandler:GetLevelOnPath(2) == targetLvlP2 then
                        rebuildAttempts[job.x], activeJobs[job.x] = nil, nil
                    else
                        local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry
                        if not maxRetry or (rebuildAttempts[job.x] or 0) < maxRetry then
                            table.insert(jobQueue, 1, job)
                        else
                            activeJobs[job.x] = nil
                        end
                    end
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do RebuildWorker() end
    VerificationWorker()

    while true do
        local content = safeReadFile(macroPath)
        if content and #content > 10 then
            local hash = #content .. "|" .. content:sub(1, 50)
            if hash ~= lastMacroHash then
                lastMacroHash = hash
                local ok, macro = pcall(HttpService.JSONDecode, HttpService, content)
                if ok and type(macro) == "table" then
                    towersByAxis, soldAxis = {}, {}
                    for i, e in ipairs(macro) do
                        local x; if e.SellTower then x = tonumber(e.SellTower); if x then soldAxis[x] = true end
                        elseif e.TowerPlaced and e.TowerVector then x = tonumber(e.TowerVector:match("^([%d%-%.]+),"))
                        elseif e.TowerUpgraded then x = tonumber(e.TowerUpgraded)
                        elseif e.TowerTargetChange then x = tonumber(e.TowerTargetChange)
                        elseif e.towermoving then x = e.towermoving end
                        if x then towersByAxis[x] = towersByAxis[x] or {}; table.insert(towersByAxis[x], {line = i, entry = e}) end
                    end
                end
            end
        end
        local cache = {}; for h, t in pairs(TowerClass.GetTowers()) do if t.SpawnCFrame then cache[t.SpawnCFrame.Position.X] = true end end
        local jobsAdded = false
        for x, records in pairs(towersByAxis) do
            if not activeJobs[x] and not (globalEnv.TDX_Config.ForceRebuildEvenIfSold == false and soldAxis[x]) and not cache[x] then
                local towerType, firstPlaceLine; for _, r in ipairs(records) do if r.entry.TowerPlaced then towerType, firstPlaceLine = r.entry.TowerPlaced, r.line; break end end
                if towerType and not ShouldSkipTower(x, towerType, firstPlaceLine) then
                    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                    activeJobs[x] = true; jobsAdded = true
                    table.insert(jobQueue, { x = x, records = records, priority = GetTowerPriority(towerType), deathTime = tick(), towerName = towerType, firstPlaceLine = firstPlaceLine })
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