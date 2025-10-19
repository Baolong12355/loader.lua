-- highlight enemy đi xa nhất trong tầm của tower và làm tower phát sáng
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
repeat task.wait() until LocalPlayer:FindFirstChild("PlayerScripts")

local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)
local EnemyClass = require(LocalPlayer.PlayerScripts.Client.GameClass.EnemyClass)

-- lấy tower đầu tiên thuộc người chơi
local function getLocalTower()
    for _, tower in pairs(TowerClass.GetTowers()) do
        if tower.OwnedByLocalPlayer and tower:Alive() then
            return tower
        end
    end
end

local function getFarthestEnemyInRange(tower)
    local enemies = EnemyClass.GetEnemies()
    local towerPos = tower:GetPosition()
    local range = tower:GetCurrentRange()
    local farthest, maxProgress = nil, -math.huge

    for _, enemy in pairs(enemies) do
        if enemy and enemy.MovementHandler and enemy:Alive() then
            local dist = (enemy:GetPosition() - towerPos).Magnitude
            if dist <= range then
                local percent = enemy.MovementHandler.PathPercentage or 0
                if percent > maxProgress then
                    maxProgress = percent
                    farthest = enemy
                end
            end
        end
    end
    return farthest
end

-- xóa mọi highlight cũ
local function clearHighlights()
    for _, e in pairs(workspace.Game.Enemies:GetChildren()) do
        local h = e:FindFirstChildOfClass("Highlight")
        if h then h:Destroy() end
    end
    for _, t in pairs(workspace.Game.Towers:GetChildren()) do
        local h = t:FindFirstChildOfClass("Highlight")
        if h then h:Destroy() end
    end
end

local function highlightEnemyAndTower(enemy, tower)
    clearHighlights()

    -- highlight enemy (vàng cam)
    if enemy and enemy.Character then
        local model = enemy.Character:GetCharacterModel()
        if model then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(255, 170, 0)
            hl.OutlineColor = Color3.fromRGB(255, 255, 200)
            hl.FillTransparency = 0.3
            hl.OutlineTransparency = 0
            hl.Parent = model
        end
    end

    -- highlight tower (xanh dương)
    if tower and tower.Character then
        local model = tower.Character:GetCharacterModel()
        if model then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(0, 150, 255)
            hl.OutlineColor = Color3.fromRGB(200, 230, 255)
            hl.FillTransparency = 0.25
            hl.OutlineTransparency = 0
            hl.Parent = model
        end
    end
end

-- loop cập nhật highlight
task.spawn(function()
    while task.wait(0.5) do
        local tower = getLocalTower()
        if tower then
            local enemy = getFarthestEnemyInRange(tower)
            highlightEnemyAndTower(enemy, tower)
        else
            clearHighlights()
        end
    end
end)