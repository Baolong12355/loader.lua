-- Auto Combat System với Heartbeat Loop
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Services và Remote
local FireInput = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.MoveInputService.RF.FireInput

-- Combat Settings
local combatSettings = {
    enabled = false,
    selectedSkills = {"B"},
    useM1 = true,
    useM2 = false,
    waitPosition = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    escapeHeight = 10,
    targetType = "cultists"
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
local shouldEscape = false
local heartbeatConnection = nil
local combatConnection = nil
local lastSkillTime = {}
local currentSkillIndex = 1
local lastSkillUse = 0

-- Helper Functions
local function getTargetFromPath(path)
    local success, result = pcall(function()
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
    end)
    return success and result or nil
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
    
    local targetCFrame = target.HumanoidRootPart.CFrame
    local behindPos = targetCFrame * CFrame.new(0, 1, 3)
    
    -- Quay mặt xuống để hitbox
    local lookDown = CFrame.Angles(math.rad(-15), 0, 0)
    character.HumanoidRootPart.CFrame = behindPos * lookDown
end

local function escapeToHeight(target)
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    local escapePos
    if isValidTarget(target) then
        escapePos = target.HumanoidRootPart.Position + Vector3.new(0, combatSettings.escapeHeight, 0)
    else
        escapePos = character.HumanoidRootPart.Position + Vector3.new(0, combatSettings.escapeHeight, 0)
    end
    
    character.HumanoidRootPart.CFrame = CFrame.new(escapePos)
end

local function useSkill(skillKey)
    if hasCooldown(skillKey) then return false end
    
    local success = pcall(function()
        FireInput:InvokeServer(skillKey)
    end)
    
    if success then
        lastSkillTime[skillKey] = tick()
        lastSkillUse = tick()
        return true
    end
    
    return false
end

-- Main Heartbeat Loop (giống script ví dụ của bạn)
local function startHeartbeatLoop()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
    end
    
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not combatSettings.enabled then return end
        
        local character = localPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then return end
        
        -- Tìm target mỗi frame
        local target = findNearestTarget()
        
        if not target then
            -- Không có target, về vị trí đợi
            teleportToPosition(combatSettings.waitPosition)
            isInCombat = false
            shouldEscape = false
            return
        end
        
        currentTarget = target
        isInCombat = true
        
        -- Check escape conditions mỗi frame
        local needEscape = isStunned() or isRagdolled()
        
        -- Check nếu tất cả skills on cooldown
        local allSkillsOnCooldown = true
        for _, skill in ipairs(combatSettings.selectedSkills) do
            if not hasCooldown(skill) then
                allSkillsOnCooldown = false
                break
            end
        end
        
        if combatSettings.useM1 and not hasCooldown("MOUSEBUTTON1") then
            allSkillsOnCooldown = false
        end
        
        if allSkillsOnCooldown then
            needEscape = true
        end
        
        -- Teleport logic mỗi frame
        if needEscape then
            shouldEscape = true
            escapeToHeight(target)
        else
            shouldEscape = false
            teleportBehindTarget(target)
        end
    end)
end

-- Combat Skills Loop (riêng biệt để không lag heartbeat)
local function startCombatLoop()
    if combatConnection then
        combatConnection:Disconnect()
    end
    
    combatConnection = RunService.Heartbeat:Connect(function()
        if not combatSettings.enabled or not isInCombat or shouldEscape then return end
        
        -- Chỉ dùng skill khi đã đủ delay (tránh spam)
        if tick() - lastSkillUse < 0.1 then return end
        
        -- Thử dùng skills theo thứ tự
        local skillUsed = false
        for _, skill in ipairs(combatSettings.selectedSkills) do
            if not hasCooldown(skill) then
                if useSkill(skill) then
                    skillUsed = true
                    break
                end
            end
        end
        
        -- Nếu không skill nào dùng được, dùng M1
        if not skillUsed and combatSettings.useM1 and not hasCooldown("MOUSEBUTTON1") then
            useSkill("MOUSEBUTTON1")
        end
        
        -- Nếu M2 enabled và không có gì khác dùng được
        if not skillUsed and combatSettings.useM2 and not hasCooldown("MOUSEBUTTON2") then
            useSkill("MOUSEBUTTON2")
        end
    end)
end

-- GUI Creation
local function createGUI()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    
    local Window = Rayfield:CreateWindow({
        Name = "Auto Combat System",
        LoadingTitle = "Combat System Loading...",
        LoadingSubtitle = "Heartbeat Loop System",
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
                startHeartbeatLoop()
                startCombatLoop()
                print("Combat system started with heartbeat loop!")
            else
                if heartbeatConnection then
                    heartbeatConnection:Disconnect()
                    heartbeatConnection = nil
                end
                if combatConnection then
                    combatConnection:Disconnect()
                    combatConnection = nil
                end
                print("Combat system stopped!")
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
    
    local EscapeSlider = MainTab:CreateSlider({
        Name = "Escape Height",
        Range = {5, 20},
        Increment = 1,
        Suffix = "studs",
        CurrentValue = 10,
        Flag = "EscapeHeight",
        Callback = function(Value)
            combatSettings.escapeHeight = Value
        end,
    })
    
    -- Skills Tab
    local SkillsTab = Window:CreateTab("Skills", "zap")
    local Section2 = SkillsTab:CreateSection("Skill Selection")
    
    local skillKeys = {"Q", "E", "R", "T", "Y", "U", "F", "G", "H", "Z", "X", "C", "V", "B", "N", "M"}
    
    for _, key in ipairs(skillKeys) do
        SkillsTab:CreateToggle({
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
    
    local StatusLabel = InfoTab:CreateLabel("Status: Disabled")
    local TargetLabel = InfoTab:CreateLabel("Target: None")
    local StateLabel = InfoTab:CreateLabel("State: Idle")
    
    -- Status update
    spawn(function()
        while wait(0.5) do
            if combatSettings.enabled then
                local status = isInCombat and "In Combat" or "Waiting"
                StatusLabel:Set("Status: " .. status)
                TargetLabel:Set("Target: " .. (currentTarget and currentTarget.Name or "None"))
                
                local state = "Normal"
                if shouldEscape then
                    state = "Escaping"
                elseif isStunned() then
                    state = "Stunned"
                elseif isRagdolled() then
                    state = "Ragdolled"
                end
                StateLabel:Set("State: " .. state)
            else
                StatusLabel:Set("Status: Disabled")
                TargetLabel:Set("Target: None")
                StateLabel:Set("State: Idle")
            end
        end
    end)
    
    -- Emergency stop button
    MainTab:CreateButton({
        Name = "Emergency Stop",
        Callback = function()
            combatSettings.enabled = false
            if heartbeatConnection then
                heartbeatConnection:Disconnect()
                heartbeatConnection = nil
            end
            if combatConnection then
                combatConnection:Disconnect()
                combatConnection = nil
            end
            print("Emergency stop activated!")
        end,
    })
end

-- Initialize
createGUI()

-- Auto reconnect when character respawns
localPlayer.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart")
    wait(2)
    if combatSettings.enabled then
        startHeartbeatLoop()
        startCombatLoop()
    end
end)

-- Stop function for console
getgenv().stopCombat = function()
    combatSettings.enabled = false
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    if combatConnection then
        combatConnection:Disconnect()
        combatConnection = nil
    end
    print("Combat system stopped from console!")
end

print("Auto Combat System loaded with Heartbeat Loop!")
print("Use getgenv().stopCombat() to stop from console")