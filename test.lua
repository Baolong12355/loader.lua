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

-- Get position
local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

-- Get current cost info
local function GetCurrentUpgradeCosts(tower)
	if not tower or not tower.LevelHandler then
		return {
			path1 = {cost = "N/A", currentLevel = 0, maxLevel = 0},
			path2 = {cost = "N/A", currentLevel = 0, maxLevel = 0, exists = false}
		}
	end

	local result = {
		path1 = {cost = "MAX", currentLevel = 0, maxLevel = 0},
		path2 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = false}
	}

	local maxLevel = tower.LevelHandler:GetMaxLevel()
	local lvl1 = tower.LevelHandler:GetLevelOnPath(1)
	result.path1.currentLevel = lvl1
	result.path1.maxLevel = maxLevel

	if lvl1 < maxLevel then
		local ok, cost = pcall(function()
			return tower.LevelHandler:GetLevelUpgradeCost(1, 1)
		end)
		result.path1.cost = ok and math.floor(cost) or "LỖI"
	end

	local hasPath2 = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(2) ~= nil
	end)

	if hasPath2 then
		result.path2.exists = true
		local lvl2 = tower.LevelHandler:GetLevelOnPath(2)
		result.path2.currentLevel = lvl2
		result.path2.maxLevel = maxLevel

		if lvl2 < maxLevel then
			local ok2, cost2 = pcall(function()
				return tower.LevelHandler:GetLevelUpgradeCost(2, 1)
			end)
			result.path2.cost = ok2 and math.floor(cost2) or "LỖI"
		end
	end

	return result
end

-- Get nearest tower by X
local function GetTowerByX(x)
	local nearest, minDist = nil, math.huge
	for _, tower in pairs(TowerClass.GetTowers()) do
		local pos = GetTowerPosition(tower)
		if pos and math.abs(pos.X - x) <= 1 then
			local dist = math.abs(pos.X - x)
			if dist < minDist then
				nearest, minDist = tower, dist
			end
		end
	end
	return nearest
end

-- Start convert
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
				local vecStr = x .. ", " .. y .. ", " .. z
				table.insert(logs, {
					TowerPlaceCost = 0,
					TowerPlaced = name:gsub('^%s*"(.-)"%s*$', '%1'),
					TowerVector = vecStr,
					Rotation = rot,
					TowerA1 = tostring(a1)
				})
			else
				local xPos, path = line:match('TDX:upgradeTower%x?%(([%d%.]+),%s*(%d)')
				if xPos and path then
					local xNum = tonumber(xPos)
					local pathNum = tonumber(path)
					local tower = GetTowerByX(xNum)
					if tower then
						local before = tower.LevelHandler:GetLevelOnPath(pathNum)
						task.wait(0.1)
						local after = tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							table.insert(logs, {
								UpgradeCost = 0,
								UpgradePath = pathNum,
								TowerUpgraded = xNum
							})
							print(string.format("✅ Upgrade: X=%.2f | %d ➜ %d", xNum, before, after))
						else
							print(string.format("❌ Upgrade failed (no level up): X=%.2f", xNum))
						end
					else
						print(string.format("⚠️ Không tìm thấy tower tại X=%.2f", xNum))
					end

				else
					local x, ttype = line:match('TDX:changeQueryType%x?%(([%d%.]+),%s*(%d)%)')
					if x and ttype then
						table.insert(logs, {
							ChangeTarget = tonumber(x),
							TargetType = tonumber(ttype)
						})
					else
						local x = line:match('TDX:sellTower%x?%(([%d%.]+)%)')
						if x then
							table.insert(logs, {
								SellTower = tonumber(x)
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
