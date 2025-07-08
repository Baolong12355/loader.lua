-- Health Tracker Executor Script
-- Đường dẫn chính xác: PlayerScripts/Client/GameClass/EnemyClass/HealthHandlerClass

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- =============================================
-- KẾT NỐI TỚI HEALTH HANDLER CLASS
-- =============================================

local function GetHealthHandlerModule()
    -- Kiểm tra từng cấp độ thư mục
    local clientScripts = LocalPlayer:WaitForChild("PlayerScripts")
    local clientModule = clientScripts:FindFirstChild("Client")
    
    if not clientModule then
        warn("Không tìm thấy thư mục Client")
        return nil
    end

    local gameClass = clientModule:FindFirstChild("GameClass")
    if not gameClass then
        warn("Không tìm thấy thư mục GameClass")
        return nil
    end

    local enemyClass = gameClass:FindFirstChild("EnemyClass")
    if not enemyClass then
        warn("Không tìm thấy thư mục EnemyClass")
        return nil
    end

    local healthHandler = enemyClass:FindFirstChild("HealthHandlerClass")
    if not healthHandler then
        warn("Không tìm thấy HealthHandlerClass")
        return nil
    end

    -- Thử require module
    local success, module = pcall(require, healthHandler)
    if not success then
        warn("Không thể require HealthHandlerClass:", module)
        return nil
    end

    return module
end

local HealthHandler = GetHealthHandlerModule()
if not HealthHandler then
    return
end

-- =============================================
-- HÀM HIỂN THỊ THÔNG TIN HEALTH
-- =============================================

local function TrackEnemyHealth(enemy)
    if not enemy or not enemy:FindFirstChild("HealthData") then
        warn("Enemy không có dữ liệu máu")
        return
    end

    -- Lấy health handler từ enemy
    local healthData = enemy:FindFirstChild("HealthData")
    local handler = healthData:GetAttribute("HealthHandler")
    
    if not handler then
        warn("Không tìm thấy HealthHandler")
        return
    end

    -- Hiển thị thông tin
    print("=== ENEMY HEALTH INFO ===")
    print("Loại enemy:", enemy:GetAttribute("Type") or "Unknown")
    print("ID:", enemy:GetAttribute("UniqueId") or "N/A")
    print("-----------------------")
    print("Máu hiện tại:", HealthHandler.GetHealth(handler))
    print("Máu tối đa:", HealthHandler.GetMaxHealth(handler))
    print("Shield hiện tại:", HealthHandler.GetShield(handler))
    print("Shield tối đa:", HealthHandler.GetMaxShield(handler))
    print("-----------------------")
    print("Có shield:", HealthHandler.HasShield(handler) and "CÓ" or "KHÔNG")
    print("Shield đang hoạt động:", HealthHandler.IsShieldActive(handler) and "CÓ" or "KHÔNG")
    print("Phần trăm máu:", string.format("%.1f%%", (HealthHandler.GetHealth(handler) / HealthHandler.GetMaxHealth(handler)) * 100))
end

-- =============================================
-- TỰ ĐỘNG THEO DÕI TẤT CẢ ENEMY
-- =============================================

local function AutoTrackAllEnemies()
    -- Tìm tất cả enemy trong workspace
    local enemiesFolder = workspace:FindFirstChild("Enemies")
    if not enemiesFolder then
        warn("Không tìm thấy thư mục Enemies trong workspace")
        return
    end

    -- Làm mới console
    if _G.clear then _G.clear() end

    print("=== THEO DÕI MÁU ENEMY TỰ ĐỘNG ===")
    print("Nhấn F5 để dừng")

    -- Kết nối sự kiện
    local connection
    connection = RunService.Heartbeat:Connect(function()
        -- Kiểm tra phím tắt
        if game:GetService("UserInputService"):IsKeyDown(Enum.KeyCode.F5) then
            connection:Disconnect()
            print("Đã dừng tự động theo dõi")
            return
        end

        -- Làm mới console
        if _G.clear then _G.clear() end

        -- Duyệt qua tất cả enemy
        for _, enemy in ipairs(enemiesFolder:GetChildren()) do
            if enemy:FindFirstChild("HealthData") then
                local healthData = enemy:FindFirstChild("HealthData")
                local handler = healthData:GetAttribute("HealthHandler")

                if handler then
                    print(string.format("[%s] HP: %d/%d | Shield: %d/%d",
                        enemy.Name,
                        HealthHandler.GetHealth(handler),
                        HealthHandler.GetMaxHealth(handler),
                        HealthHandler.GetShield(handler),
                        HealthHandler.GetMaxShield(handler)
                    ))
                end
            end
        end

        wait(2) -- Làm mới mỗi 2 giây
    end)
end

-- =============================================
-- GIAO DIỆN ĐIỀU KHIỂN
-- =============================================

local function SetupControls()
    local UIS = game:GetService("UserInputService")

    -- F5: Theo dõi tất cả enemy
    UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end

        if input.KeyCode == Enum.KeyCode.F5 then
            AutoTrackAllEnemies()
        end
    end)

    print("Nhấn F5 để bắt đầu theo dõi máu tất cả enemy")
end

-- Khởi động
SetupControls()
