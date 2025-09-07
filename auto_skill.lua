local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- Enhanced tower configurations
local directionalTowerTypes = {
        ["Commander"] = { onlyAbilityIndex = 3 },
        ["Toxicnator"] = true,
        ["Ghost"] = true,
        ["Ice Breaker"] = true,
        ["Mobster"] = true,
        ["Golden Mobster"] = true,
        ["Artillery"] = true,
        ["Golden Mine Layer"] = true,
        ["Flame Trooper"] = true  -- Added new special tower
}

local skipTowerTypes = {
        ["Helicopter"] = true,
        ["Cryo Helicopter"] = true,
        ["Medic"] = true,
        ["Combat Drone"] = true,
        ["Machine Gunner"] = true  -- Added Machine Gunner to skip list
}

local fastTowers = {
        ["Ice Breaker"] = true,
        ["John"] = true,
        ["Slammer"] = true,
        ["Mobster"] = true,
        ["Golden Mobster"] = true,
        ["Flame Trooper"] = true  -- Added to fast towers
}

local skipAirTowers = {
        ["Ice Breaker"] = true,
        ["John"] = true,
        ["Slammer"] = true,
        ["Mobster"] = true,
        ["Golden Mobster"] = true
}

-- Enhanced tracking variables
local lastUsedTime = {}
local mobsterUsedEnemies = {}
local prevCooldown = {}
local medicLastUsedTime = {}
local medicDelay = 0.5

-- New tracking for support towers
local towerAttackStates = {}  -- Track which towers are currently attacking
local lastAttackCheck = {}    -- Track last time each tower attacked

