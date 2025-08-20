-- Auto Aim Hitbox Script
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Lấy CombatService từ ReplicatedRoot
local ReplicatedRoot = ReplicatedStorage.ReplicatedRoot
local CombatService = ReplicatedRoot.Services.CombatService.Core

local function getNearestHumanoid()
    local myCharacter = player.Character
    if not myCharacter or not myCharacter:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local myPosition = myCharacter.HumanoidRootPart.Position
    local nearestHumanoid = nil
    local nearestDistance = math.huge
    
    -- Tìm trong Living folder (từ code decompile)
    local living = Workspace:FindFirstChild("Living")
    if living then
        for _, obj in pairs(living:GetChildren()) do
            if obj:IsA("Model") and obj ~= myCharacter then
                local humanoid = obj:FindFirstChildOfClass("Humanoid")
                local rootPart = obj:FindFirstChild("HumanoidRootPart")
                
                if humanoid and rootPart and humanoid.Health > 0 then
                    local distance = (rootPart.Position - myPosition).Magnitude
                    if distance < nearestDistance then
                        nearestDistance = distance
                        nearestHumanoid = obj
                    end
                end
            end
        end
    end
    
    -- Fallback: tìm trong workspace
    if not nearestHumanoid then
        for _, obj in pairs(Workspace:GetChildren()) do
            if obj:IsA("Model") and obj ~= myCharacter then
                local humanoid = obj:FindFirstChildOfClass("Humanoid")
                local rootPart = obj:FindFirstChild("HumanoidRootPart")
                
                if humanoid and rootPart and humanoid.Health > 0 then
                    local distance = (rootPart.Position - myPosition).Magnitude
                    if distance < nearestDistance and distance < 50 then -- Giới hạn 50 studs
                        nearestDistance = distance
                        nearestHumanoid = obj
                    end
                end
            end
        end
    end
    
    return nearestHumanoid
end

-- Hook vào hitbox system
local function hookHitbox()
    -- Tìm CombatService instance
    local combatServiceInstance = nil
    for _, service in pairs(ReplicatedRoot.Services:GetChildren()) do
        if service.Name == "CombatService" then
            combatServiceInstance = require(service)
            break
        end
    end
    
    if not combatServiceInstance then return end
    
    -- Hook vào _Hitbox function
    local originalHitbox = combatServiceInstance._Hitbox
    if originalHitbox then
        combatServiceInstance._Hitbox = function(hitboxData)
            -- Tìm target gần nhất
            local nearestTarget = getNearestHumanoid()
            
            if nearestTarget and nearestTarget:FindFirstChild("HumanoidRootPart") then
                local targetPosition = nearestTarget.HumanoidRootPart.Position
                local myCharacter = player.Character
                
                if myCharacter and myCharacter:FindFirstChild("HumanoidRootPart") then
                    local myPosition = myCharacter.HumanoidRootPart.Position
                    
                    -- Tính vector từ vị trí hiện tại đến target
                    local direction = (targetPosition - myPosition).Unit
                    local distance = (targetPosition - myPosition).Magnitude
                    
                    -- Điều chỉnh hitbox về phía target
                    if hitboxData and hitboxData.Origin then
                        -- Dịch chuyển Origin của hitbox về phía target
                        local offsetDistance = math.min(distance * 0.8, 20) -- Tối đa 20 studs
                        hitboxData.Origin = hitboxData.Origin + (direction * offsetDistance)
                    end
                    
                    -- Điều chỉnh CFrame nếu có
                    if hitboxData and hitboxData.CFrame then
                        hitboxData.CFrame = CFrame.lookAt(myPosition, targetPosition)
                    end
                end
            end
            
            -- Gọi function gốc với data đã được modify
            return originalHitbox(hitboxData)
        end
    end
end

-- Hook vào Hitbox function chính
local function hookMainHitbox()
    pcall(function()
        local replicatedRoot = ReplicatedStorage.ReplicatedRoot
        local combatCore = replicatedRoot.Services.CombatService.Core
        local hitboxModule = require(combatCore.Hitbox)
        
        -- Backup function gốc
        if not _G.OriginalHitboxFunction then
            _G.OriginalHitboxFunction = hitboxModule.Hitbox
        end
        
        -- Override Hitbox function
        hitboxModule.Hitbox = function(self, hitboxData)
            -- Auto aim logic
            local nearestTarget = getNearestHumanoid()
            
            if nearestTarget and nearestTarget:FindFirstChild("HumanoidRootPart") then
                local targetPos = nearestTarget.HumanoidRootPart.Position
                local myChar = player.Character
                
                if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                    local myPos = myChar.HumanoidRootPart.Position
                    local direction = (targetPos - myPos).Unit
                    local distance = (targetPos - myPos).Magnitude
                    
                    -- Modify hitbox data
                    if hitboxData then
                        -- Điều chỉnh vị trí hitbox
                        if distance < 30 then -- Chỉ aim nếu trong phạm vi 30 studs
                            local offset = direction * math.min(distance * 0.7, 15)
                            
                            if hitboxData.Origin then
                                hitboxData.Origin = hitboxData.Origin + offset
                            end
                            
                            if hitboxData.CFrame then
                                hitboxData.CFrame = CFrame.lookAt(myPos, targetPos)
                            end
                        end
                    end
                end
            end
            
            -- Gọi function gốc
            return _G.OriginalHitboxFunction(self, hitboxData)
        end
    end)
end

-- Khởi tạo auto aim
spawn(function()
    wait(3) -- Đợi game load
    hookMainHitbox()
end)

-- Player character respawn handling
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    wait(2)
    hookMainHitbox()
end)

_G.ToggleAutoAim = function()
    if _G.AutoAimEnabled == nil then _G.AutoAimEnabled = true end
    _G.AutoAimEnabled = not _G.AutoAimEnabled
    print("Auto Aim:", _G.AutoAimEnabled and "ON" or "OFF")
end

print("Auto Aim Hitbox loaded! Use _G.ToggleAutoAim() to toggle")