
local Players = game:GetService("Players") local ReplicatedStorage = game:GetService("ReplicatedStorage") local RunService = game:GetService("RunService") local LocalPlayer = Players.LocalPlayer local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass")) local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest") local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

local skipTowerTypes = { ["Farm"] = true, ["Relic"] = true, ["Scarecrow"] = true, ["Helicopter"] = true, ["Cryo Helicopter"] = true, ["Combat Drone"] = true, ["AA Turret"] = true, ["XWM Turret"] = true, ["Barracks"] = true, ["Cryo Blaster"] = true, ["Grenadier"] = true, ["Juggernaut"] = true, ["Machine Gunner"] = true, ["Zed"] = true, ["Troll Tower"] = true, ["Missile Trooper"] = true, ["Patrol Boat"] = true, ["Railgunner"] = true, ["Mine Layer"] = true, ["Sentry"] = true, ["Commander"] = true, ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true, ["Mobster"] = true, ["Golden Mobster"] = true, ["Artillery"] = true, ["EDJ"] = false, ["Accelerator"] = true, ["Engineer"] = true }

local directionalTowerTypes = { ["Commander"] = { onlyAbilityIndex = 3 }, ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = { skipRangeCheckIndexes = {1} }, ["Mobster"] = true, ["Artillery"] = true, ["Golden Mine Layer"] = true }

local function GetCurrentUpgradeCosts(tower) if not tower or not tower.LevelHandler then return { path1 = {cost = "N/A", currentLevel = "N/A", maxLevel = "N/A", exists = true}, path2 = {cost = "N/A", currentLevel = "N/A", maxLevel = "N/A", exists = false} } end

local result = {
    path1 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = true},
    path2 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = false}
}

local maxLevel = tower.LevelHandler:GetMaxLevel()

local currentLvl1 = tower.LevelHandler:GetLevelOnPath(1)
result.path1.currentLevel = currentLvl1
result.path1.maxLevel = maxLevel

if currentLvl1 < maxLevel then
    local success, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(1, 1)
    end)
    if success then
        result.path1.cost = math.floor(cost)
    else
        result.path1.cost = "LỖI"
    end
end

local hasPath2 = pcall(function()
    return tower.LevelHandler:GetLevelOnPath(2) ~= nil
end)

if hasPath2 then
    result.path2.exists = true
    local currentLvl2 = tower.LevelHandler:GetLevelOnPath(2)
    result.path2.currentLevel = currentLvl2
    result.path2.maxLevel = maxLevel

    if currentLvl2 < maxLevel then
        local success, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(2, 1)
        end)
        if success then
            result.path2.cost = math.floor(cost)
        else
            result.path2.cost = "LỖI"
        end
    end
end

return result

end

local function getTowerPos(tower) if tower.GetPosition then local ok, result = pcall(function() return tower:GetPosition() end) if ok then return result end end if tower.Model and tower.Model:FindFirstChild("Root") then return tower.Model.Root.Position end return nil end

local function getRange(tower) local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end) if ok and typeof(result) == "number" then return result elseif tower.Stats and tower.Stats.Radius then return tower.Stats.Radius * 4 end return 0 end

local function hasEnemyInRange(tower) local towerPos = getTowerPos(tower) local range = getRange(tower) if not towerPos or range <= 0 then return false end for _, enemy in ipairs(EnemiesFolder:GetChildren()) do if enemy:IsA("BasePart") and (enemy.Position - towerPos).Magnitude <= range then return true end end return false end

local function CanUseAbility(ability) return ability and not ability.Passive and not ability.CustomTriggered and ability.CooldownRemaining <= 0 and not ability.Stunned and not ability.Disabled and not ability.Converted and ability:CanUse(true) end

local function ShouldProcessTower(tower) return tower and not tower.Destroyed and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 and not skipTowerTypes[tower.Type] and tower.AbilityHandler end

local function ShouldProcessNonDirectionalSkill(tower, abilityIndex) return tower.Type == "Commander" and abilityIndex ~= 3 and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 end

