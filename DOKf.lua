local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ClientFolder = PlayerScripts:WaitForChild("Client")
local GameClassFolder = ClientFolder:WaitForChild("GameClass")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")
local CommonFolder = ReplicatedStorage.TDX_Shared:WaitForChild("Common")

local TowerClass = require(GameClassFolder:WaitForChild("TowerClass"))
local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local EnemyClass = require(GameClassFolder:WaitForChild("EnemyClass"))
local NetworkingHandler = require(CommonFolder:WaitForChild("NetworkingHandler"))
local GameStates = require(CommonFolder:WaitForChild("Enums")).GameStates

local NEW_SPLASH_RADIUS = 20
local ENABLED = true
local patchesApplied = false

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop

_G.CurrentFPSControlledTower = nil
_G.AutoAttackRunning = false
local hasNoEnemySet = false

local function applyPatches()
    if patchesApplied then return end
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
    patchesApplied = true
end

FirstPersonHandler.Begin = function(towerInstance)
    if not patchesApplied then applyPatches() end
    _G.CurrentFPSControlledTower = towerInstance
    _G.AutoAttackRunning = true
    hasNoEnemySet = false
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function()
    if not _G.CurrentFPSControlledTower then return end
    _G.CurrentFPSControlledTower = nil
    _G.AutoAttackRunning = false
    FirstPersonAttackManager.ToggleTryAttacking(false)
    hasNoEnemySet = false
    return original_FirstPersonHandler_Stop()
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

local uiWaveText = nil

RunService.Heartbeat:Connect(function()
    if not patchesApplied then return end

    if not uiWaveText then
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                uiWaveText = gameInfoBar.Wave.WaveText
            end
        end
        return
    end
    
    if uiWaveText and uiWaveText.Text == "Wave 201" then
        if _G.CurrentFPSControlledTower then
            FirstPersonHandler.Stop()
        end
        return
    end

    if ENABLED then
        local allTowers = TowerClass.GetTowers()
        if allTowers then
            for hash, tower in pairs(allTowers) do
                if tower and tower.Type == "Combat Drone" and tower.LevelHandler then
                    local success, levelStats = pcall(function() return tower.LevelHandler:GetLevelStats() end)
                    if success and levelStats then
                        levelStats.IsSplash = true
                        levelStats.SplashRadius = NEW_SPLASH_RADIUS
                    end
                end
            end
        end
    end

    if not _G.AutoAttackRunning or not _G.CurrentFPSControlledTower then return end

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
        FirstPersonAttackManager.ToggleTryAttacking(true)
        hasNoEnemySet = false
        
        local camera = workspace.CurrentCamera
        local headPart = furthestEnemy.Character and furthestEnemy.Character.GetHead and furthestEnemy.Character:GetHead()
        local targetPosition = headPart and headPart.Position or furthestEnemy:GetTorsoPosition()
        
        if targetPosition then
            camera.CFrame = CFrame.new(camera.CFrame.Position, targetPosition)
        end
    elseif not hasNoEnemySet then
        FirstPersonAttackManager.ToggleTryAttacking(false)
        hasNoEnemySet = true
    end
end)

NetworkingHandler.GetEvent("GameStateChanged"):AttachCallback(function(state)
	if state == GameStates.GameOver then
		if _G.CurrentFPSControlledTower then
            FirstPersonHandler.Stop()
        end
	end
end)

applyPatches()