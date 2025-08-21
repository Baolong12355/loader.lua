-- Advanced Combat System with Rayfield GUI
-- Generated with enhanced combat mechanics

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Player and Character
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- Remote Function
local FireInput = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.MoveInputService.RF.FireInput

-- Combat System Variables
local CombatSystem = {
    enabled = false,
    currentTarget = nil,
    waitPositionCultists = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    waitPositionCursed = Vector3.new(-240.7166290283203, 233.30340576171875, 417.1275939941406),
    targetFolders = {"Assailant", "Conjurer", "Roppongi Curse", "Mantis Curse", "Jujutsu Sorcerer", "Flyhead"},
    selectedSkills = {},
    selectedPlusSkills = {},
    farmMode = "Cultists",
    isInCombat = false,
    heartbeatConnection = nil,
    teleportConnection = nil
}

-- ==================== TELEPORT FUNCTIONS ====================
local function isValidTarget(target)
    return target and target:FindFirstChild("HumanoidRootPart") and target:FindFirstChild("Humanoid")
end

local function isTargetDead(target)
    local humanoid = target:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health <= 0
end

-- Teleport ra sau lưng target (KHÔNG DÙNG TWEEN)
local function teleportBehindTarget(target)
    if not CombatSystem.enabled or not isValidTarget(target) or isTargetDead(target) then return end
    
    local currentChar = Player.Character
    if not currentChar or not currentChar:FindFirstChild("HumanoidRootPart") then return end
    
    local targetHRP = target.HumanoidRootPart
    local behindPosition = targetHRP.CFrame * CFrame.new(0, 0, 3)
    
    -- TELEPORT TRỰC TIẾP - KHÔNG TWEEN
    currentChar.HumanoidRootPart.CFrame = behindPosition
end

-- Teleport đến vị trí (KHÔNG DÙNG TWEEN)
local function instantTP(position)
    local currentChar = Player.Character
    if currentChar and currentChar:FindFirstChild("HumanoidRootPart") then
        currentChar.HumanoidRootPart.CFrame = CFrame.new(position)
    end
end

local function startTeleportLoop()
    if CombatSystem.teleportConnection then return end
    
    CombatSystem.teleportConnection = RunService.Heartbeat:Connect(function()
        if CombatSystem.enabled and CombatSystem.currentTarget then
            teleportBehindTarget(CombatSystem.currentTarget)
        end
    end)
end

local function stopTeleportLoop()
    if CombatSystem.teleportConnection then
        CombatSystem.teleportConnection:Disconnect()
        CombatSystem.teleportConnection = nil
    end
end
-- ==================== END TELEPORT FUNCTIONS ====================

-- Status Check Functions
local function getCooldown(character, skillName)
    if not character then return nil end
    local cooldownFolder = character:FindFirstChild("Cooldowns")
    if cooldownFolder then
        return cooldownFolder:FindFirstChild(skillName)
    end
    return nil
end

local function isRagdolled(character)
    if not character then return false end
    return character:GetAttribute("Ragdolled") == true
end

local function isStunned(character)
    if not character then return false end
    local cooldownFolder = character:FindFirstChild("Cooldowns")
    if not cooldownFolder then return false end
    
    for _, child in pairs(cooldownFolder:GetChildren()) do
        if child.Name:lower():find("stun") then
            return true
        end
    end
    return false
end

local function isOnCooldown(character, skillName)
    return getCooldown(character, skillName) ~= nil
end

-- Target Management
local function findNearestEnemy()
    local nearestEnemy = nil
    local shortestDistance = math.huge
    
    if not RootPart then return nil end
    
    for _, folderName in pairs(CombatSystem.targetFolders) do
        local folder = workspace.Living:FindFirstChild(folderName)
        if folder then
            for _, enemy in pairs(folder:GetChildren()) do
                if enemy:IsA("Model") and enemy.Parent then
                    local humanoid = enemy:FindFirstChild("Humanoid")
                    local isAlive = true
                    
                    if humanoid then
                        isAlive = humanoid.Health > 0
                    end
                    
                    if isAlive then
                        local hrp = enemy:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local distance = (RootPart.Position - hrp.Position).Magnitude
                            if distance < shortestDistance then
                                shortestDistance = distance
                                nearestEnemy = enemy
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nearestEnemy
end

-- Combat Functions
local function useSkill(skillKey)
    local currentChar = Player.Character
    if not currentChar then return false end
    
    if isOnCooldown(currentChar, skillKey) or isRagdolled(currentChar) or isStunned(currentChar) then
        return false
    end
    
    pcall(function()
        FireInput:InvokeServer(skillKey)
    end)
    
    return true
end

local function useM1()
    return useSkill("MOUSEBUTTON1")
end

local function useM2()
    return useSkill("MOUSEBUTTON2")
end

local function attackTarget(target)
    if not target or not target:IsA("Model") then return false end
    
    local currentChar = Player.Character
    if not currentChar or not currentChar:FindFirstChild("HumanoidRootPart") then return false end
    
    local actionTaken = false
    
    -- Priority 1: M1 spam
    if not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) then
        local m1Success = useM1()
        if m1Success then
            actionTaken = true
        end
    end
    
    -- Priority 2: Selected skills
    for _, skill in pairs(CombatSystem.selectedSkills) do
        if not isOnCooldown(currentChar, skill) and not isRagdolled(currentChar) and not isStunned(currentChar) then
            useSkill(skill)
            actionTaken = true
            break -- Chỉ dùng 1 skill mỗi frame
        end
    end
    
    -- Priority 3: Plus skills
    for _, skill in pairs(CombatSystem.selectedPlusSkills) do
        local plusSkill = skill .. "+"
        if not isOnCooldown(currentChar, plusSkill) and not isRagdolled(currentChar) and not isStunned(currentChar) then
            useSkill(plusSkill)
            actionTaken = true
            break -- Chỉ dùng 1 skill mỗi frame
        end
    end
    
    return actionTaken
