-- Apply weapon modifications function
local function applyWeaponMods()
    for _, mod in ipairs(getloadedmodules()) do
        if mod.Name == "FirstPersonAttackHandlerClass" then
            local ModuleTable = require(mod)
            if ModuleTable and ModuleTable.New then
                local oldNew = ModuleTable.New
                ModuleTable.New = function(...)
                    local obj = oldNew(...)
                    obj.DefaultShotInterval = Config.DefaultShotInterval
                    obj.ReloadTime = Config.ReloadTime
                    obj.CurrentFirerateMultiplier = Config.CurrentFirerateMultiplier
                    obj.DefaultSpreadDegrees = Config.DefaultSpreadDegrees
                    return obj
                end
            end
        elseif mod.Name == "FirstPersonCameraHandler" then
            local cameraMod = require(mod)
            if cameraMod and cameraMod.CameraShake then
                cameraMod.CameraShake = function() end
            end
            if cameraMod and cameraMod.ApplyRecoil then
                cameraMod.ApplyRecoil = function() end
            end
        end
    end
end-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Create Window
local Window = WindUI:CreateWindow({
    Title = "D.O.K",
    Author = "Weapon Tool",
    Folder = "DOK",
    Size = UDim2.fromOffset(320, 400),
    Transparent = false,
    Theme = "Dark",
    Resizable = false,
    SideBarWidth = 100,
})

-- Configuration values
local Config = {
    DefaultShotInterval = 0.001,
    ReloadTime = 0.001,
    CurrentFirerateMultiplier = 0.001,
    DefaultSpreadDegrees = 0,
    SilentAimEnabled = false,
    Enabled = false
}

-- Main Tab
local MainTab = Window:Tab({
    Title = "Cài Đặt",
})

-- Input Fields
local ShotIntervalInput = MainTab:Input({
    Title = "Khoảng Cách Bắn",
    Desc = "Thời gian giữa các phát bắn",
    Value = "0.001",
    Placeholder = "0.001",
    Type = "Input",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.DefaultShotInterval = num
            applyWeaponMods()
            WindUI:Notify({
                Title = "Áp Dụng",
                Content = "Khoảng cách bắn: " .. value,
                Duration = 1,
            })
        end
    end
})

local ReloadTimeInput = MainTab:Input({
    Title = "Thời Gian Nạp Đạn",
    Desc = "Thời gian để nạp đạn",
    Value = "0.001",
    Placeholder = "0.001",
    Type = "Input",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.ReloadTime = num
            applyWeaponMods()
            WindUI:Notify({
                Title = "Áp Dụng",
                Content = "Nạp đạn: " .. value,
                Duration = 1,
            })
        end
    end
})

local FirerateInput = MainTab:Input({
    Title = "Tốc Độ Bắn",
    Desc = "Hệ số nhân tốc độ",
    Value = "0.001",
    Placeholder = "0.001",
    Type = "Input",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.CurrentFirerateMultiplier = num
            applyWeaponMods()
            WindUI:Notify({
                Title = "Áp Dụng",
                Content = "Tốc độ: " .. value,
                Duration = 1,
            })
        end
    end
})

local SpreadInput = MainTab:Input({
    Title = "Độ Giật",
    Desc = "Độ lan tỏa đạn",
    Value = "0",
    Placeholder = "0",
    Type = "Input",
    Callback = function(value)
        local num = tonumber(value)
        if num then
            Config.DefaultSpreadDegrees = num
            WindUI:Notify({
                Title = "Cập Nhật",
                Content = "Độ giật: " .. value,
                Duration = 1,
            })
        end
    end
})

-- Silent Aim Toggle
local SilentAimToggle = MainTab:Toggle({
    Title = "Silent Aim",
    Desc = "Tự động nhắm mục tiêu",
    Default = false,
    Callback = function(state)
        Config.SilentAimEnabled = state
        WindUI:Notify({
            Title = state and "Bật" or "Tắt",
            Content = "Silent Aim " .. (state and "Hoạt động" or "Dừng"),
            Duration = 1,
        })
    end
})

-- Main Toggle (chỉ cho Silent Aim)
local MainToggle = MainTab:Toggle({
    Title = "Silent Aim",
    Desc = "Bật/Tắt tự động nhắm",
    Default = false,
    Callback = function(state)
        Config.SilentAimEnabled = state
        if state then
            loadstring(SilentAimScript)()
            WindUI:Notify({
                Title = "Silent Aim",
                Content = "Đã kích hoạt",
                Duration = 1,
            })
        else
            WindUI:Notify({
                Title = "Silent Aim", 
                Content = "Đã tắt",
                Duration = 1,
            })
        end
    end
})

-- Guide Tab
local GuideTab = Window:Tab({
    Title = "Hướng Dẫn",
})

GuideTab:Paragraph({
    Title = "Cách Sử Dụng",
    Desc = "1. Nhập số vào các ô → tự động áp dụng\n2. Bật Silent Aim nếu muốn tự động bắn\n3. Thông số áp dụng ngay khi nhập",
    Color = "Blue",
})

