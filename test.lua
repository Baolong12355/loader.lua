-- Simple Auto Target Script - Chỉ hoạt động khi có DamagePoint
-- Tự động target humanoid gần nhất khi sử dụng skill

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Cài đặt đơn giản
local MAX_RANGE = 50 -- Khoảng cách tối đa
local DAMAGE_POINT_NAME = "DmgPoint" -- Tên damage point

-- Tìm humanoid gần nhất (không tính bản thân)
local function FindNearestHumanoid()
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local myPosition = character.HumanoidRootPart.Position
    local nearestHumanoid = nil
    local nearestDistance = math.huge
    
    -- Duyệt tất cả humanoids trong workspace
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Health > 0 then
            local targetChar = obj.Parent
            local rootPart = targetChar:FindFirstChild("HumanoidRootPart")
            
            -- Bỏ qua bản thân
            if rootPart and targetChar ~= character then
                local distance = (rootPart.Position - myPosition).Magnitude
                
                if distance <= MAX_RANGE and distance < nearestDistance then
                    nearestDistance = distance
                    nearestHumanoid = {
                        humanoid = obj,
                        character = targetChar,
                        position = rootPart.Position,
                        distance = distance
                    }
                end
            end
        end
    end
    
    return nearestHumanoid
end

-- Chuyển damage point đến target
local function RedirectDamagePoint(damagePoint, targetPosition)
    local parent = damagePoint.Parent
    if not parent or not parent:IsA("BasePart") then return end
    
    -- Tính toán vector từ parent đến target
    local parentPosition = parent.Position
    local direction = (targetPosition - parentPosition)
    
    -- Chuyển đổi sang local space của parent
    local localDirection = parent.CFrame:VectorToObjectSpace(direction)
    
    -- Set position của damage point
    damagePoint.Position = localDirection
end

-- Main function - Chỉ chạy khi có damage points
local function CheckAndRedirect()
    local character = LocalPlayer.Character
    if not character then return end
    
    -- Tìm tất cả damage points hiện tại
    local damagePoints = {}
    for _, obj in pairs(character:GetDescendants()) do
        if obj:IsA("Attachment") and obj.Name == DAMAGE_POINT_NAME then
            table.insert(damagePoints, obj)
        end
    end
    
    -- Chỉ hoạt động khi có damage points (đang dùng skill)
    if #damagePoints > 0 then
        local target = FindNearestHumanoid()
        
        if target then
            print("Targeting:", target.character.Name, "Distance:", math.floor(target.distance))
            
            -- Redirect tất cả damage points đến target
            for _, damagePoint in pairs(damagePoints) do
                RedirectDamagePoint(damagePoint, target.position)
            end
        end
    end
end

-- Chạy mỗi frame
local connection = RunService.Heartbeat:Connect(CheckAndRedirect)

-- Cleanup khi character respawn
LocalPlayer.CharacterAdded:Connect(function()
    if connection then
        connection:Disconnect()
    end
    wait(1) -- Đợi character load
    connection = RunService.Heartbeat:Connect(CheckAndRedirect)
end)

print("Auto Target loaded - Chỉ hoạt động khi có DamagePoint")