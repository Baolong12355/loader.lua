local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

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

local skipTowerTypes = {
    ["Helicopter"] = true,
    ["Cryo Helicopter"] = true,
    ["Medic"] = true,
    ["Combat Drone"] = true
}

local fastTowers = {
    ["Ice Breaker"] = true,
    ["John"] = true,
    ["Slammer"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true
}

local lastUsedTime = {}
local mobsterUsedTargets = {}

local function SendSkill(hash, index, pos)
    if useFireServer then
        TowerUseAbilityRequest:FireServer(hash, index, pos)
    else
        TowerUseAbilityRequest:InvokeServer(hash, index, pos)
    end
end

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

local function getRange(tower)
    local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
    if ok and typeof(result) == "number" then
        return result
    elseif tower.Stats and tower.Stats.Radius then
        return tower.Stats.Radius * 4
    end
    return 0
end

local function getValidEnemiesInRange(tower, studsLimit)
    local towerPos = getTowerPos(tower)
    local range = studsLimit or getRange(tower)
    local enemies = {}
    if not towerPos or range <= 0 then return enemies end
    for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
        if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
            local enemyObj = enemy:FindFirstChild("EnemyData")
            local isAir = enemy:FindFirstChild("IsAirUnit") and enemy.IsAirUnit.Value
            if (enemy.Position - towerPos).Magnitude <= range and not isAir then
                table.insert(enemies, enemy)
            end
        end
    end
    return enemies
end

local function findStrongestEnemy(tower, towerHash)
    local candidates = getValidEnemiesInRange(tower)
    local bestEnemy = nil
    local bestHp = -1
    for _, enemy in ipairs(candidates) do
        local hash = enemy:GetDebugId()
        if not mobsterUsedTargets[hash] then
            local hp = tonumber(enemy:FindFirstChild("MaxHealth") and enemy.MaxHealth.Value) or 0
            if hp > bestHp then
                bestHp = hp
                bestEnemy = enemy
            end
        end
    end
    if bestEnemy then
        return { obj = bestEnemy, hash = bestEnemy:GetDebugId() }
    end
    return nil
end

local function getRandomEnemyPosition()
    local enemies = getValidEnemiesInRange({ GetPosition = function() return Vector3.zero end }, math.huge)
    if #enemies == 0 then return nil end
    table.sort(enemies, function(a, b)
        local aHP = tonumber(a:FindFirstChild("MaxHealth") and a.MaxHealth.Value) or 0
        local bHP = tonumber(b:FindFirstChild("MaxHealth") and b.MaxHealth.Value) or 0
        return aHP > bHP
    end)
    local strongest = enemies[1]
    if math.random(1, 10) <= 6 then
        return strongest.Position
    else
        return enemies[math.random(1, #enemies)].Position
    end
end

local function CanUseAbility(ability)
    if not ability then return false end
    if ability.Passive or ability.CustomTriggered or ability.Stunned or ability.Disabled or ability.Converted then return false end
    if ability.CooldownRemaining > 0 then return false end
    local ok, usable = pcall(function() return ability:CanUse(true) end)
    return ok and usable
end

RunService.Heartbeat:Connect(function()
    local now = tick()
    for hash, tower in pairs(TowerClass.GetTowers() or {}) do
        if not tower or not tower.AbilityHandler then continue end
        local towerType = tower.Type
        if skipTowerTypes[towerType] then continue end

        local delay = fastTowers[towerType] and 0.1 or 0.2
        if lastUsedTime[hash] and now - lastUsedTime[hash] < delay then
            continue
        end
        lastUsedTime[hash] = now

        local directionalInfo = directionalTowerTypes[towerType]
        local p1, p2 = 0, 0
        pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
        pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)

        for i = 1, 3 do
            local ability = tower.AbilityHandler:GetAbilityFromIndex(i)
            if not CanUseAbility(ability) then continue end

            local allowUse = true
            local skillTargetPos
            local usedEnemyHash

            if towerType == "Ice Breaker" then
                if i == 1 then
                    allowUse = true
                elseif i == 2 then
                    allowUse = #getValidEnemiesInRange(tower, 8) > 0
                else
                    allowUse = false
                end
            elseif towerType == "Slammer" then
                allowUse = #getValidEnemiesInRange(tower) > 0
            elseif towerType == "John" then
                if p1 >= 5 then
                    allowUse = #getValidEnemiesInRange(tower) > 0
                else
                    allowUse = #getValidEnemiesInRange(tower, 4.5) > 0
                end
            elseif towerType == "Mobster" or towerType == "Golden Mobster" then
                if p2 >= 3 and p2 <= 5 then
                    local target = findStrongestEnemy(tower, hash)
                    if target then
                        allowUse = true
                        skillTargetPos = target.obj.Position
                        usedEnemyHash = target.hash
                    else
                        allowUse = false
                    end
                elseif p1 >= 4 and p1 <= 5 then
                    allowUse = #getValidEnemiesInRange(tower) > 0
                else
                    allowUse = false
                end
            end

            if allowUse then
                local pos
                if towerType == "Commander" and i == 3 then
                    pos = getRandomEnemyPosition()
                elseif skillTargetPos then
                    pos = skillTargetPos
                else
                    local valid = getValidEnemiesInRange(tower)
                    if #valid > 0 then
                        pos = valid[1].Position
                    end
                end

                if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
                    if i ~= directionalInfo.onlyAbilityIndex then
                        continue
                    end
                elseif not directionalInfo then
                    pos = nil
                end

                SendSkill(hash, i, pos)
                if usedEnemyHash then
                    mobsterUsedTargets[usedEnemyHash] = true
                end
            end
        end
    end
end)
