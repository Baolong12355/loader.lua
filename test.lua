-- rewrite_unsure with full debug repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local HttpService = game:GetService("HttpService") local Players = game:GetService("Players") local ReplicatedStorage = game:GetService("ReplicatedStorage") local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe require tower module local function SafeRequire(module) local success, result = pcall(require, module) return success and result or nil end

local function LoadTowerClass() local ps = player:WaitForChild("PlayerScripts") local client = ps:WaitForChild("Client") local gameClass = client:WaitForChild("GameClass") local towerModule = gameClass:WaitForChild("TowerClass") return SafeRequire(towerModule) end

local TowerClass = LoadTowerClass() if not TowerClass then error("[ERROR] Không thể tải TowerClass") end

-- Lấy tower theo X local function GetTowerByAxis(axisX) for hash, tower in pairs(TowerClass.GetTowers()) do local model = tower.Character and tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) if root and math.abs(root.Position.X - axisX) <= 1 then local hp = tower.HealthHandler and tower.HealthHandler:GetHealth() if hp and hp > 0 then return hash, tower end end end return nil, nil end

local function WaitForCash(amount) while cashStat.Value < amount do warn("[WaitForCash] Chờ tiền:", amount, ", hiện tại:", cashStat.Value) task.wait(0.1) end end

local function PlaceTowerRetry(args, axisX, towerName) warn("[PlaceTower] Bắt đầu đặt:", towerName, "X =", axisX) local t0 = tick() while tick() - t0 < 5 do Remotes.PlaceTower:InvokeServer(unpack(args)) warn("[PlaceTower] Thử đặt tower...") task.wait(0.15) local hash, tower = GetTowerByAxis(axisX) if hash and tower then warn("[PlaceTower] Thành công:", towerName) return true end end warn("[PlaceTower] Thất bại:", towerName) return false end

local function UpgradeTowerRetry(axisX, upgradePath) warn("[UpgradeTower] Bắt đầu nâng: X =", axisX, "path:", upgradePath) local maxTries = 5 for i = 1, maxTries do local hash, tower = GetTowerByAxis(axisX) if hash and tower and tower.LevelHandler then local hp = tower.HealthHandler and tower.HealthHandler:GetHealth() if hp and hp > 0 then local lvlBefore = tower.LevelHandler:GetLevelOnPath(upgradePath) local maxLvl = tower.LevelHandler:GetMaxLevel() if lvlBefore >= maxLvl then warn("[UpgradeTower] Đã max cấp") return end

local success, cost = pcall(function()
				return tower.LevelHandler:GetLevelUpgradeCost(upgradePath, lvlBefore)
			end)
			if not success then
				warn("[UpgradeTower] Không lấy được giá nâng cấp")
				return
			end

			warn("[UpgradeTower] Giá:", cost, " Cấp:", lvlBefore, "/", maxLvl)
			WaitForCash(cost)
			Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

			local t0 = tick()
			while tick() - t0 < 2 do
				task.wait(0.15)
				local _, t = GetTowerByAxis(axisX)
				if t and t.LevelHandler then
					local lvlAfter = t.LevelHandler:GetLevelOnPath(upgradePath)
					if lvlAfter > lvlBefore then
						warn("[UpgradeTower] Thành công nâng lên cấp:", lvlAfter)
						return
					end
				end
			end
			warn("[UpgradeTower] Thử lại lần:", i)
		end
	else
		warn("[UpgradeTower] Không tìm thấy tower để nâng")
	end
	task.wait(0.3)
end
warn("[UpgradeTower] Thất bại nâng tower X =", axisX)

end

local function SellTowerRetry(axisX) warn("[SellTower] Bán tower X =", axisX) local t0 = tick() while tick() - t0 < 2 do local hash = GetTowerByAxis(axisX) if hash then Remotes.SellTower:FireServer(hash) task.wait(0.2) local stillExists = GetTowerByAxis(axisX) if not stillExists then warn("[SellTower] Đã bán") return end else return end task.wait(0.1) end end

local function ChangeTargetRetry(axisX, targetType) warn("[Target] Đổi target X =", axisX, "->", targetType) local t0 = tick() while tick() - t0 < 2 do local hash = GetTowerByAxis(axisX) if hash then Remotes.ChangeQueryType:FireServer(hash, targetType) return end task.wait(0.1) end end

-- Load macro local config = getgenv().TDX_Config or {} local macroPath = config["Macro Path"] or "tdx/macros/x.json"

if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end

local success, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end) if not success then error("Lỗi khi đọc macro") end

warn("[Macro] Bắt đầu chạy", #macro, "lệnh") for i, entry in ipairs(macro) do warn("[Macro] Lệnh:", i) if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then local vecTab = entry.TowerVector:split(", ") local pos = Vector3.new(unpack(vecTab)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0) } WaitForCash(entry.TowerPlaceCost) PlaceTowerRetry(args, pos.X, entry.TowerPlaced)

elseif entry.TowerUpgraded and entry.UpgradePath then
	local axisValue = tonumber(entry.TowerUpgraded)
	UpgradeTowerRetry(axisValue, tonumber(entry.UpgradePath))

elseif entry.ChangeTarget and entry.TargetType then
	local axisValue = tonumber(entry.ChangeTarget)
	ChangeTargetRetry(axisValue, tonumber(entry.TargetType))

elseif entry.SellTower then
	local axisValue = tonumber(entry.SellTower)
	SellTowerRetry(axisValue)
end

end

warn("✅ rewrite_unsure HOÀN TẤT")

