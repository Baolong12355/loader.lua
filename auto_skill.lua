local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer:IsLoaded() and Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local TowerAttack = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerAttack")

local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local TowerUtilities = require(Common:WaitForChild("TowerUtilities"))

-- Thread identity management (Nếu bạn đang sử dụng environment hỗ trợ)
local function setThreadIdentity(identity)
    if setthreadidentity then
        setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then
        syn.set_thread_identity(identity)
    end
end

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
if globalEnv.TDX_Config.UseThreadedRemotes == nil then
    globalEnv.TDX_Config.UseThreadedRemotes = true
end

-- ======== Configs ========
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

local skipMedicBuffTowers = {
    ["Refractor"] = true
}

-- ======== Tracking variables ========
local mobsterUsedEnemies = {}
local prevCooldown = {}
local medicLastUsedTime = {}
local medicDelay = 0.5

-- [SỬA ĐỔI] Thêm delay cho kỹ năng liên tiếp
local lastSkillUseTime = 0
local skillDelay = 0.05 

-- ======== Core utility functions ========
local function getDistance2D(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function getTowerPos(tower)
    if not tower then return nil end
    local success, result = pcall(function() return tower:GetPosition() end)
    return success and result or nil
end

local function getRange(tower)
    if not tower then return 0 end
    local success, result = pcall(function() return tower:GetCurrentRange() end)
    return success and typeof(result) == "number" and result or 0
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
    local success, result = pcall(function()
        local levelStats = tower.LevelHandler:GetLevelStats()
        local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
        return TowerUtilities.CalculateDPS(levelStats, buffStats)
    end)
    return success and typeof(result) == "number" and result or 0
end

local function isBuffedByMedic(tower)
    if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then return false end
    for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
        local buffName = tostring(buff.Name or "")
        if buffName:match("^MedicKritz") then return true end
    end
    return false
end

local function canReceiveBuff(tower)
    if not tower or tower.NoBuffs then return false end
    if skipMedicBuffTowers[tower.Type] then return false end
    return true
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

local function getEnemyPathDistance(enemy)
    if not enemy then return 0 end
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
    if enemy.PathIndex then return enemy.PathIndex * 10 end
    return 0
end

local function getMobsterTargetPosition(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false
    local usedEnemies = options.usedEnemies
    local markUsed = options.markUsed or false
    
    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end
        
        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) > range then continue end
        
        if usedEnemies and usedEnemies[tostring(enemy)] then continue end

        table.insert(candidates, {
            enemy = enemy,
            maxHP = enemy.HealthHandler and enemy.HealthHandler:GetMaxHealth() or 0,
            pathDistance = getEnemyPathDistance(enemy)
        })
    end

    if #candidates == 0 then return nil end

    -- [SỬA ĐỔI] Logic sắp xếp theo yêu cầu:
    -- 1. Ưu tiên Max HP cao nhất (a.maxHP > b.maxHP)
    -- 2. Nếu Max HP bằng nhau, ưu tiên pathDistance xa nhất (a.pathDistance > b.pathDistance)
    table.sort(candidates, function(a, b)
        if a.maxHP ~= b.maxHP then
            return a.maxHP > b.maxHP 
        else
            return a.pathDistance > b.pathDistance 
        end
    end)

    local chosen = candidates[1].enemy

    if markUsed and usedEnemies and chosen then
         usedEnemies[tostring(chosen)] = true
    end
    
    return chosen and chosen:GetPosition() or nil
end

local function getFarthestEnemyNoRange(options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        table.insert(candidates, {
            enemy = enemy,
            pathDistance = getEnemyPathDistance(enemy)
        })
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        return a.pathDistance > b.pathDistance
    end)

    return candidates[1].enemy:GetPosition()
end

local function getFarthestEnemyInRange(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
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

local function getNearestEnemyInRange(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
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

    table.sort(candidates, function(a, b)
        return a.pathDistance > b.pathDistance
    end)

    return candidates[1].position
}

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
    if config.ManualAimInfiniteRange == true then return math.huge end
    if config.ManualAimCustomRange and config.ManualAimCustomRange > 0 then return config.ManualAimCustomRange end
    if config.Range and config.Range > 0 then return config.Range end
    if config.CustomQueryData and config.CustomQueryData.Range then return config.CustomQueryData.Range end
    return defaultRange
end

local function requiresManualAiming(ability)
    if not ability or not ability.Config then return false end
    return ability.Config.IsManualAimAtGround == true or ability.Config.IsManualAimAtPath == true
end

local function getEnhancedTarget(pos, towerRange, towerType, ability)
    local options = { excludeAir = skipAirTowers[towerType] or false }
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
        return getNearestEnemyInRange(pos, effectiveRange, options)
    end
end

local function getMobsterTarget(tower, hash, path)
    local pos = getTowerPos(tower)
    local range = getRange(tower)
    
    local options = { excludeAir = true }

    if path == 2 then
        mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}
        options.usedEnemies = mobsterUsedEnemies[hash]
        options.markUsed = true
    end

    local target = getMobsterTargetPosition(pos, range, options)
    
    if path == 2 and not target then
        mobsterUsedEnemies[hash] = nil
    end

    return target
}

