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
local Workspace = game:GetService("Workspace")

-- Hàm lấy cấp path
local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, result = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and result or nil
end

-- Ánh xạ hash -> info từ workspace
local hash2info = {}
task.spawn(function()
	while true do
		local towersFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Towers")
		if towersFolder then
			for _, part in pairs(towersFolder:GetChildren()) do
				if part:IsA("BasePart") then
					local pos = part.Position
					local name = part.Name
					for hash, tower in pairs(require(player.PlayerScripts.Client.GameClass.TowerClass).GetTowers()) do
						local ok, tpos = pcall(function()
							return tower.Character and tower.Character:GetCharacterModel() and tower.Character:GetCharacterModel().PrimaryPart.Position
						end)
						if ok and tpos and (tpos - pos).Magnitude <= 0.5 then
							hash2info[tostring(hash)] = {
								x = pos.X,
								y = pos.Y,
								z = pos.Z,
								name = name,
								tower = tower
							}
						end
					end
				end
			end
		end
		task.wait(0.2)
	end
end)

-- Lấy giá đặt tower
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

-- Tạo thư mục
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

-- Chuyển đổi record.txt → x.json
while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			-- PLACE
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
			if a1 and name and x and y and z and rot then
				name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
				table.insert(logs, {
					TowerA1 = a1,
					TowerPlaced = name,
					TowerVector = x .. ", " .. y .. ", " .. z,
					Rotation = rot,
					TowerPlaceCost = GetTowerPlaceCostByName(name)
				})
			end

			-- UPGRADE
			local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
			if hash and path and hash2info[hash] then
				local info = hash2info[hash]
				local tower = info.tower
				local pathNum = tonumber(path)
				local before = GetPathLevel(tower, pathNum)
				task.wait(0.1)
				local after = GetPathLevel(tower, pathNum)
				if before and after and after > before then
					table.insert(logs, {
						TowerUpgraded = info.x,
						UpgradePath = pathNum,
						UpgradeCost = 0
					})
				end
			end

			-- CHANGE TARGET
			local hash, qtype = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
			if hash and qtype and hash2info[hash] then
				local info = hash2info[hash]
				table.insert(logs, {
					ChangeTarget = info.x,
					TargetType = tonumber(qtype)
				})
			end

			-- SELL
			local hash = line:match('TDX:sellTower%(([^%)]+)%)')
			if hash and hash2info[hash] then
				local info = hash2info[hash]
				table.insert(logs, {
					SellTower = info.x
				})
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	task.wait(0.22)
end
