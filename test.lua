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
    escapeHeight = 30,
    targetType = "cultists",
    currentSkillIndex = 1
}

-- Target Lists
local targetLists = {
    cultists = {
        "workspace.Living.Assailant",
        "workspace.Living.Conjurer",
        "workspace.Living.Assailant"
    },
    cursed = {
        "workspace.Living.Roppongi Curse",
        "workspace.Living.Mantis Curse", 
        "workspace.Living.Jujutsu Sorcerer",
        "workspace.Living.Flyhead"
    }
}

local waitPositions = {
    cultists = Vector3.new(10291.4921875, 6204.5986328125, -255.45745849609375),
    cursed = Vector3.new(-240.7166290283203, 233.30340576171875, 417.1275939941406)
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

local function findRandomTarget()
    local validTargets = {}
    local targetPaths = targetLists[combatSettings.targetType]
    
    for _, path in ipairs(targetPaths) do
        local target = getTargetFromPath(path)
        if isTargetAlive(target) then
            table.insert(validTargets, target)
        end
    end
    
    if #validTargets > 0 then
        return validTargets[math.random(1, #validTargets)]
    end
    
    return nil
end

local function getNextTarget()
    -- Luôn tìm target mới để đánh hết (không giữ target cũ)
    return findRandomTarget()
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
    local behindPos = targetCFrame * CFrame.new(0, 0, 5) -- Ra sau lưng 5 studs
    
    character.HumanoidRootPart.CFrame = behindPos
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
        
        -- Tìm target mỗi frame (chỉ đổi khi target hiện tại chết)
        local target = getNextTarget()
        
        if not target then
            -- Không có target, về vị trí đợi
            local waitPos = waitPositions[combatSettings.targetType]
            teleportToPosition(waitPos)
            isInCombat = false
            shouldEscape = false
            return
        end
        
        currentTarget = target
        isInCombat = true
        
        -- Check nếu bị stun hoặc ragdoll thì escape
        local needEscape = isStunned() or isRagdolled()
        
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
        if tick() - lastSkillUse < 0.3 then return end
        
        -- Logic đơn giản: Dùng 1 skill rồi dùng M1 cho đến cooldown
        if #combatSettings.selectedSkills > 0 then
            -- Dùng skill hiện tại
            local skill = combatSettings.selectedSkills[combatSettings.currentSkillIndex]
            useSkill(skill)
            
            -- Chuyển sang skill tiếp theo
            combatSettings.currentSkillIndex = combatSettings.currentSkillIndex + 1
            if combatSettings.currentSkillIndex > #combatSettings.selectedSkills then
                combatSettings.currentSkillIndex = 1
            end
        end
        
        -- Dùng M1 cho đến khi cooldown
        spawn(function()
            while not hasCooldown("MOUSEBUTTON1") and combatSettings.enabled and isInCombat and not shouldEscape do
                useSkill("MOUSEBUTTON1")
                wait(0.05)
            end
        end)
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
            -- M1 luôn được dùng, chỉ để hiển thị
        end,
    })
    
    local EscapeSlider = MainTab:CreateSlider({
        Name = "Escape Height",
        Range = {10, 50},
        Increment = 5,
        Suffix = "studs",
        CurrentValue = 30,
        Flag = "EscapeHeight",
        Callback = function(Value)
            combatSettings.escapeHeight = Value
        end,
    })
    
    -- Skills Tab
    local SkillsTab = Window:CreateTab("Skills", "zap")
    local Section2 = SkillsTab:CreateSection("Skill Selection")
    
    -- Tạo skills từ A+ đến Z+ và thêm MOUSEBUTTON2
    local skillKeys = {"MOUSEBUTTON2"}
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for i = 1, #alphabet do
        local letter = alphabet:sub(i, i)
        table.insert(skillKeys, letter .. "+")
        table.insert(skillKeys, letter) -- Thêm cả phím thường
    end
    
    for _, key in ipairs(skillKeys) do
        local isDefault = key == "B"
        local displayName = key == "MOUSEBUTTON2" and "M2" or "Skill " .. key
        local flagName = key:gsub("%+", "Plus"):gsub("MOUSEBUTTON2", "M2")
        
        SkillsTab:CreateToggle({
            Name = displayName,
            CurrentValue = isDefault,
            Flag = "Skill" .. flagName,
            Callback = function(Value)
                if Value then
                    if not table.find(combatSettings.selectedSkills, key) then
                        table.insert(combatSettings.selectedSkills, key)
                    end
                else
                    local index = table.find(combatSettings.selectedSkills, key)
                    if index then
                        table.remove(combatSettings.selectedSkills, index)
                        -- Reset skill index nếu cần
                        if combatSettings.currentSkillIndex > #combatSettings.selectedSkills then
                            combatSettings.currentSkillIndex = 1
                        end
                    end
                end
            end,
        })
    end
    
    -- Info Tab
    local InfoTab = Window:CreateTab("Info", "info")
    local Section3 = InfoTab:CreateSection("Current Target")
    
    local TargetLabel = InfoTab:CreateLabel("Target: None")
    
    -- Status update (chỉ target)
    spawn(function()
        while wait(0.5) do
            if combatSettings.enabled then
                TargetLabel:Set("Target: " .. (currentTarget and currentTarget.Name or "None"))
            else
                TargetLabel:Set("Target: None")
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

print("Auto Combat System loaded with Heartbeat Loop!")