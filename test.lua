repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local fileName = "record.txt"
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

local startTime = tick()
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
	local t = {}
	for i,v in ipairs({...}) do
		t[i] = serialize(v)
	end
	return table.concat(t, ", ")
end

local function log(self, args)
	local delta = (tick() - offset) - startTime
	local prefix = "task.wait("..delta..")\nTDX:"
	startTime = tick() - offset
	local name = tostring(self.Name)
	if name=="PlaceTower" then
		appendfile(fileName, prefix.."placeTower("..args..")\n")
	elseif name=="SellTower" then
		appendfile(fileName, prefix.."sellTower("..args..")\n")
	elseif name=="TowerUpgradeRequest" then
		appendfile(fileName, prefix.."upgradeTower("..args..")\n")
	elseif name=="ChangeQueryType" then
		appendfile(fileName, prefix.."changeQueryType("..args..")\n")
	end
end

-- Hook namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if (method=="FireServer" or method=="InvokeServer") and typeof(self)=="Instance" then
		log(self, serializeArgs(...))
	end
	return oldNamecall(self, ...)
end)

print("✅ Ghi macro: bắt đầu theo dõi remote ghi vào record.txt")


local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Safe require
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
				local vector = x .. ", " .. y .. ", " .. z
				local cost = GetTowerPlaceCostByName(name)
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
				local tower = GetTowerByHash(hash)
				local pathNum = tonumber(path)
				if tower and tower.LevelHandler then
					local pos = GetTowerPosition(tower)
					if pos then
						local before = tower.LevelHandler:GetLevelOnPath(pathNum)
						task.wait(0.1)
						local after = tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							table.insert(logs, {
								UpgradeCost = 0, -- để runner xử lý
								UpgradePath = pathNum,
								TowerUpgraded = pos.X
							})
							print(string.format("✅ Upgrade: X=%.2f | Path=%d | %d➜%d", pos.X, pathNum, before, after))
						else
							print(string.format("❌ Không upgrade (cấp không đổi): X=%.2f", pos.X))
						end
					end
				end
				goto continue
			end

			local xT, targetType = line:match('TDX:changeQueryType%(([%d%.]+),%s*(%d)%)')
			if xT and targetType then
				table.insert(logs, {
					ChangeTarget = tonumber(xT),
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
		print("✅ Đã ghi macro:", outJson)
	end
	wait(0.22)
end
