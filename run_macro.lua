local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

-- các tower định hướng
local directionalTowerTypes = {
    ["Commander"] = { onlyAbilityIndex = 3 },
    ["Toxicnator"] = true,
    ["Ghost"] = true,
    ["Ice Breaker"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true,
    ["Artillery"] = true,
    ["Golden Mine Layer"] = true
}

-- các tower bỏ qua
local skipTowerTypes = {
    ["Helicopter"] = true,
    ["Cryo Helicopter"] = true
}

-- hàm gửi skill
local function SendSkill(hash, index, pos)
    if useFireServer then
        if pos then
            TowerUseAbilityRequest:FireServer(hash, index, pos)
        else
            TowerUseAbilityRequest:FireServer(hash, index)
        end
    else
        if pos then
            TowerUseAbilityRequest:InvokeServer(hash, index, pos)
        else
            TowerUseAbilityRequest:InvokeServer(hash, index)
        end
    end
end

-- lấy enemy đầu tiên
local function GetFirstEnemyPosition()
    for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
        if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
            return enemy.Position
        end
    end
    return nil
end

-- lấy vị trí tower
local function getTowerPos(tower)
    if tower.GetPosition then
        local ok, pos = pcall(function() return tower:GetPosition() end)
        if ok then return pos end
    end
    if tower.Model and tower.Model:FindFirstChild("Root") then
        return tower.Model.Root.Position
    end
    return nil
end

-- lấy range
local function getRange(tower)
    local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
    if ok and typeof(result) == "number" then
        return result
    elseif tower.Stats and tower.Stats.Radius then
        return tower.Stats.Radius * 4
    end
    return 0
end

-- kiểm tra enemy trong range
local function hasEnemyInRange(tower, studsOverride)
    local towerPos = getTowerPos(tower)
    local range = studsOverride or getRange(tower)
    if not towerPos or range <= 0 then return false end

    for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
        if enemy:IsA("BasePart") then
            local dist = (enemy.Position - towerPos).Magnitude
            if dist <= range then
                return true
            end
        end
    end
    return false
end

-- lấy cấp độ path 1 và 2
local function GetCurrentUpgradeLevels(tower)
    if not tower or not tower.LevelHandler then return 0, 0 end
    local p1, p2 = 0, 0
    pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
    pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
    return p1, p2
end

-- kiểm tra có thể dùng skill
local function CanUseAbility(ability)
    if not ability then return false end
    if ability.Passive then return false end
    if ability.CustomTriggered then return false end
    if ability.CooldownRemaining > 0 then return false end
    if ability.Stunned or ability.Disabled or ability.Converted then return false end
    local ok, result = pcall(function() return ability:CanUse(true) end)
    return ok and result
end

-- commander skill 1 2 xử lý như thường
local function ShouldProcessNonDirectionalSkill(tower, index)
    return tower.Type == "Commander" and index ~= 3
end

-- loop chính
RunService.Heartbeat:Connect(function()
    for hash, tower in pairs(TowerClass.GetTowers() or {}) do
        if not tower or not tower.AbilityHandler then continue end
        if skipTowerTypes[tower.Type] then continue end

        local towerType = tower.Type
        local p1, p2 = GetCurrentUpgradeLevels(tower)
        local directionalInfo = directionalTowerTypes[towerType]

        for index = 1, 3 do
            pcall(function()
                local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                if not CanUseAbility(ability) then return end

                local allowUse = true

                if towerType == "Ice Breaker" and index == 1 then
                    -- skill 1 dùng tự do
                elseif towerType == "Slammer" then
                    allowUse = hasEnemyInRange(tower)
                elseif towerType == "John" then
                    if p1 >= 5 then
                        allowUse = hasEnemyInRange(tower)
                    elseif p2 >= 5 then
                        allowUse = hasEnemyInRange(tower, 4.5)
                    else
                        allowUse = hasEnemyInRange(tower, 4.5)
                    end
                elseif towerType == "Mobster" or towerType == "Golden Mobster" then
                    if p1 >= 4 and p1 <= 5 then
                        allowUse = hasEnemyInRange(tower)
                    elseif p2 >= 3 and p2 <= 5 then
                        allowUse = true
                    else
                        allowUse = false
                    end
                end

                if allowUse then
                    local pos = GetFirstEnemyPosition()
                    local sendWithPos = false

                    if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
                        if index == directionalInfo.onlyAbilityIndex then
                            sendWithPos = true
                        elseif ShouldProcessNonDirectionalSkill(tower, index) then
                            sendWithPos = false
                        else
                            return
                        end
                    elseif directionalInfo then
                        sendWithPos = true
                    end

                    if sendWithPos then
                        if pos then
                            print("[🎯 skill định hướng]", towerType, "→", index)
                            SendSkill(hash, index, pos)
                        end
                    else
                        print("[⚡ skill thường]", towerType, "→", index)
                        SendSkill(hash, index)
                    end

                    task.wait(0.25)
                end
            end)
        end
    end
end)
