-- Auto Combat System với GUI
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Vị trí đợi
local waitPositions = {
    Cultists = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    Cursed = Vector3.new(0, 100, 0) -- Thay đổi theo map cursed
}

-- Targets
local targetGroups = {
    Cultists = {"Assailant", "Conjurer"},
    Cursed = {"Roppongi Curse", "Mantis Curse", "Jujutsu Sorcerer", "Flyhead"}
}

-- Combat settings
local settings = {
    enabled = false,
    selectedArea = "Cultists",
    selectedSkills = {"M1"},
    autoTarget = true,
    flyHeight = 10
}

-- Services
local FireInput = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.MoveInputService.RF.FireInput

-- State tracking
local currentTarget = nil
local isStunned = false
local isRagdolled = false
local cooldowns = {}
local heartbeatConnection = nil

-- Utility Functions
local function getCharacter()
    return LocalPlayer.Character
end

local function getHRP()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function isValidTarget(target)
    if not target or not target:FindFirstChild("HumanoidRootPart") then return false end
    local humanoid = target:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health > 0
end

-- Check Status Functions
local function checkStun()
    local char = getCharacter()
    if not char then return false end
    
    -- Check từ stun system
    local stunTable = require(ReplicatedStorage.ReplicatedRoot.Services.StunService.Core.Stun).StunTable
    local stunData = stunTable[char]
    return stunData and next(stunData) ~= nil
end

local function checkRagdoll()
    local char = getCharacter()
    return char and char:GetAttribute("Ragdolled") == true
end

local function checkCooldown(skill)
    local char = getCharacter()
    if not char then return true end
    
    local cooldownFolder = char:FindFirstChild("Cooldowns") or LocalPlayer:FindFirstChild("Cooldowns")
    if not cooldownFolder then return false end
    
    return cooldownFolder:FindFirstChild(skill) ~= nil
end

-- Combat Functions
local function fireSkill(key)
    if checkCooldown(key) then return false end
    
    pcall(function()
        FireInput:InvokeServer(key)
    end)
    
    -- Track cooldown
    cooldowns[key] = tick()
    return true
end

local function findNearestTarget()
    local char = getCharacter()
    local hrp = getHRP()
    if not char or not hrp then return nil end
    
    local targets = targetGroups[settings.selectedArea] or {}
    local nearest = nil
    local shortestDist = math.huge
    
    for _, targetName in pairs(targets) do
        local target = workspace.Living:FindFirstChild(targetName)
        if isValidTarget(target) then
            local dist = (target.HumanoidRootPart.Position - hrp.Position).Magnitude
            if dist < shortestDist then
                shortestDist = dist
                nearest = target
            end
        end
    end
    
    return nearest
end

-- Movement Functions
local function teleportTo(position)
    local hrp = getHRP()
    if hrp then
        hrp.CFrame = CFrame.new(position)
    end
end

local function teleportToTarget(target)
    if not isValidTarget(target) then return end
    
    local targetHRP = target.HumanoidRootPart
    local char = getCharacter()
    
    if char then
        -- Teleport 1 stud trên đầu kẻ địch
        local abovePosition = targetHRP.Position + Vector3.new(0, 1, 0)
        char:SetPrimaryPartCFrame(CFrame.lookAt(abovePosition, targetHRP.Position))
    end
end

local function flyUp()
    local hrp = getHRP()
    if hrp then
        local flyPosition = hrp.Position + Vector3.new(0, settings.flyHeight, 0)
        teleportTo(flyPosition)
    end
end

-- Main Combat Loop
local function combatLoop()
    if not settings.enabled then return end
    
    local char = getCharacter()
    if not char then return end
    
    -- Update status
    isStunned = checkStun()
    isRagdolled = checkRagdoll()
    
    -- Nếu bị stun hoặc ragdoll, bay lên
    if isStunned or isRagdolled then
        flyUp()
        return
    end
    
    -- Tìm target
    currentTarget = findNearestTarget()
    
    if not currentTarget then
        -- Không có target, về vị trí đợi
        local waitPos = waitPositions[settings.selectedArea]
        if waitPos then
            teleportTo(waitPos)
        end
        return
    end
    
    -- Teleport đến target
    teleportToTarget(currentTarget)
    
    -- Sử dụng skills
    for _, skill in pairs(settings.selectedSkills) do
        if skill == "M1" then
            -- M1 spam cho đến cooldown
            if not checkCooldown("MOUSEBUTTON1") then
                fireSkill("MOUSEBUTTON1")
            end
        else
            -- Skills khác chỉ ấn 1 lần nếu hết cooldown
            if not checkCooldown(skill) then
                fireSkill(skill)
            end
        end
    end
