local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = game.Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Đọc macro
local macro = HttpService:JSONDecode(readfile("tdx/macros/y.json"))

-- Chuyển chuỗi sang Vector3
local function parseVector3(str)
    local x, y, z = str:match("([^,]+),%s*([^,]+),%s*([^,]+)")
    return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
end

-- Đặt tower
local function placeTower(entry)
    local vec = parseVector3(entry.TowerVector)
    local cost = entry.TowerPlaceCost
    local towerName = entry.TowerPlaced
    local a1 = tonumber(entry.TowerA1)
    local rotation = tonumber(entry.Rotation) or 0

    while true do
        local cash = LocalPlayer.leaderstats and LocalPlayer.leaderstats:FindFirstChild("Cash")
        if cash and cash.Value >= cost then
            local args = {
                a1,
                towerName,
                vec,
                rotation
            }
            local success, result = pcall(function()
                return Remotes.PlaceTower:InvokeServer(unpack(args))
            end)
            if success then
                print("✅ Đã đặt:", towerName, "tại", tostring(vec))
                return
            end
        end
        task.wait(0.2)
    end
end

-- Nâng cấp tower
local function upgradeTower(entry)
    local index = tonumber(entry.TowerIndex)
    local path = tonumber(entry.UpgradePath)
    local cost = tonumber(entry.UpgradeCost)

    while true do
        local cash = LocalPlayer.leaderstats and LocalPlayer.leaderstats:FindFirstChild("Cash")
        if cash and cash.Value >= cost then
            local before = cash.Value
            Remotes.TowerUpgradeRequest:FireServer(index, path, 1)
            task.wait(0.3)
            local after = cash.Value
            if after < before then
                print("⬆️ Đã nâng tower", index, "path", path)
                return
            end
        end
        task.wait(0.2)
    end
end

-- Chạy macros
for _, entry in ipairs(macro) do
    if entry.TowerPlaced and entry.TowerVector and entry.TowerA1 then
        placeTower(entry)
    elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
        upgradeTower(entry)
    end
end

print("✅ Đã chạy xong toàn bộ macro."
