local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

-- 🟥 Tower định hướng
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

-- Lấy enemy gần nhất
local function GetFirstEnemyPosition()
    for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
        if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
            return enemy.Position
        end
    end
    return nil
end

-- Lấy vị trí tower
local function getTowerPos(tower)
    if tower.GetPosition then
        local ok, result = pcall(function() return tower:GetPosition() end)
        if ok then return result end
    end
    if tower.Model and tower.Model:FindFirstChild("Root") then
        return tower.Model.Root.Position
    end
    return nil
end

-- Lấy range
local function getRange(tower)
    local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
    if ok and typeof(result) == "number" then
        return result
    elseif tower.Stats and tower.Stats.Radius then
        return tower.Stats.Radius * 4
    end
    return 0
end

-- Kiểm tra enemy trong range
local function hasEnemyInRange(tower)
    local towerPos = getTowerPos(tower)
    local range = getRange(tower)
    if not towerPos or range <= 0 then return false end
    for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
        if enemy:IsA("BasePart") and (enemy.Position - towerPos).Magnitude <= range then
            return true
        end
    end
    return false
end

-- Lấy cấp độ
local function GetCurrentUpgradeLevels(tower)
    if not tower or not tower.LevelHandler then return 0, 0 end
    local p1, p2 = 0, 0
    pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
    pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
    return p1, p2
end

-- Kiểm tra dùng được skill
local function CanUseAbility(ability)
    return ability and not ability.Passive and not ability.CustomTriggered
        and ability.CooldownRemaining <= 0 and not ability.Stunned
        and not ability.Disabled and not ability.Converted and ability:CanUse(true)
end

-- Commander skill 1,2 xử lý như thường
local function ShouldProcessNonDirectionalSkill(tower, index)
    return tower.Type == "Commander" and index ~= 3
end

-- 🔁 Main loop
RunService.Heartbeat:Connect(function()
    for hash, tower in pairs(TowerClass.GetTowers() or {}) do
        if not tower or not tower.AbilityHandler then continue end

        local towerType = tower.Type
        local directionalInfo = directionalTowerTypes[towerType]
        local p1, p2 = GetCurrentUpgradeLevels(tower)

        for abilityIndex = 1, 3 do
            pcall(function()
                local ability = tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
                if not CanUseAbility(ability) then return end

                local allowUse = true

                -- Điều kiện đặc biệt
                if towerType == "Ice Breaker" and abilityIndex == 1 then
                    -- skill 1 free
                elseif towerType == "Slammer" then
                    allowUse = hasEnemyInRange(tower)
                    if not allowUse then print("[⛔ Slammer] Không có enemy trong range") end
                elseif towerType == "John" then
                    local range = getRange(tower)
                    if p1 >= 5 then
                        allowUse = hasEnemyInRange(tower)
                    elseif p2 >= 5 then
                        allowUse = (range >= 4.5 and hasEnemyInRange(tower))
                    else
                        allowUse = (range >= 4.5 and hasEnemyInRange(tower))
                    end
                    print("[John] P1:", p1, "| P2:", p2, "| Use:", allowUse)
                elseif towerType == "Mobster" or towerType == "Golden Mobster" then
                    if p1 >= 4 and p1 <= 5 then
                        allowUse = hasEnemyInRange(tower)
                        print("["..towerType.."] P1:", p1, "InRange:", allowUse)
                    elseif p2 >= 3 and p2 <= 5 then
                        allowUse = true
                        print("["..towerType.."] P2:", p2, "→ Skill định hướng")
                    else
                        allowUse = false
                    end
                end

                if allowUse then
                    local enemyPos = GetFirstEnemyPosition()
                    local callWithPos = false

                    if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
                        if abilityIndex == directionalInfo.onlyAbilityIndex then
                            callWithPos = true
                        elseif ShouldProcessNonDirectionalSkill(tower, abilityIndex) then
                            callWithPos = false
                        else
                            return
                        end
                    elseif directionalInfo then
                        callWithPos = true
                    end

                    if callWithPos then
                        if enemyPos then
                            print("[🎯 SKILL định hướng]", towerType, "→", abilityIndex)
                            TowerUseAbilityRequest:FireServer(hash, abilityIndex, enemyPos)
                        end
                    else
                        print("[⚡ SKILL thường]", towerType, "→", abilityIndex)
                        TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                    end
                    task.wait(0.25)
                end
            end)
        end
    end
end)
