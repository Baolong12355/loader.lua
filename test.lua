return function()
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
		for i, v in ipairs(args) do
			output[i] = serialize(v)
		end
		return table.concat(output, ", ")
	end

	local function log(method, self, serializedArgs)
		local name = tostring(self.Name)
		local t = "task.wait(" .. ((time() - offset) - startTime) .. ")\n"
		if name == "PlaceTower" then
			appendfile(fileName, t .. "TDX:placeTower(" .. serializedArgs .. ")\n")
			startTime = time() - offset
		elseif name == "SellTower" then
			appendfile(fileName, t .. "TDX:sellTower(" .. serializedArgs .. ")\n")
			startTime = time() - offset
		elseif name == "TowerUpgradeRequest" then
			appendfile(fileName, t .. "TDX:upgradeTower(" .. serializedArgs .. ")\n")
			startTime = time() - offset
		elseif name == "ChangeQueryType" then
			appendfile(fileName, t .. "TDX:changeQueryType(" .. serializedArgs .. ")\n")
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

	print("✅ Ghi macro TDX đã bắt đầu (luôn dùng tên record.txt).")

	local txtFile = "record.txt"
	local outJson = "tdx/macros/x.json"

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local HttpService = game:GetService("HttpService")
	local PlayerScripts = player:WaitForChild("PlayerScripts")

	local function SafeRequire(module)
		local success, result = pcall(require, module)
		return success and result or nil
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

	local function GetTowerByX(x)
		local nearest, bestDist
		for _, tower in pairs(TowerClass.GetTowers()) do
			local pos = GetTowerPosition(tower)
			if pos then
				local dist = math.abs(pos.X - x)
				if dist <= 1 and (not bestDist or dist < bestDist) then
					nearest = {tower = tower, pos = pos}
					bestDist = dist
				end
			end
		end
		return nearest
	end

	local function GetTowerPlaceCostByName(name)
		local gui = player:FindFirstChild("PlayerGui")
		local interface = gui and gui:FindFirstChild("Interface")
		local bottomBar = interface and interface:FindFirstChild("BottomBar")
		local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
		if not towersBar then return 0 end

		for _, tower in ipairs(towersBar:GetChildren()) do
			if tower.Name == name then
				local costText = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
				if costText then
					local raw = tostring(costText.Text):gsub("%D", "")
					return tonumber(raw) or 0
				end
			end
		end
		return 0
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
				local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([%d%.]+),%s*"([^"]+)",%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)%)')
				if a1 and name and x and y and z and rot then
					local cost = GetTowerPlaceCostByName(name)
					table.insert(logs, {
						TowerPlaceCost = tonumber(cost) or 0,
						TowerPlaced = name,
						TowerVector = string.format("%s, %s, %s", x, y, z),
						Rotation = rot,
						TowerA1 = tostring(a1)
					})
					goto continue
				end

				local xVal, path = line:match('TDX:upgradeTower%(([%d%.]+),%s*(%d),')
				if xVal and path then
					local result = GetTowerByX(tonumber(xVal))
					local pathNum = tonumber(path)
					if result and result.tower and result.pos then
						local before = result.tower.LevelHandler:GetLevelOnPath(pathNum)
						task.wait(0.1)
						local after = result.tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							table.insert(logs, {
								UpgradeCost = 0,
								UpgradePath = pathNum,
								TowerUpgraded = result.pos.X
							})
							print(string.format("✅ Upgrade: X=%.2f | Path=%d | %d➜%d", result.pos.X, pathNum, before, after))
						else
							print(string.format("⛔ Không ghi upgrade (không đổi cấp): X=%.2f | Path=%d", tonumber(xVal), pathNum))
						end
					else
						print(string.format("⚠️ Tower không tồn tại gần X=%.2f", tonumber(xVal)))
					end
					goto continue
				end

				local xTarget, targetType = line:match('TDX:changeQueryType%(([%d%.]+),%s*(%d)%)')
				if xTarget and targetType then
					table.insert(logs, {
						ChangeTarget = tonumber(xTarget),
						TargetType = tonumber(targetType)
					})
					goto continue
				end

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
			print("✅ Đã ghi vào:", outJson)
		end
		wait(0.22)
	end
end
