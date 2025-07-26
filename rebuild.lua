-- TDX Macro Rebuild (No Sell, No Rebuild Sold) - Executor/loadstring ready
-- Không rebuild lại tower đã từng bị bán (theo record). Không thực hiện sell.
-- Không log hành động rebuild vào record nếu đã patch recorder (_G.TDX_REBUILD_RUNNING).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/recorder_output.json"

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

-- Helper: Lấy tower hiện tại theo trục X
local function GetTowerByAxis(axisX)
    for _, tower in pairs(TowerClass.GetTowers()) do
        local pos
        pcall(function() pos = tower:GetPosition() end)
        if pos and math.abs(pos.X - axisX) < 0.1 then
            local hp = 1
            pcall(function() hp = tower.HealthHandler and tower.HealthHandler:GetHealth() or 1 end)
            if hp and hp > 0 then return tower end
        end
    end
    return nil
end

local function WaitForCash(amount)
    while cash.Value < amount do
        RunService.Heartbeat:Wait()
    end
end

-- Đặt lại 1 tower
local function PlaceTowerEntry(entry)
    local vecTab = {}
    for c in tostring(entry.TowerVector):gmatch("[^,%s]+") do table.insert(vecTab, tonumber(c)) end
    if #vecTab ~= 3 then return false end
    local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
    WaitForCash(entry.TowerPlaceCost or 0)
    local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
    _G.TDX_REBUILD_RUNNING = true
    local ok = pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
    _G.TDX_REBUILD_RUNNING = false
    -- Chờ xuất hiện tower
    local t0 = tick()
    while tick() - t0 < 3 do
        if GetTowerByAxis(pos.X) then return true end
        task.wait(0.1)
    end
    return false
end

-- Nâng cấp tower
local function UpgradeTowerEntry(entry)
    local axis = tonumber(entry.TowerUpgraded)
    local path = entry.UpgradePath
    local tower = GetTowerByAxis(axis)
    if not tower then return false end
    WaitForCash(entry.UpgradeCost or 0)
    _G.TDX_REBUILD_RUNNING = true
    pcall(function()
        Remotes.TowerUpgradeRequest:FireServer(tower.Hash, path, 1)
    end)
    _G.TDX_REBUILD_RUNNING = false
    return true
end

-- Đổi target
local function ChangeTargetEntry(entry)
    local axis = tonumber(entry.TowerTargetChange)
    local tower = GetTowerByAxis(axis)
    if not tower then return false end
    _G.TDX_REBUILD_RUNNING = true
    pcall(function()
        Remotes.ChangeQueryType:FireServer(tower.Hash, tonumber(entry.TargetWanted))
    end)
    _G.TDX_REBUILD_RUNNING = false
    return true
end

-- Không bán tower (bỏ qua SellTowerEntry)

-- Hàm chính: Liên tục reload record + rebuild nếu phát hiện tower chết, không rebuild nếu đã từng bị bán
task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis = {}
    local soldAxis = {}

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
                                table.insert(towersByAxis[x], entry)
                            end
                        elseif entry.TowerUpgraded and entry.UpgradePath then
                            local x = tonumber(entry.TowerUpgraded)
                            if x then
                                towersByAxis[x] = towersByAxis[x] or {}
                                table.insert(towersByAxis[x], entry)
                            end
                        elseif entry.TowerTargetChange then
                            local x = tonumber(entry.TowerTargetChange)
                            if x then
                                towersByAxis[x] = towersByAxis[x] or {}
                                table.insert(towersByAxis[x], entry)
                            end
                        end
                    end
                    print("[TDX Rebuild] Đã reload record mới: ", macroPath)
                end
            end
        end

        -- Rebuild nếu phát hiện tower chết, nhưng KHÔNG rebuild nếu đã từng bị bán (có trong soldAxis)
        for x, records in pairs(towersByAxis) do
            if soldAxis[x] then
                -- Vị trí này đã từng bị bán => không rebuild lại
                continue
            end
            local tower = GetTowerByAxis(x)
            if not tower then
                -- Rebuild: place + upgrade/target đúng thứ tự
                for _, entry in ipairs(records) do
                    if entry.TowerPlaced then
                        PlaceTowerEntry(entry)
                    elseif entry.UpgradePath then
                        UpgradeTowerEntry(entry)
                    elseif entry.TargetWanted then
                        ChangeTargetEntry(entry)
                    end
                    task.wait(0.2)
                end
            end
        end

        task.wait(1.5) -- Luôn reload record mới mỗi 1.5 giây
    end
end)

print("[TDX Macro Rebuild (No Sell/No Rebuild Sold/No Log)] Đã hoạt động!")