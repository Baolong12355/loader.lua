-- 📁 File settings
local recordFile = "record.txt"
local outputFile = "tdx/macros/x.json"

-- 📦 Services
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")
local Workspace = game:GetService("Workspace")

-- 📦 Safe require TowerClass
local function SafeRequire(module)
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass = (function()
	local client = PlayerScripts:FindFirstChild("Client")
	if not client then return nil end
	local gameClass = client:FindFirstChild("GameClass")
	if not gameClass then return nil end
	local towerModule = gameClass:FindFirstChild("TowerClass")
	if not towerModule then return nil end
	return SafeRequire(towerModule)
end)()

if not TowerClass then
	warn("❌ Không load được TowerClass")
	return
end

-- 🧩 Serialize args for logging
local function serialize(value)
	if type(value) == "table" then
		local str = "{"
		for k, v in pairs(value) do
			str ..= "[" .. serialize(k) .. "]=" .. serialize(v) .. ", "
		end
		return str:sub(1, -3) .. "}"
	else
		return tostring(value)
	end
end

local function serializeArgs(...)
	local args, output = {...}, {}
	for i, v in ipairs(args) do
		output[i] = serialize(v)
	end
	return table.concat(output, ", ")
end

-- 📝 Record to file
local startTime = time()
local offset = 0

if isfile(recordFile) then delfile(recordFile) end
writefile(recordFile, "")

local function log(method, self, args)
	local name = tostring(self.Name)
	local line = "TDX:" .. name .. "(" .. args .. ")"
	local waitStr = "task.wait(" .. ((time() - offset) - startTime) .. ")\n"
	appendfile(recordFile, waitStr)
	appendfile(recordFile, line .. "\n")
	startTime = time() - offset
end

-- 🔌 Hook remote calls
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
	log("FireServer", self, serializeArgs(...))
	return oldFireServer(self, ...)
end)

local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
	log("InvokeServer", self, serializeArgs(...))
	return oldInvokeServer(self, ...)
end)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if method == "FireServer" or method == "InvokeServer" then
		log(method, self, serializeArgs(...))
	end
	return oldNamecall(self, ...)
end)

print("✅ Đã bắt đầu ghi macro TDX")

-- 🧠 Lấy cấp path
local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, r = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and r or nil
end

-- 🏷️ Lấy giá đặt tower
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

-- 🔁 Ánh xạ hash → pos
local hash2info = {}
task.spawn(function()
	while true do
		local towersFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Towers")
		if towersFolder then
			for _, part in pairs(towersFolder:GetChildren()) do
				if part:IsA("BasePart") then
					local pos = part.Position
					for hash, tower in pairs(TowerClass.GetTowers()) do
						local ok, tpos = pcall(function()
							return tower.Character and tower.Character:GetCharacterModel().PrimaryPart.Position
						end)
						if ok and tpos and (tpos - pos).Magnitude <= 0.5 then
							hash2info[tostring(hash)] = {
								x = pos.X,
								tower = tower
							}
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
end)

-- 🧠 Cache cấp path
local cachedLevels = {}

-- 🔁 Chuyển đổi file
task.spawn(function()
	while true do
		if isfile(recordFile) then
			local macro = readfile(recordFile)
			local logs = {}

			for line in macro:gmatch("[^\r\n]+") do
				-- PLACE
				local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)%)')
				if a1 and name and x and y and z and rot then
					table.insert(logs, {
						TowerA1 = a1,
						TowerPlaced = name,
						TowerVector = x .. ", " .. y .. ", " .. z,
						Rotation = rot,
						TowerPlaceCost = GetTowerPlaceCostByName(name)
					})
				end

				-- UPGRADE
				local hash, path = line:match("TDX:upgradeTower%(([^,]+),%s*(%d),")
				if hash and path and hash2info[hash] then
					local tower = hash2info[hash].tower
					local pathNum = tonumber(path)
					local hashStr = tostring(hash)

					cachedLevels[hashStr] = cachedLevels[hashStr] or {}
					local before = cachedLevels[hashStr][pathNum] or GetPathLevel(tower, pathNum)
					task.wait(0.05)
					local after = GetPathLevel(tower, pathNum)

					if before and after and after > before then
						cachedLevels[hashStr][pathNum] = after
						table.insert(logs, {
							TowerUpgraded = hash2info[hash].x,
							UpgradePath = pathNum,
							UpgradeCost = 0
						})
					end
				end

				-- CHANGE TARGET
				local hash, qtype = line:match("TDX:changeQueryType%(([^,]+),%s*(%d)%)")
				if hash and qtype and hash2info[hash] then
					table.insert(logs, {
						ChangeTarget = hash2info[hash].x,
						TargetType = tonumber(qtype)
					})
				end

				-- SELL
				local hash = line:match("TDX:sellTower%(([^%)]+)%)")
				if hash and hash2info[hash] then
					table.insert(logs, {
						SellTower = hash2info[hash].x
					})
				end
			end

			writefile(outputFile, HttpService:JSONEncode(logs))
		end
		task.wait(0.2)
	end
end)
