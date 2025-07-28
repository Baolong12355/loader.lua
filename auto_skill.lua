local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- Cấu hình tower đặc biệt
local directionalTowerTypes = {
	["Commander"] = { onlyAbilityIndex = 3 },
	["Toxicnator"] = true,
	["Ghost"] = true,
	["Ice Breaker"] = true,
	["Mobster"] = true,
	["Golden Mobster"] = true,
	["Artillery"] = true,
	["Golden Mine Layer"] = true
}

local skipTowerTypes = {
	["Helicopter"] = true,
	["Cryo Helicopter"] = true,
	["Medic"] = true,
	["Combat Drone"] = true
}

local fastTowers = {
	["Ice Breaker"] = true,
	["John"] = true,
	["Slammer"] = true,
	["Mobster"] = true,
	["Golden Mobster"] = true
}

local skipAirTowers = {
	["Ice Breaker"] = true,
	["John"] = true,
	["Slammer"] = true,
	["Mobster"] = true,
	["Golden Mobster"] = true
}

local lastUsedTime = {}
local mobsterUsedEnemies = {}
local prevCooldown = {}
local medicLastUsedTime = {}
local medicDelay = 0.5 -- Delay tối thiểu giữa các lần dùng skill của mỗi Medic (giây)

-- ======== Hàm chung vị trí, range, cooldown, DPS, kiểm tra buff ========
local function getTowerPos(tower)
	local ok, pos = pcall(function() return tower:GetPosition() end)
	if ok then return pos end
	if tower.Model and tower.Model:FindFirstChild("Root") then
		return tower.Model.Root.Position
	end
	return nil
end

local function getRange(tower)
	local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
	if ok and typeof(result) == "number" then return result end
	if tower.Stats and tower.Stats.Radius then return tower.Stats.Radius * 4 end
	return 0
end

local function GetCurrentUpgradeLevels(tower)
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

local function isCooldownReady(hash, index, ability)
	if not ability then return false end
	local lastCD = (prevCooldown[hash] and prevCooldown[hash][index]) or 0
	local currentCD = ability.CooldownRemaining or 0
	if currentCD > lastCD + 0.1 or currentCD > 0 then
		prevCooldown[hash] = prevCooldown[hash] or {}
		prevCooldown[hash][index] = currentCD
		return false
	end
	prevCooldown[hash] = prevCooldown[hash] or {}
	prevCooldown[hash][index] = currentCD
	return true
end

local function getDPS(tower)
	if not tower or not tower.LevelHandler then return 0 end
	local levelStats = tower.LevelHandler:GetLevelStats()
	local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or {}
	local baseDmg = levelStats.Damage or 0
	local dmgMultiplier = buffStats.DamageMultiplier or 0
	local currentDmg = baseDmg * (1 + dmgMultiplier)
	local reload = tower.GetCurrentReloadTime and tower:GetCurrentReloadTime() or levelStats.ReloadTime or 1
	return (currentDmg / reload)
end

local function isBuffedByMedic(tower)
	if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then return false end
	for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
		local buffName = tostring(buff.Name or "")
		if buffName:match("^MedicKritz") or buffName:match("^MedicGodMode") then
			return true
		end
	end
	return false
end

local function canReceiveBuff(tower)
	return tower and not tower.NoBuffs
end

-- ======== Các hàm target đặc biệt ========
local function getEnemies()
	-- Lấy luôn danh sách enemy mỗi lần gọi, KHÔNG DÙNG CACHE
	local result = {}
	for _, e in pairs(EnemyClass.GetEnemies()) do
		if e and e.IsAlive and not e.IsFakeEnemy then
			table.insert(result, e)
		end
	end
	return result
end

local function getNearestEnemy(pos, range, towerType)
	for _, enemy in ipairs(getEnemies()) do
		if enemy.Type ~= "Arrow" and enemy.GetPosition then
			if skipAirTowers[towerType] and enemy.IsAirUnit then continue end
			local ePos = enemy:GetPosition()
			if (ePos - pos).Magnitude <= range then
				return ePos
			end
		end
	end
	return nil
end

local function getMobsterTarget(tower, hash, path)
	local pos = getTowerPos(tower)
	local range = getRange(tower)
	local maxHP, chosen = -1, nil
	for _, enemy in ipairs(getEnemies()) do
		if enemy.IsAirUnit then continue end
		local id = tostring(enemy)
		if path == 2 and mobsterUsedEnemies[hash] and mobsterUsedEnemies[hash][id] then continue end
		local ePos = enemy:GetPosition()
		if (ePos - pos).Magnitude <= range and enemy.HealthHandler then
			local hp = enemy.HealthHandler:GetMaxHealth()
			if hp > maxHP then
				maxHP = hp
				chosen = enemy
			end
		end
	end
	if chosen and path == 2 then
		mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}
		mobsterUsedEnemies[hash][tostring(chosen)] = true
	end
	return chosen and chosen:GetPosition() or nil
end

