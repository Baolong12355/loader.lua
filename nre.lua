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
local Workspace = game:GetService("Workspace")

-- Safe require
local function SafeRequire(module)
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass
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

if not TowerClass then
	warn("❌ Không thể load TowerClass")
	return
end

local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local ok, pos = pcall(function()
		local model = tower.Character:GetCharacterModel()
		local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		return root and root.Position
	end)
	return ok and pos or nil
end

local function GetTowerPlaceCostByName(name)
	local gui = player:FindFirstChild("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	local bottomBar = interface and interface:FindFirstChild("BottomBar")
	local towersBar = bottomBar and bottomBar:FindFirstChild("TowersBar")
	if not towersBar then
		warn("⚠️ Không tìm thấy TowersBar trong GUI")
		return 0
	end
	for _, tower in ipairs(towersBar:GetChildren()) do
		if tower.Name == name then
			local costFrame = tower:FindFirstChild("CostFrame")
			local costText = costFrame and costFrame:FindFirstChild("CostText")
			if costText and costText.Text then
				local raw = tostring(costText.Text):gsub("%D", "")
				local value = tonumber(raw)
				if value then
					return value
				else
					warn("⚠️ Không thể chuyển costText.Text thành số:", costText.Text)
				end
			else
				warn("⚠️ Không tìm thấy CostText trong tower:", name)
			end
		end
	end
	warn("⚠️ Không tìm thấy tower tên:", name)
	return 0
end

local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, result = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and result or nil
end

-- Cache hash → position, name, tower
local hash2info = {}
task.spawn(function()
	while true do
		local towersFolder = Workspace:FindFirstChild("Game") and Workspace.Game:FindFirstChild("Towers")
		if towersFolder then
			for _, part in pairs(towersFolder:GetChildren()) do
				if part:IsA("BasePart") then
					local pos = part.Position
					local name = part.Name
					for hash, tower in pairs(TowerClass.GetTowers()) do
						local tpos = GetTowerPosition(tower)
						if tpos and (tpos - pos).Magnitude <= 1 then
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
		else
			warn("⚠️ Không tìm thấy Workspace.Game.Towers")
		end
		task.wait(0.1)
	end
end)

-- Cache nâng cấp
local cache = {}

-- Tạo thư mục nếu cần
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
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
			if a1 and name and x and y and z and rot then
				name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
				local cost = GetTowerPlaceCostByName(name)
				local vector = x .. ", " .. y .. ", " .. z
				print("✅ Ghi PLACE:", name, "| Cost:", cost)
				table.insert(logs, {
					TowerPlaceCost = cost,
					TowerPlaced = name,
					TowerVector = vector,
					Rotation = rot,
					TowerA1 = tostring(a1)
				})
			else
				-- UPGRADE
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path then
					local info = hash2info[hash]
					if info then
						local tower = info.tower
						local p = tonumber(path)
						local before = GetPathLevel(tower, p)
						task.wait(0.05)
						local after = GetPathLevel(tower, p)
						if before and after and after > before then
							print(string.format("✅ Ghi UPGRADE: hash=%s | path=%d | %d ➜ %d", hash, p, before, after))
							table.insert(logs, {
								TowerUpgraded = info.x,
								UpgradePath = p,
								UpgradeCost = 0
							})
						else
							print(string.format("❌ Bỏ qua UPGRADE: hash=%s | path=%d | before=%s | after=%s", hash, p, tostring(before), tostring(after)))
						end
					else
						warn("❌ Không tìm thấy info cho hash (UPGRADE):", hash)
					end
				end

				-- CHANGE TARGET
				local hash, qtype = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
				if hash and qtype then
					local info = hash2info[hash]
					if info then
						print("✅ Ghi CHANGE TARGET:", info.name, "| TargetType:", qtype)
						table.insert(logs, {
							ChangeTarget = info.x,
							TargetType = tonumber(qtype)
						})
					else
						warn("❌ Không tìm thấy info cho hash (CHANGE TARGET):", hash)
					end
				end

				-- SELL
				local hash = line:match('TDX:sellTower%(([^%)]+)%)')
				if hash then
					local info = hash2info[hash]
					if info then
						print("✅ Ghi SELL:", info.name)
						table.insert(logs, {
							SellTower = info.x
						})
					else
						warn("❌ Không tìm thấy info cho hash (SELL):", hash)
					end
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
		print("📁 Ghi xong x.json, số dòng:", #logs)
	end
	task.wait(0.22)
end