end

local function escapeToSafety()
    local escapePos = RootPart.Position + Vector3.new(0, 10, 0)
    instantTP(escapePos)
end

-- Main Combat Loop
local function combatLoop()
    if not CombatSystem.enabled then return end
    
    Character = Player.Character
    if not Character then return end
    
    RootPart = Character:FindFirstChild("HumanoidRootPart")
    if not RootPart then return end
    
    -- Check for escape conditions
    if isRagdolled(Character) or isStunned(Character) then
        escapeToSafety()
        return
    end
    
    -- Find target
    local target = findNearestEnemy()
    
    if target then
        CombatSystem.currentTarget = target
        CombatSystem.isInCombat = true
        
        -- Attack the target
        local skillUsed = attackTarget(target)
        
        -- Check if target is dead
        local targetDead = false
        if target and target.Parent then
            local humanoid = target:FindFirstChild("Humanoid")
            if humanoid then
                targetDead = humanoid.Health <= 0
            end
        else
            targetDead = true
        end
        
        if targetDead then
            CombatSystem.currentTarget = nil
        end
    else
        CombatSystem.isInCombat = false
        CombatSystem.currentTarget = nil
        local waitPos = CombatSystem.farmMode == "Cultists" and CombatSystem.waitPositionCultists or CombatSystem.waitPositionCursed
        instantTP(waitPos)
    end
end

-- Create Rayfield Window
local Window = Rayfield:CreateWindow({
    Name = "Advanced Combat System",
    LoadingTitle = "Combat System Interface",
    LoadingSubtitle = "by Advanced Scripts",
    Theme = "DarkBlue",
    ToggleUIKeybind = "K",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "CombatSystem",
        FileName = "CombatConfig"
    }
})

-- Create Tabs
local MainTab = Window:CreateTab("Main Controls", "zap")
local SkillTab = Window:CreateTab("Skill Selection", "settings")

-- Main Controls
local FarmModeDropdown = MainTab:CreateDropdown({
    Name = "Farm Mode",
    Options = {"Cultists","Cursed"},
    CurrentOption = {"Cultists"},
    MultipleOptions = false,
    Flag = "FarmMode",
    Callback = function(Options)
        CombatSystem.farmMode = Options[1]
    end
})

local EnableToggle = MainTab:CreateToggle({
    Name = "Enable Combat System",
    CurrentValue = false,
    Flag = "EnableCombat",
    Callback = function(Value)
        CombatSystem.enabled = Value
        
        if Value then
            CombatSystem.heartbeatConnection = RunService.Heartbeat:Connect(combatLoop)
            startTeleportLoop()
        else
            if CombatSystem.heartbeatConnection then
                CombatSystem.heartbeatConnection:Disconnect()
                CombatSystem.heartbeatConnection = nil
            end
            stopTeleportLoop()
        end
    end
})

local WaitPosButton = MainTab:CreateButton({
    Name = "Teleport to Wait Position",
    Callback = function()
        local waitPos = CombatSystem.farmMode == "Cultists" and CombatSystem.waitPositionCultists or CombatSystem.waitPositionCursed
        instantTP(waitPos)
    end
})

-- Skill Selection
local SkillSection = SkillTab:CreateSection("Select Skills to Use")

local availableSkills = {"MOUSEBUTTON2", "Q", "E", "R", "F", "Z", "X", "C", "V", "B", "N", "M", "T", "G", "H", "Y", "U", "I", "O", "P"}

for _, skill in pairs(availableSkills) do
    local displayName = skill == "MOUSEBUTTON2" and "M2" or skill
    SkillTab:CreateToggle({
        Name = "Use " .. displayName .. " Skill",
        CurrentValue = false,
        Flag = "Skill" .. skill,
        Callback = function(Value)
            if Value then
                if not table.find(CombatSystem.selectedSkills, skill) then
                    table.insert(CombatSystem.selectedSkills, skill)
                end
            else
                local index = table.find(CombatSystem.selectedSkills, skill)
                if index then
                    table.remove(CombatSystem.selectedSkills, index)
                end
            end
        end
    })
end

local PlusSkillSection = SkillTab:CreateSection("Select Plus Skills to Use")

local availablePlusSkills = {"Q", "E", "R", "F", "Z", "X", "C", "V", "B", "N", "M", "T", "G", "H", "Y", "U", "I", "O", "P"}

for _, skill in pairs(availablePlusSkills) do
    SkillTab:CreateToggle({
        Name = "Use " .. skill .. "+ Skill",
        CurrentValue = false,
        Flag = "PlusSkill" .. skill,
        Callback = function(Value)
            if Value then
                if not table.find(CombatSystem.selectedPlusSkills, skill) then
                    table.insert(CombatSystem.selectedPlusSkills, skill)
                end
            else
                local index = table.find(CombatSystem.selectedPlusSkills, skill)
                if index then
                    table.remove(CombatSystem.selectedPlusSkills, index)
                end
            end
        end
    })
end

-- Emergency Stop
MainTab:CreateButton({
    Name = "Emergency Stop",
    Callback = function()
        CombatSystem.enabled = false
        if CombatSystem.heartbeatConnection then
            CombatSystem.heartbeatConnection:Disconnect()
            CombatSystem.heartbeatConnection = nil
        end
        stopTeleportLoop()
        EnableToggle:Set(false)
    end
})

-- Load Configuration
Rayfield:LoadConfiguration()

print("Combat System Loaded! - No Tween, Better Performance")