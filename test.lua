-- Bắt đầu ghi log
local startTime = time()
local offset = 0
local fileName = "record.txt"

if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

-- Serialize
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
	local out = {}
	for i, v in ipairs(args) do
		out[i] = serialize(v)
	end
	return table.concat(out, ", ")
end

local function log(method, self, serializedArgs)
	local name = tostring(self.Name)
	local delta = (time() - offset) - startTime
	local prefix = "task.wait(" .. delta .. ")\nTDX:"
	startTime = time() - offset

	if name == "PlaceTower" then
		appendfile(fileName, prefix .. "placeTower(" .. serializedArgs .. ")\n")
	elseif name == "SellTower" then
		appendfile(fileName, prefix .. "sellTower(" .. serializedArgs .. ")\n")
	elseif name == "TowerUpgradeRequest" then
		appendfile(fileName, prefix .. "upgradeTower(" .. serializedArgs .. ")\n")
	elseif name == "ChangeQueryType" then
		appendfile(fileName, prefix .. "changeQueryType(" .. serializedArgs .. ")\n")
	end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
	local args = serializeArgs(...)
	log("FireServer", self, args)
	return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
	local args = serializeArgs(...)
	log("InvokeServer", self, args)
	return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if method == "FireServer" or method == "InvokeServer" then
		local args = serializeArgs(...)
		log(method, self, args)
	end
	return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX đã bắt đầu.")

-- ✅ Script convert record.txt
task.spawn(function()
	local txtFile = "record.txt"
	local outJson = "tdx/macros/x.json"

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local HttpService = game:GetService("HttpService")
	local PlayerScripts = player:WaitForChild("PlayerScripts")

	local function SafeRequire(module)
		local ok, res = pcall(require, module)
		return ok and res or nil
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

	local function GetTowerByHash(hash)
		return TowerClass and TowerClass.GetTowers()[hash]
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

	-- ánh xạ hash -> pos.x
	local hash2pos = {}
	task.spawn(function()
		while true do
			for hash, tower in pairs(TowerClass.GetTowers()) do
				local pos = GetTowerPosition(tower)
				if pos then
					hash2pos[tostring(hash)] = pos
				end
			end
			task.wait(0.1)
		end
	end)

	if makefolder then
		pcall(function() makefolder("tdx") end)
		pcall(function() makefolder("tdx/macros") end)
	end

	while true do
		if isfile(txtFile) then
			local macro = readfile(txtFile)
			local logs = {}

			for line in macro:gmatch("[^\r\n]+") do
				-- place
				local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
				if a1 and name and x and y and z and rot then
					local vector = x .. ", " .. y .. ", " .. z
					local cost = GetTowerPlaceCostByName(name)
					table.insert(logs, {
						TowerPlaceCost = tonumber(cost),
						TowerPlaced = name,
						TowerVector = vector,
						Rotation = rot,
						TowerA1 = tostring(a1)
					})
					goto continue
				end

				-- upgrade
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path then
					local tower = GetTowerByHash(hash)
					local pathNum = tonumber(path)
					if tower and tower.LevelHandler then
						local before = tower.LevelHandler:GetLevelOnPath(pathNum)
						task.wait(0.1)
						local after = tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							local pos = hash2pos[tostring(hash)]
							if pos then
								table.insert(logs, {
									UpgradeCost = 0,
									UpgradePath = pathNum,
									TowerUpgraded = pos.X
								})
								print(string.format("✅ Upgrade ghi: %s | Path=%d | %d➜%d", tostring(pos.X), pathNum, before, after))
							end
						end
					end
					goto continue
				end

				-- change target
				local xTarget, targetType = line:match('TDX:changeQueryType%(([%d%.]+),%s*(%d)%)')
				if xTarget and targetType then
					table.insert(logs, {
						ChangeTarget = tonumber(xTarget),
						TargetType = tonumber(targetType)
					})
					goto continue
				end

				-- sell
				local xSell = line:match('TDX:sellTower%(([%d%.]+)%)')
				if xSell then
					table.insert(logs, {
						SellTower = tonumber(xSell)
					})
					goto continue
				end

				::continue::
			end

			writefile(outJson, HttpService:JSONEncode(logs))
			print("✅ Ghi macro xong:", outJson)
		end
		wait(0.22)
	end
end)
