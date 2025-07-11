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

-- Ghi record.txt và convert sang x.json nếu nâng cấp thành công

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local PlayerScripts = player:WaitForChild("PlayerScripts")

local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local function SafeRequire(module)
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass
do
	local client = PlayerScripts:FindFirstChild("Client")
	local gameClass = client and client:FindFirstChild("GameClass")
	local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
	TowerClass = towerModule and SafeRequire(towerModule)
end

if not TowerClass then
	error("Không thể load TowerClass")
end

-- Cache cấp path
local cache = {}
local upgraded = {}

local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, result = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and result or nil
end

-- Ánh xạ hash -> pos + name + tower
local hash2info = {}
task.spawn(function()
	while true do
		local towers = TowerClass.GetTowers()
		for hash, tower in pairs(towers) do
			local h = tostring(hash)
			cache[h] = cache[h] or {}
			local model = tower.Character and tower.Character:GetCharacterModel()
			local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			local pos = root and root.Position
			if pos then
				hash2info[h] = {
					x = pos.X,
					y = pos.Y,
					z = pos.Z,
					tower = tower
				}
			end
		end
		task.wait(0.05)
	end
end)

-- Kiểm tra nâng cấp thành công
task.spawn(function()
	while true do
		for hash, tower in pairs(TowerClass.GetTowers()) do
			local h = tostring(hash)
			cache[h] = cache[h] or {}
			for path = 1, 2 do
				local cur = GetPathLevel(tower, path)
				if cur then
					local last = cache[h][path]
					if last and cur > last then
						upgraded[h] = upgraded[h] or {}
						upgraded[h][path] = true
						print(string.format("[UPGRADE] hash=%s | path=%d | %d ➜ %d", h, path, last, cur))
					end
					cache[h][path] = cur
				end
			end
		end
		task.wait(0.05)
	end
end)

-- Get cost đặt tower
local function GetTowerPlaceCostByName(name)
	local gui = player:FindFirstChild("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	local bottomBar = interface and interface:FindFirstChild("BottomBar")
	local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
	if not towersBar then return 0 end
	for _, tower in ipairs(towersBar:GetChildren()) do
		if tower.Name == name then
			local text = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
			if text then
				return tonumber(text.Text:gsub("%D", "")) or 0
			end
		end
	end
	return 0
end

-- Đảm bảo thư mục
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

-- Convert record.txt → x.json
while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			-- PLACE
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
				-- UPGRADE (chỉ khi thành công)
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path then
					local info = hash2info[hash]
					if info and upgraded[hash] and upgraded[hash][tonumber(path)] then
						table.insert(logs, {
							UpgradeCost = 0,
							UpgradePath = tonumber(path),
							TowerUpgraded = info.x
						})
					end
				else
					-- CHANGE TARGET
					local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
					if hash and targetType and hash2info[hash] then
						local info = hash2info[hash]
						table.insert(logs, {
							ChangeTarget = info.x,
							TargetType = tonumber(targetType)
						})
					else
						-- SELL
						local hash = line:match('TDX:sellTower%(([^%)]+)%)')
						if hash and hash2info[hash] then
							local info = hash2info[hash]
							table.insert(logs, {
								SellTower = info.x
							})
						end
					end
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	task.wait(0.2)
end
