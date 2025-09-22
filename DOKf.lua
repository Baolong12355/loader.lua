local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CommonFolder = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local ClientFolder = PlayerScripts:WaitForChild("Client")
local GameClassFolder = ClientFolder:WaitForChild("GameClass")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")

local Enums = require(CommonFolder:WaitForChild("Enums"))
local TowerClass = require(GameClassFolder:WaitForChild("TowerClass"))
local EnemyClass = require(GameClassFolder:WaitForChild("EnemyClass"))
local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local NetworkingHandler = require(CommonFolder:WaitForChild("NetworkingHandler"))
local GameStates = Enums.GameStates

local SetIndexRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerFirstPersonSetIndex")

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop
local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack

local controlledTower = nil
_G.AutoAttackRunning = false
local currentWeaponIndex = 2
local hasNoEnemySet = false
local NEW_SPLASH_RADIUS = 9999
local SPLASH_ENABLED = true

FirstPersonHandler.Begin = function(towerInstance)
    if shouldStopFPS() then
        return
    end
    
    if towerInstance and towerInstance.Type == "Combat Drone" then
        controlledTower = towerInstance
        _G.AutoAttackRunning = true
        currentWeaponIndex = 2
        hasNoEnemySet = false
    end
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function(...)
    controlledTower = nil
    _G.AutoAttackRunning = false
    FirstPersonAttackManager.ToggleTryAttacking(false)
    hasNoEnemySet = false
    return original_FirstPersonHandler_Stop(...)
end

local function getWaveNumber()
    local interface = PlayerGui:FindFirstChild("Interface")
    if interface then
        local gameInfoBar = interface:FindFirstChild("GameInfoBar")
        if gameInfoBar and gameInfoBar.Wave and gameInfoBar.Wave.WaveText then
            local waveText = gameInfoBar.Wave.WaveText.Text
            return tonumber(waveText:match("(%d+)"))
        end
    end
    return nil
end

local function shouldStopFPS()
    local waveNumber = getWaveNumber()
    return waveNumber and waveNumber >= 201
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

RunService.Heartbeat:Connect(function()
    if shouldStopFPS() and controlledTower then
        FirstPersonHandler.Stop()
        return
    end

    if SPLASH_ENABLED then
        local allTowers = TowerClass.GetTowers()
        if allTowers then
            for hash, tower in pairs(allTowers) do
                if tower and tower.Type == "Combat Drone" then
                    if tower.LevelHandler then
                        local success, levelStats = pcall(function()
                            return tower.LevelHandler:GetLevelStats()
                        end)

NetworkingHandler.GetEvent("GameStateChanged"):AttachCallback(function(state)
    if state == GameStates.GameOver and controlledTower then
        FirstPersonHandler.Stop()
    end
end)

                        if success and levelStats then
                            levelStats.IsSplash = true
                            levelStats.SplashRadius = NEW_SPLASH_RADIUS
                        end
                    end
                end
            end
        end
    end

    if not controlledTower then
        return
    end

    local desiredWeaponIndex = 2
    for _, enemy in pairs(EnemyClass.GetEnemies()) do
        if enemy and enemy.IsAlive and enemy.DamageReductionTable then
            for _, reductionInfo in ipairs(enemy.DamageReductionTable) do
                if reductionInfo.DamageType == Enums.DamageTypes.Explosive and reductionInfo.Multiplier <= 0.5 then
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
        SetIndexRemote:FireServer(controlledTower.Hash, desiredWeaponIndex)
        currentWeaponIndex = desiredWeaponIndex
    end

    if not _G.AutoAttackRunning then
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

task.spawn(function()
    while task.wait(1.5) do
        if shouldStopFPS() then
            if controlledTower then
                FirstPersonHandler.Stop()
            end
            continue
        end

        local combatDrone = nil
        for _, tower in pairs(TowerClass.GetTowers()) do
            if tower.Type == "Combat Drone" then
                combatDrone = tower
                break
            end
        end

        if not combatDrone then continue end

        local shouldActivate = false
        for _, enemy in pairs(EnemyClass.GetEnemies()) do
            if enemy and enemy.IsAlive and not enemy.IsFakeEnemy then
                shouldActivate = true
                break
            end
        end

        local isCurrentlyActive = controlledTower ~= nil

        if shouldActivate and not isCurrentlyActive and FirstPersonHandler.CanBegin() then
            FirstPersonHandler.Begin(combatDrone)
        elseif not shouldActivate and isCurrentlyActive then
            FirstPersonHandler.Stop()
        end
    end
end)

FirstPersonAttackHandlerClass._Attack = function(self)
    local currentTower = controlledTower
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

        if targetChance <= 95 then
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

for _, mod in ipairs(getloadedmodules()) do
    if mod.Name == "FirstPersonAttackHandlerClass" then
        local ModuleTable = require(mod)
        if ModuleTable and ModuleTable.New then
            local oldNew = ModuleTable.New
            ModuleTable.New = function(...)
                local obj = oldNew(...)
                obj.DefaultShotInterval = 0
                obj.ReloadTime = 0.001
                obj.CurrentFirerateMultiplier = 0.0000001
                obj.DefaultSpreadDegrees = 0
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