local function getCommanderTarget()
	local list = {}
	for _, e in ipairs(getEnemies()) do
		if not e.IsAirUnit and e.Type ~= "Arrow" then table.insert(list, e) end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b)
		return (a.HealthHandler:GetMaxHealth() or 0) > (b.HealthHandler:GetMaxHealth() or 0)
	end)
	if math.random(1, 10) <= 3 then
		return list[1]:GetPosition()
	else
		return list[math.random(1, #list)]:GetPosition()
	end
end

local function getBestMedicTarget(medicTower, ownedTowers)
	local medicPos = getTowerPos(medicTower)
	local medicRange = getRange(medicTower)
	local bestHash, bestDPS = nil, -1
	for hash, tower in pairs(ownedTowers) do
		if tower == medicTower then continue end
		if canReceiveBuff(tower) and not isBuffedByMedic(tower) then
			local towerPos = getTowerPos(tower)
			if towerPos and (towerPos - medicPos).Magnitude <= medicRange then
				local dps = getDPS(tower)
				if dps > bestDPS then
					bestDPS = dps
					bestHash = hash
				end
			end
		end
	end
	return bestHash
end

-- Tìm enemy có HP cao nhất trong range
local function getHighestHpEnemyInRange(pos, range)
	local maxHP, chosen = -1, nil
	for _, e in ipairs(getEnemies()) do
		if e.GetPosition and e.HealthHandler then
			local ePos = e:GetPosition()
			if (ePos - pos).Magnitude <= range then
				local hp = e.HealthHandler:GetMaxHealth()
				if hp > maxHP then
					maxHP = hp
					chosen = e
				end
			end
		end
	end
	return chosen
end

local function SendSkill(hash, index, pos, targetHash)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos, targetHash)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
	end
end

-- ======== MAIN LOOP ========
RunService.Heartbeat:Connect(function()
	local now = tick()
	local ownedTowers = TowerClass.GetTowers() or {}

	for hash, tower in pairs(ownedTowers) do
		if not tower or not tower.AbilityHandler then continue end

		-- Medic đặc biệt với delay riêng biệt
		if tower.Type == "Medic" then
			local _, p2 = GetCurrentUpgradeLevels(tower)
			if p2 >= 4 then
				if medicLastUsedTime[hash] and now - medicLastUsedTime[hash] < medicDelay then continue end
				for index = 1, 3 do
					local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
					if not isCooldownReady(hash, index, ability) then continue end
					local targetHash = getBestMedicTarget(tower, ownedTowers)
					if targetHash then
						SendSkill(hash, index, nil, targetHash)
						medicLastUsedTime[hash] = now
						break -- chỉ dùng 1 lần cho mỗi Medic mỗi lần quét
					end
				end
			end
			continue
		end

		if skipTowerTypes[tower.Type] then continue end

		local delay = fastTowers[tower.Type] and 0.1 or 0.2
		if lastUsedTime[hash] and now - lastUsedTime[hash] < delay then continue end
		lastUsedTime[hash] = now

		local p1, p2 = GetCurrentUpgradeLevels(tower)
		local pos = getTowerPos(tower)
		local range = getRange(tower)

		for index = 1, 3 do
			local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
			if not isCooldownReady(hash, index, ability) then continue end

			local targetPos = nil
			local allowUse = true

			-- Jet Trooper không dùng skill 1
			if tower.Type == "Jet Trooper" and index == 1 then
				allowUse = false
			end

			-- Ghost: skip nếu path 2 > 2
			if tower.Type == "Ghost" then
				if p2 > 2 then
					allowUse = false
					break
				else
					-- giữ logic cũ: target enemy có max HP
					local maxHP, chosen = -1, nil
					for _, e in ipairs(getEnemies()) do
						if e.Type ~= "Arrow" and e.HealthHandler then
							local hp = e.HealthHandler:GetMaxHealth()
							if hp > maxHP then
								maxHP = hp
								chosen = e
							end
						end
					end
					if chosen then SendSkill(hash, index, chosen:GetPosition()) end
					break
				end
			end

			-- Toxicnator: dùng skill lên enemy có HP cao nhất trong range, nếu có
			if tower.Type == "Toxicnator" then
				local targetEnemy = getHighestHpEnemyInRange(pos, range)
				if targetEnemy then
					SendSkill(hash, index, targetEnemy:GetPosition())
				end
				break
			end

			if tower.Type == "Ice Breaker" then
				allowUse = index == 1 or (index == 2 and getNearestEnemy(pos, 8, tower.Type))
			elseif tower.Type == "Slammer" then
				allowUse = getNearestEnemy(pos, range, tower.Type) ~= nil
			elseif tower.Type == "John" then
				allowUse = (p1 >= 5 and getNearestEnemy(pos, range, tower.Type)) or getNearestEnemy(pos, 4.5, tower.Type)
			elseif tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
				if p2 >= 3 and p2 <= 5 then
					targetPos = getMobsterTarget(tower, hash, 2)
					if not targetPos then break end
				elseif p1 >= 4 and p1 <= 5 then
					targetPos = getMobsterTarget(tower, hash, 1)
					if not targetPos then break end
				else
					allowUse = false
				end
			end

			if tower.Type == "Commander" and index == 3 then
				targetPos = getCommanderTarget()
				if not targetPos then break end
			end

			local directional = directionalTowerTypes[tower.Type]
			local sendWithPos = typeof(directional) == "table" and directional.onlyAbilityIndex == index or directional == true

			if not targetPos and sendWithPos then
				targetPos = getNearestEnemy(pos, range, tower.Type)
				if not targetPos then break end
			end

			if allowUse then
				if sendWithPos then
					SendSkill(hash, index, targetPos)
				else
					SendSkill(hash, index)
				end
			end
		end
	end
end)
