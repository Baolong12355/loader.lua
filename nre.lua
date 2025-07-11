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
	local args, output = {...}, {}
	for i, v in ipairs(args) do output[i] = serialize(v) end
	return table.concat(output, ", ")
end

local function log(method, self, serializedArgs)
	local name = tostring(self.Name)
	local waitTime = ((time() - offset) - startTime)
	if name == "PlaceTower" then
		appendfile(fileName, ("task.wait(%.2f)\nTDX:placeTower(%s)\n"):format(waitTime, serializedArgs))
	elseif name == "SellTower" then
		appendfile(fileName, ("task.wait(%.2f)\nTDX:sellTower(%s)\n"):format(waitTime, serializedArgs))
	elseif name == "TowerUpgradeRequest" then
		appendfile(fileName, ("task.wait(%.2f)\nTDX:upgradeTower(%s)\n"):format(waitTime, serializedArgs))
	elseif name == "ChangeQueryType" then
		appendfile(fileName, ("task.wait(%.2f)\nTDX:changeQueryType(%s)\n"):format(waitTime, serializedArgs))
	end
	startTime = time() - offset
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

print("✅ Ghi macro TDX đã bắt đầu.")

-- Convert script
local txtFile, outJson = "record.txt", "tdx/macros/x.json"
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Require TowerClass
local function SafeRequire(module)
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass = SafeRequire(PlayerScripts:WaitForChild("Client"):WaitForChild("GameClass"):WaitForChild("TowerClass"))

local function GetTowerPosition(tower)
	local ok, pos = pcall(function()
		local model = tower.Character and tower.Character:GetCharacterModel()
		return model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")).Position
	end)
	return ok and pos or nil
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
	local bar = gui and gui:FindFirstChild("Interface") and gui.Interface:FindFirstChild("BottomBar")
	local towersBar = bar and bar:FindFirstChild("TowersBar")
	if not towersBar then return 0 end
	for _, t in ipairs(towersBar:GetChildren()) do
		if t.Name == name then
			local text = t:FindFirstChild("CostFrame") and t.CostFrame:FindFirstChild("CostText")
			if text then
				return tonumber(text.Text:gsub("%D", "")) or 0
			end
		end
	end
	return 0
end

-- Cache hash → pos + level
local hash2pos, cache = {}, {}
task.spawn(function()
	while true do
		for hash, tower in pairs(TowerClass.GetTowers()) do
			local pos = GetTowerPosition(tower)
			if pos then
				local h = tostring(hash)
				hash2pos[h] = {x = pos.X, y = pos.Y, z = pos.Z}
				cache[h] = cache[h] or {}
				for path = 1, 2 do
					local lvl = GetPathLevel(tower, path)
					if lvl then
						local old = cache[h][path]
						if old and lvl > old then
							print(string.format("🟢 Upgrade success: %s | path %d: %d ➜ %d", h, path, old, lvl))
						elseif old and lvl == old then
							print(string.format("🔸 No upgrade yet: %s | path %d = %d", h, path, lvl))
						end
						cache[h][path] = lvl
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

local function IsUpgradeSuccess(hash, path)
	local h = tostring(hash)
	local before = cache[h] and cache[h][path]
	task.wait(0.05)
	local tower = TowerClass.GetTowers()[hash]
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

-- Convert record
task.spawn(function()
	while true do
		if isfile(txtFile) then
			local macro = readfile(txtFile)
			local logs = {}

			for line in macro:gmatch("[^\r\n]+") do
				local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
				if a1 and name and x and y and z and rot then
					name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
					local vector = x .. ", " .. y .. ", " .. z
					table.insert(logs, {
						TowerPlaceCost = GetTowerPlaceCostByName(name),
						TowerPlaced = name,
						TowerVector = vector,
						Rotation = rot,
						TowerA1 = tostring(a1)
					})
				else
					local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),')
					if hash and path then
						if IsUpgradeSuccess(hash, tonumber(path)) then
							local pos = hash2pos[tostring(hash)]
							if pos then
								table.insert(logs, {
									UpgradeCost = 0,
									UpgradePath = tonumber(path),
									TowerUpgraded = pos.x
								})
							end
						end
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
end)
