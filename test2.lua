local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local function autoAscend()
    local abilityId = LocalPlayer.Data.Ability.Value
    if not abilityId then return end

    local coinLabel = LocalPlayer.PlayerGui.UI.Menus.Ability.Tabs.Ascensions.AscendSection.Requirements.UCoins.AmountLabel
    local levelLabel = LocalPlayer.PlayerGui.UI.Menus.Ability.Tabs.Ascensions.AscendSection.Requirements.Level.AmountLabel

    if not coinLabel or not levelLabel then return end

    local coinText = coinLabel.ContentText or ""
    local levelText = levelLabel.ContentText or ""

    if coinText == "" or levelText == "" then return end

    local currentCoins, requiredCoins = coinText:match("(%d+)%s*/%s*(%d+)")
    if not currentCoins or not requiredCoins then return end
    currentCoins = tonumber(currentCoins)
    requiredCoins = tonumber(requiredCoins)

    local currentLevel, requiredLevel = levelText:match("(%d+)%s*/%s*(%d+)")
    if not currentLevel or not requiredLevel then return end
    currentLevel = tonumber(currentLevel)
    requiredLevel = tonumber(requiredLevel)

    if currentCoins >= requiredCoins and currentLevel >= requiredLevel then
        local AscendAbility = ReplicatedStorage.ReplicatedModules.KnitPackage.Knit.Services.LevelService.RF.AscendAbility
        AscendAbility:InvokeServer(abilityId)
    end
end

-- Chạy liên tục mỗi 3 giây
task.spawn(function()
    while true do
        pcall(autoAscend)
        task.wait(3) -- chỉnh lại số giây nếu muốn chạy nhanh hoặc chậm hơn
    end
end)