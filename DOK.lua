-- Load WindUI
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
    
    -- Key System
    KeySystem = {
        Key = { "DOK2025", "DRONE123", "OVERKILL" },
        Note = "Nhập key để sử dụng D.O.K",
        SaveKey = true,
        URL = "https://discord.gg/yourserver",
    },
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
            WindUI:Notify({
                Title = "Cập Nhật",
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
            WindUI:Notify({
                Title = "Cập Nhật",
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
            WindUI:Notify({
                Title = "Cập Nhật",
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

-- Main Toggle
local MainToggle = MainTab:Toggle({
    Title = "Kích Hoạt D.O.K",
    Desc = "Bật/Tắt chế độ sửa đổi",
    Default = false,
    Callback = function(state)
        Config.Enabled = state
        
        if state then
            -- Apply weapon modifications
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
            
            -- Apply Silent Aim if enabled
            if Config.SilentAimEnabled then
                loadstring(game:HttpGet("https://raw.githubusercontent.com/your-repo/silent-aim.lua"))()
            end
            
            WindUI:Notify({
                Title = "Kích Hoạt",
                Content = "D.O.K đang hoạt động",
                Duration = 2,
            })
        else
            WindUI:Notify({
                Title = "Tắt",
                Content = "D.O.K đã dừng",
                Duration = 2,
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
    Desc = "1. Nhập số vào các ô (số nhỏ = mạnh)\n2. Bật Silent Aim nếu muốn\n3. Bật D.O.K để áp dụng",
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
    Desc = "Tự động nhắm vào kẻ địch xa nhất với 99% headshot",
    Color = "Green",
})

-- Silent Aim Script Integration
local SilentAimScript = [[
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local ClientFolder = PlayerScripts:WaitForChild("Client")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")

local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local EnemyClass = require(ClientFolder:WaitForChild("GameClass"):WaitForChild("EnemyClass"))

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop
local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack

_G.CurrentFPSControlledTower = nil

FirstPersonHandler.Begin = function(towerInstance)
    _G.CurrentFPSControlledTower = towerInstance
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function()
    _G.CurrentFPSControlledTower = nil
    return original_FirstPersonHandler_Stop()
end

local function getEnemyPathProgress(enemy)
    if not enemy or not enemy.MovementHandler then
        return 0
    end
    
    if enemy.MovementHandler.GetPathPercentage then
        return enemy.MovementHandler:GetPathPercentage() or 0
    end
    
    if enemy.MovementHandler.PathPercentage then
        return enemy.MovementHandler.PathPercentage or 0
    end
    
    if enemy.MovementHandler.GetCurrentNode and enemy.MovementHandler.GetCurrentNode then
        local currentNode = enemy.MovementHandler:GetCurrentNode()
        if currentNode and currentNode.GetPercentageAlongPath then
            return currentNode:GetPercentageAlongPath(1) or 0
        end
    end
    
    return 0
end

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
        local targetPosition
        local hitPart
        
        if targetChance <= 1 then
            targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
            hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                      or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                      or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
        else
            local headPart = nil
            if furthestEnemy.Character and furthestEnemy.Character.GetHead then
                headPart = furthestEnemy.Character:GetHead()
            end
            
            if headPart then
                targetPosition = headPart.Position
                hitPart = headPart
            else
                targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
                hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                          or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                          or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
            end
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