local function getCommanderTarget()
    local candidates = {}
    for _, e in ipairs(getEnemies()) do
        if not e.IsAirUnit then 
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
}

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
}

local function SendSkill(hash, index, pos, targetHash)
    if globalEnv.TDX_Config.UseThreadedRemotes then
        task.spawn(function()
            setThreadIdentity(2)
            pcall(function()
                TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
            end)
        end)
    else
        pcall(function()
            TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
        end)
    end
}

-- ======== Tower Attack Event Handler ========
local function handleTowerAttack(attackData)
    local ownedTowers = TowerClass.GetTowers() or {}

    for _, data in ipairs(attackData) do
        local attackingTowerHash = data.X
        local targetHash = data.Y

        local attackingTower = ownedTowers[attackingTowerHash]
        if not attackingTower then continue end

        task.spawn(function()
            setThreadIdentity(2)

            for hash, tower in pairs(ownedTowers) do
                if hash == attackingTowerHash then continue end

                local towerPos = getTowerPos(tower)
                local attackingPos = getTowerPos(attackingTower)
                if not towerPos or not attackingPos then continue end

                local distance = getDistance2D(towerPos, attackingPos)
                local towerRange = getRange(tower)

                if distance <= towerRange then
                    if tower.Type == "EDJ" or tower.Type == "Commander" then
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
}

TowerAttack.OnClientEvent:Connect(handleTowerAttack)

-- ======== MAIN LOOP ========
RunService.Heartbeat:Connect(function()
    local ownedTowers = TowerClass.GetTowers() or {}
    local now = tick()

    -- [SỬA ĐỔI] Kiểm tra delay trước khi bắt đầu vòng lặp chính
    if now - lastSkillUseTime < skillDelay then
        return 
    end

    local skillUsedInThisFrame = false

    for hash, tower in pairs(ownedTowers) do
        if skillUsedInThisFrame then break end

        if not tower or not tower.AbilityHandler then continue end
        if skipTowerTypes[tower.Type] then continue end

        local p1, p2 = GetCurrentUpgradeLevels(tower)
        local pos = getTowerPos(tower)
        local range = getRange(tower)

        for index = 1, 3 do
            if skillUsedInThisFrame then break end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
            if not isCooldownReady(hash, index, ability) then continue end

            local targetPos = nil
            local allowUse = true

            -- Jet Trooper: chỉ dùng skill 2
            if tower.Type == "Jet Trooper" then
                if index ~= 2 then allowUse = false end
            end

            -- Ghost: lấy kẻ địch xa nhất không giới hạn range
            if tower.Type == "Ghost" then
                if p2 > 2 then
                    allowUse = false
                    break
                else
                    targetPos = getFarthestEnemyNoRange({ excludeAir = false })
                    if targetPos then 
                        SendSkill(hash, index, targetPos)
                        skillUsedInThisFrame = true
                    end
                    break
                end
            end

            -- Toxicnator: dùng range của tower
            if tower.Type == "Toxicnator" then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillUsedInThisFrame = true
                end
                break
            end

            -- Flame Trooper: dùng range tùy chỉnh 9.5
            if tower.Type == "Flame Trooper" then
                local customRange = range
                if ability and hasSplashDamage(ability) then
                    customRange = 9.5 
                end
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillUsedInThisFrame = true
                end
                break
            end

            -- Ice Breaker: skill 1 dùng range, skill 2 dùng 8
            if tower.Type == "Ice Breaker" then
                local customRange = index == 2 and 8 or range
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillUsedInThisFrame = true
                end
                break
            end

            -- Slammer: dùng range của tower
            if tower.Type == "Slammer" then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillUsedInThisFrame = true
                end
                break
            end

            -- John: dùng range của tower, hoặc 4.5 nếu p1 < 5
            if tower.Type == "John" then
                local customRange = p1 >= 5 and range or 4.5
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillUsedInThisFrame = true
                end
                break
            end

            -- Mobster & Golden Mobster
            if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                if (p2 >= 3 and p2 <= 5) or (p1 >= 4 and p1 <= 5) then
                    targetPos = getMobsterTarget(tower, hash, p2 >= 3 and 2 or 1)
                    if targetPos then 
                        SendSkill(hash, index, targetPos)
                        skillUsedInThisFrame = true
                    end
                end
                break
            end

            -- Commander: chỉ skill 3
            if tower.Type == "Commander" then
                if index == 3 then
                    targetPos = getCommanderTarget()
                    if targetPos then 
                        SendSkill(hash, index, targetPos)
                        skillUsedInThisFrame = true
                    end
                end
                break
            end

            -- General targeting cho directional towers
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
                    excludeAir = skipAirTowers[tower.Type] or false
                })
                if not hasEnemies then allowUse = false end
            end

            if allowUse then
                if sendWithPos and targetPos then
                    SendSkill(hash, index, targetPos)
                    skillUsedInThisFrame = true
                elseif not sendWithPos then
                    SendSkill(hash, index)
                    skillUsedInThisFrame = true
                end
            end
        end
    end
    
    -- [SỬA ĐỔI] Cập nhật thời gian sử dụng kỹ năng cuối cùng
    if skillUsedInThisFrame then
        lastSkillUseTime = now
    end
end)