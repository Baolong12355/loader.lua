-- 📦 Auto-Skill PRO với điều kiện phạm vi riêng cho từng tower đặc biệt

local Players = game:GetService("Players") local ReplicatedStorage = game:GetService("ReplicatedStorage") local RunService = game:GetService("RunService") local LocalPlayer = Players.LocalPlayer local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass")) local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest") local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

local skipTowerTypes = { ["Farm"] = true, ["Relic"] = true, ["Scarecrow"] = true, ["Helicopter"] = true, ["Cryo Helicopter"] = true, ["Combat Drone"] = true, ["AA Turret"] = true, ["XWM Turret"] = true, ["Barracks"] = true, ["Cryo Blaster"] = true, ["Grenadier"] = true, ["Juggernaut"] = true, ["Machine Gunner"] = true, ["Zed"] = true, ["Troll Tower"] = true, ["Missile Trooper"] = true, ["Patrol Boat"] = true, ["Railgunner"] = true, ["Mine Layer"] = true, ["Sentry"] = true, ["Commander"] = true, ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true, ["Mobster"] = true, ["Golden Mobster"] = true, ["Artillery"] = true, ["EDJ"] = false, ["Accelerator"] = true, ["Engineer"] = true }

local directionalTowerTypes = { ["Commander"] = { onlyAbilityIndex = 3 }, ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true, ["Mobster"] = true, ["Golden Mobster"] = true, ["Artillery"] = true, ["Golden Mine Layer"] = true }

local function GetFirstEnemyPosition() for _, enemy in ipairs(EnemiesFolder:GetChildren()) do if enemy.Name ~= "Arrow" and enemy:IsA("BasePart") then return enemy.Position end end return nil end

local function GetDistanceToNearestEnemy(towerPos) local minDist = math.huge for _, enemy in ipairs(EnemiesFolder:GetChildren()) do if enemy:IsA("BasePart") then local dist = (enemy.Position - towerPos).Magnitude if dist < minDist then minDist = dist end end end return minDist end

local function CanUseAbility(ability) return ability and not ability.Passive and not ability.CustomTriggered and ability.CooldownRemaining <= 0 and not ability.Stunned and not ability.Disabled and not ability.Converted and ability:CanUse(true) end

local function ShouldProcessTower(tower) return tower and not tower.Destroyed and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 and not skipTowerTypes[tower.Type] and tower.AbilityHandler end

local function ShouldProcessNonDirectionalSkill(tower, abilityIndex) return tower.Type == "Commander" and abilityIndex ~= 3 and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 end

local function GetPathLevel(tower, path) if tower.LevelHandler and tower.LevelHandler.GetLevelOnPath then return tower.LevelHandler:GetLevelOnPath(path) end return 0 end

RunService.Heartbeat:Connect(function() for hash, tower in pairs(TowerClass.GetTowers() or {}) do local towerType = tower.Type local directionalInfo = directionalTowerTypes[towerType]

if ShouldProcessTower(tower) or ShouldProcessNonDirectionalSkill(tower, 1) then
        for abilityIndex = 1, 3 do
            pcall(function()
                local ability = tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
                if CanUseAbility(ability) then
                    local pos = tower.GetPosition and tower:GetPosition()
                    if not pos then return end

                    local shouldUse = true
                    local dist = GetDistanceToNearestEnemy(pos)

                    if towerType == "Ice Breaker" then
                        shouldUse = dist <= 8
                    elseif towerType == "Slammer" then
                        shouldUse = dist <= (TowerClass.GetCurrentRange and TowerClass:GetCurrentRange(tower) or 20)
                    elseif towerType == "John" then
                        local lvl = GetPathLevel(tower, 1)
                        if lvl >= 5 then
                            local range = TowerClass.GetCurrentRange and TowerClass:GetCurrentRange(tower) or 5
                            shouldUse = dist <= range
                        else
                            shouldUse = dist <= 4.5
                        end
                    elseif towerType == "Mobster" or towerType == "Golden Mobster" then
                        local path1 = GetPathLevel(tower, 1)
                        if path1 >= 4 then
                            shouldUse = dist <= (TowerClass.GetCurrentRange and TowerClass:GetCurrentRange(tower) or 20)
                        else
                            shouldUse = false
                        end
                    end

                    if shouldUse then
                        if directionalInfo then
                            local enemyPos = GetFirstEnemyPosition()
                            if enemyPos then
                                TowerUseAbilityRequest:FireServer(hash, abilityIndex, enemyPos)
                                task.wait(0.25)
                            end
                        else
                            TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                            task.wait(0.25)
                        end
                    end
                end
            end)
        end
    end
end

end)

