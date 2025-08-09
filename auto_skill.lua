local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- Cấu hình tower đặc biệt
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

local skipAirTowers = {
        ["Ice Breaker"] = true,
        ["John"] = true,
        ["Slammer"] = true,
        ["Mobster"] = true,
        ["Golden Mobster"] = true
}

local lastUsedTime = {}
local mobsterUsedEnemies = {}
local prevCooldown = {}
local medicLastUsedTime = {}
local medicDelay = 0.5

-- ======== Hàm cơ bản ========
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

-- ======== Hàm lấy enemies (dùng chung) ========
local function getEnemies()
        local result = {}
        for _, e in pairs(EnemyClass.GetEnemies()) do
                if e and e.IsAlive and not e.IsFakeEnemy then
                        table.insert(result, e)
                end
        end
        return result
end

-- ======== Hàm tìm target hợp nhất ========
-- Các tùy chọn cho hàm findTarget:
-- mode: "nearest", "maxhp", "random_weighted" 
-- excludeAir: có bỏ qua air unit không
-- excludeArrows: có bỏ qua Arrow type không  
-- usedEnemies: table chứa enemies đã dùng (cho mobster path 2)
-- markUsed: có đánh dấu enemy đã dùng không
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
                
                -- Kiểm tra đã dùng chưa (cho mobster)
                if usedEnemies then
                        local id = tostring(enemy)
                        if usedEnemies[id] then continue end
                end
                
                table.insert(candidates, enemy)
        end
        
        if #candidates == 0 then return nil end
        
        local chosen = nil
        if mode == "nearest" then
                -- Lấy enemy đầu tiên (đã trong range)
                chosen = candidates[1]
        elseif mode == "maxhp" then
                -- Lấy enemy có HP cao nhất
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
                -- Sắp xếp theo HP giảm dần, 30% chọn cao nhất, 70% random
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
        
        -- Đánh dấu đã dùng nếu cần
        if chosen and markUsed and usedEnemies then
                usedEnemies[tostring(chosen)] = true
        end
        
        return chosen and chosen:GetPosition() or nil
end

-- ======== Các hàm target chuyên biệt ========
local function getNearestEnemy(pos, range, towerType)
        return findTarget(pos, range, {
                mode = "nearest",
                excludeAir = skipAirTowers[towerType] or false,
                excludeArrows = true
        })
end

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
        -- Lấy tất cả ground enemies, không cần kiểm tra range
        local candidates = {}
        for _, e in ipairs(getEnemies()) do
                if not e.IsAirUnit and e.Type ~= "Arrow" then 
                        table.insert(candidates, e) 
                end
        end
        
        if #candidates == 0 then return nil end
        
        -- Sắp xếp theo HP giảm dần
        table.sort(candidates, function(a, b)
                local hpA = a.HealthHandler and a.HealthHandler:GetMaxHealth() or 0
                local hpB = b.HealthHandler and b.HealthHandler:GetMaxHealth() or 0
                return hpA > hpB
        end)
        
        -- 30% chọn HP cao nhất, 70% random
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

local function getHighestHpEnemyInRange(pos, range)
        local targetEnemy = findTarget(pos, range, {
                mode = "maxhp",
                excludeArrows = false,
                excludeAir = false
        })
        if not targetEnemy then return nil end
        
        -- Trả về enemy object thay vì position để có thể gọi :GetPosition() 
        for _, enemy in ipairs(getEnemies()) do
                if enemy:GetPosition() == targetEnemy then
                        return enemy
                end
        end
        return nil
end

local function SendSkill(hash, index, pos, targetHash)
        if useFireServer then
                TowerUseAbilityRequest:FireServer(hash, index, pos, targetHash)
        else
                TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
        end
end

-- ======== MAIN LOOP ========
RunService.Heartbeat:Connect(function()
        local now = tick()
        local ownedTowers = TowerClass.GetTowers() or {}

        for hash, tower in pairs(ownedTowers) do
                if not tower or not tower.AbilityHandler then continue end

                -- Medic đặc biệt với delay riêng biệt
                if tower.Type == "Medic" then
                        local _, p2 = GetCurrentUpgradeLevels(tower)
                        if p2 >= 4 then
                                if medicLastUsedTime[hash] and now - medicLastUsedTime[hash] < medicDelay then continue end
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

                        -- Jet Trooper không dùng skill 1
                        if tower.Type == "Jet Trooper" and index == 1 then
                                allowUse = false
                        end

                        -- Ghost: skip nếu path 2 > 2
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

                        -- Toxicnator: dùng skill lên enemy có HP cao nhất trong range
                        if tower.Type == "Toxicnator" then
                                targetPos = findTarget(pos, range, {
                                        mode = "maxhp",
                                        excludeArrows = false,
                                        excludeAir = false
                                })
                                if targetPos then SendSkill(hash, index, targetPos) end
                                break
                        end

                        if tower.Type == "Ice Breaker" then
                                allowUse = index == 1 or (index == 2 and getNearestEnemy(pos, 8, tower.Type))
                        elseif tower.Type == "Slammer" then
                                allowUse = getNearestEnemy(pos, range, tower.Type) ~= nil
                        elseif tower.Type == "John" then
                                allowUse = (p1 >= 5 and getNearestEnemy(pos, range, tower.Type)) or getNearestEnemy(pos, 4.5, tower.Type)
                        elseif tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                                if p2 >= 3 and p2 <= 5 then
                                        targetPos = getMobsterTarget(tower, hash, 2)
                                        if not targetPos then break end
                                elseif p1 >= 4 and p1 <= 5 then
                                        targetPos = getMobsterTarget(tower, hash, 1)
                                        if not targetPos then break end
                                else
                                        allowUse = false
                                end
                        end

                        if tower.Type == "Commander" and index == 3 then
                                targetPos = getCommanderTarget()
                                if not targetPos then break end
                        end

                        local directional = directionalTowerTypes[tower.Type]
                        local sendWithPos = typeof(directional) == "table" and directional.onlyAbilityIndex == index or directional == true

                        if not targetPos and sendWithPos then
                                targetPos = getNearestEnemy(pos, range, tower.Type)
                                if not targetPos then break end
                        end

                        if allowUse then
                                if sendWithPos then
                                        SendSkill(hash, index, targetPos)
                                else
                                        SendSkill(hash, index)
                                end
                        end
                end
        end
end)