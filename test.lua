local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Safe require tower module
local function SafeRequire(module)
	local success, result = pcall(require, module)
	return success and result or nil
end

-- Load TowerClass
local TowerClass
do
	local client = PlayerScripts:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	TowerClass = SafeRequire(towerModule)
end

-- Get tower position
local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

-- Get tower placement cost
local function GetTowerPlaceCostByName(name)
	local gui = player:FindFirstChild("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	local bottomBar = interface and interface:FindFirstChild("BottomBar")
	local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
	if not towersBar then return 0 end

	for _, tower in ipairs(towersBar:GetChildren()) do
		if tower.Name == name then
			local costFrame = tower:FindFirstChild("CostFrame")
			local costText = costFrame and costFrame:FindFirstChild("CostText")
			if costText then
				local raw = tostring(costText.Text):gsub("%D", "")
				return tonumber(raw) or 0
			end
		end
	end
	return 0
end

-- Get upgrade cost
local function GetUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return 0 end
	local lvl = tower.LevelHandler:GetLevelOnPath(path)
	local ok, cost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, lvl + 1)
	end)
	return (ok and tonumber(cost)) or 0
end

-- Hash → Position
local hash2pos = {}
task.spawn(function()
	while true do
		for hash, tower in pairs(TowerClass.GetTowers()) do
			local pos = GetTowerPosition(tower)
			if pos then
				hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
			end
		end
		task.wait(0.1)
	end
end)

-- Tạo thư mục nếu chưa có
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

-- Vòng lặp chính
while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			-- Place tower
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
			if a1 and name and x and y and z and rot then
				name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
				local cost = GetTowerPlaceCostByName(name)
				local vector = x .. ", " .. y .. ", " .. z
				table.insert(logs, {
					TowerPlaceCost = tonumber(cost) or 0,
					TowerPlaced = name,
					TowerVector = vector,
					Rotation = rot,
					TowerA1 = tostring(a1)
				})

			-- Upgrade tower
			else
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*[^%)]+%)')
				if hash and path then
					local tower = TowerClass.GetTowers()[hash]
					local pos = hash2pos[tostring(hash)]
					local pathNum = tonumber(path)

					if tower and pos and tower.LevelHandler then
						local before = tower.LevelHandler:GetLevelOnPath(pathNum)
						task.wait(0.1)
						local after = tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							local upgradeCost = GetUpgradeCost(tower, pathNum)
							table.insert(logs, {
								UpgradeCost = upgradeCost,
								UpgradePath = pathNum,
								TowerUpgraded = pos.x
							})
						end
					end

				-- Change target
				else
					local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
					if hash and targetType then
						local pos = hash2pos[tostring(hash)]
						if pos then
							table.insert(logs, {
								ChangeTarget = pos.x,
								TargetType = tonumber(targetType)
							})
						end

					-- Sell tower
					else
						local hash = line:match('TDX:sellTower%(([^%)]+)%)')
						if hash then
							local pos = hash2pos[tostring(hash)]
							if pos then
								table.insert(logs, {
									SellTower = pos.x
								})
							end
						end
					end
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	task.wait(0.22)
end
