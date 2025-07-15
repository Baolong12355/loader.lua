local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "ooooo"
local macroPath = "tdx/macros/" .. macroName .. ".json"
local placeMode = config["PlaceMode"] or "ashed"

-- Require tower class
local function SafeRequire(module)
    local ok, result = pcall(require, module)
    return ok and result or nil
end

local function LoadTowerClass()
    local ps = player:WaitForChild("PlayerScripts")
    local client = ps:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then error("Không thể load TowerClass") end

-- === Utilities ===

local function WaitForCash(amount)
    while cashStat.Value < amount do task.wait() end
end

local function GetTowerByAxis(x)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local ok, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            return root and root.Position
        end)
        if ok and pos and math.abs(pos.X - x) <= 1 then
            return hash, tower
        end
    end
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local level = tower.LevelHandler:GetLevelOnPath(path)
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, level + 1)
    end)
    return ok and cost or nil
end

-- === Rebuild Setup ===

local savedTeam = {}
local rebuildTrigger = nil
local skipMap = {}
local beTime = nil

-- Save snapshot
local function SaveSnapshot(logs)
    for _, entry in ipairs(logs) do
        if entry.TowerPlaced then
            table.insert(savedTeam, table.clone(entry))
        elseif entry.UpgradePath and entry.TowerUpgraded then
            table.insert(savedTeam, table.clone(entry))
        end
    end
end

-- Tower priority
local function GetPriority(name)
    if name == "Medic" then return 1 end
    if name == "Mobster" or name == "Golden Mobster" then return 2 end
    if name == "DJ" then return 3 end
    if name == "Commander" then return 4 end
    return 5
end

-- === Core functions ===

local function PlaceTower(entry)
    local pos = Vector3.new(table.unpack(string.split(entry.TowerVector, ", ")))
    local args = {
        tonumber(entry.TowerA1),
        entry.TowerPlaced,
        pos,
        tonumber(entry.Rotation or 0)
    }
    WaitForCash(entry.TowerPlaceCost)
    Remotes.PlaceTower:InvokeServer(unpack(args))

    -- Đợi tower hiện ra
    for _ = 1, 20 do
        if GetTowerByAxis(pos.X) then return true end
        task.wait(0.1)
    end
    return false
end

local function UpgradeTower(entry)
    local x = tonumber(entry.TowerUpgraded)
    local hash, tower = GetTowerByAxis(x)
    if not hash or not tower then return false end
    local levelBefore = tower.LevelHandler:GetLevelOnPath(entry.UpgradePath)
    local cost = GetCurrentUpgradeCost(tower, entry.UpgradePath)
    if not cost then return false end

    WaitForCash(cost)
    Remotes.TowerUpgradeRequest:FireServer(hash, entry.UpgradePath, 1)

    for _ = 1, 10 do
        task.wait(0.25)
        local _, newTower = GetTowerByAxis(x)
        if newTower then
            local lvlNow = newTower.LevelHandler:GetLevelOnPath(entry.UpgradePath)
            if lvlNow > levelBefore then return true end
        end
    end
    return false
end

local function SellTower(entry)
    local x = tonumber(entry.SellTower)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.SellTower:FireServer(hash)
        return true
    end
end

local function ChangeTarget(entry)
    local x = tonumber(entry.ChangeTarget)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.ChangeQueryType:FireServer(hash, entry.TargetType)
        return true
    end
end

-- === Rebuild logic ===

local function ShouldSkip(name)
    if not rebuildTrigger then return false end
    if rebuildTrigger.Be then
        return skipMap[name] == true
    else
        return false
    end
end

local function RunRebuild()
    if not savedTeam or #savedTeam == 0 then return end
    for _, entry in ipairs(savedTeam) do
        if entry.TowerPlaced then
            local skip = ShouldSkip(entry.TowerPlaced)
            if not skip then
                PlaceTower(entry)
                task.wait(2)
            end
        elseif entry.UpgradePath then
            UpgradeTower(entry)
        end
    end
end

local function MonitorRebuild()
    while true do
        task.wait(0.5)
        if not rebuildTrigger then continue end

        for _, part in ipairs(Workspace.Game.Towers:GetChildren()) do
            if part:IsA("BasePart") and part:GetAttribute("Dead") then
                local name = part.Name
                if not ShouldSkip(name) then
                    RunRebuild()
                    break
                end
            end
        end
    end
end

-- === Main ===

local success, macro = pcall(function()
    return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then error("Không đọc được macro") end

-- Tách SuperFunction và ghi lại team
local finalLogs = {}
for _, entry in ipairs(macro) do
    if entry.SuperFunction == "SellAll" then
        for _, part in ipairs(Workspace.Game.Towers:GetChildren()) do
            if part:IsA("BasePart") and not table.find(entry.Skip or {}, part.Name) then
                local x = part.Position.X
                local hash = GetTowerByAxis(x)
                if hash then Remotes.SellTower:FireServer(hash) end
            end
        end
    elseif entry.SuperFunction == "rebuild" then
        rebuildTrigger = {
            Skip = entry.Skip or {},
            Be = entry.Be == true
        }
        for _, name in ipairs(rebuildTrigger.Skip) do
            skipMap[name] = true
        end
        SaveSnapshot(finalLogs)
    else
        table.insert(finalLogs, entry)
    end
end

-- Chạy macro
task.spawn(MonitorRebuild)
for _, entry in ipairs(finalLogs) do
    if entry.TowerPlaced then
        PlaceTower(entry)
    elseif entry.UpgradePath then
        UpgradeTower(entry)
    elseif entry.ChangeTarget then
        ChangeTarget(entry)
    elseif entry.SellTower then
        SellTower(entry)
    end
end

print("✅ Macro runner hoàn tất.")
