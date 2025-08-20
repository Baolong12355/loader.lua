-- Advanced Combat System with Rayfield GUI
-- Generated with enhanced combat mechanics

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
local PathShortcuts = require(game.ReplicatedStorage.ReplicatedModules.PathShortcuts)
local Core = require(game.ReplicatedStorage.ReplicatedRoot.Core)

-- Initialize game services
local CooldownService = nil
local RagdollService = nil  
local StunService = nil

-- Try to get the services from the game
pcall(function()
    CooldownService = require(game.ReplicatedStorage.ReplicatedModules:WaitForChild("Independent"):WaitForChild("CooldownService"))
    RagdollService = require(game.ReplicatedStorage.ReplicatedModules:WaitForChild("Independent"):WaitForChild("RagdollService"))
    StunService = require(game.ReplicatedStorage.ReplicatedModules:WaitForChild("Independent"):WaitForChild("StunService"))
end)

-- Loading Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Combat System Variables
local CombatSystem = {
    enabled = false,
    currentTarget = nil,
    waitPositionCultists = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    waitPositionCursed = Vector3.new(-543.8663330078125, 118.04730224609375, -278.4595031738281),
    targetFolders = {"Assailant", "Conjurer", "Roppongi Curse", "Mantis Curse", "Jujutsu Sorcerer", "Flyhead"},
    selectedSkills = {},
    farmMode = "Cultists", -- "Cultists" or "Cursed"
    isInCombat = false,
    lastM1Time = 0,
    lastM2Time = 0,
    skillCooldowns = {},
    heartbeatConnection = nil
}

-- Status Check Functions using game modules
local function getCooldownFolder(character)
    if not character then return nil end
    
    local player = Players:GetPlayerFromCharacter(character)
    local folder = nil
    
    if player then
        folder = player:FindFirstChild("Cooldowns")
    end
    
    if not folder and character then
        folder = character:FindFirstChild("Cooldowns")
    end
    
    return folder
end

local function getCooldown(character, skillName)
    local folder = getCooldownFolder(character)
    if not folder then return nil end
    return folder:FindFirstChild(skillName)
end

local function isRagdolled(character)
    if not character then return false end
    return character:GetAttribute("Ragdolled") == true
end

local function isStunned(character)
    if not character then return false end
    
    -- Check if StunService exists and use it
    if StunService and StunService.IsStunned then
        local success, result = pcall(function()
            return StunService.IsStunned(character)
        end)
        if success then return result end
    end
    
    -- Fallback: check cooldown folder for stun effects
    local cooldownFolder = getCooldownFolder(character)
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
    
    for _, folderName in pairs(CombatSystem.targetFolders) do
        local folder = workspace.Living:FindFirstChild(folderName)
        if folder then
            for _, enemy in pairs(folder:GetChildren()) do
                if enemy:FindFirstChild("HumanoidRootPart") and enemy:FindFirstChild("Humanoid") then
                    local enemyHumanoid = enemy.Humanoid
                    if enemyHumanoid.Health > 0 then
                        local distance = (RootPart.Position - enemy.HumanoidRootPart.Position).Magnitude
                        if distance < shortestDistance then
                            shortestDistance = distance
                            nearestEnemy = enemy
                        end
                    end
                end
            end
        end
    end
    
    return nearestEnemy
end

-- Movement Functions
local function instantTP(position)
    if RootPart then
        RootPart.CFrame = CFrame.new(position)
    end
end

local function moveToPosition(targetPos, instant)
    if instant then
        instantTP(targetPos)
    else
        if RootPart then
            local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local tween = TweenService:Create(RootPart, tweenInfo, {CFrame = CFrame.new(targetPos)})
            tween:Play()
        end
    end
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
    if not target or not target:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local currentChar = Player.Character
    if not currentChar or not currentChar:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local targetPos = target.HumanoidRootPart.Position
    local attackPos = targetPos + Vector3.new(0, 1, 0) -- 1 stud above target
    
    -- Move to attack position
    moveToPosition(attackPos, true)
    
    -- Face downward for hitbox optimization
    local lookDirection = Vector3.new(0, -1, 0)
    currentChar.HumanoidRootPart.CFrame = CFrame.lookAt(currentChar.HumanoidRootPart.Position, currentChar.HumanoidRootPart.Position + lookDirection)
    
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
    
    -- Priority 2: Use M2 once if not on cooldown
    if not isOnCooldown(currentChar, "MOUSEBUTTON2") and not isRagdolled(currentChar) and not isStunned(currentChar) then
        useM2()
        actionTaken = true
        
        -- Check M1 again after M2 (in case M1 cooldown finished)
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
    
    -- Priority 3: Use selected skills one by one, checking M1 after each
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
    
    return actionTaken
end

local function escapeToSafety()
    local escapePos = RootPart.Position + Vector3.new(0, 10, 0)
    moveToPosition(escapePos, true)
end

-- Main Combat Loop
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
        
        -- Attack the target (returns true if any skill was used)
        local skillUsed = attackTarget(target)
        
        -- If target is dead, escape
        if target.Humanoid.Health <= 0 then
            escapeToSafety()
        end
        -- If no skills were used (all on cooldown), escape temporarily
        if not skillUsed then
            escapeToSafety()
        end
    else
        -- No target found, return to wait position
        CombatSystem.isInCombat = false
        CombatSystem.currentTarget = nil
        local waitPos = CombatSystem.farmMode == "Cultists" and CombatSystem.waitPositionCultists or CombatSystem.waitPositionCursed
        moveToPosition(waitPos, true)
    end
end

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
            -- Start combat system
            CombatSystem.heartbeatConnection = RunService.Heartbeat:Connect(combatLoop)
        else
            -- Stop combat system
            if CombatSystem.heartbeatConnection then
                CombatSystem.heartbeatConnection:Disconnect()
                CombatSystem.heartbeatConnection = nil
            end
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

local availableSkills = {"Q", "E", "R", "F", "Z", "X", "C", "V", "B", "N", "M", "T", "G", "H", "Y", "U", "I", "O", "P"}

for _, skill in pairs(availableSkills) do
    SkillTab:CreateToggle({
        Name = "Use " .. skill .. " Skill",
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
        local cooldownFolder = getCooldownFolder(Character)
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
    end
})

-- Load Configuration
Rayfield:LoadConfiguration()