GuideTab:Paragraph({
    Title = "Khoảng Cách Bắn",
    Desc = "Thời gian giữa phát bắn. Khuyến nghị: 0.001",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Nạp Đạn",
    Desc = "Thời gian nạp đạn. Khuyến nghị: 0.001",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Tốc Độ Bắn",
    Desc = "Hệ số nhân tốc độ. Khuyến nghị: 0.001",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Độ Giật",
    Desc = "Độ lan tỏa đạn. Khuyến nghị: 0 (chính xác)",
    Color = "White",
})

GuideTab:Paragraph({
    Title = "Silent Aim",
    Desc = "Tự động nhắm xa nhất với 95% headshot + auto bắn",
    Color = "Green",
})

-- Silent Aim Script Integration
local SilentAimScript = [[
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local ClientFolder = PlayerScripts:WaitForChild("Client")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")

local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local EnemyClass = require(ClientFolder:WaitForChild("GameClass"):WaitForChild("EnemyClass"))

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop
local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack

_G.CurrentFPSControlledTower = nil
_G.AutoAttackRunning = false
local hasNoEnemySet = false

-- Begin / Stop Tower Control
FirstPersonHandler.Begin = function(towerInstance)
    _G.CurrentFPSControlledTower = towerInstance
    _G.AutoAttackRunning = true
    hasNoEnemySet = false
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function()
    _G.CurrentFPSControlledTower = nil
    _G.AutoAttackRunning = false
    FirstPersonAttackManager.ToggleTryAttacking(false)
    hasNoEnemySet = false
    return original_FirstPersonHandler_Stop()
end

-- Helper: tính tiến độ của enemy
local function getEnemyPathProgress(enemy)
    if not enemy or not enemy.MovementHandler then return 0 end
    
    if enemy.MovementHandler.GetPathPercentage then
        return enemy.MovementHandler:GetPathPercentage() or 0
    end
    
    if enemy.MovementHandler.PathPercentage then
        return enemy.MovementHandler.PathPercentage or 0
    end
    
    if enemy.MovementHandler.GetCurrentNode then
        local currentNode = enemy.MovementHandler:GetCurrentNode()
        if currentNode and currentNode.GetPercentageAlongPath then
            return currentNode:GetPercentageAlongPath(1) or 0
        end
    end

    return 0
end

-- Heartbeat: bật/tắt attack dựa vào enemy targetable
RunService.Heartbeat:Connect(function()
    if not _G.AutoAttackRunning or not _G.CurrentFPSControlledTower then
        return
    end

    local foundEnemy = false
    for _, enemy in pairs(EnemyClass.GetEnemies()) do
        if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
            foundEnemy = true
            break
        end
    end

    if foundEnemy then
        FirstPersonAttackManager.ToggleTryAttacking(true)
        hasNoEnemySet = false
    elseif not hasNoEnemySet then
        FirstPersonAttackManager.ToggleTryAttacking(false)
        hasNoEnemySet = true
    end
end)

-- Override _Attack: chọn enemy đi xa nhất + headshot 95%
FirstPersonAttackHandlerClass._Attack = function(self)
    if not Config.SilentAimEnabled then
        return original_AttackHandler_Attack(self)
    end

    local currentTower = _G.CurrentFPSControlledTower
    if not (currentTower and currentTower.DirectControlHandler and currentTower.DirectControlHandler:IsActive()) then
        return original_AttackHandler_Attack(self)
    end

    local towerPosition = currentTower:GetTorsoPosition() or currentTower:GetPosition()
    local furthestEnemy = nil
    local maxProgress = -1

    for _, enemy in pairs(EnemyClass.GetEnemies()) do
        if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
            local enemyPosition = enemy:GetTorsoPosition() or enemy:GetPosition()
            if enemyPosition and towerPosition then
                local pathProgress = getEnemyPathProgress(enemy)
                if pathProgress > maxProgress then
                    maxProgress = pathProgress
                    furthestEnemy = enemy
                end
            end
        end
    end

    if furthestEnemy then
        local targetChance = math.random(1, 100)
        local targetPosition, hitPart

        if targetChance <= 95 then -- headshot 95%
            local headPart = furthestEnemy.Character and furthestEnemy.Character.GetHead and furthestEnemy.Character:GetHead()
            if headPart then
                targetPosition = headPart.Position
                hitPart = headPart
            else
                targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
                hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                          or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                          or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
            end
        else
            targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
            hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                      or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                      or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
        end

        if hitPart and targetPosition then
            local hitNormal = (targetPosition - towerPosition).Unit
            if self.IsProjectile then
                self:_AttackProjectile(hitPart, targetPosition, hitNormal)
            else
                self:_AttackHitscan(hitPart, targetPosition, hitNormal)
            end

            self:_BurstAttackHandling()
            FirstPersonHandler.Attacked(self.Index, self.UseAbilityName, self.AttackConfig.NoTriggerClientTowerAttacked)
            return
        end
    end

    return original_AttackHandler_Attack(self)
end
]]

-- Apply Silent Aim when toggle is activated
SilentAimToggle.Callback = function(state)
    Config.SilentAimEnabled = state
    if state then
        loadstring(SilentAimScript)()
        WindUI:Notify({
            Title = "Silent Aim",
            Content = "Đã kích hoạt",
            Duration = 1,
        })
    else
        WindUI:Notify({
            Title = "Silent Aim", 
            Content = "Đã tắt",
            Duration = 1,
        })
    end
end