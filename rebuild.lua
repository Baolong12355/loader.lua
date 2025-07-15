-- *****************************************
--  RUN_MACRO  v12  (full compatibility)
--  – thay thế file gốc của bạn
--  – rebuild tự động khi SuperFunction = rebuild
-- *****************************************
local HttpService    = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players        = game:GetService("Players")
local player         = Players.LocalPlayer
local cashStat       = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes        = ReplicatedStorage:WaitForChild("Remotes")

-------------------------------------------------
-- Safe require
local function SafeRequire(path, timeout)
	timeout = timeout or 5
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local ok,res = pcall(require, path)
		if ok then return res end
		task.wait()
	end
	return nil
end

-- Load TowerClass
local TowerClass
do
	local ps=player:WaitForChild("PlayerScripts")
	local cli=ps:WaitForChild("Client")
	local gc=cli:WaitForChild("GameClass")
	TowerClass = SafeRequire(gc:WaitForChild("TowerClass"))
	if not TowerClass then error("Không thể tải TowerClass") end
end
local function Towers() return TowerClass.GetTowers() end

-------------------------------------------------
-- Utilities
local function PosOf(tower)
	local model = tower.Character:GetCharacterModel()
	local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
	return root and root.Position
end
local function ByX(axisX)
	for h,t in pairs(Towers()) do
		local pos = PosOf(t)
		if pos and math.abs(pos.X - axisX) <= 1 then
			local hp = t.HealthHandler and t.HealthHandler:GetHealth()
			if hp and hp>0 then return h,t end
		end
	end
	return nil,nil
end

local function UpgradeCost(t,path)
	if not t or not t.LevelHandler then return end
	local ok,c = pcall(function()
		return t.LevelHandler:GetLevelUpgradeCost(path,1)
	end)
	return ok and c or nil
end

local function WaitCash(amt)
	while cashStat.Value < amt do task.wait() end
end

-------------------------------------------------
-- Actions – 100 % giữ nguyên logic retry
local function PlaceRetry(args, x, name)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		local t0=tick() repeat task.wait(.1) until ByX(x) or tick()-t0>2
		if ByX(x) then return end
		warn("[RETRY] Đặt thất bại, thử lại:",name,x)
	end
end

local function UpgradeRetry(x,path,mode)
	local max = mode=="rewrite" and math.huge or 3
	local tries = 0
	while tries < max do
		local h,t=ByX(x)
		if not t then if mode~="rewrite" then warn("[SKIP] ko thấy tower x",x) return end tries+=1 task.wait(); continue end
		local before = t.LevelHandler:GetLevelOnPath(path)
		local cost = UpgradeCost(t,path); if not cost then return end
		WaitCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(h,path,1)
		local ok=false local t0=tick()
		repeat task.wait(.1)
			local _,tw=ByX(x) if tw and tw.LevelHandler then ok=tw.LevelHandler:GetLevelOnPath(path)>before end
		until ok or tick()-t0>2
		if ok then return end
		tries+=1; task.wait()
	end
end

local function TargetRetry(x,typ)
	repeat local h=ByX(x); if h then Remotes.ChangeQueryType:FireServer(h,typ); return end task.wait() until false end
local function SellRetry(x)
	repeat local h=ByX(x); if h then Remotes.SellTower:FireServer(h); task.wait(.1); if not ByX(x) then return end end task.wait() until false end

-------------------------------------------------
-- Metric: globalPlaceMode (đồng bộ với gốc)
local cfg = getgenv().TDX_Config or {}
local macroName = cfg["Macro Name"] or "y"
local macroDir  = "tdx/macros/"
globalPlaceMode = cfg["PlaceMode"] or "normal"
if globalPlaceMode=="unsure" then globalPlaceMode="rewrite" elseif globalPlaceMode=="normal" then globalPlaceMode="ashed" end

-- *****************************************
--  REBUILD HANDLER
-- *****************************************
local function rebuild(jsonObj)
	local skip = jsonObj.Skip or {}
	local be    = jsonObj.Be  or false
	local kept = {}

	for _,t in pairs(Towers()) do
		local nm=t.Type
		local pos=PosOf(t)
		if not pos then continue end
		local skipNow = be   -- Nếu be=true : chỉ skip nếu tower hiện tại nằm trong Skip
				  and table.find(skip,nm)
				  or (not be and table.find(skip,nm))
		if not skipNow then
			table.insert(kept,{x=pos.X})
		end
	end

	local path=macroDir.."R.json"
	writefile(path, HS:JSONEncode(kept))
	warn("🔁 Rebuild R.json ..",#kept,"tower x")
	return path
end

-- *****************************************
--  MAIN EXECUTOR – duyệt liên tiếp file
--  (có rebuild auto)
-- *****************************************
local function execute(filePath)
	if not isfile(filePath) then warn("file not found:",filePath) return end
	local suc,macro=pcall(function() return HS:JSONDecode(readfile(filePath)) end)
	if not suc then warn("malformed json:",filePath) return end

	for _,entry in ipairs(macro) do
		-- Case rebuild
		if entry.SuperFunction == "rebuild" then
			local newPath=rebuild(entry)
			return execute(newPath)  -- jump sang macro mới R.json
		end

		-- NORMAL
		if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
			local v=Vector3.new(unpack(entry.TowerVector:gsub("[%Vector3new()%s]",""):split(",")))
			local args={tonumber(entry.TowerA1),entry.TowerPlaced,v,tonumber(entry.Rotation or 0)}
			WaitCash(entry.TowerPlaceCost)
			PlaceRetry(args,v.X,entry.TowerPlaced)

		elseif entry.TowerUpgraded and entry.UpgradePath then
			UpgradeRetry(tonumber(entry.TowerUpgraded),entry.UpgradePath,globalPlaceMode)

		elseif entry.ChangeTarget and entry.TargetType then
			TargetRetry(tonumber(entry.ChangeTarget),entry.TargetType)

		elseif entry.SellTower then
			SellRetry(tonumber(entry.SellTower))
		end
	end
	print("✅ Macro hoàn thành:",filePath)
end

-- khởi chạy
execute(macroDir..macroName..".json")
