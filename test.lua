-- this is the RELEASE version of autohop
repeat task.wait() until game:IsLoaded()
if game.PlaceId ~= 2809202155 then return end

--// 📦 Services & Variables
local replicatedFirst = game:GetService("ReplicatedFirst")
local replicatedStorage = game:GetService("ReplicatedStorage")
local plr = game.Players.LocalPlayer
local itemSpawns = workspace["Item_Spawns"].Items
local plrGui = plr.PlayerGui
local coregui = game.CoreGui
local loaded = false
local Option = getgenv().Settings.SellAll and "Option2" or "Option1"
local luckyBought = false

--// 📁 Folder & File Setup

if not isfolder("YBA_AUTOHOP") then makefolder("YBA_AUTOHOP") end
if not isfile("YBA_AUTOHOP/Count.txt") then writefile("YBA_AUTOHOP/Count.txt", "") end
if not isfile("YBA_AUTOHOP/lastLucky.txt") then
    writefile("YBA_AUTOHOP/lastLucky.txt","")
end
if not isfile("YBA_AUTOHOP/theme.mp3") then
    local response = request({Url = "https://raw.githubusercontent.com/crcket/YBA/refs/heads/main/Diavolo%20Theme%20but%20it's%20EPIC%20VERSION%20(King%20Crimson%20Requiem).mp3",Method = "GET"})
    if response.StatusCode == 200 then
        writefile("YBA_AUTOHOP/theme.mp3", response.Body)
        print("File saved successfully!")
    else
        warn("Failed to download file. Status Code:", response.StatusCode)
    end
end
--// ⏳ Wait for Core Game Objects
repeat task.wait() until game:IsLoaded() and game.ReplicatedStorage and game.ReplicatedFirst 
    and plr and plr.Character and plr.PlayerGui and plr:FindFirstChild("PlayerStats")

