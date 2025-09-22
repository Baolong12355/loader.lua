local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GameClass = require(PlayerScripts.Client.GameClass)
local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local CommonFolder = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local ClientFolder = PlayerScripts:WaitForChild("Client")
local GameClassFolder = ClientFolder:WaitForChild("GameClass")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")

local Enums = require(CommonFolder:WaitForChild("Enums"))
local EnemyClass = require(GameClassFolder:WaitForChild("EnemyClass"))
local FirstPersonHandler = require(UserInputHandlerFolder:WaitForChild("FirstPersonHandler"))
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local NetworkingHandler = require(ReplicatedStorage.TDX_Shared.Common:WaitForChild("NetworkingHandler"))
local GameStates = require(ReplicatedStorage.TDX_Shared.Common:WaitForChild("Enums")).GameStates
local SetIndexRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerFirstPersonSetIndex")

local NEW_SPLASH_RADIUS = 20
local ENABLED = true

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop
local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack

_G.CurrentFPSControlledTower = nil
_G.AutoAttackRunning = false
local hasNoEnemySet = false
local controlledTower = nil
local currentWeaponIndex = 1

local function getEnemyPathProgress(enemy)
	if not enemy or not enemy.MovementHandler then return 0 end
	if enemy.MovementHandler.GetPathPercentage then return enemy.MovementHandler:GetPathPercentage() or 0 end
	if enemy.MovementHandler.PathPercentage then return enemy.MovementHandler.PathPercentage or 0 end
	if enemy.MovementHandler.GetCurrentNode then
		local currentNode = enemy.MovementHandler:GetCurrentNode()
		if currentNode and currentNode.GetPercentageAlongPath then
			return currentNode:GetPercentageAlongPath(1) or 0
		end
	end
	return 0
end

FirstPersonHandler.Begin = function(towerInstance)
	_G.CurrentFPSControlledTower = towerInstance
	_G.AutoAttackRunning = true
	hasNoEnemySet = false
	if towerInstance and towerInstance.Type == "Combat Drone" then
		controlledTower = towerInstance
		currentWeaponIndex = 1
	end
	return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function(...)
	_G.CurrentFPSControlledTower = nil
	_G.AutoAttackRunning = false
	FirstPersonAttackManager.ToggleTryAttacking(false)
	hasNoEnemySet = false
	controlledTower = nil
	return original_FirstPersonHandler_Stop(...)
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

RunService.Heartbeat:Connect(function()
	if not ENABLED then return end
	local allTowers = TowerClass.GetTowers()
	if allTowers then
		for _, tower in pairs(allTowers) do
			if tower and tower.Type == "Combat Drone" and tower.LevelHandler then
				local success, levelStats = pcall(function()
					return tower.LevelHandler:GetLevelStats()
				end)
				if success and levelStats then
					levelStats.IsSplash = true
					levelStats.SplashRadius = NEW_SPLASH_RADIUS
				end
			end
		end
	end

	if _G.AutoAttackRunning and _G.CurrentFPSControlledTower then
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
	end

	if controlledTower then
		local desiredWeaponIndex = 2
		for _, enemy in pairs(EnemyClass.GetEnemies()) do
			if enemy and enemy.IsAlive and enemy.DamageReductionTable then
				for _, reductionInfo in ipairs(enemy.DamageReductionTable) do
					if reductionInfo.DamageType == Enums.DamageTypes.Explosive and reductionInfo.Multiplier <= 0.5 then
						desiredWeaponIndex = 1
						break
					end
				end
				if desiredWeaponIndex == 1 then break end
			end
		end
		if desiredWeaponIndex ~= currentWeaponIndex then
			SetIndexRemote:FireServer(controlledTower.Hash, desiredWeaponIndex)
			currentWeaponIndex = desiredWeaponIndex
		end
	end

	if _G.WaveConfig then
		local interface = PlayerGui:FindFirstChild("Interface")
		if interface then
			local gameInfoBar = interface:FindFirstChild("GameInfoBar")
			if gameInfoBar then
				local waveText = gameInfoBar.Wave.WaveText
				local timeText = gameInfoBar.TimeLeft.TimeLeftText
				if waveText and timeText then
					local waveName = waveText.Text
					local currentTime = timeText.Text
					local targetTime = _G.WaveConfig[waveName]
					if targetTime and targetTime > 0 then
						local mins = math.floor(targetTime / 100)
						local secs = targetTime % 100
						local targetTimeStr = string.format("%02d:%02d", mins, secs)
						if currentTime == targetTimeStr then
							ReplicatedStorage.Remotes.SkipWaveVoteCast:FireServer(true)
						end
					end
					if waveName == "Wave 201" then
						FirstPersonHandler.Stop()
					end
				end
			end
		end
	end
end)

for _, mod in ipairs(getloadedmodules()) do
	if mod.Name == "FirstPersonAttackHandlerClass" then
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
	elseif mod.Name == "FirstPersonCameraHandler" then
		local cameraMod = require(mod)
		if cameraMod then
			cameraMod.CameraShake = function() end
			cameraMod.ApplyRecoil = function() end
		end
	end
end

NetworkingHandler.GetEvent("GameStateChanged"):AttachCallback(function(state)
	if state == GameStates.GameOver then
	end
end)