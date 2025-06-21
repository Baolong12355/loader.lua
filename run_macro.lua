local HttpService = game:GetService("HttpService") local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local config = getgenv().TDX_Config or {} local macroName = config["Macro Name"] or "y" local macroPath = "tdx/macros/" .. macroName .. ".json"

local DEBUG = true local function DebugPrint(...) if DEBUG then print("[DEBUG]", ...) end end

local TowerClass local function LoadTowerClass() local PlayerScripts = player:WaitForChild("PlayerScripts") local client = PlayerScripts:WaitForChild("Client") local gameClass = client:WaitForChild("GameClass") return require(gameClass:WaitForChild("TowerClass")) end

TowerClass = LoadTowerClass()

local function IsSamePosition(p1, p2, tol) return (p1 - p2).Magnitude <= (tol or 2) end

local function IsTowerAtPosition(pos) for _, tower in pairs(TowerClass.GetTowers()) do local root = tower.Character and tower.Character:FindFirstChild("HumanoidRootPart") if root and IsSamePosition(root.Position, pos) then return true end end return false end

local function FindTowerByPosition(pos) for hash, tower in pairs(TowerClass.GetTowers()) do local root = tower.Character and tower.Character:FindFirstChild("HumanoidRootPart") if root and IsSamePosition(root.Position, pos) then return hash, tower end end return nil, nil end

local function IsAlive(tower) return tower and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 end

if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end

local macro = HttpService:JSONDecode(readfile(macroPath)) DebugPrint("Chạy macro với", #macro, "bước")

for i, entry in ipairs(macro) do if entry.TowerPlaced and entry.TowerVector then local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)") local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation) or 0 }

repeat
        while cashStat.Value < entry.TowerPlaceCost do task.wait(0.1) end
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.2)

        if IsTowerAtPosition(pos) then
            DebugPrint("Đặt tower thành công tại:", pos)
            break
        end

        DebugPrint("Tower chưa đặt thành công, thử lại...")
        task.wait(1)
    until false

elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
    local pos = Vector3.new(tonumber(entry.TowerUpgraded), 0, 0)
    repeat
        if not IsTowerAtPosition(pos) then
            DebugPrint("Không còn tower tại vị trí nâng cấp, bỏ qua")
            break
        end

        local hash, tower = FindTowerByPosition(pos)
        if not tower or not IsAlive(tower) then
            DebugPrint("Tower nâng cấp đã chết, bỏ qua")
            break
        end

        while cashStat.Value < entry.UpgradeCost do task.wait(0.1) end
        local before = tower.LevelHandler:GetLevelOnPath(entry.UpgradePath)
        local upgraded = false

        for attempt = 1, 3 do
            Remotes.TowerUpgradeRequest:FireServer(tonumber(hash:match("%d+")), entry.UpgradePath, 1)
            task.wait(0.2)

            local _, after = FindTowerByPosition(pos)
            if after and IsAlive(after) and after.LevelHandler:GetLevelOnPath(entry.UpgradePath) > before then
                DebugPrint("Nâng cấp thành công path", entry.UpgradePath)
                upgraded = true
                break
            end
        end

        if upgraded then break end
        DebugPrint("Nâng cấp thất bại, thử lại...")
        task.wait(1)
    until false

elseif entry.TargetType and entry.TowerVector then
    local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
    local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
    local hash, tower = FindTowerByPosition(pos)

    if not tower or not IsAlive(tower) then
        DebugPrint("Tower đổi target đã chết hoặc không tồn tại, bỏ qua")
        continue
    end

    Remotes.ChangeQueryType:FireServer(tonumber(hash:match("%d+")), entry.TargetType)
    task.wait(0.2)
    DebugPrint("Đã đổi target")

elseif entry.SellTower and entry.TowerVector then
    local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
    local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
    local hash, tower = FindTowerByPosition(pos)

    if not tower or not IsAlive(tower) then
        DebugPrint("Tower cần bán đã chết hoặc không tồn tại, bỏ qua")
        continue
    end

    Remotes.SellTower:FireServer(tonumber(hash:match("%d+")))
    task.wait(0.2)
    DebugPrint("Đã bán tower")
end

end

print("Đã hoàn thành toàn bộ macro!")

