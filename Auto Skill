-- 📦 TDX Auto Skill Module (dùng trong loader)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TowersFolder = Workspace:WaitForChild("Game"):WaitForChild("Towers")
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- Bỏ qua các tower không dùng skill
local skipTowers = {
    ["Helicopter"] = true, ["Cryo Helicopter"] = true, ["Artillery"] = true, ["Combat Drone"] = true,
    ["AA Turret"] = true, ["XWM Turret"] = true, ["Barracks"] = true, ["Cryo Blaster"] = true,
    ["Farm"] = true, ["Grenadier"] = true, ["Juggernaut"] = true, ["Machine Gunner"] = true,
    ["Relic"] = true, ["Sentry"] = true, ["Scarecrow"] = true, ["Zed"] = true,
    ["Troll Tower"] = true, ["Missile Trooper"] = true, ["Patrol Boat"] = true, ["Railgunner"] = true,
    ["Mine Layer"] = true
}

-- Gán lại tên dạng ID.Name nếu chưa có
local placedIndex = 1
local function RenameTowers()
    for _, tower in ipairs(TowersFolder:GetChildren()) do
        if not tower.Name:match("^%d+%.") then
            tower.Name = placedIndex .. "." .. tower.Name
            placedIndex += 1
        end
    end
end

-- Tự động dùng skill cho tower đủ điều kiện
local function AutoUseSkills()
    for _, tower in ipairs(TowersFolder:GetChildren()) do
        local id = tonumber(tower.Name:match("^(%d+)"))
        local towerName = tower.Name:match("^%d+%.(.+)")
        if id and towerName and not skipTowers[towerName] then
            for skillId = 1, 3 do
                pcall(function()
                    if useFireServer then
                        TowerUseAbilityRequest:FireServer(id, skillId)
                    else
                        TowerUseAbilityRequest:InvokeServer(id, skillId)
                    end
                end)
            end
        end
    end
end

-- Lặp mỗi giây
while task.wait(1) do
    RenameTowers()
    AutoUseSkills()
end
