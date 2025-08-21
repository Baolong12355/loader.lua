-- Auto Combat System với GUI
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Services và Remote
local FireInput = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.MoveInputService.RF.FireInput

-- Combat Settings
local combatSettings = {
    enabled = false,
    selectedSkills = {"B"}, -- Mặc định chỉ có B
    useM1 = true,
    useM2 = false,
    waitPosition = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    escapeHeight = 10,
    targetType = "cultists" -- cultists hoặc cursed
}

-- Target Lists
local targetLists = {
    cultists = {
        "workspace.Living.Assailant",
        "workspace.Living.Conjurer"
    },
    cursed = {
        "workspace.Living['Roppongi Curse']",
        "workspace.Living['Mantis Curse']", 
        "workspace.Living['Jujutsu Sorcerer']",
        "workspace.Living.Flyhead"
    }
}

-- State Variables
local currentTarget = nil
local isInCombat = false
local isEscaping = false
local combatConnection = nil
local lastSkillTime = {}

-- Helper Functions
local function getTargetFromPath(path)
    local parts = string.split(path, ".")
    local obj = _G
    for i, part in ipairs(parts) do
        if i == 1 and part == "workspace" then
            obj = workspace
        else
            local cleanPart = part:gsub("'", ""):gsub("%[", ""):gsub("%]", "")
            obj = obj:FindFirstChild(cleanPart)
            if not obj then return nil end
        end
    end
    return obj
end

local function isValidTarget(target)
    return target and target:FindFirstChild("HumanoidRootPart") and target:FindFirstChild("Humanoid")
end

local function isTargetAlive(target)
    if not isValidTarget(target) then return false end
    local humanoid = target:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function findNearestTarget()
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local myPos = character.HumanoidRootPart.Position
    local nearest = nil
    local shortestDist = math.huge
    
    local targetPaths = targetLists[combatSettings.targetType]
    
    for _, path in ipairs(targetPaths) do
        local target = getTargetFromPath(path)
        if isTargetAlive(target) then
            local dist = (target.HumanoidRootPart.Position - myPos).Magnitude
            if dist < shortestDist then
                shortestDist = dist
                nearest = target
            end
        end
    end
    
    return nearest
end

local function isStunned()
    local character = localPlayer.Character
    if not character then return false end
    
    -- Check stun attribute hoặc các condition khác
    return character:GetAttribute("Stunned") or false
end

local function isRagdolled()
    local character = localPlayer.Character
    if not character then return false end
    
    return character:GetAttribute("Ragdolled") or false
end

local function hasCooldown(skillKey)
    local character = localPlayer.Character
    if not character then return true end
    
    local cooldownFolder = character:FindFirstChild("Cooldowns")
    if not cooldownFolder then return false end
    
    return cooldownFolder:FindFirstChild(skillKey) ~= nil
end

local function teleportToPosition(position)
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    character.HumanoidRootPart.CFrame = CFrame.new(position)
end

local function teleportBehindTarget(target)
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") or not isValidTarget(target) then return end
    
    local targetPos = target.HumanoidRootPart.CFrame
    local behindPos = targetPos * CFrame.new(0, 1, 3) -- 1 stud trên, 3 studs phía sau
    
    character.HumanoidRootPart.CFrame = behindPos
    
    -- Quay mặt xuống để hitbox
    character.HumanoidRootPart.CFrame = character.HumanoidRootPart.CFrame * CFrame.Angles(math.rad(-15), 0, 0)
end

local function escapeToHeight(target)
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") or not isValidTarget(target) then return end
    
    local targetPos = target.HumanoidRootPart.Position
    local escapePos = targetPos + Vector3.new(0, combatSettings.escapeHeight, 0)
    
    character.HumanoidRootPart.CFrame = CFrame.new(escapePos)
end

local function useSkill(skillKey)
    if hasCooldown(skillKey) then return false end
    
    local success, result = pcall(function()
        return FireInput:InvokeServer(skillKey)
    end)
    
    if success then
        lastSkillTime[skillKey] = tick()
        return true
    end
    
    return false
end

local function waitForCooldown(skillKey)
    while hasCooldown(skillKey) and combatSettings.enabled do
        wait(0.1)
    end
end

