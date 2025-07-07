-- Phiên bản đã sửa lỗi 'attempt to call a string value'
local PlayerService = game:GetService("Players")
local LocalPlayer = PlayerService.LocalPlayer
local RunService = game:GetService("RunService")

local function SafeRequire(moduleScript)
    local success, module = pcall(require, moduleScript)
    return success and module or nil
end

local function GetEnemyModule()
    -- Kiểm tra nhiều vị trí có thể
    local locations = {
        LocalPlayer.PlayerScripts:FindFirstChild("GameClass") and LocalPlayer.PlayerScripts.GameClass.EnemyClass,
        LocalPlayer.PlayerScripts:FindFirstChild("Game") and LocalPlayer.PlayerScripts.Game.EnemyClass,
        ReplicatedStorage:FindFirstChild("TDX_Shared") and ReplicatedStorage.TDX_Shared.Common.EnemyClass
    }
    
    for _, location in ipairs(locations) do
        if location then
            local module = SafeRequire(location)
            if module then return module end
        end
    end
    return nil
end

local EnemyClass = GetEnemyModule()
if not EnemyClass then
    warn("Không thể tìm thấy EnemyClass!")
    return
end

-- Hàm giả lập để lấy enemies (thay thế bằng phương thức thực tế của game)
local function GetLiveEnemies()
    local enemies = {}
    
    -- Cách 1: Duyệt qua workspace (nếu game lưu enemy trong workspace)
    if workspace:FindFirstChild("Enemies") then
        for _, enemyModel in ipairs(workspace.Enemies:GetChildren()) do
            if enemyModel:FindFirstChild("HumanoidRootPart") then
                table.insert(enemies, {
                    Model = enemyModel,
                    Position = enemyModel.HumanoidRootPart.Position
                })
            end
        end
    end
    
    -- Cách 2: Dùng metatable hook (nâng cao)
    -- ... (code hook sẽ phụ thuộc vào executor)
    
    return enemies
end

local function CreateEnemyInfoDisplay(enemy)
    -- Kiểm tra enemy hợp lệ
    if not enemy or typeof(enemy) ~= "table" then return end
    
    -- Lấy thông tin cơ bản
    local info = {
        Type = enemy._type or "Unknown",
        Health = "N/A",
        MaxHealth = "N/A",
        Position = Vector3.new(0,0,0),
        Bounty = 0,
        States = {}
    }
    
    -- Lấy thông tin máu (nếu có)
    if enemy.Health and typeof(enemy.Health.GetPercent) == "function" then
        info.Health = enemy.Health.Current or "N/A"
        info.MaxHealth = enemy.Health.Max or "N/A"
        info.HealthPercent = enemy.Health:GetPercent() or 0
    end
    
    -- Lấy vị trí
    if enemy.Movement and enemy.Movement.Position then
        info.Position = enemy.Movement.Position
    elseif enemy.Model and enemy.Model:FindFirstChild("HumanoidRootPart") then
        info.Position = enemy.Model.HumanoidRootPart.Position
    end
    
    -- Lấy trạng thái
    if enemy._states then
        info.States = {
            Stunned = enemy._states.Stunned or false,
            Stealthed = enemy._states.Stealthed or false,
            Invulnerable = enemy._states.Invulnerable or false
        }
    end
    
    -- Lấy bounty (nếu có)
    if enemy.Bounty and enemy.Bounty.Value then
        info.Bounty = enemy.Bounty.Value
    end
    
    return info
end

local function UpdateEnemyTracker()
    local enemies = GetLiveEnemies()
    if not enemies then return end
    
    -- Xóa console cũ (nếu executor hỗ trợ)
    if _G.clear then _G.clear() end
    
    print("=== ENEMY TRACKER ===")
    print("Thời gian:", os.date("%X"))
    print("Tổng số enemy:", #enemies)
    print("-----------------------")
    
    for i, enemy in ipairs(enemies) do
        local info = CreateEnemyInfoDisplay(enemy)
        if info then
            local statusFlags = ""
            if info.States.Stunned then statusFlags = statusFlags.."STUN " end
            if info.States.Stealthed then statusFlags = statusFlags.."STEALTH " end
            if info.States.Invulnerable then statusFlags = statusFlags.."INVUL " end
            
            print(string.format("[%d] %s", i, info.Type))
            print(string.format("HP: %s/%s (%d%%)", 
                tostring(info.Health), 
                tostring(info.MaxHealth), 
                info.HealthPercent))
            print("Bounty:", info.Bounty)
            print("Position:", info.Position)
            print("Status:", statusFlags)
            print("-----------------------")
        end
    end
end

-- Tạo UI đồ họa (tùy chọn)
local function CreateVisualTracker()
    -- Code tạo ESP box, health bar...
    -- Phụ thuộc vào executor cụ thể
end

-- Main loop
CreateVisualTracker()
local trackerLoop = RunService.Heartbeat:Connect(function()
    UpdateEnemyTracker()
    wait(3) -- Làm mới mỗi 3 giây
end)

-- Tắt tracker khi không cần
_G.StopEnemyTracker = function()
    trackerLoop:Disconnect()
    print("Đã tắt Enemy Tracker")
end
