local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local TowerAttack = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerAttack")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- Thread identity management
local function setThreadIdentity(identity)
    if setthreadidentity then
        setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then
        syn.set_thread_identity(identity)
    end
end

-- Global config for threaded remotes
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
if globalEnv.TDX_Config.UseThreadedRemotes == nil then
    globalEnv.TDX_Config.UseThreadedRemotes = true -- Default to true
end

-- Threaded remote call wrapper
local function SafeRemoteCall(remoteType, remote, ...)
    local args = {...}
    if globalEnv.TDX_Config.UseThreadedRemotes then
        return task.spawn(function()
            setThreadIdentity(2) -- Elevated identity for priority
            
            if remoteType == "FireServer" then
                pcall(function()
                    remote:FireServer(unpack(args))
                end)
            elseif remoteType == "InvokeServer" then
                local success, result = pcall(function()
                    return remote:InvokeServer(unpack(args))
                end)
                return success and result or nil
            end
        end)
    else
        -- Original non-threaded approach
        if remoteType == "FireServer" then
            pcall(function()
                remote:FireServer(unpack(args))
            end)
        elseif remoteType == "InvokeServer" then
            local success, result = pcall(function()
                return remote:InvokeServer(unpack(args))
            end)
            return success and result or nil
        end
    end
end

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
        ["Flame Trooper"] = true
}

local skipTowerTypes = {
        ["Helicopter"] = true,
        ["Cryo Helicopter"] = true,
        ["Medic"] = true,
        ["Combat Drone"] = true,
        ["Machine Gunner"] = true
}

local skipAirTowers = {
        ["Ice Breaker"] = true,
        ["John"] = true,
        ["Slammer"] = true,
        ["Mobster"] = true,
        ["Golden Mobster"] = true
}

-- Tracking variables
local mobsterUsedEnemies = {}
local prevCooldown = {}
local medicLastUsedTime = {}
local medicDelay = 0.5

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

-- Function to get enemy's progress along their path (UPDATED)
local function getEnemyPathDistance(enemy)
        if not enemy then return 0 end
        
        -- Try multiple methods to get path progress
        if enemy.MovementHandler then
                if enemy.MovementHandler.GetPathPercentage then
                        local success, percentage = pcall(function() 
                                return enemy.MovementHandler:GetPathPercentage() 
                        end)
                        if success and percentage then return percentage end
                end
                
                if enemy.MovementHandler.PathPercentage then
                        return enemy.MovementHandler.PathPercentage or 0
                end
                
                if enemy.MovementHandler.GetCurrentNode then
                        local success, node = pcall(function() 
                                return enemy.MovementHandler:GetCurrentNode() 
                        end)
                        if success and node and node.GetPercentageAlongPath then
                                local success2, percentage = pcall(function()
                                        return node:GetPercentageAlongPath(1)
                                end)
                                if success2 and percentage then return percentage end
                        end
                end
                
                if enemy.MovementHandler.DistanceTraveled then
                        return enemy.MovementHandler.DistanceTraveled
                end
        end
        
        -- Fallback using path index
        if enemy.PathIndex then
                return enemy.PathIndex * 10
        end
        
        return 0
end

-- UNCHANGED: Keep original logic for getFarthestEnemyInRange
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

        table.sort(candidates, function(a, b)
                return a.pathDistance > b.pathDistance
        end)

        return candidates[1].enemy:GetPosition()
end

-- UPDATED: Now prioritizes furthest enemy in range for directional towers only
local function getNearestEnemyInRange(pos, range, options)
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
                                position = ePos,
                                pathDistance = getEnemyPathDistance(enemy)
                        })
                end
        end

        if #candidates == 0 then return nil end

        -- Sort by path distance (furthest first) - Only for directional towers
        table.sort(candidates, function(a, b)
                return a.pathDistance > b.pathDistance
        end)

        return candidates[1].position
end

local function hasSplashDamage(ability)
        if not ability or not ability.Config then return false end

        if ability.Config.ProjectileHitData then
                local hitData = ability.Config.ProjectileHitData
                if hitData.IsSplash and hitData.SplashRadius and hitData.SplashRadius > 0 then
                        return true, hitData.SplashRadius
                end
        end

        if ability.Config.HasRadiusEffect and ability.Config.EffectRadius and ability.Config.EffectRadius > 0 then
                return true, ability.Config.EffectRadius
        end

        return false, 0
end

