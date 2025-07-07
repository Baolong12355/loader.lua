-- Script này yêu cầu executor hỗ trợ các hàm cơ bản
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- =============================================
-- PHẦN KHAI BÁO VÀ TIỆN ÍCH
-- =============================================

-- Hàm tìm module enemy trong game
local function findEnemyModule()
    -- Thử các vị trí thường chứa module enemy
    local locations = {
        game:GetService("ReplicatedStorage"):FindFirstChild("TDX_Shared") and game:GetService("ReplicatedStorage").TDX_Shared.Common.EnemyClass,
        game:GetService("ReplicatedStorage"):FindFirstChild("Common") and game:GetService("ReplicatedStorage").Common.EnemyClass,
        LocalPlayer.PlayerScripts:FindFirstChild("Game") and LocalPlayer.PlayerScripts.Game.EnemyClass
    }
    
    for _, location in ipairs(locations) do
        if location then
            local success, module = pcall(require, location)
            if success then
                return module
            end
        end
    end
    
    warn("Không tìm thấy module EnemyClass!")
    return nil
end

-- Hàm tạo bảng thông tin enemy
local function createEnemyInfoTable(enemy)
    if not enemy or not enemy.IsAlive then return nil end
    
    local info = {
        -- Thông tin cơ bản
        Type = enemy.Type or "Unknown",
        DisplayName = enemy.DisplayName or enemy.Type or "Unknown",
        UniqueId = enemy.UniqueId or "N/A",
        Class = enemy.IsBoss and "BOSS" or enemy.IsMiniBoss and "MINIBOSS" or "NORMAL",
        
        -- Thông tin HP
        Health = "N/A",
        MaxHealth = "N/A",
        HealthPercent = 0,
        Armor = "N/A",
        Shield = "N/A",
        
        -- Thông tin vị trí
        Position = Vector3.new(0, 0, 0),
        Distance = 0,
        
        -- Thông tin combat
        Bounty = "N/A",
        DamageMultiplier = enemy.DamageMultiplier or 1,
        SpeedMultiplier = enemy.SpeedMultiplier or 1,
        
        -- Trạng thái
        IsStunned = enemy.Stunned or false,
        IsStealthed = enemy.Stealth or false,
        IsInvulnerable = enemy.Invulnerable or false,
        IsAirUnit = enemy.IsAirUnit or false,
        
        -- Thông tin tấn công
        AttackRange = "N/A",
        AttackDamage = "N/A",
        AttackSpeed = "N/A"
    }
    
    -- Lấy thông tin HP
    if enemy.HealthHandler then
        info.Health = enemy.HealthHandler:GetCurrentHealth() or "N/A"
        info.MaxHealth = enemy.HealthHandler:GetMaxHealth() or "N/A"
        info.HealthPercent = math.floor((info.Health / info.MaxHealth) * 100)
        info.Armor = enemy.HealthHandler:GetArmor() or 0
        info.Shield = enemy.HealthHandler:GetShield() or 0
    end
    
    -- Lấy thông tin vị trí
    if enemy.GetPosition and typeof(enemy.GetPosition) == "function" then
        info.Position = enemy:GetPosition()
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            info.Distance = (char.HumanoidRootPart.Position - info.Position).Magnitude
        end
    end
    
    -- Lấy thông tin bounty
    if enemy.BountyDisplayHandler and enemy.BountyDisplayHandler.GetBounty then
        info.Bounty = enemy.BountyDisplayHandler:GetBounty() or 0
    end
    
    -- Lấy thông tin tấn công
    if enemy.AttackClientDataTable then
        for _, attackData in pairs(enemy.AttackClientDataTable) do
            info.AttackRange = attackData.Range or "N/A"
            info.AttackDamage = attackData.Damage or "N/A"
            info.AttackSpeed = attackData.ReloadTime and (1 / attackData.ReloadTime) or "N/A"
            break -- Chỉ lấy thông tin từ attack đầu tiên
        end
    end
    
    return info
end

-- =============================================
-- PHẦN HIỂN THỊ THÔNG TIN
-- =============================================

local EnemyModule = findEnemyModule()
if not EnemyModule then
    warn("Không thể khởi chạy script do không tìm thấy module enemy!")
    return
end

-- Tạo UI để hiển thị thông tin
local function createTrackerUI()
    -- Code tạo UI sẽ phụ thuộc vào executor bạn sử dụng
    -- Đây là phần giả lập UI cơ bản
    print("===== ENEMY TRACKER INITIALIZED =====")
end

-- Hàm cập nhật thông tin enemy
local function updateEnemyInfo()
    local enemies = EnemyModule.GetEnemies()
    local enemyCount = 0
    local bossCount = 0
    
    -- Làm mới console
    if _G.clear then _G.clear() end
    
    print("=== REAL-TIME ENEMY TRACKER ===")
    print(string.format("Thời gian: %s", os.date("%X")))
    print("--------------------------------")
    
    for hash, enemy in pairs(enemies) do
        local info = createEnemyInfoTable(enemy)
        if info then
            enemyCount = enemyCount + 1
            if info.Class ~= "NORMAL" then
                bossCount = bossCount + 1
            end
            
            -- Hiển thị thông tin
            print(string.format("[%s] %s (ID: %s)", info.Class, info.DisplayName, info.UniqueId))
            print(string.format("  HP: %d/%d (%d%%) | Armor: %d | Shield: %d", 
                info.Health, info.MaxHealth, info.HealthPercent, info.Armor, info.Shield))
            print(string.format("  Vị trí: (%.1f, %.1f, %.1f) | Khoảng cách: %.1f studs", 
                info.Position.X, info.Position.Y, info.Position.Z, info.Distance))
            print(string.format("  Bounty: %d | Nhân sát thương: %.1fx | Tốc độ: %.1fx", 
                info.Bounty, info.DamageMultiplier, info.SpeedMultiplier))
            print(string.format("  Trạng thái: %s%s%s%s", 
                info.IsStunned and "STUN " or "",
                info.IsStealthed and "STEALTH " or "",
                info.IsInvulnerable and "INVUL " or "",
                info.IsAirUnit and "AIR" or "GROUND"))
            print(string.format("  Tấn công: DMG %s | Tầm %s | Tốc độ %.1f/s", 
                info.AttackDamage, info.AttackRange, info.AttackSpeed))
            print("--------------------------------")
        end
    end
    
    print(string.format("TỔNG: %d enemy (%d boss/miniboss)", enemyCount, bossCount))
    print("===== NHẤN F5 ĐỂ LÀM MỚI =====")
end

-- =============================================
-- PHẦN CHẠY CHÍNH
-- =============================================

createTrackerUI()

-- Tùy chọn 1: Làm mới thủ công bằng phím F5
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.F5 then
        updateEnemyInfo()
    end
end)

-- Tùy chọn 2: Làm mới tự động mỗi 3 giây
_G.autoRefresh = true
spawn(function()
    while _G.autoRefresh and wait(3) do
        updateEnemyInfo()
    end
end)

-- Chạy lần đầu
updateEnemyInfo()
