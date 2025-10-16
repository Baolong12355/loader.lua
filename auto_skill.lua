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
local maxSkillsPerFrame = 10 -- Tăng giới hạn để phản ứng nhanh hơn

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

local function IsKritzed(tower)
    if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then return false end
    for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
        if buff.Name and string.match(buff.Name, "^MedicKritz") then return true end
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
    if enemy.MovementHandler and enemy.MovementHandler.PathPercentage then return enemy.MovementHandler.PathPercentage end
    return 0
end

local function getFarthestEnemyInRange(pos, range, options)
    options = options or {}
    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if (options.excludeArrows and enemy.Type == "Arrow") or (options.excludeAir and enemy.IsAirUnit) then continue end
        if getDistance2D(enemy:GetPosition(), pos) <= range then
            table.insert(candidates, {enemy = enemy, pathDistance = getEnemyPathDistance(enemy)})
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.pathDistance > b.pathDistance end)
    return candidates[1].enemy:GetPosition()
end

local function findTarget(pos, range, options)
    options = options or {}
    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if (options.excludeArrows and enemy.Type == "Arrow") or (options.excludeAir and enemy.IsAirUnit) then continue end
        if getDistance2D(enemy:GetPosition(), pos) > range then continue end
        if options.usedEnemies and options.usedEnemies[tostring(enemy)] then continue end
        table.insert(candidates, enemy)
    end
    if #candidates == 0 then return nil end
    local chosen = nil
    if options.mode == "maxhp" then
        local maxHP = -1
        for _, enemy in ipairs(candidates) do
            if enemy.HealthHandler then
                local hp = enemy.HealthHandler:GetMaxHealth()
                if hp > maxHP then maxHP = hp; chosen = enemy end
            end
        end
    else -- default to nearest
        chosen = candidates[1]
    end
    if chosen and options.markUsed and options.usedEnemies then
        options.usedEnemies[tostring(chosen)] = true
    end
    return chosen and chosen:GetPosition() or nil
end

local function getMobsterTarget(tower, hash, path)
    local pos, range = getTowerPos(tower), getRange(tower)
    if not pos then return nil end
    mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}
    local usedEnemies = (path == 2) and mobsterUsedEnemies[hash] or nil
    return findTarget(pos, range, {mode = "maxhp", excludeAir = true, excludeArrows = true, usedEnemies = usedEnemies, markUsed = (path == 2)})
end

local function getCommanderTarget()
    local candidates = {}
    for _, e in ipairs(getEnemies()) do
        if not e.IsAirUnit and e.Type ~= "Arrow" then table.insert(candidates, e) end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return (a.HealthHandler and a.HealthHandler:GetMaxHealth() or 0) > (b.HealthHandler and b.HealthHandler:GetMaxHealth() or 0) end)
    return candidates[1]:GetPosition()
end