local function getAbilityRange(ability, defaultRange)
        if not ability or not ability.Config then return defaultRange end

        local config = ability.Config

        if config.ManualAimInfiniteRange == true then
                return math.huge
        end

        if config.ManualAimCustomRange and config.ManualAimCustomRange > 0 then
                return config.ManualAimCustomRange
        end

        if config.Range and config.Range > 0 then
                return config.Range
        end

        if config.CustomQueryData and config.CustomQueryData.Range then
                return config.CustomQueryData.Range
        end

        return defaultRange
end

local function requiresManualAiming(ability)
        if not ability or not ability.Config then return false end

        return ability.Config.IsManualAimAtGround == true or 
               ability.Config.IsManualAimAtPath == true
end

local function getEnhancedTarget(pos, towerRange, towerType, ability)
        local options = {
                excludeAir = skipAirTowers[towerType] or false,
                excludeArrows = true
        }

        local effectiveRange = getAbilityRange(ability, towerRange)

        if ability then
                local isSplash, splashRadius = hasSplashDamage(ability)
                local isManualAim = requiresManualAiming(ability)

                if isSplash or isManualAim then
                        return getFarthestEnemyInRange(pos, effectiveRange, options)
                end
        end

        if not directionalTowerTypes[towerType] then
                return getFarthestEnemyInRange(pos, effectiveRange, options)
        else
                return getNearestEnemyInRange(pos, effectiveRange, options) -- This now also targets furthest
        end
end

-- UNCHANGED: Special targeting functions that use specific modes (maxhp, etc.) remain the same
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

-- UNCHANGED: Mobster targeting uses specific maxhp mode
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

-- UNCHANGED: Commander targeting uses specific maxhp mode
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

-- Enhanced SendSkill function with threaded remotes
local function SendSkill(hash, index, pos, targetHash)
        if useFireServer then
                SafeRemoteCall("FireServer", TowerUseAbilityRequest, hash, index, pos, targetHash)
        else
                SafeRemoteCall("InvokeServer", TowerUseAbilityRequest, hash, index, pos, targetHash)
        end
end

-- ======== Enhanced Tower Attack Event Handler với threaded support ========
local function handleTowerAttack(attackData)
        local ownedTowers = TowerClass.GetTowers() or {}

        for _, data in ipairs(attackData) do
                local attackingTowerHash = data.X  -- Hash of tower that just attacked
                local targetHash = data.Y  -- Target hash (if needed)

                local attackingTower = ownedTowers[attackingTowerHash]
                if not attackingTower then continue end

                -- Spawn in separate thread for non-blocking execution
                task.spawn(function()
                        setThreadIdentity(2) -- Elevated priority for support actions
                        
                        -- Check for support towers in range that can buff the attacking tower
                        for hash, tower in pairs(ownedTowers) do
                                if hash == attackingTowerHash then continue end -- Skip self

                                local towerPos = getTowerPos(tower)
                                local attackingPos = getTowerPos(attackingTower)
                                if not towerPos or not attackingPos then continue end

                                local distance = getDistance2D(towerPos, attackingPos)
                                local towerRange = getRange(tower)

                                -- Check if support tower is in range of attacking tower
                                if distance <= towerRange then
                                        -- Handle different support tower types
                                        if tower.Type == "EDJ" then
                                                local ability = tower.AbilityHandler:GetAbilityFromIndex(1)
                                                if isCooldownReady(hash, 1, ability) then
                                                        SendSkill(hash, 1)
                                                end
                                        elseif tower.Type == "Commander" then
                                                local ability = tower.AbilityHandler:GetAbilityFromIndex(1)
                                                if isCooldownReady(hash, 1, ability) then
                                                        SendSkill(hash, 1)
                                                end
                                        elseif tower.Type == "Medic" then
                                                local _, p2 = GetCurrentUpgradeLevels(tower)
                                                if p2 >= 4 then
                                                        local now = tick()
                                                        if not medicLastUsedTime[hash] or now - medicLastUsedTime[hash] >= medicDelay then
                                                                for index = 1, 3 do
                                                                        local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                                                                        if isCooldownReady(hash, index, ability) then
                                                                                local targetHash = getBestMedicTarget(tower, ownedTowers)
                                                                                if targetHash then
                                                                                        SendSkill(hash, index, nil, targetHash)
                                                                                        medicLastUsedTime[hash] = now
                                                                                        break
                                                                                end
                                                                        end
                                                                end
                                                        end
                                                end
                                        end
                                end
                        end
                end)
        end
end

-- Listen to TowerAttack event
TowerAttack.OnClientEvent:Connect(handleTowerAttack)

