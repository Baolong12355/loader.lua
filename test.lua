-- [[ Auto Rebuild In-Game - Test Mode - Cho phép rebuild dù bán ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- === Load TowerClass
local TowerClass
do
    local ps = player:WaitForChild("PlayerScripts")
    local client = ps:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end

-- === Lấy giá tiền đặt tower theo tên
local function GetTowerPlaceCostByName(name)
    local gui = player:FindFirstChild("PlayerGui")
    local bar = gui and gui:FindFirstChild("Interface") and gui.Interface:FindFirstChild("BottomBar")
    local towersBar = bar and bar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costText = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
            if costText then
                return tonumber(tostring(costText.Text):gsub("%D", "")) or 0
            end
        end
    end
    return 0
end

-- === Lấy giá nâng cấp
local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    local disc = 0
    if tower.BuffHandler then
        local ok2, d = pcall(function()
            return tower.BuffHandler:GetDiscount() or 0
        end)
        if ok2 then disc = d end
    end
    return math.floor((cost or 0) * (1 - disc))
end

-- === Chờ đủ tiền
local function WaitForCash(amount)
    local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
    while cash.Value < amount do task.wait() end
end

-- === Tìm tower bằng trục X chính xác
local function GetTowerByX(x)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local model = tower.Character and tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        if root and root.Position.X == x then
            return hash, tower
        end
    end
    return nil, nil
end

-- === Ghi lại hành động
local towerRecords = {} -- [X] = { {type = "...", data = {...}} }

local function logAction(typ, data)
    if not data.Axis then return end
    towerRecords[data.Axis] = towerRecords[data.Axis] or {}
    table.insert(towerRecords[data.Axis], {type = typ, data = data})
end

-- === Hook ghi lại
local old
old = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if method == "FireServer" then
        if self.Name == "PlaceTower" then
            local a1, name, pos, rot = unpack(args)
            logAction("Place", {
                A1 = a1,
                Name = name,
                Vector = pos,
                Rotation = rot,
                Cost = GetTowerPlaceCostByName(name),
                Axis = pos.X
            })
        elseif self.Name == "TowerUpgradeRequest" then
            local hash, path, count = unpack(args)
            local tower = TowerClass.GetTowers()[hash]
            if tower then
                local model = tower.Character and tower.Character:GetCharacterModel()
                local root = model and model.PrimaryPart
                if root then
                    logAction("Upgrade", {
                        Path = path,
                        Count = count,
                        Axis = root.Position.X
                    })
                end
            end
        elseif self.Name == "ChangeQueryType" then
            local hash, typ = unpack(args)
            local tower = TowerClass.GetTowers()[hash]
            if tower then
                local model = tower.Character and tower.Character:GetCharacterModel()
                local root = model and model.PrimaryPart
                if root then
                    logAction("Target", {
                        Type = typ,
                        Axis = root.Position.X
                    })
                end
            end
        end
    end
    return old(self, ...)
end)

-- === Hệ thống rebuild
task.spawn(function()
    while true do
        for x, actions in pairs(towerRecords) do
            local hash, tower = GetTowerByX(x)
            if not hash then -- ✅ luôn rebuild nếu tower biến mất (kể cả do bán)
                for _, act in ipairs(actions) do
                    local t = act.type
                    local d = act.data
                    if t == "Place" then
                        WaitForCash(d.Cost or 100)
                        pcall(function()
                            Remotes.PlaceTower:InvokeServer(d.A1, d.Name, d.Vector, d.Rotation)
                        end)
                        task.wait(1)

                    elseif t == "Upgrade" then
                        for i = 1, d.Count do
                            local hash2, tower2 = GetTowerByX(x)
                            if hash2 and tower2 then
                                local cost = GetUpgradeCost(tower2, d.Path)
                                if cost then WaitForCash(cost) end
                                pcall(function()
                                    Remotes.TowerUpgradeRequest:FireServer(hash2, d.Path, 1)
                                end)
                            end
                            task.wait(0.2)
                        end

                    elseif t == "Target" then
                        local hash2 = GetTowerByX(x)
                        if hash2 then
                            pcall(function()
                                Remotes.ChangeQueryType:FireServer(hash2, d.Type)
                            end)
                        end
                    end
                    task.wait(0.2)
                end
            end
        end
        task.wait(0.5)
    end
end)

print("✅ Auto Rebuild (Test Mode) đã chạy – sẽ rebuild lại cả khi bạn bán tower")