-- ======== Core utility functions ========
local function getDistance2D(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function getTowerPos(tower)
        local ok, pos = pcall(function() return tower:GetPosition() end)
        if ok then return pos end
        if tower.Model and tower.Model:FindFirstChild("Root") then
                return tower.Model.Root.Position
        end
        return nil
end

local function getRange(tower)
        local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
        if ok and typeof(result) == "number" then return result end
        if tower.Stats and tower.Stats.Radius then return tower.Stats.Radius * 4 end
        return 0
end

local function GetCurrentUpgradeLevels(tower)
        local p1, p2 = 0, 0
        pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
        pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
        return p1, p2
end

local function isCooldownReady(hash, index, ability)
        if not ability then return false end
        local lastCD = (prevCooldown[hash] and prevCooldown[hash][index]) or 0
        local currentCD = ability.CooldownRemaining or 0
        if currentCD > lastCD + 0.1 or currentCD > 0 then
                prevCooldown[hash] = prevCooldown[hash] or {}
                prevCooldown[hash][index] = currentCD
                return false
        end
        prevCooldown[hash] = prevCooldown[hash] or {}
        prevCooldown[hash][index] = currentCD
        return true
end

local function getDPS(tower)
        if not tower or not tower.LevelHandler then return 0 end
        local levelStats = tower.LevelHandler:GetLevelStats()
        local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or {}
        local baseDmg = levelStats.Damage or 0
        local dmgMultiplier = buffStats.DamageMultiplier or 0
        local currentDmg = baseDmg * (1 + dmgMultiplier)
        local reload = tower.GetCurrentReloadTime and tower:GetCurrentReloadTime() or levelStats.ReloadTime or 1
        return (currentDmg / reload)
end

local function isBuffedByMedic(tower)
        if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then return false end
        for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
                local buffName = tostring(buff.Name or "")
                if buffName:match("^MedicKritz") or buffName:match("^MedicGodMode") then
                        return true
                end
        end
        return false
end

local function canReceiveBuff(tower)
        return tower and not tower.NoBuffs
end

-- ======== Enhanced enemy management ========
local function getEnemies()
        local result = {}
        for _, e in pairs(EnemyClass.GetEnemies()) do
                if e and e.IsAlive and not e.IsFakeEnemy then
                        table.insert(result, e)
                end
        end
        return result
end

-- Enhanced pathfinding distance calculation
local function getEnemyPathDistance(enemy)
        if not enemy or not enemy.GetPathPosition then return 0 end
        local success, pathPos = pcall(function() return enemy:GetPathPosition() end)
        if not success then return 0 end

        -- Calculate distance traveled along path (approximate)
        local totalDistance = 0
        if enemy.PathHandler and enemy.PathHandler.DistanceTraveled then
                totalDistance = enemy.PathHandler.DistanceTraveled
        elseif enemy.PathIndex then
                totalDistance = enemy.PathIndex * 10  -- Rough estimate
        end

        return totalDistance
end

-- Enhanced targeting system with farthest enemy priority
local function getFarthestEnemyInRange(pos, range, options)
        options = options or {}
        local excludeAir = options.excludeAir or false
        local excludeArrows = options.excludeArrows or false

        local candidates = {}
        for _, enemy in ipairs(getEnemies()) do
                if not enemy.GetPosition then continue end
                if excludeArrows and enemy.Type == "Arrow" then continue end
                if excludeAir and enemy.IsAirUnit then continue end

                local ePos = enemy:GetPosition()
                if getDistance2D(ePos, pos) <= range then
                        table.insert(candidates, {
                                enemy = enemy,
                                pathDistance = getEnemyPathDistance(enemy)
                        })
                end
        end

        if #candidates == 0 then return nil end

        -- Sort by path distance (farthest first)
        table.sort(candidates, function(a, b)
                return a.pathDistance > b.pathDistance
        end)

        return candidates[1].enemy:GetPosition()
end

-- Get nearest enemy (for original behavior preservation)
local function getNearestEnemyInRange(pos, range, options)
        options = options or {}
        local excludeAir = options.excludeAir or false
        local excludeArrows = options.excludeArrows or false

        for _, enemy in ipairs(getEnemies()) do
                if not enemy.GetPosition then continue end
                if excludeArrows and enemy.Type == "Arrow" then continue end
                if excludeAir and enemy.IsAirUnit then continue end

                local ePos = enemy:GetPosition()
                if getDistance2D(ePos, pos) <= range then
                        return ePos
                end
        end

        return nil
end

-- NEW: Check if ability has splash damage for enhanced targeting
local function hasSplashDamage(ability)
        if not ability or not ability.Config then return false end
        
        -- Check for splash damage indicators
        if ability.Config.ProjectileHitData then
                local hitData = ability.Config.ProjectileHitData
                if hitData.IsSplash and hitData.SplashRadius and hitData.SplashRadius > 0 then
                        return true, hitData.SplashRadius
                end
        end
        
        -- Check for radius effects
        if ability.Config.HasRadiusEffect and ability.Config.EffectRadius and ability.Config.EffectRadius > 0 then
                return true, ability.Config.EffectRadius
        end
        
        return false, 0
end

-- NEW: Get effective range for ability (ability range overrides tower range)
local function getAbilityRange(ability, defaultRange)
        if not ability or not ability.Config then return defaultRange end
        
        local config = ability.Config
        
        -- Check for infinite range
        if config.ManualAimInfiniteRange == true then
                return math.huge
        end
        
        -- Check for custom manual aim range
        if config.ManualAimCustomRange and config.ManualAimCustomRange > 0 then
                return config.ManualAimCustomRange
        end
        
        -- Check for ability-specific range
        if config.Range and config.Range > 0 then
                return config.Range
        end
        
        -- Check for custom query data range
        if config.CustomQueryData and config.CustomQueryData.Range then
                return config.CustomQueryData.Range
        end
        
        -- Default to tower range
        return defaultRange
end

-- NEW: Check if ability requires manual aiming
local function requiresManualAiming(ability)
        if not ability or not ability.Config then return false end
        
        return ability.Config.IsManualAimAtGround == true or 
               ability.Config.IsManualAimAtPath == true
end

-- ======== Tower attack state tracking ========
local function updateTowerAttackStates()
        local ownedTowers = TowerClass.GetTowers() or {}
        local now = tick()

        for hash, tower in pairs(ownedTowers) do
                if not tower or not tower.TimeUntilNextAttack then continue end

                local currentTime = tower.TimeUntilNextAttack
                local lastTime = lastAttackCheck[hash]

                -- If TimeUntilNextAttack just reset (was higher, now lower), tower attacked
                if lastTime and lastTime > currentTime and currentTime > 0 then
                        towerAttackStates[hash] = {
                                isAttacking = true,
                                lastAttackTime = now,
                                tower = tower
                        }
                end

                lastAttackCheck[hash] = currentTime

                -- Clear attack state if too much time has passed
                if towerAttackStates[hash] and (now - towerAttackStates[hash].lastAttackTime) > 3 then
                        towerAttackStates[hash] = nil
                end
        end
end

local function hasAttackingTowersInRange(checkTower, range)
        local checkPos = getTowerPos(checkTower)
        if not checkPos then return false end

        for hash, attackState in pairs(towerAttackStates) do
                if hash == checkTower.Hash then continue end  -- Skip self
                if not attackState.isAttacking then continue end

                local otherPos = getTowerPos(attackState.tower)
                if otherPos and getDistance2D(checkPos, otherPos) <= range then
                        return true
                end
        end

        return false
end

-- ======== Enhanced targeting functions ========
local function getEnhancedTarget(pos, towerRange, towerType, ability)
        local options = {
                excludeAir = skipAirTowers[towerType] or false,
                excludeArrows = true
        }

        -- Get the actual range for this ability (may override tower range)
        local effectiveRange = getAbilityRange(ability, towerRange)

        -- NEW: Enhanced logic for splash abilities
        if ability then
                local isSplash, splashRadius = hasSplashDamage(ability)
                local isManualAim = requiresManualAiming(ability)
                
                -- If it's a splash ability or requires manual aiming, target farthest enemy
                if isSplash or isManualAim then
                        return getFarthestEnemyInRange(pos, effectiveRange, options)
                end
        end

        -- For regular towers (non-special), always use farthest enemy
        if not directionalTowerTypes[towerType] then
                return getFarthestEnemyInRange(pos, effectiveRange, options)
        else
                -- For special towers, use nearest enemy to preserve original behavior
                return getNearestEnemyInRange(pos, effectiveRange, options)
        end
end

local function findTarget(pos, range, options)
        options = options or {}
        local mode = options.mode or "nearest"
        local excludeAir = options.excludeAir or false
        local excludeArrows = options.excludeArrows or false
        local usedEnemies = options.usedEnemies
        local markUsed = options.markUsed or false

        local candidates = {}
        for _, enemy in ipairs(getEnemies()) do
                if not enemy.GetPosition then continue end
                if excludeArrows and enemy.Type == "Arrow" then continue end
                if excludeAir and enemy.IsAirUnit then continue end

                local ePos = enemy:GetPosition()
                if getDistance2D(ePos, pos) > range then continue end

                if usedEnemies then
                        local id = tostring(enemy)
                        if usedEnemies[id] then continue end
                end

                table.insert(candidates, enemy)
        end

        if #candidates == 0 then return nil end

        local chosen = nil
        if mode == "nearest" then
                chosen = candidates[1]
        elseif mode == "maxhp" then
                local maxHP = -1
                for _, enemy in ipairs(candidates) do
                        if enemy.HealthHandler then
                                local hp = enemy.HealthHandler:GetMaxHealth()
                                if hp > maxHP then
                                        maxHP = hp
                                        chosen = enemy
                                end
                        end
                end
        elseif mode == "random_weighted" then
                table.sort(candidates, function(a, b)
                        local hpA = a.HealthHandler and a.HealthHandler:GetMaxHealth() or 0
                        local hpB = b.HealthHandler and b.HealthHandler:GetMaxHealth() or 0
                        return hpA > hpB
                end)
                if math.random(1, 10) <= 3 then
                        chosen = candidates[1]
                else
                        chosen = candidates[math.random(1, #candidates)]
                end
        end

        if chosen and markUsed and usedEnemies then
                usedEnemies[tostring(chosen)] = true
        end

        return chosen and chosen:GetPosition() or nil
end

-- ======== Specialized targeting functions ========
local function getMobsterTarget(tower, hash, path)
        local pos = getTowerPos(tower)
        local range = getRange(tower)

        mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}
        local usedEnemies = (path == 2) and mobsterUsedEnemies[hash] or nil

        return findTarget(pos, range, {
                mode = "maxhp",
                excludeAir = true,
                excludeArrows = true,
                usedEnemies = usedEnemies,
                markUsed = (path == 2)
        })
end

local function getCommanderTarget()
        local candidates = {}
        for _, e in ipairs(getEnemies()) do
                if not e.IsAirUnit and e.Type ~= "Arrow" then 
                        table.insert(candidates, e) 
                end
        end

        if #candidates == 0 then return nil end

        table.sort(candidates, function(a, b)
                local hpA = a.HealthHandler and a.HealthHandler:GetMaxHealth() or 0
                local hpB = b.HealthHandler and b.HealthHandler:GetMaxHealth() or 0
                return hpA > hpB
        end)

        local chosen
        if math.random(1, 10) <= 3 then
                chosen = candidates[1]
        else
                chosen = candidates[math.random(1, #candidates)]
        end

        return chosen and chosen:GetPosition() or nil
end

local function getBestMedicTarget(medicTower, ownedTowers)
        local medicPos = getTowerPos(medicTower)
        local medicRange = getRange(medicTower)
        local bestHash, bestDPS = nil, -1

        for hash, tower in pairs(ownedTowers) do
                if tower == medicTower then continue end
                if canReceiveBuff(tower) and not isBuffedByMedic(tower) then
                        local towerPos = getTowerPos(tower)
                        if towerPos and getDistance2D(towerPos, medicPos) <= medicRange then
                                local dps = getDPS(tower)
                                if dps > bestDPS then
                                        bestDPS = dps
                                        bestHash = hash
                                end
                        end
                end
        end
        return bestHash
end

local function SendSkill(hash, index, pos, targetHash)
        if useFireServer then
                TowerUseAbilityRequest:FireServer(hash, index, pos, targetHash)
        else
                TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
        end
end

-- ======== ENHANCED MAIN LOOP ========
RunService.Heartbeat:Connect(function()
        local now = tick()
        local ownedTowers = TowerClass.GetTowers() or {}

        -- Update tower attack states for support tower logic
        updateTowerAttackStates()

        for hash, tower in pairs(ownedTowers) do
                if not tower or not tower.AbilityHandler then continue end

                -- Enhanced Medic logic with attack state checking
                if tower.Type == "Medic" then
                        local _, p2 = GetCurrentUpgradeLevels(tower)
                        if p2 >= 4 then
                                if medicLastUsedTime[hash] and now - medicLastUsedTime[hash] < medicDelay then continue end

                                local medicRange = getRange(tower)
                                -- Only use skill if there are attacking towers in range
                                if hasAttackingTowersInRange(tower, medicRange) then
                                        for index = 1, 3 do
                                                local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                                                if not isCooldownReady(hash, index, ability) then continue end
                                                local targetHash = getBestMedicTarget(tower, ownedTowers)
                                                if targetHash then
                                                        SendSkill(hash, index, nil, targetHash)
                                                        medicLastUsedTime[hash] = now
                                                        break
                                                end
                                        end
                                end
                        end
                        continue
                end

                if skipTowerTypes[tower.Type] then continue end

                local delay = fastTowers[tower.Type] and 0.1 or 0.2
                if lastUsedTime[hash] and now - lastUsedTime[hash] < delay then continue end
                lastUsedTime[hash] = now

                local p1, p2 = GetCurrentUpgradeLevels(tower)
                local pos = getTowerPos(tower)
                local range = getRange(tower)

                for index = 1, 3 do
                        local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                        if not isCooldownReady(hash, index, ability) then continue end

                        local targetPos = nil
                        local allowUse = true
                        local hasSkillRange = false

                        -- Check if ability has range (from ability config)
                        if ability and ability.Config then
                                hasSkillRange = ability.Config.Range ~= nil and ability.Config.Range > 0
                        end

                        -- Enhanced Jet Trooper logic (skip skill 1, only use skill 2)
                        if tower.Type == "Jet Trooper" then
                                if index == 1 then
                                        allowUse = false  -- Always skip skill 1
                                elseif index == 2 then
                                        allowUse = true   -- Only use skill 2
                                else
                                        allowUse = false  -- Skip any other skills
                                end
                        end

                        -- Enhanced Ghost logic
                        if tower.Type == "Ghost" then
                                if p2 > 2 then
                                        allowUse = false
                                        break
                                else
                                        targetPos = findTarget(pos, math.huge, {
                                                mode = "maxhp",
                                                excludeArrows = true,
                                                excludeAir = false
                                        })
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                        break
                                end
                        end

                        -- Enhanced Toxicnator logic
                        if tower.Type == "Toxicnator" then
                                targetPos = findTarget(pos, range, {
                                        mode = "maxhp",
                                        excludeArrows = false,
                                        excludeAir = false
                                })
                                if targetPos then SendSkill(hash, index, targetPos) end
                                break
                        end

                        -- NEW: Flame Trooper logic
                        if tower.Type == "Flame Trooper" then
                                targetPos = getEnhancedTarget(pos, 9.5, tower.Type, ability)
                                if targetPos then SendSkill(hash, index, targetPos) end
                                break -- Skip general logic
                        end

                        -- Enhanced Ice Breaker logic
                        if tower.Type == "Ice Breaker" then
                                if index == 1 then
                                        targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                elseif index == 2 then
                                        targetPos = getEnhancedTarget(pos, 8, tower.Type, ability)
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                end
                                break -- Skip general logic
                        end

                        -- Enhanced Slammer logic
                        if tower.Type == "Slammer" then
                                local enemyInRange = getEnhancedTarget(pos, range, tower.Type, ability)
                                if enemyInRange then
                                        SendSkill(hash, index, enemyInRange)
                                end
                                break -- Skip general logic
                        end

                        -- Enhanced John logic
                        if tower.Type == "John" then
                                if p1 >= 5 then
                                        targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                                else
                                        targetPos = getEnhancedTarget(pos, 4.5, tower.Type, ability)
                                end
                                if targetPos then SendSkill(hash, index, targetPos) end
                                break -- Skip general logic
                        end

                        -- Enhanced Mobster logic
                        if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                                if p2 >= 3 and p2 <= 5 then
                                        targetPos = getMobsterTarget(tower, hash, 2)
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                elseif p1 >= 4 and p1 <= 5 then
                                        targetPos = getMobsterTarget(tower, hash, 1)
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                end
                                break -- Skip general logic
                        end

                        -- Enhanced Commander logic (skill 3 only)
                        if tower.Type == "Commander" and index == 3 then
                                targetPos = getCommanderTarget()
                                if targetPos then SendSkill(hash, index, targetPos) end
                                break -- Skip general logic
                        end

                        -- MODIFIED: EDJ logic (skill 1 only) - Removed enemy range check
                        if tower.Type == "EDJ" and index == 1 then
                                local edjRange = getRange(tower)
                                if hasAttackingTowersInRange(tower, edjRange) then
                                        SendSkill(hash, index)
                                end
                                break -- Skip general logic
                        end

                        -- MODIFIED: Commander skill 1 logic - Removed enemy range check
                        if tower.Type == "Commander" and index == 1 then
                                local commanderRange = getRange(tower)
                                if hasAttackingTowersInRange(tower, commanderRange) then
                                        SendSkill(hash, index)
                                end
                                -- Continue to check other skills (don't break)
                        end

                        -- General targeting for directional towers
                        local directional = directionalTowerTypes[tower.Type]
                        local sendWithPos = typeof(directional) == "table" and directional.onlyAbilityIndex == index or directional == true
                        
                        -- NEW: Also check if ability requires manual aiming (needs pos)
                        if ability and requiresManualAiming(ability) then
                                sendWithPos = true
                        end

                        if not targetPos and sendWithPos and allowUse then
                                -- NEW: Use enhanced targeting system
                                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                                if not targetPos then allowUse = false end
                        end

                        -- For non-directional regular towers, ensure they target farthest enemy
                        if not sendWithPos and not directional and allowUse then
                                local hasEnemies = getFarthestEnemyInRange(pos, range, {
                                        excludeAir = skipAirTowers[tower.Type] or false,
                                        excludeArrows = true
                                })
                                if not hasEnemies then allowUse = false end
                        end

                        -- Execute skill if conditions are met
                        if allowUse then
                                if sendWithPos and targetPos then
                                        SendSkill(hash, index, targetPos)
                                elseif not sendWithPos then
                                        SendSkill(hash, index)
                                end
                        end
                end
        end
end)