local HttpService = game:GetService("HttpService")
local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local TowersFolder = game:GetService("Workspace"):WaitForChild("Game"):WaitForChild("Towers")
local player = game.Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local macro = HttpService:JSONDecode(readfile("tdx/macros/y.json"))

local placedIndex = 1

-- So sánh gần đúng vị trí
local function samePos(a, b)
	return (a - b).Magnitude < 0.05
end

-- Đếm số tower theo tên
local function countTowerByName(name)
	local count = 0
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		if tower.Name == name then
			count += 1
		end
	end
	return count
end

-- Tìm tower mới được thêm vào
local function findNewTower(name, beforeCount)
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		if tower.Name == name then
			beforeCount -= 1
			if beforeCount < 0 then
				return tower
			end
		end
	end
	return nil
end

-- Đợi đủ tiền
local function waitUntilCashEnough(amount)
	while cashStat.Value < amount do task.wait() end
end

-- ▶️ Replay từng dòng macro
for _, entry in ipairs(macro) do
	-- Đặt tower
	if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
		local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
		local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation) or 0
		}

		local beforeCount = countTowerByName(entry.TowerPlaced)
		local startTime = tick()
		local placed = false

		while tick() - startTime < 1 do
			waitUntilCashEnough(entry.TowerPlaceCost)
			local beforeCash = cashStat.Value
			Remotes.PlaceTower:InvokeServer(unpack(args))
			task.wait(0.25)
			local afterCash = cashStat.Value
			local afterCount = countTowerByName(entry.TowerPlaced)

			if afterCash < beforeCash and afterCount > beforeCount then
				local tower = findNewTower(entry.TowerPlaced, beforeCount)
				if tower then
					tower.Name = placedIndex .. "." .. entry.TowerPlaced
					placedIndex += 1
				end
				placed = true
				break
			end
		end

	elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
		local idStr = tostring(entry.TowerIndex)
		local found = TowersFolder:FindFirstChild(idStr)
		if not found then continue end

		waitUntilCashEnough(entry.UpgradeCost)

		local startTime = tick()
		while tick() - startTime < 5 do
			local before = cashStat.Value
			Remotes.TowerUpgradeRequest:FireServer(tonumber(idStr), tonumber(entry.UpgradePath), 1)
			task.wait(0.25)
			local after = cashStat.Value
			if after < before then
				break
			end
		end
	end
end
