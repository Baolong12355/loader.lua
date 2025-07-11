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
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass
do
	local client = PlayerScripts:FindFirstChild("Client")
	local gameClass = client and client:FindFirstChild("GameClass")
	local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
	TowerClass = towerModule and SafeRequire(towerModule)
end

if not TowerClass then
	warn("❌ Không thể load TowerClass")
	return
end

-- Lấy cấp path
local function GetPathLevel(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, result = pcall(function()
		return tower.LevelHandler:GetLevelOnPath(path)
	end)
	return ok and result or nil
end

-- Lấy vị trí tower
local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local ok, pos = pcall(function()
		local model = tower.Character:GetCharacterModel()
		local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		return root and root.Position
	end)
	return ok and pos or nil
end

-- Tìm tower bằng X
local function GetTowerByAxis(axisX)
	for _, tower in pairs(TowerClass.GetTowers()) do
		local pos = GetTowerPosition(tower)
		if pos and math.abs(pos.X - axisX) <= 0.5 then
			return tower
		end
	end
	return nil
end

-- Lấy giá tiền
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

-- Tạo thư mục nếu cần
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

print("✅ Đang convert record.txt → x.json...")

while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			-- PLACE: không được sai định dạng
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*("?[^,"]+"?),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
			if a1 and name and x and y and z and rot then
				name = name:gsub('^%s*"(.-)"%s*$', '%1') -- loại bỏ dấu "
				local cost = GetTowerPlaceCostByName(name)
				local vector = x .. ", " .. y .. ", " .. z
				table.insert(logs, {
					TowerPlaceCost = tonumber(cost) or 0,
					TowerPlaced = name,
					TowerVector = vector,
					Rotation = rot,
					TowerA1 = tostring(a1)
				})
				print("[✓] PLACE:", name, vector)
			else
				-- UPGRADE
				local axis, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if axis and path then
					local axisX = tonumber(axis)
					path = tonumber(path)
					local tower = GetTowerByAxis(axisX)
					if tower then
						local before = GetPathLevel(tower, path)
						task.wait(0.1)
						local after = GetPathLevel(tower, path)
						if after and before and after > before then
							table.insert(logs, {
								UpgradeCost = 0,
								UpgradePath = path,
								TowerUpgraded = axisX
							})
							print(string.format("[✓] UPGRADE: %.2f | path %d | %d➜%d", axisX, path, before, after))
						else
							print(string.format("[✗] Upgrade failed: X=%.2f path=%d", axisX, path))
						end
					end
				end

				-- CHANGE TARGET
				local axis, qtype = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
				if axis and qtype then
					local tower = GetTowerByAxis(tonumber(axis))
					if tower then
						local pos = GetTowerPosition(tower)
						table.insert(logs, {
							ChangeTarget = pos.X,
							TargetType = tonumber(qtype)
						})
						print("[✓] TARGET:", pos.X, qtype)
					end
				end

				-- SELL
				local axis = line:match('TDX:sellTower%(([^%)]+)%)')
				if axis then
					local tower = GetTowerByAxis(tonumber(axis))
					if tower then
						local pos = GetTowerPosition(tower)
						table.insert(logs, {
							SellTower = pos.X
						})
						print("[✓] SELL:", pos.X)
					end
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	task.wait(0.22)
end
