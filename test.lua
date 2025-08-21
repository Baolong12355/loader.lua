-- Advanced Combat System with Rayfield GUI and Enemy Anchoring
-- Enhanced with target anchoring system

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
    heartbeatConnection = nil,
    
    -- NEW: Anchoring System
    anchorEnabled = false,
    anchorConnection = nil,
    anchorOffset = Vector3.new(0, 1, 0), -- Default: 1 stud above target
    anchorDistance = 5, -- Maximum distance to maintain anchor
    lockRotation = true, -- Lock rotation to face target
    anchorMode = "above" -- "above", "behind", "side", "custom"
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

-- NEW: Anchoring System Functions
local function getAnchorOffset(mode, targetRootPart)
    local offset = Vector3.new(0, 1, 0)
    
    if mode == "above" then
        offset = Vector3.new(0, 3, 0)
    elseif mode == "behind" then
        local lookDirection = targetRootPart.CFrame.LookVector
        offset = -lookDirection * 3 + Vector3.new(0, 1, 0)
    elseif mode == "side" then
        local rightDirection = targetRootPart.CFrame.RightVector
        offset = rightDirection * 3 + Vector3.new(0, 1, 0)
    elseif mode == "custom" then
        offset = CombatSystem.anchorOffset
    end
    
    return offset
end

local function startAnchoring(target)
    if CombatSystem.anchorConnection then
        CombatSystem.anchorConnection:Disconnect()
    end
    
    CombatSystem.anchorConnection = RunService.Heartbeat:Connect(function()
        if not target or not target.Parent then
            stopAnchoring()
            return
        end
        
        local currentChar = Player.Character
        if not currentChar or not currentChar:FindFirstChild("HumanoidRootPart") then
            return
        end
        
        local targetRootPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso")
        if not targetRootPart then
            return
        end
        
        -- Calculate anchor position
        local offset = getAnchorOffset(CombatSystem.anchorMode, targetRootPart)
        local anchorPosition = targetRootPart.Position + offset
        
        -- Check if we need to reposition
        local currentPosition = currentChar.HumanoidRootPart.Position
        local distance = (currentPosition - anchorPosition).Magnitude
        
        if distance > CombatSystem.anchorDistance or distance < 1 then
            currentChar.HumanoidRootPart.CFrame = CFrame.new(anchorPosition)
        end
        
        -- Lock rotation to face target if enabled
        if CombatSystem.lockRotation then
            local lookDirection = (targetRootPart.Position - currentChar.HumanoidRootPart.Position).Unit
            if CombatSystem.anchorMode == "above" then
                lookDirection = Vector3.new(0, -1, 0) -- Look down when above
            end
            currentChar.HumanoidRootPart.CFrame = CFrame.lookAt(currentChar.HumanoidRootPart.Position, currentChar.HumanoidRootPart.Position + lookDirection)
        end
    end)
end

local function stopAnchoring()
    if CombatSystem.anchorConnection then
        CombatSystem.anchorConnection:Disconnect()
        CombatSystem.anchorConnection = nil
    end
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
                -- Check if it's a model
                if enemy:IsA("Model") and enemy.Parent then
                    -- Check if enemy is alive (has Humanoid with health > 0, or just exists if no Humanoid)
                    local humanoid = enemy:FindFirstChild("Humanoid")
                    local isAlive = true
                    
                    if humanoid then
                        isAlive = humanoid.Health > 0
                    end
                    
                    if isAlive then
                        local success, modelCFrame = pcall(function()
                            return enemy:GetModelCFrame()
                        end)
                        
                        if success and modelCFrame then
                            local distance = (RootPart.Position - modelCFrame.Position).Magnitude
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

-- Movement Functions with Heartbeat Loop
local teleportQueue = {}
local teleportConnection = nil

