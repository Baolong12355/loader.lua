--[[
  ENEMY TRACKER EXECUTOR SCRIPT
  Cách sử dụng:
  1. Dán vào executor (Synapse, Krnl, Fluxus...)
  2. Nhấn F5 để làm mới dữ liệu
  3. Nhấn F6 để bật/tắt auto-refresh
  4. Nhấn F7 để hiển thị ESP
--]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- =============================================
-- PHẦN KẾT NỐI VỚI GAME
-- =============================================

local function GetEnemyModule()
    -- Thử các vị trí có thể chứa EnemyClass
    local locations = {
        LocalPlayer.PlayerScripts:FindFirstChild("GameClass") and LocalPlayer.PlayerScripts.GameClass.EnemyClass,
        LocalPlayer.PlayerScripts:FindFirstChild("Client") and LocalPlayer.PlayerScripts.Client.GameClass.EnemyClass,
        game:GetService("ReplicatedStorage"):FindFirstChild("EnemyClass")
    }
    
    for _, location in ipairs(locations) do
        if location then
            local success, module = pcall(require, location)
            if success then return module end
        end
    end
    return nil
end

local EnemyClass = GetEnemyModule()
if not EnemyClass then
    warn("Không tìm thấy EnemyClass!")
    return
end

-- =============================================
-- PHẦN HIỂN THỊ THÔNG TIN
-- =============================================

local ESPEnabled = false
local ESPHighlights = {}
local AutoRefresh = true

local function ClearConsole()
    if _G.clear then _G.clear() end
end

local function UpdateEnemyInfo()
    ClearConsole()
    
    local enemies = EnemyClass.GetEnemies() or {}
    local liveEnemies = 0
    local bosses = 0
    
    print("=== ENEMY TRACKER ===")
    print("Thời gian:", os.date("%X"))
    print("Tổng số enemy:", #enemies)
    print("-----------------------")
    
    for hash, enemy in pairs(enemies) do
        if enemy:Alive() then
            liveEnemies = liveEnemies + 1
            if enemy:GetIsBoss() then bosses = bosses + 1 end
            
            -- Lấy thông tin cơ bản
            local info = {
                Type = enemy.Type or "Unknown",
                HP = string.format("%d/%d", enemy:GetHealth(), enemy:GetMaxHealth()),
                Shield = enemy:HasShield() and string.format("%d/%d", enemy:GetShield(), enemy:GetMaxShield()) or "None",
                Position = enemy:GetPosition(),
                Distance = (LocalPlayer.Character and LocalPlayer.Character:GetPivot().Position - enemy:GetPosition()).Magnitude or 0,
                Status = (enemy:IsStunned() and "STUN " or "") .. 
                        (enemy:IsStealthed() and "STEALTH " or "") ..
                        (enemy:IsInvulnerable() and "INVUL " or "")
            }
            
            -- Hiển thị thông tin
            print(string.format("[%s] %s", hash:sub(1, 8), info.Type))
            print("HP:", info.HP, "| Shield:", info.Shield)
            print("Pos:", string.format("(%.1f, %.1f, %.1f)", info.Position.X, info.Position.Y, info.Position.Z))
            print("Distance:", string.format("%.1f studs", info.Distance))
            print("Status:", info.Status)
            print("-----------------------")
            
            -- Cập nhật ESP nếu bật
            if ESPEnabled and enemy.Character then
                if not ESPHighlights[hash] then
                    local highlight = Instance.new("Highlight")
                    highlight.FillTransparency = 0.5
                    highlight.OutlineColor = enemy:GetIsBoss() and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
                    highlight.Parent = enemy.Character
                    ESPHighlights[hash] = highlight
                end
            end
        end
    end
    
    print(string.format("ENEMY ĐANG SỐNG: %d (%d boss)", liveEnemies, bosses))
    print("F5: Refresh | F6: Auto-refresh ("..(AutoRefresh and "ON" or "OFF")..") | F7: ESP ("..(ESPEnabled and "ON" or "OFF")..")")
end

-- =============================================
-- PHẦN ĐIỀU KHIỂN
-- =============================================

-- Auto-refresh loop
local autoRefreshConnection
local function ToggleAutoRefresh()
    AutoRefresh = not AutoRefresh
    if AutoRefresh then
        autoRefreshConnection = RunService.Heartbeat:Connect(function()
            UpdateEnemyInfo()
            wait(3) -- Làm mới mỗi 3 giây
        end)
    elseif autoRefreshConnection then
        autoRefreshConnection:Disconnect()
    end
    UpdateEnemyInfo()
end

-- ESP toggle
local function ToggleESP()
    ESPEnabled = not ESPEnabled
    if not ESPEnabled then
        for _, highlight in pairs(ESPHighlights) do
            highlight:Destroy()
        end
        ESPHighlights = {}
    end
    UpdateEnemyInfo()
end

-- Input bindings
game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.F5 then
        UpdateEnemyInfo()
    elseif input.KeyCode == Enum.KeyCode.F6 then
        ToggleAutoRefresh()
    elseif input.KeyCode == Enum.KeyCode.F7 then
        ToggleESP()
    end
end)

-- Khởi động
UpdateEnemyInfo()
if AutoRefresh then
    ToggleAutoRefresh()
end
