-- Hitbox Hook with Nearest NPC Targeting
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Configuration
local NPC_SEARCH_DISTANCE = 100 -- Maximum distance to search for NPCs

-- Function to check if entity is a player
local function isPlayer(entity)
    return Players:GetPlayerFromCharacter(entity) ~= nil
end

-- Function to find nearest NPC
local function findNearestNPC()
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local playerPosition = character.HumanoidRootPart.Position
    local nearestNPC = nil
    local nearestDistance = math.huge
    
    -- Search in workspace.Living folder
    local livingFolder = Workspace:FindFirstChild("Living")
    if livingFolder then
        for _, entity in ipairs(livingFolder:GetChildren()) do
            if entity:FindFirstChild("Humanoid") and not isPlayer(entity) then
                local rootPart = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity:FindFirstChild("Head")
                if rootPart then
                    local distance = (rootPart.Position - playerPosition).Magnitude
                    if distance < nearestDistance and distance <= NPC_SEARCH_DISTANCE then
                        nearestDistance = distance
                        nearestNPC = entity
                    end
                end
            end
        end
    end
    
    return nearestNPC
end

-- Hitbox Function Hook with Nearest NPC Targeting
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Configuration
local NPC_SEARCH_DISTANCE = 100 -- Maximum distance to search for NPCs

-- Function to check if entity is a player
local function isPlayer(entity)
    return Players:GetPlayerFromCharacter(entity) ~= nil
end

-- Function to find nearest NPC
local function findNearestNPC()
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local playerPosition = character.HumanoidRootPart.Position
    local nearestNPC = nil
    local nearestDistance = math.huge
    
    -- Search in workspace.Living folder
    local livingFolder = Workspace:FindFirstChild("Living")
    if livingFolder then
        for _, entity in ipairs(livingFolder:GetChildren()) do
            if entity:FindFirstChild("Humanoid") and not isPlayer(entity) then
                local rootPart = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity:FindFirstChild("Head")
                if rootPart then
                    local distance = (rootPart.Position - playerPosition).Magnitude
                    if distance < nearestDistance and distance <= NPC_SEARCH_DISTANCE then
                        nearestDistance = distance
                        nearestNPC = entity
                    end
                end
            end
        end
    end
    
    return nearestNPC
end

-- Find and hook the hitbox module
local function hookHitboxModule()
    -- Direct path to the Cast module
    local castModule = game:GetService("ReplicatedStorage").ReplicatedRoot.Services.CombatService.Core.Hitbox.Types.Cast
    
    local success, hitboxModule = pcall(require, castModule)
    if success and hitboxModule.Cast then
        print("Found Cast module at:", castModule:GetFullName())
        
        -- Store original function
        local originalCast = hitboxModule.Cast
        
        -- Hook the function
        hitboxModule.Cast = function(arg1)
            -- Find nearest NPC
            local nearestNPC = findNearestNPC()
            
            if nearestNPC then
                local rootPart = nearestNPC:FindFirstChild("HumanoidRootPart") or nearestNPC:FindFirstChild("Torso") or nearestNPC:FindFirstChild("Head")
                if rootPart then
                    -- Modify the Origin to target the nearest NPC
                    if typeof(arg1.Origin) == "CFrame" then
                        arg1.Origin = rootPart.CFrame
                    elseif typeof(arg1.Origin) == "Vector3" then
                        arg1.Origin = rootPart.Position
                    end
                    
                    print("Hooked Cast function - Targeting:", nearestNPC.Name)
                end
            end
            
            -- Call original function with modified parameters
            return originalCast(arg1)
        end
        
        print("Successfully hooked Cast function!")
        return true
    else
        print("Failed to require Cast module or Cast function not found")
        return false
    end
end

-- Alternative method: Hook by scanning all modules
local function scanAndHookModules()
    local function checkModule(moduleScript)
        local success, module = pcall(require, moduleScript)
        if success and type(module) == "table" and module.Cast then
            print("Found Cast function in:", moduleScript:GetFullName())
            
            -- Store original function
            local originalCast = module.Cast
            
            -- Hook the function
            module.Cast = function(arg1)
                local nearestNPC = findNearestNPC()
                
                if nearestNPC then
                    local rootPart = nearestNPC:FindFirstChild("HumanoidRootPart") or nearestNPC:FindFirstChild("Torso") or nearestNPC:FindFirstChild("Head")
                    if rootPart then
                        if typeof(arg1.Origin) == "CFrame" then
                            arg1.Origin = rootPart.CFrame
                        elseif typeof(arg1.Origin) == "Vector3" then
                            arg1.Origin = rootPart.Position
                        end
                        
                        print("Auto-targeting NPC:", nearestNPC.Name)
                    end
                end
                
                return originalCast(arg1)
            end
            
            return true
        end
        return false
    end
    
    -- Scan ReplicatedStorage
    for _, child in ipairs(game.ReplicatedStorage:GetDescendants()) do
        if child:IsA("ModuleScript") then
            if checkModule(child) then
                print("Successfully hooked Cast function from scan!")
                return true
            end
        end
    end
    
    return false
end

-- Try to hook the function
print("Attempting to hook Cast function...")
if not hookHitboxModule() then
    print("Failed to hook Cast function from direct path")
end