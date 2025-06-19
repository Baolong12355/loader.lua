-- 📦 TDX Auto Skill Module (Bỏ qua tower trong danh sách, kích hoạt skill cho các tower còn lại)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TowersFolder = Workspace:WaitForChild("Game"):WaitForChild("Towers")
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- Danh sách tower BỎ QUA (không dùng skill)
local skipTowers = {
    ["Helicopter"] = true, ["Cryo Helicopter"] = true, ["Artillery"] = true, ["Combat Drone"] = true,
    ["AA Turret"] = true, ["XWM Turret"] = true, ["Barracks"] = true, ["Cryo Blaster"] = true,
    ["Farm"] = true, ["Grenadier"] = true, ["Juggernaut"] = true, ["Machine Gunner"] = true,
    ["Relic"] = true, ["Sentry"] = true, ["Scarecrow"] = true, ["Zed"] = true,
    ["Troll Tower"] = true, ["Missile Trooper"] = true, ["Patrol Boat"] = true, ["Railgunner"] = true,
    ["Mine Layer"] = true
}

-- Đánh lại tên tower dạng "ID.Tên" (nếu cần)
local placedIndex = 1
local function RenameTowers()
    for _, tower in ipairs(TowersFolder:GetChildren()) do
        if not tower.Name:match("^%d+%.") then
            tower.Name = placedIndex .. "." .. tower.Name
            placedIndex += 1
        end
    end
end

-- Kiểm tra tower có nằm trong danh sách bỏ qua không
local function ShouldSkip(towerName)
    if not towerName then return true end
    return skipTowers[towerName] ~= nil
end

-- Tự động dùng skill cho tower KHÔNG nằm trong danh sách skip
local function AutoUseSkills()
    for _, tower in ipairs(TowersFolder:GetChildren()) do
        local id = tonumber(tower.Name:match("^(%d+)"))
        local towerName = tower.Name:match("^%d+%.(.+)")
        if id and towerName and not ShouldSkip(towerName) then
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
