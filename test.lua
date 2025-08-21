getgenv().stopCombat = function()
    combatSettings.enabled = false
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    if combatConnection then
        combatConnection:Disconnect()
        combatConnection = nil
    end
    print("Combat system stopped from console!")
end