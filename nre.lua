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
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

local function SafeRequire(module)
	local success, result = pcall(require, module)
	return success and result or nil
end

local TowerClass = nil
do
	local client = PlayerScripts:FindFirstChild("Client")
	if client then
		local gameClass = client:FindFirstChild("GameClass")
		if gameClass then
			local towerModule = gameClass:FindFirstChild("TowerClass")
			if towerModule then
				TowerClass = SafeRequire(towerModule)
			end
		end
	end
end

local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, level = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and level or nil
end

-- ánh xạ hash đến model name và position
local hashInfo = {}
task.spawn(function()
	while true do
		local towersFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Towers")
		if towersFolder then
			for _, model in ipairs(towersFolder:GetChildren()) do
				if model:IsA("BasePart") then
					for hash, tower in pairs(TowerClass.GetTowers()) do
						local ok, pos = pcall(function()
							local m = tower.Character and tower.Character:GetCharacterModel()
							return m and m.PrimaryPart and m.PrimaryPart.Position
						end)
						if ok and pos and (model.Position - pos).Magnitude <= 0.5 then
							hashInfo[tostring(hash)] = {
								x = model.Position.X,
								name = model.Name,
								tower = tower,
								lastLevel = { [1] = GetPathLevel(tower, 1), [2] = GetPathLevel(tower, 2) }
							}
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
end)

-- lấy cost từ gui
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

-- chuyển đổi record
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			-- PLACE
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"(.-)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^)]+)%)')
			if a1 and name and x and y and z and rot then
				table.insert(logs, {
					TowerA1 = a1,
					TowerPlaced = name,
					TowerVector = x .. ", " .. y .. ", " .. z,
					Rotation = rot,
					TowerPlaceCost = GetTowerPlaceCostByName(name)
				})
				print("[LOG] PLACE:", name)
			else
				-- UPGRADE
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path and hashInfo[hash] then
					local info = hashInfo[hash]
					local newLevel = GetPathLevel(info.tower, tonumber(path))
					if newLevel and info.lastLevel and info.lastLevel[tonumber(path)] and newLevel > info.lastLevel[tonumber(path)] then
						table.insert(logs, {
							UpgradeCost = 0,
							UpgradePath = tonumber(path),
							TowerUpgraded = info.x
						})
						print(("[LOG] UPGRADE: hash %s | path %s | %d ➜ %d"):format(hash, path, info.lastLevel[tonumber(path)], newLevel))
						info.lastLevel[tonumber(path)] = newLevel
					else
						print("[SKIP] upgrade không thành công", hash, path)
					end
				end

				-- CHANGE TARGET
				local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
				if hash and targetType and hashInfo[hash] then
					table.insert(logs, {
						ChangeTarget = hashInfo[hash].x,
						TargetType = tonumber(targetType)
					})
					print("[LOG] CHANGE TARGET", hash)
				end

				-- SELL
				local hash = line:match('TDX:sellTower%(([^%)]+)%)')
				if hash and hashInfo[hash] then
					table.insert(logs, {
						SellTower = hashInfo[hash].x
					})
					print("[LOG] SELL", hash)
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
		print("✅ Đã ghi", #logs, "entry vào", outJson)
	end
	task.wait(0.2)
end
