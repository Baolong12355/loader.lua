
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ⚙️ Webhook URL
local WEBHOOK_URL = https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC" -- <<== ĐỔI LINK TẠI ĐÂY

-- ✅ Kiểm tra có thể gửi webhook
local function canSend()
	local hasExecutor = typeof(getgenv) == "function" or typeof(syn) == "table" or typeof(is_synapse_function) == "function" or typeof(http_request) == "function"
	local ok, httpEnabled = pcall(function() return HttpService.HttpEnabled end)
	return hasExecutor and ok and httpEnabled
end

-- 🔁 Chuyển table sang dạng Discord fields
local function fieldsFromTable(tab, prefix)
	local fields = {}
	prefix = prefix and (prefix .. " ") or ""
	for k, v in pairs(tab) do
		if typeof(v) == "table" then
			for _, f in ipairs(fieldsFromTable(v, prefix .. k)) do
				table.insert(fields, f)
			end
		else
			table.insert(fields, {name = prefix .. tostring(k), value = tostring(v), inline = false})
		end
	end
	return fields
end

-- 📨 Format JSON cho Discord
local function formatDiscordEmbed(data, title)
	title = title or (data.type == "game" and "Game Result" or "Lobby Info")
	local fields = {}
	if data.stats then
		fields = fieldsFromTable(data.stats)
	elseif data.rewards then
		fields = fieldsFromTable(data.rewards)
	else
		fields = fieldsFromTable(data)
	end
	return HttpService:JSONEncode({
		embeds = {{
			title = title,
			color = 0x5B9DFF,
			fields = fields
		}}
	})
end

-- 🚀 Gửi webhook
local function sendToWebhook(data)
	if not canSend() then return end
	local body = formatDiscordEmbed(data)
	if typeof(http_request) == "function" then
		pcall(function()
			http_request({
				Url = WEBHOOK_URL,
				Method = "POST",
				Headers = {["Content-Type"] = "application/json"},
				Body = body
			})
		end)
	else
		pcall(function()
			HttpService:PostAsync(WEBHOOK_URL, body, Enum.HttpContentType.ApplicationJson)
		end)
	end
end

-- 🏠 Gửi dữ liệu lobby
local function sendLobbyInfo()
	local stats = {
		Level = LocalPlayer.leaderstats and LocalPlayer.leaderstats.Level and LocalPlayer.leaderstats.Level.Value or "N/A",
		Wins  = LocalPlayer.leaderstats and LocalPlayer.leaderstats.Wins and LocalPlayer.leaderstats.Wins.Value or "N/A",
		Gold  = LocalPlayer.PlayerGui and LocalPlayer.PlayerGui.GUI and LocalPlayer.PlayerGui.GUI.NewGoldDisplay 
			and LocalPlayer.PlayerGui.GUI.NewGoldDisplay.GoldText and LocalPlayer.PlayerGui.GUI.NewGoldDisplay.GoldText.Text or "N/A"
	}
	sendToWebhook({type = "lobby", stats = stats})
end

-- 🧠 Hook DisplayScreen từ GameOverRewardsScreenHandler
local function hookGameOver()
	local success, err = pcall(function()
		local RewardsHandler = require(LocalPlayer.PlayerScripts.Client.UserInterfaceHandler:WaitForChild("GameOverRewardsScreenHandler"))
		local oldDisplayScreen = RewardsHandler.DisplayScreen

		RewardsHandler.DisplayScreen = function(delay1, delay2, data)
			task.spawn(function()
				local name = LocalPlayer.Name
				local rewardData = {
					type = "game",
					rewards = {
						Map = data.MapName or "Unknown",
						Mode = tostring(data.Difficulty),
						Time = data.TimeElapsed and tostring(data.TimeElapsed) or "N/A",
						Result = data.Victory and "Victory" or "Defeat",
						Gold = tostring((data.PlayerNameToGoldMap or {})[name] or 0),
						XP = tostring((data.PlayerNameToXPMap or {})[name] or 0),
						Tokens = tostring((data.PlayerNameToTokensMap or {})[name] or 0),
						PowerUps = {}
					}
				}
				local powerups = (data.PlayerNameToPowerUpsRewardedMapMap or {})[name] or {}
				for id, count in pairs(powerups) do
					table.insert(rewardData.rewards.PowerUps, id .. " x" .. tostring(count))
				end
				sendToWebhook(rewardData)
			end)
			return oldDisplayScreen(delay1, delay2, data)
		end
	end)
	if not success then warn("Webhook hook error: ", err) end
end

-- 🎯 Xác định ở lobby hay trong trận
local function isLobby()
	local gui = LocalPlayer.PlayerGui:FindFirstChild("GUI")
	return gui and gui:FindFirstChild("NewGoldDisplay")
end

-- 🚦 Chạy
if isLobby() then
	sendLobbyInfo()
else
	hookGameOver()
end