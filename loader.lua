-- webhook
local webhook_url = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"
if webhook_url == "YOUR_WEBHOOK_URL_HERE" then return end

-- services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

repeat wait() until game:IsLoaded() and Players.LocalPlayer
local player = Players.LocalPlayer

-- kiểm tra place ID để skip một số tính năng
local currentPlaceId = game.PlaceId
local shouldSkipFeatures = (currentPlaceId == 9503261072)

-- send webhook
local function sendToWebhook(embedData)
    local data = { ["embeds"] = {embedData} }
    local json = HttpService:JSONEncode(data)

    pcall(function()
        local headers = {["Content-Type"] = "application/json"}
        local requestData = {Url = webhook_url, Method = "POST", Headers = headers, Body = json}

        if syn and syn.request then
            syn.request(requestData)
        elseif request then
            request(requestData)
        elseif http and http.request then
            http.request(requestData)
        else
            HttpService:PostAsync(webhook_url, json, Enum.HttpContentType.ApplicationJson)
        end
    end)
end

-- chạy script từ url
local function tryRun(playerName, name, enabled, url)
    if not (enabled and typeof(url) == "string" and url:match("^https?://")) then return end

    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)

    if ok then
        sendToWebhook({
            title = "Function Loaded Successfully",
            description = "Function **`" .. name .. "`** has been loaded for user **`" .. playerName .. "`**.",
            color = 3066993,
            fields = {{ name = "Source URL", value = "`" .. url .. "`" }},
            footer = { text = "Loader Log" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
        })
    else
        sendToWebhook({
            title = "Function Failed to Load",
            description = "Function **`" .. name .. "`** failed to load for user **`" .. playerName .. "`**.",
            color = 15158332,
            fields = {
                { name = "Source URL", value = "`" .. url .. "`" },
                { name = "Error Message", value = "```\n" .. tostring(result) .. "\n```" }
            },
            footer = { text = "Loader Log" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
        })
    end
end

-- sửa config tạm
if getgenv().TDX_Config["mapvoting"] ~= nil then getgenv().TDX_Config["Voter"] = true end
if getgenv().TDX_Config["loadout"] ~= nil then getgenv().TDX_Config["Loadout"] = true end

-- đường dẫn scripts
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed.lua",
    ["Auto Skill"]      = base .. "auto_skill.lua",
    ["Run Macro"]       = base .. "run_macro.lua",
    ["Record Macro"]    = base .. "record.lua",
    ["Join Map"]        = base .. "auto_join.lua",
    ["Auto Difficulty"] = base .. "difficulty.lua",
    ["Return Lobby"]    = base .. "return_lobby.lua",
    ["Heal"]            = base .. "heal.lua",
    ["Loadout"]         = base .. "loadout.lua",
    ["Voter"]           = base .. "voter.lua"
}

-- báo bắt đầu
local initMessage = "User **`" .. player.Name .. "`** (ID: `" .. player.UserId .. "`) has started the script."
if shouldSkipFeatures then
    initMessage = initMessage .. " **[Place ID " .. currentPlaceId .. " - Some features disabled]**"
end

sendToWebhook({
    title = "Script Initialized",
    description = initMessage,
    color = 8359053,
    footer = { text = "Loader Log" },
    timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
})

-- load các chức năng (một số sẽ bị skip nếu ở place ID 9503261072)
-- Các tính năng luôn chạy (không bị skip)
spawn(function() tryRun(player.Name, "Join Map", getgenv().TDX_Config["Map"] ~= nil, links["Join Map"]) end)

-- Các tính năng bị skip nếu ở place ID 9503261072
if not shouldSkipFeatures then
    spawn(function() tryRun(player.Name, "Return Lobby",     getgenv().TDX_Config["Return Lobby"],    links["Return Lobby"]) end)
    spawn(function() tryRun(player.Name, "x1.5 Speed",       getgenv().TDX_Config["x1.5 Speed"],      links["x1.5 Speed"]) end)
    spawn(function() tryRun(player.Name, "Auto Difficulty",  getgenv().TDX_Config["Auto Difficulty"] ~= nil, links["Auto Difficulty"]) end)
    spawn(function() tryRun(player.Name, "Heal",             getgenv().TDX_Config["Heal"],            links["Heal"]) end)
    spawn(function() tryRun(player.Name, "Loadout",          getgenv().TDX_Config["Loadout"],         links["Loadout"]) end)
    spawn(function() tryRun(player.Name, "Voter",            getgenv().TDX_Config["Voter"],           links["Voter"]) end)
    spawn(function() tryRun(player.Name, "Auto Skill",       getgenv().TDX_Config["Auto Skill"],      links["Auto Skill"]) end)
else
    -- Gửi thông báo về việc skip các tính năng
    sendToWebhook({
        title = "Features Skipped",
        description = "User **`" .. player.Name .. "`** - Skipped features due to Place ID: `" .. currentPlaceId .. "`",
        color = 16776960, -- Màu vàng
        fields = {{
            name = "Skipped Features",
            value = "• Return Lobby\n• x1.5 Speed\n• Auto Difficulty\n• Heal\n• Loadout\n• Voter\n• Auto Skill"
        }},
        footer = { text = "Loader Log" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
    })
end

-- macro (không bị ảnh hưởng bởi place ID)
local macro_type = getgenv().TDX_Config["Macros"]
if macro_type == "run" or macro_type == "record" then
    local macroName = (macro_type == "run") and "Run Macro" or "Record Macro"

    sendToWebhook({
        title = "Macro Usage Detected",
        description = "User **`" .. player.Name .. "`** has activated the **`" .. macroName .. "`**.",
        color = 4886754,
        footer = { text = "Loader Log" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
    })

    spawn(function() tryRun(player.Name, macroName, true, links[macroName]) end)
end