-- ======== MAIN LOOP (for regular towers) với threaded processing ========
RunService.Heartbeat:Connect(function()
        local ownedTowers = TowerClass.GetTowers() or {}

        -- Process towers in batches to prevent frame drops
        for hash, tower in pairs(ownedTowers) do
                if not tower or not tower.AbilityHandler then continue end
                if skipTowerTypes[tower.Type] then continue end

                -- Spawn individual tower processing in separate threads for better performance
                task.spawn(function()
                        setThreadIdentity(2) -- Elevated priority for skill processing
                        
                        local p1, p2 = GetCurrentUpgradeLevels(tower)
                        local pos = getTowerPos(tower)
                        local range = getRange(tower)

                        for index = 1, 3 do
                                local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                                if not isCooldownReady(hash, index, ability) then continue end

                                local targetPos = nil
                                local allowUse = true

                                -- Enhanced Jet Trooper logic
                                if tower.Type == "Jet Trooper" then
                                        if index == 1 then
                                                allowUse = false
                                        elseif index == 2 then
                                                allowUse = true
                                        else
                                                allowUse = false
                                        end
                                end

                                -- Enhanced Ghost logic - UNCHANGED (uses maxhp mode)
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

                                -- Enhanced Toxicnator logic - UNCHANGED (uses maxhp mode)
                                if tower.Type == "Toxicnator" then
                                        targetPos = findTarget(pos, range, {
                                                mode = "maxhp",
                                                excludeArrows = false,
                                                excludeAir = false
                                        })
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                        break
                                end

                                -- Flame Trooper logic - UPDATED (uses getEnhancedTarget which now targets furthest)
                                if tower.Type == "Flame Trooper" then
                                        targetPos = getEnhancedTarget(pos, 9.5, tower.Type, ability)
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                        break
                                end

                                -- Enhanced Ice Breaker logic - UPDATED (uses getEnhancedTarget)
                                if tower.Type == "Ice Breaker" then
                                        if index == 1 then
                                                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                                                if targetPos then SendSkill(hash, index, targetPos) end
                                        elseif index == 2 then
                                                targetPos = getEnhancedTarget(pos, 8, tower.Type, ability)
                                                if targetPos then SendSkill(hash, index, targetPos) end
                                        end
                                        break
                                end

                                -- Enhanced Slammer logic - UPDATED (uses getEnhancedTarget)
                                if tower.Type == "Slammer" then
                                        local enemyInRange = getEnhancedTarget(pos, range, tower.Type, ability)
                                        if enemyInRange then
                                                SendSkill(hash, index, enemyInRange)
                                        end
                                        break
                                end

                                -- Enhanced John logic - UPDATED (uses getEnhancedTarget)
                                if tower.Type == "John" then
                                        if p1 >= 5 then
                                                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                                        else
                                                targetPos = getEnhancedTarget(pos, 4.5, tower.Type, ability)
                                        end
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                        break
                                end

                                -- Enhanced Mobster logic - UNCHANGED (uses getMobsterTarget with maxhp mode)
                                if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                                        if p2 >= 3 and p2 <= 5 then
                                                targetPos = getMobsterTarget(tower, hash, 2)
                                                if targetPos then SendSkill(hash, index, targetPos) end
                                        elseif p1 >= 4 and p1 <= 5 then
                                                targetPos = getMobsterTarget(tower, hash, 1)
                                                if targetPos then SendSkill(hash, index, targetPos) end
                                        end
                                        break
                                end

                                -- Enhanced Commander logic (skill 3 only) - UNCHANGED (uses getCommanderTarget with maxhp)
                                if tower.Type == "Commander" and index == 3 then
                                        targetPos = getCommanderTarget()
                                        if targetPos then SendSkill(hash, index, targetPos) end
                                        break
                                end

                                -- General targeting for directional towers - UPDATED (uses getEnhancedTarget)
                                local directional = directionalTowerTypes[tower.Type]
                                local sendWithPos = typeof(directional) == "table" and directional.onlyAbilityIndex == index or directional == true

                                if ability and requiresManualAiming(ability) then
                                        sendWithPos = true
                                end

                                if not targetPos and sendWithPos and allowUse then
                                        targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                                        if not targetPos then allowUse = false end
                                end

                                if not sendWithPos and not directional and allowUse then
                                        local hasEnemies = getFarthestEnemyInRange(pos, range, {
                                                excludeAir = skipAirTowers[tower.Type] or false,
                                                excludeArrows = true
                                        })
                                        if not hasEnemies then allowUse = false end
                                end

                                if allowUse then
                                        if sendWithPos and targetPos then
                                                SendSkill(hash, index, targetPos)
                                        elseif not sendWithPos then
                                                SendSkill(hash, index)
                                        end
                                end
                        end
                end)
        end
end)