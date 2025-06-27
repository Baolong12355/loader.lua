-- 📦 Auto-Skill PRO với phân xử tower thường và tower định hướng

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- 🟨 Danh sách các tower không xử lý (kể cả tower định hướng để tránh xử lý sai)
local skipTowerTypes = {
    ["Farm"] = true,
    ["Relic"] = true,
    ["Scarecrow"] = true,
    ["Helicopter"] = true,
    ["Cryo Helicopter"] = true,
    ["Combat Drone"] = true,
    ["AA Turret"] = true,
    ["XWM Turret"] = true,
    ["Barracks"] = true,
    ["Cryo Blaster"] = true,
    ["Grenadier"] = true,
    ["Juggernaut"] = true,
    ["Machine Gunner"] = true,
    ["Zed"] = true,
    ["Troll Tower"] = true,
    ["Missile Trooper"] = true,
    ["Patrol Boat"] = true,
    ["Railgunner"] = true,
    ["Mine Layer"] = true,
    ["Sentry"] = true,
    ["Commander"] = true, -- Commander chỉ xử lý skill 3 ở phần tower định hướng
    ["Toxicnator"] = true,
    ["Ghost"] = true,
    ["Ice Breaker"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true,
    ["Artillery"] = true,
    ["EDJ"] = false,
    ["Accelerator"] = true,
    ["Engineer"] = true
}

-- 🟥 Danh sách các tower định hướng và yêu cầu vị trí enemy
local directionalTowerTypes = {
    ["Commander"] = { onlyAbilityIndex = 3 }, -- chỉ dùng skill 3 là định hướng
    ["Toxicnator"] = true,
    ["Ghost"] = true,
    ["Ice Breaker"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true,
    ["Artillery"] = true
}

-- 📌 Vị trí kẻ địch đầu tiên
local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

local function GetFirstEnemyPosition()
    for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
        if enemy.Name ~= "Arrow" and enemy:IsA("BasePart") then
            return enemy.Position
        end
    end
    return nil
end

-- 🧠 Điều kiện có thể dùng skill
local function CanUseAbility(ability)
    return ability and
        not ability.Passive and
        not ability.CustomTriggered and
        ability.CooldownRemaining <= 0 and
        not ability.Stunned and
        not ability.Disabled and
        not ability.Converted and
        ability:CanUse(true)
end

-- ✅ Kiểm tra tower thường có thể xử lý không
local function ShouldProcessTower(tower)
    return tower and
        not tower.Destroyed and
        tower.HealthHandler and
        tower.HealthHandler:GetHealth() > 0 and
        not skipTowerTypes[tower.Type] and
        tower.AbilityHandler
end

-- ✅ Kiểm tra tower định hướng nhưng không phải skill định hướng
local function ShouldProcessNonDirectionalSkill(tower, abilityIndex)
    if tower.Type == "Commander" and abilityIndex ~= 3 then
        -- Commander skill 1, 2 xử lý như tower thường
        return tower and
            not tower.Destroyed and
            tower.HealthHandler and
            tower.HealthHandler:GetHealth() > 0 and
            tower.AbilityHandler
    end
    return false
end

-- 🔁 Vòng lặp chính
while task.wait(0.1) do
    for hash, tower in pairs(TowerClass.GetTowers() or {}) do
        local towerType = tower.Type
        local directionalInfo = directionalTowerTypes[towerType]

        if directionalInfo and tower and tower.AbilityHandler then
            for abilityIndex = 1, 3 do
                pcall(function()
                    local ability = tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
                    if CanUseAbility(ability) then
                        -- Nếu là Commander, chỉ skill 3 mới định hướng
                        if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
                            if abilityIndex == directionalInfo.onlyAbilityIndex then
                                local enemyPos = GetFirstEnemyPosition()
                                if enemyPos then
                                    local args = {
                                        hash,
                                        abilityIndex,
                                        enemyPos
                                    }
                                    if useFireServer then
                                        TowerUseAbilityRequest:FireServer(unpack(args))
                                    else
                                        TowerUseAbilityRequest:InvokeServer(unpack(args))
                                    end
                                    task.wait(0.25)
                                    return
                                end
                            else
                                -- Skill 1, 2 của Commander xử lý như tower thường
                                if ShouldProcessNonDirectionalSkill(tower, abilityIndex) then
                                    if useFireServer then
                                        TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                                    else
                                        TowerUseAbilityRequest:InvokeServer(hash, abilityIndex)
                                    end
                                    task.wait(0.25)
                                end
                            end
                        else
                            -- Các tower định hướng khác: mọi skill đều cần enemy position
                            local enemyPos = GetFirstEnemyPosition()
                            if enemyPos then
                                local args = {
                                    hash,
                                    abilityIndex,
                                    enemyPos
                                }
                                if useFireServer then
                                    TowerUseAbilityRequest:FireServer(unpack(args))
                                else
                                    TowerUseAbilityRequest:InvokeServer(unpack(args))
                                end
                                task.wait(0.25)
                                return
                            end
                        end
                    end
                end)
            end
        elseif ShouldProcessTower(tower) then
            for abilityIndex = 1, 3 do
                pcall(function()
                    local ability = tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
                    if CanUseAbility(ability) then
                        if useFireServer then
                            TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                        else
                            TowerUseAbilityRequest:InvokeServer(hash, abilityIndex)
                        end
                        task.wait(0.25)
                    end
                end)
            end
        end
    end
end
