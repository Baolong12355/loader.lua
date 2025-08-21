-- Advanced Combat System with Rayfield GUI
-- Updated with improved teleportation mechanism

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player and Character
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- Remote Function
local FireInput = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.MoveInputService.RF.FireInput

-- Game Services - Using the actual game modules
local CombatService = game:GetService("ReplicatedStorage").ReplicatedRoot.Services.CombatService.Client
local ClientCooldown = require(CombatService.ClientCooldown)
local ClientRagdoll = require(CombatService.ClientRagdoll)
local ClientStun = require(CombatService.ClientStun)

-- Loading Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Combat System Variables
local CombatSystem = {
    enabled = false,
    currentTarget = nil,
    waitPositionCultists = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    waitPositionCursed = Vector3.new(-240.7166290283203, 233.30340576171875, 417.1275939941406),
    targetFolders = {"Assailant", "Conjurer", "Roppongi Curse", "Mantis Curse", "Jujutsu Sorcerer", "Flyhead"},
    selectedSkills = {},
    selectedPlusSkills = {}, -- For skills with +
    farmMode = "Cultists", -- "Cultists" or "Cursed"
    isInCombat = false,
    lastM1Time = 0,
    lastM2Time = 0,
    skillCooldowns = {},
    heartbeatConnection = nil
}

-- Status Check Functions using game modules
local function getCooldown(character, skillName)
    if not character then return nil end
    
    -- Try using ClientCooldown service
    local success, result = pcall(function()
        return ClientCooldown.GetCooldown(character, skillName)
    end)
    
    if success and result then
        return result
    end
    
    -- Fallback method
    local cooldownFolder = character:FindFirstChild("Cooldowns")
    if cooldownFolder then
        return cooldownFolder:FindFirstChild(skillName)
    end
    
    return nil
end

local function isRagdolled(character)
    if not character then return false end
    
    -- Try using ClientRagdoll service
    local success, result = pcall(function()
        return ClientRagdoll.IsRagdolled(character)
    end)
    
    if success and result ~= nil then
        return result
    end
    
    -- Fallback
    return character:GetAttribute("Ragdolled") == true
end

local function isStunned(character)
    if not character then return false end
    
    -- Try using ClientStun service
    local success, result = pcall(function()
        return ClientStun.IsStunned(character)
    end)
    
    if success and result ~= nil then
        return result
    end
    
    -- Fallback: check cooldown folder for stun effects
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

-- Improved Target Validation Functions (from second script)
local function isValidTarget(target)
    if not target or not target:IsA("Model") or not target.Parent then
        return false
    end
    
    local humanoidRootPart = target:FindFirstChild("HumanoidRootPart")
    local humanoid = target:FindFirstChild("Humanoid")
    
    return humanoidRootPart and humanoid
end

local function isTargetDead(target)
    if not isValidTarget(target) then
        return true
    end
    
    local humanoid = target:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health <= 0
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
                -- Use improved validation
                if isValidTarget(enemy) and not isTargetDead(enemy) then
                    local distance = (RootPart.Position - enemy.HumanoidRootPart.Position).Magnitude
                    if distance < shortestDistance then
                        shortestDistance = distance
                        nearestEnemy = enemy
                    end
                end
            end
        end
    end
    
    return nearestEnemy
end

-- Improved Movement Functions (from second script approach)
local function instantTP(position)
    local currentChar = Player.Character
    if currentChar and currentChar:FindFirstChild("HumanoidRootPart") then
        currentChar.HumanoidRootPart.CFrame = CFrame.new(position)
    end
end

local function teleportBehindTarget(target)
    if not isValidTarget(target) or isTargetDead(target) then 
        return false
    end
    
    local targetHRP = target.HumanoidRootPart
    local behindPosition = targetHRP.CFrame * CFrame.new(0, 1, 3) -- 3 studs behind, 1 stud up
    
    local currentChar = Player.Character
    if currentChar and currentChar:FindFirstChild("HumanoidRootPart") then
        currentChar.HumanoidRootPart.CFrame = behindPosition
        return true
    end
    return false
