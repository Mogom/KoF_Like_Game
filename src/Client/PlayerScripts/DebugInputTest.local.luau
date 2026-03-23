--local UserInputService = game:GetService("UserInputService")
--local Players = game:GetService("Players")

--local player = Players.LocalPlayer
--print("DebugInputTest running for player:", player.Name)

--UserInputService.InputBegan:Connect(function(input, processed)
--	print("[InputBegan] processed:", processed, "UserInputType:", input.UserInputType, "KeyCode:", input.KeyCode)
--	if input.UserInputType == Enum.UserInputType.Keyboard then
--		if input.KeyCode == Enum.KeyCode.W then
--			print("W detected by InputBegan (Keyboard). processed=", processed)
--		elseif input.KeyCode == Enum.KeyCode.Space then
--			print("Space detected by InputBegan (Keyboard). processed=", processed)
--		end
--	end
--end)