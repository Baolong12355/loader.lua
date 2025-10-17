local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local GameModules = {}
local function LoadGameModules()
    if next(GameModules) then return end
    pcall(function()
        local ClientGameClass = PlayerScripts.Client:WaitForChild("GameClass")
        local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
        GameModules.TowerClass = require(ClientGameClass:WaitForChild("TowerClass"))
        GameModules.EnemyClass = require(ClientGameClass:WaitForChild("EnemyClass"))
        GameModules.TowerUtilities = require(Common:WaitForChild("TowerUtilities"))
        GameModules.AbilityHotbarHandler = require(
            PlayerScripts.Client:WaitForChild("UserInterfaceHandler"):WaitForChild("AbilityHotbarHandler")
        )
    end)
end
LoadGameModules()

local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local TowerAttack = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerAttack")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

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

local function SafeRemoteCall(remoteType, remote, ...)
    local args = {...}
    if globalEnv.TDX_Config.UseThreadedRemotes then
        return task.spawn(function()
            setThreadIdentity(2)
            if remoteType == "FireServer" then
                pcall(function() remote:FireServer(unpack(args)) end)
            elseif remoteType == "InvokeServer" then
                pcall(function() return remote:InvokeServer(unpack(args)) end)
            end
        end)
    else
        if remoteType == "FireServer" then
            pcall(function() remote:FireServer(unpack(args)) end)
        elseif remoteType == "InvokeServer" then
            pcall(function() return remote:InvokeServer(unpack(args)) end)
        end
    end
end

local directionalTowerTypes = {["Commander"] = { onlyAbilityIndex = 3 }, ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true, ["Mobster"] = true, ["Golden Mobster"] = true, ["Artillery"] = true, ["Golden Mine Layer"] = true, ["Flame Trooper"] = true}
local skipTowerTypes = {["Helicopter"] = true, ["Cryo Helicopter"] = true, ["Combat Drone"] = true, ["Machine Gunner"] = true}
local skipAirTowers = {["Ice Breaker"] = true, ["John"] = true, ["Slammer"] = true, ["Mobster"] = true, ["Golden Mobster"] = true}

local mobsterUsedEnemies = {}
local medicLastUsedTime = {}
local medicDelay = 0.5

local skillsUsedThisFrame = 0
local maxSkillsPerFrame = 10 

local function getDistance2D(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function getTowerPos(tower)
    local ok, pos = pcall(function() return tower:GetPosition() end)
    if ok and pos then return pos end
    if tower and tower.Character and tower.Character.GetTorso and tower.Character:GetTorso() then return tower.Character:GetTorso().Position end
    return nil
end

local function getRange(tower)
    local ok, result = pcall(function() return tower:GetCurrentRange() end)
    if ok and typeof(result) == "number" then return result end
    return 0
end

local function GetCurrentUpgradeLevels(tower)
    local p1, p2 = 0, 0
    pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
    pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
    return p1, p2
end

local function getAccurateDPS(tower)
    if not tower or not GameModules.TowerUtilities then return 0 end
    local success, dps = pcall(function()
        local levelStats = tower.LevelHandler:GetLevelStats()
        local buffStats = tower.BuffHandler:GetStatMultipliers()
        return GameModules.TowerUtilities.CalculateDPS(levelStats, buffStats)
    end)
    return success and dps or 0
end

local function isBuffedByMedic(tower)
    if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then return false end
    for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
        if tostring(buff.Name or ""):match("^MedicKritz") then return true end
    end
    return false
end

local function canReceiveBuff(tower)
    return tower and not tower.NoBuffs
end

local function getEnemies()
    local result = {}
    if not GameModules.EnemyClass then return result end
    for _, e in pairs(GameModules.EnemyClass.GetEnemies()) do
        if e and e.IsAlive and not e.IsFakeEnemy then table.insert(result, e) end
    end
    return result
end

local function getEnemyPathDistance(enemy)
    if not enemy then return 0 end
    if enemy.MovementHandler and enemy.MovementHandler.PathPercentage then
        return enemy.MovementHandler.PathPercentage
    end
    return 0
end

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
            table.insert(candidates, {enemy = enemy, pathDistance = getEnemyPathDistance(enemy)})
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.pathDistance > b.pathDistance end)
    return candidates[1].enemy:GetPosition()
end

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
            table.insert(candidates, {enemy = enemy, position = ePos, pathDistance = getEnemyPathDistance(enemy)})
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.pathDistance > b.pathDistance end)
    return candidates[1].position
end

