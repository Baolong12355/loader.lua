local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TowerUseAbilityRequest = ReplicatedStorage.Remotes:WaitForChild("TowerUseAbilityRequest")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))

-- Các tower cần truyền target
local specialTargetTowers = {
    ["Medic"] = true,
    ["Uber Medic"] = true
}

-- Lấy tất cả hash tower của bạn
local function getOwnedTowers()
    local towers = TowerClass.GetTowers()
    if typeof(towers) ~= "table" then return {} end
    return towers
end

-- Tìm tower gần nhất để làm target (cho Medic)
local function getClosestTowerHash(fromHash, range)
    local towers = getOwnedTowers()
    local selfTower = towers[fromHash]
    if not selfTower or not selfTower.GetPosition then return nil end
    local pos = selfTower:GetPosition()
    local nearest, dist = nil, math.huge

    for hash, tower in pairs(towers) do
        if hash ~= fromHash and tower.GetPosition then
            local targetPos = tower:GetPosition()
            local d = (targetPos - pos).Magnitude
            if d < dist and d <= (range or 25) then
                dist = d
                nearest = hash
            end
        end
    end
    return nearest
end

-- Kiểm tra cooldown skill
local function isCooldownReady(ability)
    return ability and (ability.CooldownRemaining or 0) <= 0
end

-- Vòng lặp auto skill
task.spawn(function()
    while task.wait(0.2) do
        local towers = getOwnedTowers()

        for hash, tower in pairs(towers) do
            if not tower or not tower.AbilityHandler then continue end
            local towerType = tostring(tower.Type)

            for index = 1, 3 do
                local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                if not isCooldownReady(ability) then continue end

                local args = { hash, index }

                -- Nếu tower yêu cầu truyền target (ví dụ Medic)
                if specialTargetTowers[towerType] then
                    local targetHash = getClosestTowerHash(hash, 30)
                    if targetHash then
                        args[4] = targetHash
                    else
                        continue
                    end
                end

                TowerUseAbilityRequest:InvokeServer(unpack(args, 1, table.maxn(args)))
            end
        end
    end
end)

print("✅ Auto skill chạy đúng định dạng với args[4] nếu cần.")