end

-- GUI Creation
local Window = Rayfield:CreateWindow({
    Name = "Auto Combat System",
    LoadingTitle = "Combat Bot",
    LoadingSubtitle = "by User",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = nil,
        FileName = "CombatBot"
    },
    Discord = {
        Enabled = false,
    },
    KeySystem = false,
})

local MainTab = Window:CreateTab("Main", 4483362458)

-- Enable Toggle
local EnableToggle = MainTab:CreateToggle({
    Name = "Enable Auto Combat",
    CurrentValue = false,
    Flag = "EnableToggle",
    Callback = function(Value)
        settings.enabled = Value
        
        if Value then
            -- Start combat loop
            heartbeatConnection = RunService.Heartbeat:Connect(combatLoop)
            Rayfield:Notify({
                Title = "Combat Started",
                Content = "Auto combat system enabled",
                Duration = 3,
            })
        else
            -- Stop combat loop
            if heartbeatConnection then
                heartbeatConnection:Disconnect()
                heartbeatConnection = nil
            end
            Rayfield:Notify({
                Title = "Combat Stopped", 
                Content = "Auto combat system disabled",
                Duration = 3,
            })
        end
    end,
})

-- Area Selection
local AreaDropdown = MainTab:CreateDropdown({
    Name = "Select Area",
    Options = {"Cultists", "Cursed"},
    CurrentOption = {"Cultists"},
    MultipleOptions = false,
    Flag = "AreaDropdown",
    Callback = function(Option)
        settings.selectedArea = Option[1]
    end,
})

-- Skill Selection
local skillOptions = {"M1", "M2", "Q", "E", "R", "T", "F", "G", "V", "B", "N", "X", "Z", "C"}
local SkillDropdown = MainTab:CreateDropdown({
    Name = "Select Skills",
    Options = skillOptions,
    CurrentOption = {"M1"},
    MultipleOptions = true,
    Flag = "SkillDropdown", 
    Callback = function(Options)
        settings.selectedSkills = Options
        
        -- Convert skill names to actual keys
        local keyMap = {
            M1 = "MOUSEBUTTON1",
            M2 = "MOUSEBUTTON2"
        }
        
        for i, skill in pairs(settings.selectedSkills) do
            if keyMap[skill] then
                settings.selectedSkills[i] = keyMap[skill]
            end
        end
    end,
})

-- Settings Tab
local SettingsTab = Window:CreateTab("Settings", "settings")

-- Fly Height
local FlySlider = SettingsTab:CreateSlider({
    Name = "Fly Height",
    Range = {5, 50},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = 10,
    Flag = "FlySlider",
    Callback = function(Value)
        settings.flyHeight = Value
    end,
})

-- Status Tab
local StatusTab = Window:CreateTab("Status", "activity")

local StatusLabel = StatusTab:CreateLabel("Status: Waiting...")

-- Manual Controls Tab
local ControlsTab = Window:CreateTab("Controls", "gamepad-2")

local TeleportButton = ControlsTab:CreateButton({
    Name = "Teleport to Wait Position",
    Callback = function()
        local waitPos = waitPositions[settings.selectedArea]
        if waitPos then
            teleportTo(waitPos)
        end
    end,
})

local FindTargetButton = ControlsTab:CreateButton({
    Name = "Find and Teleport to Target",
    Callback = function()
        local target = findNearestTarget()
        if target then
            teleportToTarget(target)
            Rayfield:Notify({
                Title = "Target Found",
                Content = "Teleported to " .. target.Name,
                Duration = 2,
            })
        else
            Rayfield:Notify({
                Title = "No Target",
                Content = "No valid targets found",
                Duration = 2,
            })
        end
    end,
})

-- Status Update Loop
spawn(function()
    while wait(1) do
        if StatusLabel then
            local status = "Disabled"
            if settings.enabled then
                if isStunned then
                    status = "Stunned - Flying Up"
                elseif isRagdolled then
                    status = "Ragdolled - Flying Up"  
                elseif currentTarget then
                    status = "Fighting: " .. currentTarget.Name
                else
                    status = "Waiting for targets..."
                end
            end
            
            StatusLabel:Set("Status: " .. status)
        end
    end
end)

-- Character respawn handling
LocalPlayer.CharacterAdded:Connect(function(character)
    wait(2) -- Wait for character to load
    if settings.enabled and heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = RunService.Heartbeat:Connect(combatLoop)
    end
end)

Rayfield:Notify({
    Title = "Combat System Loaded",
    Content = "Ready to start auto combat",
    Duration = 5,
})

print("Auto Combat System loaded successfully!")