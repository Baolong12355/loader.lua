-- 📦 Auto-Skill PRO với danh sách skip đầy đủ
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- DANH SÁCH TOWER BỎ QUA ĐẦY ĐỦ (từ p4.txt + p15.txt + kinh nghiệm game)
local skipTowerTypes = {
    -- Tower không có skill
    ["Farm"] = true,
    ["Relic"] = true,
    ["Scarecrow"] = true,
    
    -- Tower skill đặc biệt (không nên auto)
    ["Helicopter"] = true,
    ["Cryo Helicopter"] = true,
    ["Artillery"] = true,
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

    -- Tower chỉ có passive skill
    ["EDJ"] = true,
    ["Accelerator"] = true,
    ["Engineer"] = true
}

local function CanUseAbility(ability)
    -- Kiểm tra 7 điều kiện quan trọng từ p15.txt
    return ability and
           not ability.Passive and
           not ability.CustomTriggered and
           ability.CooldownRemaining <= 0 and
           not ability.Stunned and
           not ability.Disabled and
           not ability.Converted and
           ability:CanUse(true)
end

local function ShouldProcessTower(tower)
    -- Kiểm tra 5 lớp điều kiện
    return tower and
           not tower.Destroyed and
           tower.HealthHandler and
           tower.HealthHandler:GetHealth() > 0 and
           not skipTowerTypes[tower.Type] and
           tower.AbilityHandler
end

while task.wait(0.1) do
    for hash, tower in pairs(TowerClass.GetTowers() or {}) do
        if ShouldProcessTower(tower) then
            -- Duyệt qua tất cả skill index hợp lệ (p17.txt)
            for abilityIndex = 1, 3 do -- Giả định max 3 skill/tower
                pcall(function()
                    local ability = tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
                    if CanUseAbility(ability) then
                        if useFireServer then
                            TowerUseAbilityRequest:FireServer(hash, abilityIndex)
                        else
                            TowerUseAbilityRequest:InvokeServer(hash, abilityIndex)
                        end
                        task.wait(0.01) -- Chống spam
                    end
                end)
            end
        end
    end
end
