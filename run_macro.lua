-- [TDX] Macro Runner - Final Version with Correct Tower Validation
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Cấu hình macro
local config = getgenv().TDX_Config or {}
local mode = config["Macros"] or "run"
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"

-- SafeRequire (tải module đúng cách)
local function SafeRequire(path, timeout)
	timeout = timeout or 5
	local start = os.clock()
	while os.clock() - start < timeout do
		local ok, result = pcall(function() return require(path) end)
		if ok then return result end
		task.wait(0.1)
	end
	return nil
end

-- Load TowerClass chuẩn
local function LoadTowerClass()
	local ps = player:WaitForChild("PlayerScripts")
	local client = ps:FindFirstChild("Client")
	if not client then return end
	local gameClass = client:FindFirstChild("GameClass")
	if not gameClass then return end
	local towerModule = gameClass:FindFirstChild("TowerClass")
	if not towerModule then return end
	return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then
	error("❌ Không thể load TowerClass.")
end

-- === HỖ TRỢ KIỂM TRA TOWER ===
local function GetTowerPosition(tower)
	if not tower or not tower.Character then return nil end
	local model = tower.Character:GetCharacterModel()
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return root and root.Position or nil
end

local function GetTowerHealth(tower)
	if not tower or not tower.HealthHandler then return 0 end
	local success, health = pcall(function()
		return tower.HealthHandler:GetHealth()
	end)
	return (success and health) or 0
end

local function IsAliveTowerAt(position, radius)
	for _, tower in pairs(TowerClass.GetTowers()) do
		local pos = GetTowerPosition(tower)
		if pos and (pos - position).Magnitude <= radius then
			local health = GetTowerHealth(tower)
			if health > 0 then
				return tower
			end
		end
	end
	return nil
end

local function GetAnyTowerAt(position, radius)
	for _, tower in pairs(TowerClass.GetTowers()) do
		local pos = GetTowerPosition(tower)
		if pos and (pos - position).Magnitude <= radius then
			return tower
		end
	end
	return nil
end

local function Vector3FromString(str)
	local x, y, z = str:match("([^,]+), ([^,]+), ([^,]+)")
	return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
end

-- === HÀM TIỀN ===
local function WaitForCash(amount)
	local timeout = os.clock() + 30
	while cashStat.Value < amount do
		if os.clock() > timeout then return false end
		task.wait(0.1)
	end
	return true
end

-- === MAIN RUN ===
local actionDone = {}

if mode == "run" then
	if not isfile(macroPath) then
		error("❌ Không tìm thấy file macro: " .. macroPath)
	end

	local success, macro = pcall(function()
		return HttpService:JSONDecode(readfile(macroPath))
	end)
	if not success then
		error("❌ Lỗi đọc macro:", macro)
	end

	print("▶️ Bắt đầu macro với", #macro, "thao tác")

	for index, entry in ipairs(macro) do
		if actionDone[index] then continue end

		-- ▶️ Đặt tower
		if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
			local pos = Vector3FromString(entry.TowerVector)
			if GetAnyTowerAt(pos, 1) then
				print("⚠️ Đã có tower tại vị trí, bỏ qua.")
				actionDone[index] = true continue
			end

			if not WaitForCash(entry.TowerPlaceCost) then
				print("❌ Không đủ tiền đặt tower.")
				actionDone[index] = true continue
			end

			local args = {
				tonumber(entry.TowerA1) or 0,
				entry.TowerPlaced,
				pos,
				tonumber(entry.Rotation) or 0
			}

			local success = false
			for attempt = 1, 3 do
				Remotes.PlaceTower:InvokeServer(unpack(args))
				task.wait(0.2)
				if GetAnyTowerAt(pos, 1) then
					success = true break
				end
			end

			if success then
				print("✅ Đặt tower thành công:", entry.TowerPlaced)
			else
				print("❌ Đặt tower thất bại.")
			end
			actionDone[index] = true

		-- ▶️ Nâng cấp tower
		elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
			local pos = Vector3FromString(entry.TowerUpgraded)
			local tower = IsAliveTowerAt(pos, 1)
			if not tower then
				print("⚠️ Không tìm thấy tower còn sống tại vị trí.")
				actionDone[index] = true continue
			end

			if not WaitForCash(entry.UpgradeCost) then
				print("❌ Không đủ tiền nâng cấp.")
				actionDone[index] = true continue
			end

			local beforeLevel = tower.LevelHandler:GetLevelOnPath(entry.UpgradePath)
			local upgraded = false
			for i = 1, 3 do
				Remotes.TowerUpgradeRequest:FireServer(tower.Hash, entry.UpgradePath, 1)
				task.wait(0.2)
				tower = IsAliveTowerAt(pos, 1)
				if tower then
					local afterLevel = tower.LevelHandler:GetLevelOnPath(entry.UpgradePath)
					if afterLevel > beforeLevel then
						upgraded = true break
					end
				end
			end

			if upgraded then
				print("✅ Nâng cấp thành công (Lv." .. beforeLevel .. " → " .. (beforeLevel + 1) .. ")")
			else
				print("❌ Nâng cấp thất bại.")
			end
			actionDone[index] = true

		-- ▶️ Đổi target
		elseif entry.ChangeTarget and entry.TargetType then
			local pos = Vector3FromString(entry.ChangeTarget)
			local tower = IsAliveTowerAt(pos, 1)
			if not tower then
				print("⚠️ Không tìm thấy tower còn sống tại vị trí.")
				actionDone[index] = true continue
			end
			Remotes.ChangeQueryType:FireServer(tower.Hash, entry.TargetType)
			task.wait(0.2)
			actionDone[index] = true

		-- ▶️ Bán tower
		elseif entry.SellTower then
			local pos = Vector3FromString(entry.SellTower)
			local tower = GetAnyTowerAt(pos, 1)
			if not tower then
				print("⚠️ Không tìm thấy tower tại vị trí để bán.")
				actionDone[index] = true continue
			end
			Remotes.SellTower:FireServer(tower.Hash)
			task.wait(0.2)
			actionDone[index] = true
		end
	end

	print("✅ Đã hoàn thành tất cả thao tác macro.")
else
	print("ℹ️ Macro đang ở chế độ:", mode)
end
