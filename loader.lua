local webhook_url = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"
if webhook_url == "YOUR_WEBHOOK_URL_HERE" then return end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local PlaceId = game.PlaceId

repeat wait() until game:IsLoaded() and Players.LocalPlayer
local player = Players.LocalPlayer

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

if getgenv().TDX_Config["mapvoting"] ~= nil then getgenv().TDX_Config["Voter"] = true end
if getgenv().TDX_Config["loadout"] ~= nil then getgenv().TDX_Config["Loadout"] = true end

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

if PlaceId == 9503261072 then
    for k,v in pairs(getgenv().TDX_Config) do
        if k ~= "Join Map" then
            getgenv().TDX_Config[k] = nil
        end
    end
end

sendToWebhook({
    title = "Script Initialized",
    description = "User **`" .. player.Name .. "`** (ID: `" .. player.UserId .. "`) has started the script.",
    color = 8359053,
    footer = { text = "Loader Log" },
    timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
})

for name, url in pairs(links) do
    local enabled = getgenv().TDX_Config[name] or false
    spawn(function() tryRun(player.Name, name, enabled, url) end)
end

local macro_type = getgenv().TDX_Config["Macros"]
if macro_type == "run" or macro_type == "record" then
    local macroName = (macro_type == "run") and "Run Macro" or "Record Macro"
    getgenv().TDX_Config["Macro Name"] = macro_type:sub(1,1)
    sendToWebhook({
        title = "Macro Usage Detected",
        description = "User **`" .. player.Name .. "`** has activated the **`" .. macroName .. "`**.",
        fields = {{ name = "Macro Name", value = "`" .. getgenv().TDX_Config["Macro Name"] .. "`" }},
        color = 4886754,
        footer = { text = "Loader Log" },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
    })
    spawn(function() tryRun(player.Name, macroName, true, links[macroName]) end)
end