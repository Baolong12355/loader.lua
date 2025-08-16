getgenv().ANUBISREQUIEM = true

task.spawn(function()
    while getgenv().ANUBISREQUIEM == true do
        pcall(function()
            local QTE = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("QuickTimeEvent")
            QTE:Destroy()
        end)
        task.wait(0.1);
    end
end)

task.spawn(function()
    while getgenv().ANUBISREQUIEM == true do
        pcall(function()
            game:GetService("ReplicatedStorage"):WaitForChild("Start"):FireServer()
        end)
        task.wait(0.1);
    end
end)

task.spawn(function()
    while getgenv().ANUBISREQUIEM == true do
        pcall(function()
            local gameid = game.PlaceId
            if (gameid == 8534845015) then
                local TeleportService = game:GetService("TeleportService")
                local PLACE_ID = 119078961994407
                local Localplayer = game:GetService("Players").LocalPlayer;
                TeleportService:Teleport(PLACE_ID, Localplayer)
            end
        end)
        task.wait(0.5);
    end
end)