end

local function moveToPosition(targetPos, instant)
    instantTP(targetPos)
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
    if not isValidTarget(target) or isTargetDead(target) then
        return false
    end
    
    local currentChar = Player.Character
    if not currentChar or not currentChar:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    -- Use improved teleportation - teleport behind target
    if not teleportBehindTarget(target) then
        return false
    end
    
    -- Face the target
    local targetPos = target.HumanoidRootPart.Position
    local lookDirection = (targetPos - currentChar.HumanoidRootPart.Position).Unit
    currentChar.HumanoidRootPart.CFrame = CFrame.lookAt(currentChar.HumanoidRootPart.Position, targetPos)
    
    local actionTaken = false
    
    -- Priority 1: Always check M1 first (since it recovers fast)
    if not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) then
        while not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) do
            local m1Success = useM1()
            if m1Success then
                wait(0.1) -- Small delay between M1 attacks
                actionTaken = true
            else
                break
            end
        end
    end
    
    -- Priority 2: Use selected skills one by one, checking M1 after each
    for _, skill in pairs(CombatSystem.selectedSkills) do
        if not isOnCooldown(currentChar, skill) and not isRagdolled(currentChar) and not isStunned(currentChar) then
            useSkill(skill)
            actionTaken = true
            
            -- Check M1 again after each skill (since M1 recovers fast)
            if not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) then
                while not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) do
                    local m1Success = useM1()
                    if m1Success then
                        wait(0.1)
                    else
                        break
                    end
                end
            end
        end
    end
    
    -- Priority 3: Use selected plus skills one by one, checking M1 after each
    for _, skill in pairs(CombatSystem.selectedPlusSkills) do
        local plusSkill = skill .. "+"
        if not isOnCooldown(currentChar, plusSkill) and not isRagdolled(currentChar) and not isStunned(currentChar) then
            useSkill(plusSkill)
            actionTaken = true
            
            -- Check M1 again after each plus skill (since M1 recovers fast)
            if not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) then
                while not isOnCooldown(currentChar, "MOUSEBUTTON1") and not isRagdolled(currentChar) and not isStunned(currentChar) do
                    local m1Success = useM1()
                    if m1Success then
                        wait(0.1)
                    else
                        break
                    end
                end
            end
        end
    end
    
    return actionTaken
end

local function escapeToSafety()
    local escapePos = RootPart.Position + Vector3.new(0, 10, 0)
    instantTP(escapePos)
end

-- Main Combat Loop - Improved with continuous teleportation
local function combatLoop()
    if not CombatSystem.enabled then return end
    
    -- Update character references
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
        
        -- Continuously teleport behind target (like second script)
        teleportBehindTarget(target)
        
        -- Attack the target (returns true if any skill was used)
        local skillUsed = attackTarget(target)
        
        -- Check if target is dead/destroyed using improved validation
        if isTargetDead(target) then
            escapeToSafety()
        elseif not skillUsed then
            -- If no skills were used (all on cooldown), just stay behind target
            -- Don't escape, keep following the target
        end
    else
        -- No target found, return to wait position
        CombatSystem.isInCombat = false
        CombatSystem.currentTarget = nil
        local waitPos = CombatSystem.farmMode == "Cultists" and CombatSystem.waitPositionCultists or CombatSystem.waitPositionCursed
        instantTP(waitPos)
    end
end

-- Auto reconnect when character respawns (from second script)
local function onCharacterAdded(newCharacter)
    Character = newCharacter
    RootPart = Character:WaitForChild("HumanoidRootPart")
    Humanoid = Character:WaitForChild("Humanoid")
    
    -- Reconnect combat loop if it was running
    if CombatSystem.enabled and not CombatSystem.heartbeatConnection then
        CombatSystem.heartbeatConnection = RunService.Heartbeat:Connect(combatLoop)
        print("Reconnected combat loop after character respawn")
    end
end

Player.CharacterAdded:Connect(onCharacterAdded)

