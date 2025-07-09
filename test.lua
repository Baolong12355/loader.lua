repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ✅ Ghi record
local fileName = "record.txt"
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

local startTime = time()
local offset = 0

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
	local out = {}
	for i, v in ipairs(args) do
		out[i] = serialize(v)
	end
	return table.concat(out, ", ")
end

local function log(method, self, args)
	local delta = (time() - offset) - startTime
	local prefix = "task.wait(" .. delta .. ")\nTDX:"
	local name = tostring(self.Name)
	startTime = time() - offset

	if name == "PlaceTower" then
		appendfile(fileName, prefix .. "placeTower(" .. args .. ")\n")
	elseif name == "SellTower" then
		appendfile(fileName, prefix .. "sellTower(" .. args .. ")\n")
	elseif name == "TowerUpgradeRequest" then
		appendfile(fileName, prefix .. "upgradeTower(" .. args .. ")\n")
	elseif name == "ChangeQueryType" then
		appendfile(fileName, prefix .. "changeQueryType(" .. args .. ")\n")
	end
end

-- ✅ Ghi log thông qua hook
local oldNamecall = nil
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if typeof(self) == "Instance" and (method == "FireServer" or method == "InvokeServer") then
		local args = serializeArgs(...)
		log(method, self, args)
	end
	return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX đang chạy...")

-- ✅ Convert record.txt thành macro JSON (rewrite style)
task.spawn(function()
	local txtFile = "record.txt"
	local outJson = "tdx/macros/x.json"
	local HttpService = game:GetService("HttpService")
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
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

	local function GetTowerByHash(hash)
		return TowerClass and TowerClass.GetTowers()[hash]
	end

	local function GetTowerXByHash(hash)
		local tower = GetTowerByHash(hash)
		if tower then
			local pos = GetTowerPosition(tower)
			if pos then return pos.X end
		end
		return nil
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
				local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
				if a1 and name and x and y and z and rot then
					local cost = GetTowerPlaceCostByName(name)
					local vector = x .. ", " .. y .. ", " .. z
					table.insert(logs, {
						TowerPlaceCost = tonumber(cost) or 0,
						TowerPlaced = name,
						TowerVector = vector,
						Rotation = rot,
						TowerA1 = tostring(a1)
					})
					goto continue
				end

				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path then
					local pathNum = tonumber(path)
					local x = GetTowerXByHash(hash)
					if x then
						table.insert(logs, {
							UpgradeCost = 0,
							UpgradePath = pathNum,
							TowerUpgraded = x
						})
						print(string.format("✅ Convert upgrade: Path=%d X=%.2f", pathNum, x))
					else
						print(string.format("⚠️ Không tìm thấy tower hash=%s", hash))
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
			print("✅ Ghi JSON:", outJson)
		end
		wait(0.22)
	end
end)