-- Main Combat Logic
local function combatLoop()
    while combatSettings.enabled do
        local character = localPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then
            wait(1)
            continue
        end
        
        -- Tìm target
        currentTarget = findNearestTarget()
        
        if not currentTarget then
            -- Không có target, về vị trí đợi
            if not isInCombat then
                teleportToPosition(combatSettings.waitPosition)
                wait(1)
                continue
            end
        end
        
        isInCombat = true
        
        -- Check stun/ragdoll
        if isStunned() or isRagdolled() then
            isEscaping = true
            escapeToHeight(currentTarget)
            wait(0.5)
            continue
        end
        
        isEscaping = false
        
        -- Teleport phía sau target
        teleportBehindTarget(currentTarget)
        
        -- Combat sequence: Skills -> M1 -> Skills -> M1...
        local skillUsed = false
        
        -- Thử dùng skills
        for _, skill in ipairs(combatSettings.selectedSkills) do
            if not hasCooldown(skill) then
                if useSkill(skill) then
                    skillUsed = true
                    waitForCooldown(skill)
                    break
                end
            end
        end
        
        -- Nếu không có skill nào dùng được, dùng M1
        if not skillUsed and combatSettings.useM1 and not hasCooldown("MOUSEBUTTON1") then
            useSkill("MOUSEBUTTON1")
            waitForCooldown("MOUSEBUTTON1")
        end
        
        -- Nếu hết skill hoặc bị stun/ragdoll, escape
        local allSkillsOnCooldown = true
        for _, skill in ipairs(combatSettings.selectedSkills) do
            if not hasCooldown(skill) then
                allSkillsOnCooldown = false
                break
            end
        end
        
        if allSkillsOnCooldown and hasCooldown("MOUSEBUTTON1") then
            escapeToHeight(currentTarget)
            wait(2) -- Đợi cooldown
        end
        
        wait(0.1)
    end
end

-- GUI Creation
local function createGUI()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    
    local Window = Rayfield:CreateWindow({
        Name = "Auto Combat System",
        LoadingTitle = "Combat System Loading...",
        LoadingSubtitle = "by Script Creator",
        Theme = "DarkBlue",
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "CombatSystem",
            FileName = "Config"
        }
    })
    
    -- Main Tab
    local MainTab = Window:CreateTab("Main", "sword")
    
    local Section1 = MainTab:CreateSection("Combat Settings")
    
    local EnableToggle = MainTab:CreateToggle({
        Name = "Enable Combat",
        CurrentValue = false,
        Flag = "EnableCombat",
        Callback = function(Value)
            combatSettings.enabled = Value
            if Value then
                spawn(combatLoop)
            end
        end,
    })
    
    local TargetDropdown = MainTab:CreateDropdown({
        Name = "Target Type",
        Options = {"cultists", "cursed"},
        CurrentOption = {"cultists"},
        Flag = "TargetType",
        Callback = function(Options)
            combatSettings.targetType = Options[1]
        end,
    })
    
    local M1Toggle = MainTab:CreateToggle({
        Name = "Use M1",
        CurrentValue = true,
        Flag = "UseM1",
        Callback = function(Value)
            combatSettings.useM1 = Value
        end,
    })
    
    local M2Toggle = MainTab:CreateToggle({
        Name = "Use M2",
        CurrentValue = false,
        Flag = "UseM2",
        Callback = function(Value)
            combatSettings.useM2 = Value
        end,
    })
    
    -- Skills Tab
    local SkillsTab = Window:CreateTab("Skills", "zap")
    
    local Section2 = SkillsTab:CreateSection("Skill Selection")
    
    local skillKeys = {"Q", "E", "R", "T", "Y", "U", "F", "G", "H", "Z", "X", "C", "V", "B", "N", "M"}
    
    for _, key in ipairs(skillKeys) do
        local toggle = SkillsTab:CreateToggle({
            Name = "Skill " .. key,
            CurrentValue = key == "B",
            Flag = "Skill" .. key,
            Callback = function(Value)
                if Value then
                    if not table.find(combatSettings.selectedSkills, key) then
                        table.insert(combatSettings.selectedSkills, key)
                    end
                else
                    local index = table.find(combatSettings.selectedSkills, key)
                    if index then
                        table.remove(combatSettings.selectedSkills, index)
                    end
                end
            end,
        })
    end
    
    -- Info Tab
    local InfoTab = Window:CreateTab("Info", "info")
    
    local Section3 = InfoTab:CreateSection("Current Status")
    
    local StatusLabel = InfoTab:CreateLabel("Status: Idle")
    local TargetLabel = InfoTab:CreateLabel("Target: None")
    local SkillsLabel = InfoTab:CreateLabel("Selected Skills: B")
    
    -- Update status
    spawn(function()
        while wait(1) do
            if combatSettings.enabled then
                StatusLabel:Set("Status: " .. (isInCombat and "Combat" or "Waiting"))
                TargetLabel:Set("Target: " .. (currentTarget and currentTarget.Name or "None"))
                SkillsLabel:Set("Selected Skills: " .. table.concat(combatSettings.selectedSkills, ", "))
            else
                StatusLabel:Set("Status: Disabled")
            end
        end
    end)
end

-- Initialize
createGUI()

-- Auto reconnect when character respawns
localPlayer.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart")
    wait(2) -- Đợi load xong
end)

print("Auto Combat System loaded!")
print("GUI created with Rayfield")