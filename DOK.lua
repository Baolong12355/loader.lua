local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local ClientFolder = PlayerScripts:WaitForChild("Client")
local GameClassFolder = ClientFolder:WaitForChild("GameClass")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")
local CommonFolder = ReplicatedStorage.TDX_Shared:WaitForChild("Common")

local TowerClass = require(GameClassFolder:WaitForChild("TowerClass"))
local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local EnemyClass = require(GameClassFolder:WaitForChild("EnemyClass"))
local ProjectileHandler = require(GameClassFolder:WaitForChild("ProjectileHandler"))
local Enums = require(CommonFolder:WaitForChild("Enums"))

local NEW_SPLASH_RADIUS = 9999
local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop

_G.CurrentFPSControlledTower = nil
local hasNoEnemySet = false
local isHooked = false

local function ApplyHooks()
    if isHooked then return end
    isHooked = true

    local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack
    FirstPersonAttackHandlerClass._Attack = function(self)
        local currentTower = _G.CurrentFPSControlledTower
        if not (currentTower and currentTower.DirectControlHandler and currentTower.DirectControlHandler:IsActive()) then
            return original_AttackHandler_Attack(self)
        end
        local towerPosition = currentTower:GetTorsoPosition() or currentTower:GetPosition()
        local furthestEnemy = nil
        local maxProgress = -1
        for _, enemy in pairs(EnemyClass.GetEnemies()) do
            if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
                local pathProgress = (pcall(function() return enemy.MovementHandler:GetPathPercentage() end) and enemy.MovementHandler:GetPathPercentage() or 0)
                if pathProgress > maxProgress then
                    maxProgress = pathProgress
                    furthestEnemy = enemy
                end
            end
        end
        if furthestEnemy then
            local targetPosition, hitPart
            local headPart = furthestEnemy.Character and furthestEnemy.Character.GetHead and furthestEnemy.Character:GetHead()
            if headPart then
                targetPosition = headPart.Position
                hitPart = headPart
            else
                targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
                hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso()
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
    
    local original_NewProjectile = ProjectileHandler.NewProjectile
    ProjectileHandler.NewProjectile = function(initData)
        if _G.CurrentFPSControlledTower and initData and initData.OriginHash == _G.CurrentFPSControlledTower.Hash then
            local furthestEnemy = nil; local maxProgress = -1
            for _, enemy in pairs(EnemyClass.GetEnemies()) do
                if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
                    local pathProgress = (pcall(function() return enemy.MovementHandler:GetPathPercentage() end) and enemy.MovementHandler:GetPathPercentage() or 0)
                    if pathProgress > maxProgress then maxProgress = pathProgress; furthestEnemy = enemy end
                end
            end
            if furthestEnemy then
                initData.TargetHash = furthestEnemy.Hash
                initData.TargetEntityClass = "Enemy"
                initData.OverrideGoalPosition = furthestEnemy:GetTorsoPosition()
                initData.ForceTrackCharacter = true
            end
        end
        return original_NewProjectile(initData)
    end

    for _, mod in ipairs(getloadedmodules()) do
        if mod.Name == "FirstPersonAttackHandlerClass" then
            pcall(function()
                local ModuleTable = require(mod)
                if ModuleTable and ModuleTable.New then
                    local oldNew = ModuleTable.New
                    ModuleTable.New = function(...)
                        local obj = oldNew(...)
                        obj.DefaultShotInterval = 0.001
                        obj.ReloadTime = 0.001
                        obj.CurrentFirerateMultiplier = 0.001
                        obj.DefaultSpreadDegrees = 0
                        obj.DamageType = Enums.DamageTypes.Toxic 
                        if obj.AttackConfig and obj.AttackConfig.DamageData and obj.AttackConfig.DamageData.StunData then
                            obj.AttackConfig.DamageData.StunData.StunDuration = 99999999
                        end
                        return obj
                    end
                end
            end)
        elseif mod.Name == "FirstPersonCameraHandler" then
            pcall(function()
                local cameraMod = require(mod)
                if cameraMod then
                    if cameraMod.CameraShake then cameraMod.CameraShake = function() end end
                    if cameraMod.ApplyRecoil then cameraMod.ApplyRecoil = function() end end
                end
            end)
        end
    end
end

FirstPersonHandler.Begin = function(towerInstance)
    ApplyHooks() 
    _G.CurrentFPSControlledTower = towerInstance
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function(...)
    if not _G.CurrentFPSControlledTower then return end
    _G.CurrentFPSControlledTower = nil
    FirstPersonAttackManager.ToggleTryAttacking(false)
    hasNoEnemySet = false
    return original_FirstPersonHandler_Stop(...)
end

RunService.Heartbeat:Connect(function()
    pcall(function()
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower and tower.Type == "Combat Drone" and tower.OwnedByLocalPlayer and tower.LevelHandler then
                local levelStats = tower.LevelHandler:GetLevelStats()
                if levelStats then
                    levelStats.IsSplash = true
                    levelStats.SplashRadius = NEW_SPLASH_RADIUS
                end
            end
        end
    end)

    if not _G.CurrentFPSControlledTower then return end

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