local function startTeleportLoop()
    if teleportConnection then return end
    
    teleportConnection = RunService.Heartbeat:Connect(function()
        if #teleportQueue > 0 then
            local targetPosition = teleportQueue[#teleportQueue]
            teleportQueue = {} -- Clear queue after getting latest position
            
            local currentChar = Player.Character
            if currentChar and currentChar:FindFirstChild("HumanoidRootPart") then
                currentChar.HumanoidRootPart.CFrame = CFrame.new(targetPosition)
            end
        end
    end)
end

local function stopTeleportLoop()
    if teleportConnection then
        teleportConnection:Disconnect()
        teleportConnection = nil
    end
    teleportQueue = {}
end

local function instantTP(position)
    -- Don't queue teleport if anchoring is active
    if not CombatSystem.anchorConnection then
        table.insert(teleportQueue, position)
        startTeleportLoop()
    end
end

local function moveToPosition(targetPos, instant)
    if not CombatSystem.anchorConnection then
        instantTP(targetPos) -- Only move if not anchored
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
    if not target or not target:IsA("Model") then
        return false
    end
    
    -- Find the root part of the target
    local targetRootPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso") or target:FindFirstChild("UpperTorso")
    if not targetRootPart then
        return false
    end
    
    local currentChar = Player.Character
    if not currentChar or not currentChar:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    -- Start anchoring if enabled
    if CombatSystem.anchorEnabled and not CombatSystem.anchorConnection then
        startAnchoring(target)
    end
    
    -- If not anchored, move to attack position
    if not CombatSystem.anchorConnection then
        local targetPos = targetRootPart.Position
        local attackPos = targetPos + Vector3.new(0, 1, 0) -- 1 stud above target
        
        -- Move to attack position
        moveToPosition(attackPos, true)
        
        -- Face downward for hitbox optimization
        local lookDirection = Vector3.new(0, -1, 0)
        currentChar.HumanoidRootPart.CFrame = CFrame.lookAt(currentChar.HumanoidRootPart.Position, currentChar.HumanoidRootPart.Position + lookDirection)
    end
    
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
    stopAnchoring() -- Stop anchoring when escaping
    local escapePos = RootPart.Position + Vector3.new(0, 10, 0)
    instantTP(escapePos)
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
        
        -- Check if target is dead/destroyed
        local targetStillExists = target and target.Parent
        local targetDead = false
        
        if targetStillExists then
            local humanoid = target:FindFirstChild("Humanoid")
            if humanoid then
                targetDead = humanoid.Health <= 0
            end
        else
            targetDead = true -- Target was destroyed/removed
        end
        
        -- If target is dead or doesn't exist, escape
        if targetDead or not targetStillExists then
            escapeToSafety()
        end
        -- If no skills were used (all on cooldown), escape temporarily only if not anchored
        if not skillUsed and not CombatSystem.anchorConnection then
            escapeToSafety()
        end
    else
        -- No target found, stop anchoring and return to wait position
        stopAnchoring()
        CombatSystem.isInCombat = false
        CombatSystem.currentTarget = nil
        local waitPos = CombatSystem.farmMode == "Cultists" and CombatSystem.waitPositionCultists or CombatSystem.waitPositionCursed
        instantTP(waitPos) -- Force position every loop when no target
    end
end

-- Create Rayfield Window
local Window = Rayfield:CreateWindow({
    Name = "Advanced Combat System with Anchoring",
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
local AnchorTab = Window:CreateTab("Anchoring System", "anchor") -- NEW TAB
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
            startTeleportLoop()
        else
            -- Stop combat system
            if CombatSystem.heartbeatConnection then
                CombatSystem.heartbeatConnection:Disconnect()
                CombatSystem.heartbeatConnection = nil
            end
            stopTeleportLoop()
            stopAnchoring()
        end
    end
})

-- NEW: Anchoring Controls Tab
local AnchorSection = AnchorTab:CreateSection("Anchor Settings")

local AnchorToggle = AnchorTab:CreateToggle({
    Name = "Enable Target Anchoring",
    CurrentValue = false,
    Flag = "EnableAnchor",
    Callback = function(Value)
        CombatSystem.anchorEnabled = Value
        if not Value then
            stopAnchoring()
        end
    end
})

local AnchorModeDropdown = AnchorTab:CreateDropdown({
    Name = "Anchor Position Mode",
    Options = {"above", "behind", "side", "custom"},
    CurrentOption = {"above"},
    MultipleOptions = false,
    Flag = "AnchorMode",
    Callback = function(Options)
        CombatSystem.anchorMode = Options[1]
    end
})

local LockRotationToggle = AnchorTab:CreateToggle({
    Name = "Lock Rotation to Target",
    CurrentValue = true,
    Flag = "LockRotation",
    Callback = function(Value)
        CombatSystem.lockRotation = Value
    end
})

local AnchorDistanceSlider = AnchorTab:CreateSlider({
    Name = "Anchor Distance",
    Range = {1, 10},
    Increment = 0.5,
    Suffix = " studs",
    CurrentValue = 5,
    Flag = "AnchorDistance",
    Callback = function(Value)
        CombatSystem.anchorDistance = Value
    end
})

-- Custom Anchor Offset Controls
local CustomSection = AnchorTab:CreateSection("Custom Anchor Offset (when mode = custom)")

local CustomXSlider = AnchorTab:CreateSlider({
    Name = "X Offset",
    Range = {-10, 10},
    Increment = 0.5,
    Suffix = " studs",
    CurrentValue = 0,
    Flag = "CustomX",
    Callback = function(Value)
        CombatSystem.anchorOffset = Vector3.new(Value, CombatSystem.anchorOffset.Y, CombatSystem.anchorOffset.Z)
    end
})

local CustomYSlider = AnchorTab:CreateSlider({
    Name = "Y Offset",
    Range = {-10, 10},
    Increment = 0.5,
    Suffix = " studs",
    CurrentValue = 1,
    Flag = "CustomY",
    Callback = function(Value)
        CombatSystem.anchorOffset = Vector3.new(CombatSystem.anchorOffset.X, Value, CombatSystem.anchorOffset.Z)
    end
})

local CustomZSlider = AnchorTab:CreateSlider({
    Name = "Z Offset",
    Range = {-10, 10},
    Increment = 0.5,
    Suffix = " studs",
    CurrentValue = 0,
    Flag = "CustomZ",
    Callback = function(Value)
        CombatSystem.anchorOffset = Vector3.new(CombatSystem.anchorOffset.X, CombatSystem.anchorOffset.Y, Value)
    end
})

-- Anchor Control Buttons
local AnchorControlSection = AnchorTab:CreateSection("Anchor Controls")

local StartAnchorButton = AnchorTab:CreateButton({
    Name = "Start Anchoring to Current Target",
    Callback = function()
        if CombatSystem.currentTarget then
            startAnchoring(CombatSystem.currentTarget)
        else
            -- Find and anchor to nearest enemy
            local target = findNearestEnemy()
            if target then
                CombatSystem.currentTarget = target
                startAnchoring(target)
            end
        end
    end
})

local StopAnchorButton = AnchorTab:CreateButton({
    Name = "Stop Anchoring",
    Callback = function()
        stopAnchoring()
    end
})

-- Continue with rest of original code...
local WaitPosButton = MainTab:CreateButton({
    Name = "Teleport to Wait Position",
    Callback = function()
        stopAnchoring() -- Stop anchoring when manually moving
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
local AnchorStatusLabel = StatusTab:CreateLabel("Anchor: Inactive", "anchor") -- NEW STATUS

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
        
        -- Update anchor status
        local anchorStatus = CombatSystem.anchorConnection and "Active (" .. CombatSystem.anchorMode .. ")" or "Inactive"
        AnchorStatusLabel:Set("Anchor: " .. anchorStatus, "anchor")
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
        stopTeleportLoop()
        stopAnchoring()
        EnableToggle:Set(false)
    end
})

-- Load Configuration
Rayfield:LoadConfiguration()