local function getBestMedicTarget(medicTower, ownedTowers)
    local medicPos, medicRange = getTowerPos(medicTower), getRange(medicTower)
    if not medicPos then return nil end
    local bestHash, bestDPS = nil, -1
    for hash, tower in pairs(ownedTowers) do
        if tower ~= medicTower and tower.Type ~= "Refractor" and canReceiveBuff(tower) and not IsKritzed(tower) then
            local towerPos = getTowerPos(tower)
            if towerPos and getDistance2D(towerPos, medicPos) <= medicRange then
                local dps = getAccurateDPS(tower)
                if dps > bestDPS then bestDPS = dps; bestHash = hash end
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
        if not ownedTowers[attackingTowerHash] then continue end
        task.spawn(function()
            setThreadIdentity(2)
            for hash, tower in pairs(ownedTowers) do
                if hash == attackingTowerHash or skipTowerTypes[tower.Type] then continue end
                local towerPos, attackingPos = getTowerPos(tower), getTowerPos(ownedTowers[attackingTowerHash])
                if not towerPos or not attackingPos then continue end
                if getDistance2D(towerPos, attackingPos) <= getRange(tower) then
                    local ability = tower.AbilityHandler:GetAbilityFromIndex(1)
                    if (tower.Type == "EDJ" or tower.Type == "Commander") and ability and ability:CanUse() then
                        SendSkill(hash, 1)
                    elseif tower.Type == "Medic" then
                        local _, p2 = GetCurrentUpgradeLevels(tower)
                        if p2 >= 4 and (not medicLastUsedTime[hash] or tick() - medicLastUsedTime[hash] >= medicDelay) then
                            for index = 1, 3 do
                                local medicAbility = tower.AbilityHandler:GetAbilityFromIndex(index)
                                if medicAbility and medicAbility:CanUse() then
                                    local targetHash = getBestMedicTarget(tower, ownedTowers)
                                    if targetHash then SendSkill(hash, index, nil, targetHash); medicLastUsedTime[hash] = tick(); break end
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
    if not GameModules.AbilityHotbarHandler then LoadGameModules(); return readyAbilities end
    local success, hotbarData = pcall(function() return debug.getupvalue(GameModules.AbilityHotbarHandler.Update, 3) end)
    if not success or not hotbarData then return readyAbilities end
    for _, slotData in pairs(hotbarData) do
        if type(slotData) == "table" then
            for _, groupData in pairs(slotData) do
                if type(groupData) == "table" and groupData.LevelToAbilityDataMap then
                    for _, levelData in pairs(groupData.LevelToAbilityDataMap) do
                        if levelData.AvailableCount and levelData.AvailableCount > 0 then
                            table.insert(readyAbilities, { tower = levelData.ClosestTower, ability = levelData.ClosestAbility })
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
            local tower, ability = data.tower, data.ability
            if not tower or not ability or skipTowerTypes[tower.Type] then continue end
            
            local pos = getTowerPos(tower)
            if not pos then continue end

            local hash, index, range = tower.Hash, ability.Index, getRange(tower)
            local p1, p2 = GetCurrentUpgradeLevels(tower)
            local targetPos = nil

            -- FIX: Khôi phục logic xử lý chuyên biệt cho từng loại tháp định hướng
            if tower.Type == "Ghost" then
                if p2 <= 2 then
                    targetPos = findTarget(pos, math.huge, {mode = "maxhp", excludeArrows = true, excludeAir = false})
                    if targetPos then SendSkill(hash, index, targetPos) end
                end
            elseif tower.Type == "Toxicnator" then
                targetPos = findTarget(pos, range, {mode = "maxhp", excludeArrows = false, excludeAir = false})
                if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "Flame Trooper" then
                targetPos = getFarthestEnemyInRange(pos, 9.5, {excludeAir = false, excludeArrows = true})
                if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "Ice Breaker" then
                if index == 1 then
                    targetPos = getFarthestEnemyInRange(pos, range, {excludeAir = true, excludeArrows = true})
                elseif index == 2 then
                    targetPos = getFarthestEnemyInRange(pos, 8, {excludeAir = true, excludeArrows = true})
                end
                if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "Slammer" then
                targetPos = getFarthestEnemyInRange(pos, range, {excludeAir = true, excludeArrows = true})
                if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "John" then
                local targetRange = (p1 >= 5) and range or 4.5
                targetPos = getFarthestEnemyInRange(pos, targetRange, {excludeAir = true, excludeArrows = true})
                if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                if p2 >= 3 and p2 <= 5 then targetPos = getMobsterTarget(tower, hash, 2)
                elseif p1 >= 4 and p1 <= 5 then targetPos = getMobsterTarget(tower, hash, 1) end
                if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "Commander" and index == 3 then
                 targetPos = getCommanderTarget()
                 if targetPos then SendSkill(hash, index, targetPos) end
            elseif tower.Type == "Jet Trooper" then
                if index == 2 then SendSkill(hash, index) end
            else
                -- Logic chung cho các tháp còn lại
                local directional = directionalTowerTypes[tower.Type]
                local sendWithPos = (typeof(directional) == "table" and directional.onlyAbilityIndex == index) or (directional == true)
                if ability and requiresManualAiming(ability) then sendWithPos = true end

                if sendWithPos then
                    targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                    if targetPos then SendSkill(hash, index, targetPos) end
                else
                    if getFarthestEnemyInRange(pos, range, {excludeAir = skipAirTowers[tower.Type] or false, excludeArrows = true}) then
                        SendSkill(hash, index)
                    end
                end
            end
        end
    end)
end)