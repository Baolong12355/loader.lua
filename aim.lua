local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

-- trạng thái
_G.CurrentFPSControlledTower = nil
_G.AutoAttackRunning = false
_G.AutoAttackEnabled = false -- MẶC ĐỊNH TẮT (chỉ bật nếu GUI thay đổi)

-- override Begin và Stop
FirstPersonHandler.Begin = function(towerInstance)
    _G.CurrentFPSControlledTower = towerInstance
    _G.AutoAttackRunning = true
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function()
    _G.CurrentFPSControlledTower = nil
    _G.AutoAttackRunning = false
    FirstPersonAttackManager.ToggleTryAttacking(false)
    return original_FirstPersonHandler_Stop()
end

-- heartbeat loop: kiểm tra điều kiện và bật/tắt try attack
RunService.Heartbeat:Connect(function()
    if not _G.AutoAttackEnabled then
        FirstPersonAttackManager.ToggleTryAttacking(false)
        return
    end

    if _G.AutoAttackRunning and _G.CurrentFPSControlledTower then
        for _, enemy in pairs(EnemyClass.GetEnemies()) do
            if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
                FirstPersonAttackManager.ToggleTryAttacking(true)
                return
            end
        end
    end

    FirstPersonAttackManager.ToggleTryAttacking(false)
end)

-- logic silent aim + 95% headshot
FirstPersonAttackHandlerClass._Attack = function(self)
    local tower = _G.CurrentFPSControlledTower
    if not (tower and tower.DirectControlHandler and tower.DirectControlHandler:IsActive()) then
        return original_AttackHandler_Attack(self)
    end

    local towerPosition = tower:GetTorsoPosition() or tower:GetPosition()
    local furthestEnemy = nil
    local maxProgress = -1

    for _, enemy in pairs(EnemyClass.GetEnemies()) do
        if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
            local progress = 0
            if enemy.MovementHandler and enemy.MovementHandler.GetPathPercentage then
                progress = enemy.MovementHandler:GetPathPercentage() or 0
            end
            if progress > maxProgress then
                maxProgress = progress
                furthestEnemy = enemy
            end
        end
    end

    if furthestEnemy then
        local targetChance = math.random(1, 100)
        local targetPosition, hitPart

        if targetChance > 95 then
            -- 5% cơ hội bắn vào thân
            targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
            hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                      or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                      or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
        else
            -- 95% headshot
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