--// 🔁 Server Hop Function
local function serverHop()
    local gameId = game.PlaceId
    local servers, cursor = {}, ""

    repeat
        local success, result = pcall(function()
            return game.HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/" .. gameId .. "/servers/Public?sortOrder=Asc&limit=100&cursor=" .. cursor
            ))
        end)

        if success and result and result.data then
            for _, server in ipairs(result.data) do
                if server.playing >= 14 and server.playing < server.maxPlayers and server.id ~= game.JobId then
                    table.insert(servers, server.id)
                end
            end
            cursor = result.nextPageCursor or ""
        else
            break
        end
    until cursor == "" or #servers >= 1

    if #servers > 0 then
        game:GetService("TeleportService"):TeleportToPlaceInstance(gameId, servers[math.random(1, #servers)], plr)
    else
        warn("No available servers found.")
    end
end

--// 📬 Webhook Notification Handler
local function webHookHandler(Mode)
    local lCount = 1
    for _, item in pairs(plr.Backpack:GetChildren()) do
        if item.Name == "Lucky Arrow" then
            lCount += 1
        end
    end

    local textContent, titleContent, descriptionContent, colorContent, imageContent, thumbnailContent, footerContent

    if Mode == "luckyArrow" then
        
        local req = request({Url = `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds={plr.UserId}&size=48x48&format=png`})
        local body = game:GetService("HttpService"):JSONDecode(req.Body)

        titleContent = plr.Name
        descriptionContent = os.date("%I:%M %p")
        colorContent = 16776960
        imageContent = {url = "https://static.wikia.nocookie.net/your-bizarre-adventure/images/f/fd/LuckyArrow.png/revision/latest?cb=20221020062009"}
        thumbnailContent = {url = body.data[1].imageUrl}
        
        if getgenv().Settings.PingOnLuckyArrow and lCount >=9 and readfile("YBA_AUTOHOP/lastLucky.txt") ~= plr.Name then
            
            writefile("YBA_AUTOHOP/lastLucky.txt",plr.Name)
            warn(getgenv().Settings.DiscordID)
            textContent = `<@{getgenv().Settings.DiscordID}>, your account, {plr.Name} has ~9/9 lucky arrows`
        end
        footerContent = {text = `{lCount}/9 lucky arrows`}
    end

    request({
        Url = getgenv().Settings.URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = game:GetService("HttpService"):JSONEncode({
            content = textContent,
            embeds = {{
                title = titleContent,
                description = descriptionContent,
                color = colorContent,
                image = imageContent,
                thumbnail = thumbnailContent,
                footer = footerContent,
            }}
        })
    })
end

--// 🎒 Inventory Processor
local function processInventory()
    if not getgenv().Settings.SellAll then return end

    local uniqueItems = {}
    for _, item in ipairs(plr.Backpack:GetChildren()) do
        uniqueItems[item.Name] = item
    end

    for name, item in pairs(uniqueItems) do
        if name ~= "Lucky Arrow" and name ~= "Stand Arrow" then
            task.wait(0.5)
            plr.Character.Humanoid:EquipTool(item)
            plr.Character.RemoteEvent:FireServer("EndDialogue", {
                NPC = "Merchant",
                Option = Option,
                Dialogue = "Dialogue5"
            })
        end
    end
end

-- Auto Sell Inventory Every 12 Seconds
task.spawn(function()
    while task.wait(12) do
        processInventory()
    end
end)

--// 🔧 Main Setup
local function setup()
    -- Hook "Returner" InvokeServer call
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        if tostring(self) == "Returner" and tostring(getnamecallmethod()) == "InvokeServer" then
            return "  ___XP DE KEY"
        end
        return old(self, ...)
    end)

    -- Prevent spawn distance checks
    local vector3Metatable = getrawmetatable(Vector3.new())
    local oldIndex = vector3Metatable.__index
    setreadonly(vector3Metatable, false)
    vector3Metatable.__index = newcclosure(function(self, idx)
        if string.lower(idx) == "magnitude" and getcallingscript() == replicatedFirst.ItemSpawn then
            return 0
        end
        return oldIndex(self, idx)
    end)
    setreadonly(vector3Metatable, true)

    -- Rename items based on their prompt text
    for _, item in pairs(itemSpawns:GetChildren()) do
        local prox = item:WaitForChild("ProximityPrompt", 9)
        item.Name = prox.ObjectText
    end

    -- Handle newly spawned items
    itemSpawns.ChildAdded:Connect(function(item)
        print("new item added to workspace")
        local prox = item:WaitForChild("ProximityPrompt", 9)
        item.Name = prox.ObjectText
        for _, v in pairs(itemSpawns:GetDescendants()) do
            if v:IsA("ProximityPrompt") and v.MaxActivationDistance == 0 and v.Name ~= "Proximity Prompt __" then
                v.Name = "ProximityPrompt __"
            end
        end

        for _, v in pairs(itemSpawns:GetChildren()) do
            if not v:FindFirstChild("ProximityPrompt") then v:Destroy() end
        end
    end)
end

local function checkForKickMessage()
    local message = coregui:FindFirstChild("RobloxPromptGui")
    if message and message:FindFirstChild("ErrorPrompt", true) then
        return true
    end
    return false
end

--// ▶️ Skip Loading Screen and Enter Game
if not plr.Character:FindFirstChild("RemoteEvent") then
    task.wait(1)    
end
plr.Character.RemoteEvent:FireServer("PressedPlay")
loaded = true
task.spawn(function()
    workspace:WaitForChild("LoadingScreen",90):WaitForChild("Song",90).SoundId = getcustomasset("YBA_AUTOHOP/theme.mp3")
end)

--// 🚀 Start Automation
if not getgenv().Settings.AutoFarm then return end
repeat task.wait(0.5) until loaded
local console = loadstring(game:HttpGet("https://raw.githubusercontent.com/crcket/ROBLOX/refs/heads/main/crckonsle.lua"))()

task.wait(12)
setup()
print("ran setup")
task.spawn(function()
    console.Send(`ran setup @ {game.JobId}!`,"ANNOUNCEMENT")
end)

--// 🧲 Auto Pickup Logic
local isNotOnAlready = true
local lastPickupTime = tick()
itemSpawns.ChildAdded:Connect(function(item)
    repeat task.wait() until item.Name ~= "Model" and isNotOnAlready and not plr.Character.HumanoidRootPart.Anchored
    if getgenv().Settings.AutoFarm and item.PrimaryPart and item:FindFirstChild("ProximityPrompt __") then
        print(`-> picking up {item.Name}!`)
        task.spawn(function() console.Send(`picking up {item.Name}!`,"ITEM_PICKUP") end)
        lastPickupTime = tick()
        isNotOnAlready = false
        plr.Character.HumanoidRootPart.CFrame = item.PrimaryPart.CFrame
        task.wait(getgenv().Settings.PickupDelay or 0.5)
        firesignal(item:FindFirstChildWhichIsA("ProximityPrompt").Triggered)
        spawn(function()
            task.wait((getgenv().Settings.PickupDelay or 0.5)+0.5)
            if item.Parent then
                firesignal(item:FindFirstChildWhichIsA("ProximityPrompt").Triggered)
                task.wait((getgenv().Settings.PickupDelay or 0.5)+0.5)
                if item.Parent then
                    item.Parent = nil
                    task.spawn(function()
                        console.Send(`{item.Name} took too long to pick up.. deleting`,"ITEM_TIMEOUT")
                    end)
                end
            end
        end)
        item.AncestryChanged:Wait()
        isNotOnAlready = true
        plr.Character.HumanoidRootPart.CFrame = CFrame.new(-23, -33, 28)
    end
end)

--// 🧾 Auto Sell When "Message" Pops Up
plrGui.ChildAdded:Connect(function(thing)
    if thing.Name == "Message" then
        task.wait()
        local itemName = thing:WaitForChild("TextLabel").Text:match("%d+%s+(.+) in your inventory"):gsub("%(s%)$", "")
        local item = plr.Backpack:FindFirstChild(itemName)
        if item then item.Parent = plr.Character end

        plr.Character.RemoteEvent:FireServer("EndDialogue", {
            NPC = "Merchant",
            Option = Option,
            Dialogue = "Dialogue5"
        })
    end
end)

--// 🍀 Auto Buy Lucky Arrows
plr.PlayerStats.Money.Changed:Connect(function()
    if not luckyBought and plr.PlayerStats.Money.Value >= 50000 then
        local luckyNum = 0
        for _, v in pairs(plr.Backpack:GetChildren()) do
            if v.Name == "Lucky Arrow" then luckyNum += 1 end
        end
        if luckyNum <= 8 then
            luckyBought = true
            task.wait(1)
            plr.Character.RemoteEvent:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
            webHookHandler("luckyArrow")
            local log = `{plr.Name} {os.date("%I:%M %p")}\n`
            writefile("YBA_AUTOHOP/Count.txt", readfile("YBA_AUTOHOP/Count.txt") .. log)
        else
            luckyBought = true
            if getgenv().Settings.PingOnLuckyArrow then
                warn(readfile("YBA_AUTOHOP/lastLucky.txt"))
                if readfile("YBA_AUTOHOP/lastLucky.txt") == plr.Name then
                    else
                    webHookHandler("luckyArrow")
                end
                warn("didthislucksend")
            end
            getgenv().Settings.SellAll = false
            Option = "Option1"
        end
    end
end)

--// ⏰ Server Hop if Inactive
task.spawn(function()
    while task.wait(0.5) do
        if tick() - lastPickupTime > 5*2 or checkForKickMessage() then -- 10*2 to account for 0.5
            serverHop() -- maybe lastditch l8r
        end
    end
end)