RunService.Heartbeat:Connect(function() for hash, tower in pairs(TowerClass.GetTowers() or {}) do local towerType = tower.Type local directionalInfo = directionalTowerTypes[towerType]

local upgrades = GetCurrentUpgradeCosts(tower)
    local p1 = upgrades.path1.currentLevel
    local p2 = upgrades.path2.currentLevel

    if towerType == "Golden Mobster" and p2 >= 3 then
        directionalInfo = true
    end

    if ShouldProcessTower(tower) or ShouldProcessNonDirectionalSkill(tower, 1) then
        for abilityIndex = 1, 3 do
            pcall(function()
                local ability = tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
                if CanUseAbility(ability) then
                    local shouldUse = true

                    if towerType == "Ice Breaker" and (not directionalInfo.skipRangeCheckIndexes or not table.find(directionalInfo.skipRangeCheckIndexes, abilityIndex)) then
                        shouldUse = hasEnemyInRange(tower)
                    elseif towerType == "Slammer" then
                        shouldUse = hasEnemyInRange(tower)
                    elseif towerType == "John" then
                        if p1 >= 5 then
                            shouldUse = hasEnemyInRange(tower)
                        elseif p2 >= 5 then
                            shouldUse = getRange(tower) >= 4.5 and hasEnemyInRange(tower)
                        else
                            shouldUse = getRange(tower) >= 4.5 and hasEnemyInRange(tower)
                        end
                    elseif towerType == "Mobster" or towerType == "Golden Mobster" then
                        if p1 >= 4 and p1 <= 5 then
                            shouldUse = hasEnemyInRange(tower)
                        elseif p2 >= 3 and p2 <= 5 then
                            shouldUse = true
                        else
                            shouldUse = false
                        end
                    end

                    if shouldUse then
                        if directionalInfo then
                            local enemyPos = getTowerPos(tower)
                            if enemyPos then
                                if useFireServer then
                                    TowerUseAbilityRequest:FireServer(hash, abilityIndex, enemyPos)
                                else
                                    TowerUseAbilityRequest:InvokeServer(hash, abilityIndex, enemyPos)
                                end
                                task.wait(0.25)
                            end
                        else
                            if useFireServer then
                                TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                            else
                                TowerUseAbilityRequest:InvokeServer(hash, abilityIndex)
                            end
                            task.wait(0.25)
                        end
                    end
                end
            end)
        end
    end
end

end)


                    if towerType == "Ice Breaker" and (not directionalInfo.skipRangeCheckIndexes or not table.find(directionalInfo.skipRangeCheckIndexes, abilityIndex)) then
                        shouldUse = dist <= 8
                    elseif towerType == "Slammer" then
                        shouldUse = dist <= (TowerClass.GetCurrentRange and TowerClass:GetCurrentRange(tower) or 20)
                    elseif towerType == "John" then
                        local path1 = GetPathLevel(tower, 1)
                        local path2 = GetPathLevel(tower, 2)
                        if path1 >= 5 then
                            local range = TowerClass.GetCurrentRange and TowerClass:GetCurrentRange(tower) or 5
                            shouldUse = dist <= range
                        elseif path2 >= 5 then
                            shouldUse = dist <= 4.5
                        else
                            shouldUse = dist <= 4.5
                        end
                    elseif towerType == "Mobster" or towerType == "Golden Mobster" then
                        local path1 = GetPathLevel(tower, 1)
                        local path2 = GetPathLevel(tower, 2)
                        if path1 >= 4 and path1 <= 5 then
                            shouldUse = dist <= (TowerClass.GetCurrentRange and TowerClass:GetCurrentRange(tower) or 20)
                        elseif path2 >= 3 and path2 <= 5 then
                            shouldUse = true -- path 2 cấp 3-5 là định hướng, không giới hạn khoảng cách
                        else
                            shouldUse = false
                        end
                    end

                    if shouldUse then
                        if directionalInfo then
                            local enemyPos = GetFirstEnemyPosition()
                            if enemyPos then
                                if useFireServer then
                                    TowerUseAbilityRequest:FireServer(hash, abilityIndex, enemyPos)
                                else
                                    TowerUseAbilityRequest:InvokeServer(hash, abilityIndex, enemyPos)
                                end
                                task.wait(0.25)
                            end
                        else
                            if useFireServer then
                                TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                            else
                                TowerUseAbilityRequest:InvokeServer(hash, abilityIndex)
                            end
                            task.wait(0.25)
                        end
                    end
                end
            end)
        end
    end
end

end)