-- Create Rayfield Window
local Window = Rayfield:CreateWindow({
    Name = "Advanced Combat System",
    Icon = 0,
    LoadingTitle = "Combat System Interface",
    LoadingSubtitle = "by Advanced Scripts",
    ShowText = "Combat System",
    Theme = "DarkBlue",
    
    ToggleUIKeybind = "K",
    
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "CombatSystem",
        FileName = "CombatConfig"
    },
    
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    },
    
    KeySystem = false
})

-- Create Tabs
local MainTab = Window:CreateTab("Main Controls", "zap")
local SkillTab = Window:CreateTab("Skill Selection", "settings")
local StatusTab = Window:CreateTab("Status Monitor", "activity")

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
            -- Start combat system with continuous heartbeat
            CombatSystem.heartbeatConnection = RunService.Heartbeat:Connect(combatLoop)
            print("Combat system started with improved teleportation")
        else
            -- Stop combat system
            if CombatSystem.heartbeatConnection then
                CombatSystem.heartbeatConnection:Disconnect()
                CombatSystem.heartbeatConnection = nil
            end
            print("Combat system stopped")
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

local TargetButton = MainTab:CreateButton({
    Name = "Find and Target Enemy",
    Callback = function()
        local target = findNearestEnemy()
        if target then
            CombatSystem.currentTarget = target
        end
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

-- Status Monitor
local StatusSection = StatusTab:CreateSection("System Status")

local StatusLabel = StatusTab:CreateLabel("Status: Idle", "info")
local TargetLabel = StatusTab:CreateLabel("Target: None", "crosshair")
local HealthLabel = StatusTab:CreateLabel("Health: 100%", "heart")
local CooldownLabel = StatusTab:CreateLabel("Cooldowns: None", "clock")

-- Status Update Loop
RunService.Heartbeat:Connect(function()
    if Character and Character:FindFirstChild("Humanoid") then
        -- Update status
        local status = "Idle"
        if CombatSystem.enabled then
            if isRagdolled(Character) then
                status = "Ragdolled"
            elseif isStunned(Character) then
                status = "Stunned"
            elseif CombatSystem.isInCombat then
                status = "In Combat"
            else
                status = "Active"
            end
        end
        StatusLabel:Set("Status: " .. status, "info")
        
        -- Update target
        local targetName = CombatSystem.currentTarget and CombatSystem.currentTarget.Name or "None"
        TargetLabel:Set("Target: " .. targetName, "crosshair")
        
        -- Update health
        local health = math.floor((Character.Humanoid.Health / Character.Humanoid.MaxHealth) * 100)
        HealthLabel:Set("Health: " .. health .. "%", "heart")
        
        -- Update cooldowns
        local cooldowns = {}
        local cooldownFolder = Character:FindFirstChild("Cooldowns")
        if cooldownFolder then
            for _, cooldown in pairs(cooldownFolder:GetChildren()) do
                table.insert(cooldowns, cooldown.Name)
            end
        end
        local cooldownText = #cooldowns > 0 and table.concat(cooldowns, ", ") or "None"
        CooldownLabel:Set("Cooldowns: " .. cooldownText, "clock")
    end
end)

-- Emergency Stop
MainTab:CreateButton({
    Name = "Emergency Stop",
    Callback = function()
        CombatSystem.enabled = false
        if CombatSystem.heartbeatConnection then
            CombatSystem.heartbeatConnection:Disconnect()
            CombatSystem.heartbeatConnection = nil
        end
        EnableToggle:Set(false)
        print("Emergency stop activated")
    end
})

-- Load Configuration
Rayfield:LoadConfiguration()

-- Global reference for stopping (from second script)
getgenv().stopCombatScript = function()
    CombatSystem.enabled = false
    if CombatSystem.heartbeatConnection then
        CombatSystem.heartbeatConnection:Disconnect()
        CombatSystem.heartbeatConnection = nil
    end
    print("Combat script stopped from console")
end

print("Advanced Combat System loaded with improved teleportation!")
print("Use getgenv().stopCombatScript() to stop from console if needed")