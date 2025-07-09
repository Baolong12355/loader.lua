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

-- Safe require TowerClass
local function SafeRequire(module)
	local ok, result = pcall(require, module)
	return ok and result or nil
end

local TowerClass
do
	local client = PlayerScripts:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	TowerClass = SafeRequire(towerModule)
end

-- Kiểm tra module
if not TowerClass or type(TowerClass.GetTowers) ~= "function" then
	error("❌ Không thể load TowerClass")
end

-- Lấy vị trí tower
local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position or nil
end

-- Lấy giá đặt tower
local function GetTowerPlaceCostByName(name)
	local gui = player:FindFirstChild("PlayerGui")
	local bar = gui and gui:FindFirstChild("Interface") and gui.Interface:FindFirstChild("BottomBar")
	local towersBar = bar and bar:FindFirstChild("TowersBar")
	if not towersBar then return 0 end

	for _, t in ipairs(towersBar:GetChildren()) do
		if t.Name == name then
			local text = t:FindFirstChild("CostFrame") and t.CostFrame:FindFirstChild("CostText")
			if text then
				return tonumber(text.Text:gsub("%D", "")) or 0
			end
		end
	end
	return 0
end

-- Tạo folder nếu chưa có
if makefolder then
	pcall(function() makefolder("tdx") end)
	pcall(function() makefolder("tdx/macros") end)
end

-- Map hash -> tower info
local hashInfo = {}
task.spawn(function()
	while true do
		for hash, tower in pairs(TowerClass.GetTowers()) do
			local pos = GetTowerPosition(tower)
			if pos and tower.LevelHandler then
				hashInfo[tostring(hash)] = {
					x = pos.X,
					lv1 = tower.LevelHandler:GetLevelOnPath(1),
					lv2 = tower.LevelHandler:GetLevelOnPath(2)
				}
			end
		end
		task.wait(0.1)
	end
end)

print("✅ Đã bắt đầu convert record.txt → x.json")

while true do
	if isfile(txtFile) then
		local macro = readfile(txtFile)
		local logs = {}

		for line in macro:gmatch("[^\r\n]+") do
			local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*([%d%.]+),%s*([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)%)')
			if a1 and name and x and y and z and rot then
				table.insert(logs, {
					TowerA1 = a1,
					TowerPlaced = name,
					TowerVector = x .. ", " .. y .. ", " .. z,
					Rotation = rot,
					TowerPlaceCost = GetTowerPlaceCostByName(name)
				})
			else
				local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*(%d),')
				if hash and path then
					local pathNum = tonumber(path)
					local info = hashInfo[tostring(hash)]
					local tower = TowerClass.GetTowers()[hash]
					if tower and tower.LevelHandler and info then
						local before = pathNum == 1 and info.lv1 or info.lv2
						task.wait(0.1)
						local after = tower.LevelHandler:GetLevelOnPath(pathNum)
						if after > before then
							table.insert(logs, {
								TowerUpgraded = info.x,
								UpgradePath = pathNum,
								UpgradeCost = 0
							})
						end
					end
				else
					local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*(%d)%)')
					if hash and targetType then
						local info = hashInfo[tostring(hash)]
						if info then
							table.insert(logs, {
								ChangeTarget = info.x,
								TargetType = tonumber(targetType)
							})
						end
					else
						local hash = line:match('TDX:sellTower%(([^%)]+)%)')
						if hash then
							local info = hashInfo[tostring(hash)]
							if info then
								table.insert(logs, {
									SellTower = info.x
								})
							end
						end
					end
				end
			end
		end

		writefile(outJson, HttpService:JSONEncode(logs))
	end
	wait(0.22)
end
