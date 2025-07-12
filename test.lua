local tower = require(game:GetService("Players").LocalPlayer.PlayerScripts
    :WaitForChild("Client")
    :WaitForChild("GameClass")
    :WaitForChild("TowerClass")
    .GetTower(towerHash) -- Thay towerHash bằng hash của tower

if tower and tower.CurrentTarget and not tower.CurrentTargetIsTower then
    print("Tower đang target enemy:", tower.CurrentTarget)
else
    print("Tower chưa có mục tiêu hoặc đang target tower khác.")
end
