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

-- Safe require tower module
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

-- Get tower position
local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

-- Get level on path
local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, result = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and result or nil
end

-- Get place cost
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
				local raw = tostring(costText.Text or ""):gsub("%D", "")
				local num = tonumber(raw)
				if num then return num end
			end
		end
	end
	return 0
end

-- Mapping hash -> pos + tower
local hash2info = {}
task.spawn(function()
	while true do
		for hash, tower in pairs(TowerClass.GetTowers()) do
			local pos = GetTowerPosition(tower)
			if pos then
				hash2info[tostring(hash)] = {
					x = pos.X,
					tower = tower
				}
			end
		end
		task.wait(0.05)
	end
end)

-- Cache để kiểm tra upgrade
local cache = {}
local function CheckUpgrade(hash, path)
	local info = hash2info[hash]
	local tower = info and info.tower
	if not tower then return false end
	local current = GetPathLevel(tower, path)
	if current == nil then return false end

	cache[hash] = cache[hash] or {}
	local last = cache[hash][path]
	if last == nil then
		cache[hash][path] = current
		return false
	elseif current > last then
		cache[hash][path] = current
		warn(string.format("[UPGRADE] hash %s path %d: %d ➜ %d", hash, path, last, current))
		return true
	else
		return false
	end
end

-- Đảm bảo thư mục tồn tại
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

-- Loop chuyển đổi
while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			-- PLACE
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
			if a1 and name and x and y and z and rot then
				name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
				local cost = GetTowerPlaceCostByName(name)
				table.insert(logs, {
					TowerA1 = tostring(a1),
					TowerPlaced = name,
					TowerVector = x .. ", " .. y .. ", " .. z,
					Rotation = rot,
					TowerPlaceCost = cost
				})
			end

			-- UPGRADE
			local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
			if hash and path then
				path = tonumber(path)
				if CheckUpgrade(hash, path) then
					local info = hash2info[hash]
					if info then
						table.insert(logs, {
							TowerUpgraded = info.x,
							UpgradePath = path,
							UpgradeCost = 0
						})
					end
				end
			end

			-- CHANGE TARGET
			local hash, target = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
			if hash and target then
				local info = hash2info[hash]
				if info then
					table.insert(logs, {
						ChangeTarget = info.x,
						TargetType = tonumber(target)
					})
				end
			end

			-- SELL
			local hash = line:match('TDX:sellTower%(([^%)]+)%)')
			if hash then
				local info = hash2info[hash]
				if info then
					table.insert(logs, {
						SellTower = info.x
					})
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	task.wait(0.2)
end
