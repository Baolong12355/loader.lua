--cak
local startTime = time()
local offset = 0
local fileName = "record.txt"

-- Xóa file cũ nếu có
if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

-- Serialize giá trị
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

-- Serialize toàn bộ argument
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Ghi log vào file
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

-- Safe require
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

local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

local function GetTowerByX(axisX)
	local nearestTower = nil
	local minDist = 1
	for _, tower in pairs(TowerClass.GetTowers()) do
		local pos = GetTowerPosition(tower)
		if pos then
			local dist = math.abs(pos.X - axisX)
			if dist <= minDist then
				minDist = dist
				nearestTower = tower
			end
		end
	end
	return nearestTower
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

-- init folder
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			local matched = false

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
				matched = true
			end

			if not matched then
				local xVal, path = line:match('TDX:upgradeTower%(([%d%.]+),%s*(%d),')
				if xVal and path then
					local axisX = tonumber(xVal)
					local tower = GetTowerByX(axisX)
					local pathNum = tonumber(path)
					if tower and tower.LevelHandler then
						local before = tower.LevelHandler:GetLevelOnPath(pathNum)
						task.wait(0.1)
						local after = tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							table.insert(logs, {
								UpgradeCost = 0,
								UpgradePath = pathNum,
								TowerUpgraded = axisX
							})
							print(string.format("✅ Upgrade: X=%.2f | Path=%d | %d➜%d", axisX, pathNum, before, after))
						else
							print(string.format("⛔ Không ghi nâng (không đổi cấp): X=%.2f | Path=%d", axisX, pathNum))
						end
					else
						print(string.format("⚠️ Tower không tồn tại tại X=%.2f", axisX))
					end
					matched = true
				end
			end

			if not matched then
				local xTarget, targetType = line:match('TDX:changeQueryType%(([%d%.]+),%s*(%d)%)')
				if xTarget and targetType then
					table.insert(logs, {
						ChangeTarget = tonumber(xTarget),
						TargetType = tonumber(targetType)
					})
					matched = true
				end
			end

			if not matched then
				local xSell = line:match('TDX:sellTower%(([%d%.]+)%)')
				if xSell then
					table.insert(logs, {
						SellTower = tonumber(xSell)
					})
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
		print("✅ Đã ghi lại macro vào", outJson)
	end
	wait(0.22)
end
