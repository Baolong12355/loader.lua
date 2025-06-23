local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local interface = playerGui:WaitForChild("Interface")
local bottomBar = interface:WaitForChild("BottomBar")
local towersBar = bottomBar:WaitForChild("TowersBar")

local output = {}
local start = os.clock()

local table_insert = table.insert
local string_format = string.format
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pcall = pcall
local task_wait = task.wait
local os_clock = os.clock

-- SafeRequire
local function SafeRequire(path, timeout)
	timeout = timeout or 5
	local t0 = os_clock()
	while os_clock() - t0 < timeout do
		local success, result = pcall(function()
			return require(path)
		end)
		if success then return result end
		task_wait()
	end
	return nil
end

-- Load TowerClass
local TowerClass
local function LoadTowerClass()
	local ps = LocalPlayer:WaitForChild("PlayerScripts")
	local client = ps:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	return SafeRequire(towerModule)
end
TowerClass = LoadTowerClass()
if not TowerClass then error("Không thể tải TowerClass") end

-- Lấy giá tower theo tên
local function getTowerCostByName(towerName)
	for _, tower in ipairs(towersBar:GetChildren()) do
		if tower.Name == towerName then
			local costFrame = tower:FindFirstChild("CostFrame")
			if costFrame then
				local costText = costFrame:FindFirstChild("CostText")
				if costText then
					return tonumber(costText.Text) or 0
				end
			end
		end
	end
	return 0
end

-- Serialize Vector3 dạng replay được
local function vecToStr(vec)
	return string_format("Vector3.new(%.5f, %.5f, %.5f)", vec.X, vec.Y, vec.Z)
end

-- Lấy vị trí X từ tower hash
local function GetTowerXFromHash(hash)
	local towers = TowerClass.GetTowers()
	if not towers then return nil end
	local tower = towers[hash]
	if not tower then return nil end
	local success, pos = pcall(function()
		if not tower.Character then return nil end
		local model = tower.Character:GetCharacterModel()
		if not model then return nil end
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		return root and root.Position
	end)
	if success and pos then
		return tonumber(string_format("%.3f", pos.X))
	end
	return nil
end

-- Ghi log
local function log(method, self, ...)
	local remoteName = tostring(self.Name)
	local args = {...}

	if remoteName == "PlaceTower" then
		local towerName = args[2]
		if type(towerName) ~= "string" then return end
		local towerCost = getTowerCostByName(towerName)
		local towerVector = vecToStr(args[3])
		table_insert(output, {
			type = "PlaceTower",
			name = towerName,
			cost = towerCost,
			pos = towerVector,
			time = os_clock() - start
		})

	elseif remoteName == "TowerUpgradeRequest" then
		local hash = tostring(args[1])
		local path = args[2]
		local tower = TowerClass.GetTowers()[hash]
		if not tower or not tower.Config then return end
		local upgradeData = tower.Config.UpgradePathData and tower.Config.UpgradePathData[path]
		local currentLevel = tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(path) or 0
		local cost = upgradeData and upgradeData[currentLevel + 1] and upgradeData[currentLevel + 1].Cost or 0
		local x = GetTowerXFromHash(hash)
		if x then
			table_insert(output, {
				type = "UpgradeTower",
				x = x,
				path = path,
				cost = cost,
				time = os_clock() - start
			})
		end

	elseif remoteName == "SellTower" then
		local hash = tostring(args[1])
		local x = GetTowerXFromHash(hash)
		if x then
			table_insert(output, {
				type = "SellTower",
				x = x,
				time = os_clock() - start
			})
		end

	elseif remoteName == "ChangeQueryType" then
		local hash = tostring(args[1])
		local targetWanted = args[2]
		local x = GetTowerXFromHash(hash)
		if x then
			table_insert(output, {
				type = "ChangeTarget",
				x = x,
				target = targetWanted,
				time = os_clock() - start
			})
		end
	end
end

-- === CÁCH HOOK MỚI (serialize in log như file .txt nhưng vẫn xài log gốc) ===

-- serialize debug
local function serialize(value)
	if type(value) == "table" then
		local result = "{"
		for k, v in pairs(value) do
			result ..= "[" .. serialize(k) .. "]=" .. serialize(v) .. ", "
		end
		if result ~= "{" then
			result = result:sub(1, -3)
		end
		return result .. "}"
	else
		return tostring(value)
	end
end

local function serializeArgs(...)
	local args = {...}
	local output = {}
	for i, v in ipairs(args) do
		output[i] = serialize(v)
	end
	return table.concat(output, ", ")
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
	local args = {...}
	pcall(log, "FireServer", self, unpack(args))
	local serialized = serializeArgs(...)
	print("🔥 FireServer:", self.Name, serialized)
	return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
	local args = {...}
	pcall(log, "InvokeServer", self, unpack(args))
	local serialized = serializeArgs(...)
	print("📞 InvokeServer:", self.Name, serialized)
	return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
		local args = {...}
		pcall(log, method, self, unpack(args))
		local serialized = serializeArgs(...)
		print("🔁", method .. ":", self.Name, serialized)
	end
	return oldNamecall(self, ...)
end)

-- Ghi đè file JSON tự động mỗi 10s
task.spawn(function()
	while true do
		task_wait(10)
		local success, json = pcall(function()
			return HttpService:JSONEncode(output)
		end)
		if success then
			pcall(function()
				writefile("tdx_macro_record.json", json)
			end)
		end
	end
end)

print("✅ Ghi macro TDX đã bật (hook an toàn & serialize kiểu mới).")
