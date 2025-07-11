local startTime = time()
local offset = 0
local fileName = "record.txt"

if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

local function serialize(value)
	if type(value) == "table" then
		local result = "{"
		for k, v in pairs(value) do
			result ..= "[" .. serialize(k) .. "]=" .. serialize(v) .. ", "
		end
		if result ~= "{" then result = result:sub(1, -3) end
		return result .. "}"
	else
		return tostring(value)
	end
end

local function serializeArgs(...)
	local args = {...}
	local output = {}
	for i, v in ipairs(args) do output[i] = serialize(v) end
	return table.concat(output, ", ")
end

local function log(method, self, serializedArgs)
	local name = tostring(self.Name)
	if name == "PlaceTower" then
		appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
		appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
		startTime = time() - offset
	elseif name == "SellTower" then
		appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
		appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
		startTime = time() - offset
	elseif name == "TowerUpgradeRequest" then
		appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
		appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
		startTime = time() - offset
	elseif name == "ChangeQueryType" then
		appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
		appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
		startTime = time() - offset
	end
end

local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
	local args = serializeArgs(...)
	log("FireServer", self, args)
	return oldFireServer(self, ...)
end)

local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
	local args = serializeArgs(...)
	log("InvokeServer", self, args)
	return oldInvokeServer(self, ...)
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if method == "FireServer" or method == "InvokeServer" then
		local args = serializeArgs(...)
		log(method, self, args)
	end
	return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX đã bắt đầu (record.txt).")

-- convert section
local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

local function SafeRequire(module)
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass
do
	local client = PlayerScripts:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	TowerClass = SafeRequire(towerModule)
end

local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, result = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and result or nil
end

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

local hash2pos = {}
local cache = {}

task.spawn(function()
	while true do
		for hash, tower in pairs(TowerClass and TowerClass.GetTowers() or {}) do
			local pos = GetTowerPosition(tower)
			if pos then
				hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
				cache[tostring(hash)] = cache[tostring(hash)] or {}
				for path = 1, 2 do
					local level = GetPathLevel(tower, path)
					if level then
						cache[tostring(hash)][path] = level
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

local function GetUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return 0 end
	local lvl = tower.LevelHandler:GetLevelOnPath(path)
	local ok, cost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, lvl+1)
	end)
	return ok and tonumber(tostring(cost):gsub("%D", "")) or 0
end

local function IsUpgradeSuccess(hash, path)
	local h = tostring(hash)
	local before = cache[h] and cache[h][path]
	task.wait(0.05)
	local tower = TowerClass and TowerClass.GetTowers()[hash]
	local after = GetPathLevel(tower, path)
	if after and before and after > before then
		cache[h][path] = after
		return true
	end
	return false
end

if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
			if a1 and name and x and y and z and rot then
				name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
				table.insert(logs, {
					TowerA1 = a1,
					TowerPlaced = name,
					TowerVector = x .. ", " .. y .. ", " .. z,
					Rotation = rot,
					TowerPlaceCost = GetTowerPlaceCostByName(name)
				})
			else
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path and hash2pos[hash] then
					if IsUpgradeSuccess(hash, tonumber(path)) then
						local tower = TowerClass and TowerClass.GetTowers()[hash]
						table.insert(logs, {
							UpgradeCost = GetUpgradeCost(tower, tonumber(path)),
							UpgradePath = tonumber(path),
							TowerUpgraded = hash2pos[hash].x
						})
					end
				else
					local hash2, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
					if hash2 and targetType and hash2pos[hash2] then
						table.insert(logs, {
							ChangeTarget = hash2pos[hash2].x,
							TargetType = tonumber(targetType)
						})
					else
						local hash3 = line:match('TDX:sellTower%(([^%)]+)%)')
						if hash3 and hash2pos[hash3] then
							table.insert(logs, {
								SellTower = hash2pos[hash3].x
							})
						end
					end
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	task.wait(0.22)
end