local function hasSplashDamage(ability)
    if not ability or not ability.Config then return false, 0 end
    if ability.Config.ProjectileHitData then
        local hitData = ability.Config.ProjectileHitData
        if hitData.IsSplash and hitData.SplashRadius and hitData.SplashRadius > 0 then return true, hitData.SplashRadius end
    end
    if ability.Config.HasRadiusEffect and ability.Config.EffectRadius and ability.Config.EffectRadius > 0 then return true, ability.Config.EffectRadius end
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
    local options = {excludeAir = skipAirTowers[towerType] or false, excludeArrows = true}
    local effectiveRange = getAbilityRange(ability, towerRange)
    if ability then
        local isSplash, _ = hasSplashDamage(ability)
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
        if usedEnemies and usedEnemies[tostring(enemy)] then continue end
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

-- UPDATE: Hàm mới chuyên dụng cho logic của Mobster Path 2
local function getBestMobsterTarget(pos, range, usedEnemies)
    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if enemy.GetPosition and not enemy.IsAirUnit and enemy.Type ~= "Arrow" then
            local ePos = enemy:GetPosition()
            if getDistance2D(ePos, pos) <= range and not usedEnemies[tostring(enemy)] then
                table.insert(candidates, enemy)
            end
        end
    end

    if #candidates == 0 then return nil end

    -- Sắp xếp theo: Máu tối đa (cao nhất) -> Quãng đường đi được (xa nhất)
    table.sort(candidates, function(a, b)
        local maxHpA = a.HealthHandler:GetMaxHealth() or 0
        local maxHpB = b.HealthHandler:GetMaxHealth() or 0
        if maxHpA ~= maxHpB then
            return maxHpA > maxHpB -- Ưu tiên 1: Máu tối đa
        else
            -- Ưu tiên 2: Quãng đường đi được
            local pathDistA = getEnemyPathDistance(a) or 0
            local pathDistB = getEnemyPathDistance(b) or 0
            return pathDistA > pathDistB
        end
    end)

    local chosen = candidates[1]
    if chosen then
        -- Đánh dấu kẻ địch đã được chọn để không nhắm lại
        usedEnemies[tostring(chosen)] = true
        return chosen:GetPosition()
    end
    return nil
end

local function getMobsterTarget(tower, hash, path)
    local pos = getTowerPos(tower)
    if not pos then return nil end
    local range = getRange(tower)
    mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}
    
    -- UPDATE: Gọi hàm mới cho Path 2
    if path == 2 then
        return getBestMobsterTarget(pos, range, mobsterUsedEnemies[hash])
    else 
        -- Giữ lại logic cũ cho Path 1
        return findTarget(pos, range, {mode = "maxhp", excludeAir = true, excludeArrows = true, usedEnemies = nil, markUsed = false})
    end
end

local function getCommanderTarget()
    local candidates = {}
    for _, e in ipairs(getEnemies()) do
        if not e.IsAirUnit and e.Type ~= "Arrow" then table.insert(candidates, e) end
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
    if not medicPos then return nil end
    local medicRange = getRange(medicTower)
    local bestHash, bestDPS = nil, -1
    for hash, tower in pairs(ownedTowers) do
        if tower == medicTower or tower.Type == "Refractor" then continue end
        if canReceiveBuff(tower) and not isBuffedByMedic(tower) then
            local towerPos = getTowerPos(tower)
            if towerPos and getDistance2D(towerPos, medicPos) <= medicRange then
                local dps = getAccurateDPS(tower)
                if dps > bestDPS then
                    bestDPS = dps
                    bestHash = hash
                end
            end
        end
    end
    return bestHash
end

local function canUseSkill()
    if skillsUsedThisFrame < maxSkillsPerFrame then
        skillsUsedThisFrame = skillsUsedThisFrame + 1
        return true
    end
    return false
end

local function SendSkill(hash, index, pos, targetHash)
    if not canUseSkill() then return end
    if useFireServer then
        SafeRemoteCall("FireServer", TowerUseAbilityRequest, hash, index, pos, targetHash)
    else
        SafeRemoteCall("InvokeServer", TowerUseAbilityRequest, hash, index, pos, targetHash)
    end
end

