local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared")
local ClientFolder = PlayerScripts:WaitForChild("Client")
local GameClassFolder = ClientFolder:WaitForChild("GameClass")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")
local CommonFolder = TDX_Shared:WaitForChild("Common")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local TowerClass = require(GameClassFolder:WaitForChild("TowerClass"))
local EnemyClass = require(GameClassFolder:WaitForChild("EnemyClass"))
local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local Enums = require(CommonFolder:WaitForChild("Enums"))
local NetworkingHandler = require(CommonFolder:WaitForChild("NetworkingHandler"))
local GameStates = Enums.GameStates

_G.CurrentFPSControlledTower = nil
_G.AutoAttackRunning = false
local hasNoEnemySet = false
local currentWeaponIndex = 1

local NEW_SPLASH_RADIUS = 20
local ENABLED_SPLASH = true

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop
local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack

FirstPersonHandler.Begin = function(towerInstance)
    _G.CurrentFPSControlledTower = towerInstance
    _G.AutoAttackRunning = true
    hasNoEnemySet = false
    if towerInstance and towerInstance.Type == "Combat Drone" then
        currentWeaponIndex = 1
    end
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function(...)
    _G.CurrentFPSControlledTower = nil
    _G.AutoAttackRunning = false
    if FirstPersonAttackManager and typeof(FirstPersonAttackManager.ToggleTryAttacking) == "function" then
        FirstPersonAttackManager.ToggleTryAttacking(false)
    end
    hasNoEnemySet = false
    return original_FirstPersonHandler_Stop(...)
end

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

local function LocalPlayerHasCombatDrone()
    if not (TowerClass and typeof(TowerClass.GetTowers) == "function") then return false end
    
    local success, allTowers = pcall(TowerClass.GetTowers)
    if not success or not allTowers then return false end

    for _, tower in pairs(allTowers) do
        if tower and tower.OwnedByLocalPlayer and tower.Type == "Combat Drone" then
            return true
        end
    end
    return false
end

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
            local pathProgress = getEnemyPathProgress(enemy)
            if pathProgress > maxProgress then
                maxProgress = pathProgress
                furthestEnemy = enemy
            end
        end
    end

    if furthestEnemy then
        local targetPosition, hitPart
        if math.random(1, 100) <= 95 then
            local headPart = furthestEnemy.Character and furthestEnemy.Character:GetHead and furthestEnemy.Character:GetHead()
            if headPart then
                targetPosition = headPart.Position
                hitPart = headPart
            end
        end

        if not targetPosition then
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

RunService.Heartbeat:Connect(function()
    -- KIỂM TRA AN TOÀN: Đảm bảo module game đã sẵn sàng trước khi sử dụng
    if not (TowerClass and typeof(TowerClass.GetTowers) == "function") then
        return
    end

    if ENABLED_SPLASH then
        local success, allTowers = pcall(TowerClass.GetTowers)
        if success and allTowers then
            for _, tower in pairs(allTowers) do
                if tower and tower.Type == "Combat Drone" and tower.LevelHandler then
                    local statsSuccess, levelStats = pcall(function() return tower.LevelHandler:GetLevelStats() end)
                    if statsSuccess and levelStats then
                        levelStats.IsSplash = true
                        levelStats.SplashRadius = NEW_SPLASH_RADIUS
                    end
                end
            end
        end
    end

    if not LocalPlayerHasCombatDrone() then
        return
    end

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

    if FirstPersonAttackManager and typeof(FirstPersonAttackManager.ToggleTryAttacking) == "function" then
        if foundEnemy then
            FirstPersonAttackManager.ToggleTryAttacking(true)
            hasNoEnemySet = false
        elseif not hasNoEnemySet then
            FirstPersonAttackManager.ToggleTryAttacking(false)
            hasNoEnemySet = true
        end
    end

    if _G.CurrentFPSControlledTower.Type == "Combat Drone" then
        local desiredWeaponIndex = 2
        for _, enemy in pairs(EnemyClass.GetEnemies()) do
            if enemy and enemy.IsAlive and enemy.DamageReductionTable then
                for _, reductionInfo in ipairs(enemy.DamageReductionTable) do
                    if reductionInfo.DamageType == Enums.DamageTypes.Explosive and reductionInfo.Multiplier >= 0.5 then
                        desiredWeaponIndex = 1
                        break
                    end
                end
                if desiredWeaponIndex == 1 then
                    break
                end
            end
        end

        if desiredWeaponIndex ~= currentWeaponIndex then
            -- KIỂM TRA AN TOÀN: Đảm bảo vũ khí có tồn tại trước khi chuyển
            if FirstPersonAttackManager and typeof(FirstPersonAttackManager.GetAttackHandlerData) == "function" and FirstPersonAttackManager.GetAttackHandlerData(desiredWeaponIndex) then
                local SetIndexRemote = RemotesFolder:WaitForChild("TowerFirstPersonSetIndex")
                SetIndexRemote:FireServer(_G.CurrentFPSControlledTower.Hash, desiredWeaponIndex)
                currentWeaponIndex = desiredWeaponIndex
            end
        end
    end
end)

if NetworkingHandler and typeof(NetworkingHandler.GetEvent) == "function" then
    local event = NetworkingHandler.GetEvent("GameStateChanged")
    if event and typeof(event.AttachCallback) == "function" then
        event:AttachCallback(function(state)
            if state == GameStates.GameOver or state == GameStates.Victory then
                if _G.AutoAttackRunning and _G.CurrentFPSControlledTower then
                    FirstPersonHandler.Stop()
                end
            end
        end)
    end
end

for _, mod in ipairs(getloadedmodules()) do
    if mod and mod.Name == "FirstPersonAttackHandlerClass" then
        local ModuleTable = require(mod)
        if ModuleTable and ModuleTable.New then
            local oldNew = ModuleTable.New
            ModuleTable.New = function(...)
                local obj = oldNew(...)
                obj.DefaultShotInterval = 0.001
                obj.ReloadTime = 0.001
                obj.CurrentFirerateMultiplier = 0.001
                obj.DefaultSpreadDegrees = 0
                return obj
            end
        end
    elseif mod and mod.Name == "FirstPersonCameraHandler" then
        local cameraMod = require(mod)
        if cameraMod then
            if cameraMod.CameraShake then
                cameraMod.CameraShake = function() end
            end
            if cameraMod.ApplyRecoil then
                cameraMod.ApplyRecoil = function() end
            end
        end
    end
end