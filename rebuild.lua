-- TDX Macro Runner - Rebuild (X-only Tracking, Retry & Priority)

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local player   = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes  = ReplicatedStorage:WaitForChild("Remotes")

-- safe require
local function SafeRequire(path)
    local ok, result = pcall(require, path)
    return ok and result or nil
end

-- load TowerClass module
local function LoadTowerClass()
    local ps          = player:WaitForChild("PlayerScripts")
    local client      = ps:WaitForChild("Client")
    local gameClass   = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then
    error("Không thể tải TowerClass")
end

-- get tower by exact X-axis match
local function GetTowerByAxis(x)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local ok, posX = pcall(function()
            local model = tower.Character:GetCharacterModel()
            return model and model.PrimaryPart.Position.X
        end)
        if ok and posX == x then
            local okHp, hp = pcall(function()
                return tower.HealthHandler:GetHealth()
            end)
            if okHp and hp > 0 then
                return hash, tower
            end
        end
    end
    return nil, nil
end

-- wait until player has at least `amount` cash
local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

-- try placing a tower until it appears at X
local function PlaceTower)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        local hash = GetTowerByAxis(x)
        if hash then
            return true
        end
        warn("[RETRY] Đặt thất bại:", name, x)
    end
end

-- try upgrading path on tower at X until level increases or maxed
local function UpgradeTowerRetry(x, path)
    while true do
        local hash, tower = GetTowerByAxis(x)
        if not tower then
            task.wait()
            continue
        end

        local lvlBefore = tower.LevelHandler:GetLevelOnPath(path)
        local maxLevel  = tower.LevelHandler:GetMaxLevel()
        if lvlBefore >= maxLevel then
            return true
        end

        local okCost, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
        end)
        if not okCost or not cost then
            return false
        end

        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        task.wait(0.1)

        local lvlAfter = tower.LevelHandler:GetLevelOnPath(path)
        if lvlAfter > lvlBefore then
            return true
        end
    end
end

-- fire sell remote on tower at X
local function SellTowerRetry(x)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.SellTower:FireServer(hash)
    end
end

-- fire change-target remote on tower at X
local function ChangeTargetRetry(x, t)
    local hash = GetTowerByAxis(x)
    if hash then
        Remotes.ChangeQueryType:FireServer(hash, t)
    end
end

-- load macro JSON
local cfg       = _G.TDX_Config or {}
local macroPath = "tdx/macros/" .. (cfg["Macro Name"] or "event") .. ".json"
local macro     = HttpService:JSONDecode(readfile(macroPath))

-- state
local rebuildActive = false
local skipSet       = {}    -- tower names to skip on rebuild
local rebuildTime   = 0     -- index in macro to rebuild up to
local placedPositions = {}  -- key = X (number), value = true

-- priority map for sorting place actions
local typePriority = {
    Medic            = 1,
    ["Golden Mobster"] = 2,
    Mobster          = 2,
    DJ               = 3,
    Commander        = 4,
    default          = 5,
}

local function getPriority(name)
    return typePriority[name] or typePriority.default
end

-- rebuild sequence at position X
local function rebuildTowerAtX(x)
    local actions = {}
    for i = 1, rebuildTime do
        local step = macro[i]
        -- place
        if step.TowerVector then
            local v = step.TowerVector:split(", ")
            if tonumber(v[1]) == x and not skipSet[step.TowerPlaced] then
                table.insert(actions, {
                    type     = "place",
                    data     = step,
                    priority = getPriority(step.TowerPlaced),
                })
            end

        -- upgrade
        elseif step.TowerUpgraded and tonumber(step.TowerUpgraded) == x then
            table.insert(actions, { type = "upgrade", data = step })

        -- change target
        elseif step.ChangeTarget and tonumber(step.ChangeTarget) == x then
            table.insert(actions, { type = "target", data = step })
        end
    end

    table.sort(actions, function(a, b)
        return (a.priority or 10) < (b.priority or 10)
    end)

    for _, act in ipairs(actions) do
        local s = act.data
        if act.type == "place" then
            local v    = s.TowerVector:split(", ")
            local args = {
                tonumber(s.TowerA1),
                s.TowerPlaced,
                Vector3.new(unpack(v)),
                tonumber(s.Rotation or 0),
            }
            WaitForCash(s.TowerPlaceCost or 0)
            if PlaceTowerRetry(args, x, s.TowerPlaced) then
                placedPositions[x] = true
            end

        elseif act.type == "upgrade" then
            UpgradeTowerRetry(x, s.UpgradePath)

        elseif act.type == "target" then
            ChangeTargetRetry(x, s.TargetType)
        end
    end
end

-- main macro loop
for idx, line in ipairs(macro) do
    -- Sell All
    if line.SuperFunction == "SellAll" then
        local skipNames = {}
        for _, nm in ipairs(line.Skip or {}) do
            skipNames[nm] = true
        end
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            if model and not skipNames[model.Name] then
                Remotes.SellTower:FireServer(hash)
            end
        end

    -- start rebuild mode
    elseif line.SuperFunction == "rebuild" then
        rebuildActive = true
        for _, nm in ipairs(line.Skip or {}) do
            skipSet[nm] = true
        end
        rebuildTime = idx

        task.spawn(function()
            while rebuildActive do
                for x in pairs(placedPositions) do
                    local _, tower = GetTowerByAxis(x)
                    if not tower then
                        placedPositions[x] = nil
                        rebuildTowerAtX(x)
                    end
                end
                task.wait(1)
            end
        end)

    -- normal macro actions
    else
        -- place
        if line.TowerPlaced and line.TowerVector local vec = line.TowerVector:split(", ")
            local pos = Vector3.new(unpack(vec))
            local args = {
                tonumber(line.TowerA1),
                line.TowerPlaced,
                pos,
                tonumber(line.Rotation or 0),
            }

            WaitForCash(line.TowerPlaceCost or 0)
            if PlaceTowerRetry(args, pos.X, line.TowerPlaced) then
                placedPositions[pos.X] = true
            end

        -- upgrade
        elseif line.TowerUpgraded then
            UpgradeTowerRetry(tonumber(line.TowerUpgraded), line.UpgradePath)

        -- sell
        elseif line.SellTower then
            SellTowerRetry(line.SellTower)

        -- change target
        elseif line.ChangeTarget then
            ChangeTargetRetry(tonumber(line.ChangeTarget), line.TargetType)
        end
    end
end

print("✅ Macro hoàn tất")