local function handleTowerAttack(attackData)
    if not GameModules.TowerClass then return end
    local ownedTowers = GameModules.TowerClass.GetTowers() or {}
    for _, data in ipairs(attackData) do
        local attackingTowerHash = data.X
        local attackingTower = ownedTowers[attackingTowerHash]
        if not attackingTower then continue end
        task.spawn(function()
            setThreadIdentity(2)
            for hash, tower in pairs(ownedTowers) do
                if hash == attackingTowerHash then continue end
                if skipTowerTypes[tower.Type] and tower.Type ~= "Medic" then continue end

                local towerPos = getTowerPos(tower)
                local attackingPos = getTowerPos(attackingTower)
                if not towerPos or not attackingPos then continue end
                
                local distance = getDistance2D(towerPos, attackingPos)
                local towerRange = getRange(tower)
                
                if distance <= towerRange then
                    local ability = tower.AbilityHandler:GetAbilityFromIndex(1)
                    if tower.Type == "EDJ" or tower.Type == "Commander" then
                        if ability and ability:CanUse() then
                            SendSkill(hash, 1)
                        end
                    elseif tower.Type == "Medic" then
                        local _, p2 = GetCurrentUpgradeLevels(tower)
                        if p2 >= 4 then
                            local now = tick()
                            if not medicLastUsedTime[hash] or now - medicLastUsedTime[hash] >= medicDelay then
                                for index = 1, 3 do
                                    local medicAbility = tower.AbilityHandler:GetAbilityFromIndex(index)
                                    if medicAbility and medicAbility:CanUse() then
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
TowerAttack.OnClientEvent:Connect(handleTowerAttack)

local function GetAllReadyAbilitiesFromHotbar()
    local readyAbilities = {}
    if not GameModules.AbilityHotbarHandler then
        LoadGameModules()
        return readyAbilities
    end
    
    local success, hotbarData = pcall(function()
        return debug.getupvalue(GameModules.AbilityHotbarHandler.Update, 3)
    end)
    
    if not success or not hotbarData then return readyAbilities end
    
    for _, slotData in pairs(hotbarData) do
        if type(slotData) == "table" then
            for _, groupData in pairs(slotData) do
                if type(groupData) == "table" and groupData.LevelToAbilityDataMap then
                    for _, levelData in pairs(groupData.LevelToAbilityDataMap) do
                        if levelData.AvailableCount and levelData.AvailableCount > 0 then
                            table.insert(readyAbilities, {
                                tower = levelData.ClosestTower,
                                ability = levelData.ClosestAbility,
                            })
                        end
                    end
                end
            end
        end
    end
    
    return readyAbilities
end

RunService.Heartbeat:Connect(function()
    if not GameModules.TowerClass or not GameModules.AbilityHotbarHandler then LoadGameModules(); return end
    
    skillsUsedThisFrame = 0
    
    task.spawn(function()
        setThreadIdentity(2)
        local hotbarAbilities = GetAllReadyAbilitiesFromHotbar()
        
        for _, data in ipairs(hotbarAbilities) do
            local tower = data.tower
            local ability = data.ability
            
            if not tower or not ability or skipTowerTypes[tower.Type] then continue end
            
            local pos = getTowerPos(tower)
            if not pos then continue end

            local hash = tower.Hash
            local index = ability.Index
            local range = getRange(tower)
            
            local targetPos = nil
            local allowUse = true

            local directional = directionalTowerTypes[tower.Type]
            local sendWithPos = (typeof(directional) == "table" and directional.onlyAbilityIndex == index) or (directional == true)
            if ability and requiresManualAiming(ability) then
                sendWithPos = true
            end

            if tower.Type == "Jet Trooper" then
                if index == 2 then SendSkill(hash, index) end
                continue
            elseif tower.Type == "Ghost" then
                local _, p2 = GetCurrentUpgradeLevels(tower)
                if p2 <= 2 then
                    targetPos = findTarget(pos, math.huge, {mode = "maxhp", excludeArrows = true, excludeAir = false})
                    if targetPos then SendSkill(hash, index, targetPos) end
                end
                continue
            elseif tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                local p1, p2 = GetCurrentUpgradeLevels(tower)
                if p2 >= 3 and p2 <= 5 then
                    targetPos = getMobsterTarget(tower, hash, 2)
                elseif p1 >= 4 and p1 <= 5 then
                    targetPos = getMobsterTarget(tower, hash, 1)
                end
                if targetPos then SendSkill(hash, index, targetPos) end
                continue
            elseif tower.Type == "Commander" and index == 3 then
                 targetPos = getCommanderTarget()
                 if targetPos then SendSkill(hash, index, targetPos) end
                 continue
            end
            
            if sendWithPos then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                if not targetPos then
                    allowUse = false
                end
            else 
                if not getFarthestEnemyInRange(pos, range, {excludeAir = skipAirTowers[tower.Type] or false, excludeArrows = true}) then
                    allowUse = false
                end
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
end)