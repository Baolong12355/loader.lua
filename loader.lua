local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}

-- Kiểm tra game hiện tại có phải lobby TDX không
local function isInTDXLobby()
	return game.PlaceId == 9503261072 -- ID lobby TDX
end

-- Hàm chạy link
local function tryRun(name, enabled, url)
	if enabled == nil or enabled == false then
		print("⏭️ Bỏ qua (tắt/null):", name)
		return
	end
	if typeof(enabled) == "string" and enabled:lower() == "null" then
		print("⏭️ Bỏ qua (null string):", name)
		return
	end
	if typeof(url) == "string" and url:match("^https?://") then
		print("⏳ Đang tải:", name)
		local ok, result = pcall(function()
			return loadstring(game:HttpGet(url))()
		end)
		if ok then
			print("✅ Đã chạy:", name)
		else
			warn("❌ Lỗi chạy:", name, result)
		end
	else
		warn("⛔ Link không hợp lệ cho:", name)
	end
end

-- Link raw chính xác
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
	["x1.5 Speed"]      = base .. "speed.lua",
	["Auto Skill"]      = base .. "auto_skill.lua",
	["Run Macro"]       = base .. "run_macro.lua",
	["Return Lobby"]    = base .. "return_lobby.lua",
	["Join Map"]        = base .. "auto_join.lua",
	["Auto Difficulty"] = base .. "difficulty.lua"
}

-- Chạy loader theo đúng vị trí game
task.spawn(function()
	-- 🚩 Luôn chạy tăng tốc sớm
	tryRun("x1.5 Speed", config["x1.5 Speed"], links["x1.5 Speed"])
	task.wait(0.5)

	if isInTDXLobby() then
		-- 📌 Chỉ chạy ở lobby
		tryRun("Join Map", config["Map"], links["Join Map"])
		task.wait(0.5)

		tryRun("Auto Difficulty", config["Auto Difficulty"], links["Auto Difficulty"])
		task.wait(0.5)
	else
		-- ⚔️ Chỉ chạy trong trận
		tryRun("Run Macro", config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
		task.wait(0.5)

		tryRun("Auto Skill", config["Auto Skill"], links["Auto Skill"])
		task.wait(0.5)

		tryRun("Return Lobby", true, links["Return Lobby"])
	end
end)
