local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CombatSystem = {}


function CombatSystem.setupPlayer(player)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end


	local isBusy = character:FindFirstChild("IsBusy")
	if not isBusy then
		isBusy = Instance.new("BoolValue")
		isBusy.Name = "IsBusy"
		isBusy.Value = false
		isBusy.Parent = character
	end

	local isStun = character:FindFirstChild("IsStun")
	if not isStun then
		isStun = Instance.new("BoolValue")
		isStun.Name = "IsStun"
		isStun.Value = false
		isStun.Parent = character
	end

	local isInvincible = character:FindFirstChild("IsInvincible")
	if not isInvincible then
		isInvincible = Instance.new("BoolValue")
		isInvincible.Name = "IsInvincible"
		isInvincible.Value = false
		isInvincible.Parent = character
	end

	local isBlocking = character:FindFirstChild("IsBlocking")
	if not isBlocking then
		isBlocking = Instance.new("BoolValue")
		isBlocking.Name = "IsBlocking"
		isBlocking.Value = false
		isBlocking.Parent = character
	end

	local isCountering = character:FindFirstChild("IsCountering")
	if not isCountering then
		isCountering = Instance.new("BoolValue")
		isCountering.Name = "IsCountering"
		isCountering.Value = false
		isCountering.Parent = character
	end


	if not humanoid:GetAttribute("OriginalWS") then
		humanoid:SetAttribute("OriginalWS", humanoid.WalkSpeed)
	end
end

function CombatSystem.createHitbox(user, size, offset)
	local character 
	if user:IsA("Player") then
		character = user.Character
	else
		character = user
	end
	print("triggered")
	if not character then return {} end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return {} end
	local hitboxSize = size or Vector3.new(4, 6, 6)
	local hitboxOffset = offset or Vector3.new(0, 0, -3)
	local hitboxCFrame = humanoidRootPart.CFrame * CFrame.new(hitboxOffset.X, hitboxOffset.Y, hitboxOffset.Z)
	local hitboxPart = Instance.new("Part")
	hitboxPart.Name = "Hitbox"
	hitboxPart.Anchored = true
	hitboxPart.CanCollide = false
	hitboxPart.Transparency = 1
	hitboxPart.Size = hitboxSize
	hitboxPart.CFrame = hitboxCFrame
	hitboxPart.Parent = workspace
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character}
	local partsInRegion = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
	local targets = {}
	for _, part in pairs(partsInRegion) do
		local targetCharacter = part.Parent
		if targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid") then
			if targetCharacter and targetCharacter ~= character then
				table.insert(targets, targetCharacter)
			end
		end
	end
	hitboxPart:Destroy()
	return targets
end

function CombatSystem.takeDamage(target, damage, damageType, attacker)
	local targetCharacter
	if typeof(target) == "Instance" and target:IsA("Player") then
		targetCharacter = target.Character
	elseif typeof(target) == "Instance" and target:FindFirstChildOfClass("Humanoid") then
		targetCharacter = target
	else
		return false
	end
	if not targetCharacter then return false end
	local targetHumanoid = targetCharacter:FindFirstChild("Humanoid")
	if not targetHumanoid then return false end

	local canTakeDamage = true



	if CombatSystem.isBlocking(targetCharacter) then
		canTakeDamage = false
		print((target.Name or targetCharacter.Name) .. " blocked the attack!")
	end

	if CombatSystem.isCountering(targetCharacter) then
		canTakeDamage = false
		print((target.Name or targetCharacter.Name) .. " countered the attack!")
		if attacker then
			CombatSystem.takeDamage(attacker, damage * 1.5, "counter", target)
		end
	end

	if CombatSystem.isInvincible(targetCharacter) then
		canTakeDamage = false
		print((target.Name or targetCharacter.Name) .. " is invincible!")
	end

	if canTakeDamage then
		targetHumanoid.Health = math.max(0, targetHumanoid.Health - damage)
		print((target.Name or targetCharacter.Name) .. " took " .. damage .. " damage from " .. (attacker and (attacker.Name or "unknown") or "unknown"))
		return true
	end
	return false
end


function CombatSystem.setBusy(character, busy)
	if not character then return end
	local isBusy = character:FindFirstChild("IsBusy")
	if isBusy then
		isBusy.Value = busy
	end
end

function CombatSystem.setStun(character, stun)
	if not character then return end
	local isStun = character:FindFirstChild("IsStun")
	if isStun then
		isStun.Value = stun
	end
end

function CombatSystem.setBlocking(character, blocking)
	if not character then return end
	local isBlocking = character:FindFirstChild("IsBlocking")
	if isBlocking then
		isBlocking.Value = blocking
	end
end

function CombatSystem.setCountering(character, countering)
	if not character then return end
	local isCountering = character:FindFirstChild("IsCountering")
	if isCountering then
		isCountering.Value = countering
	end
end

function CombatSystem.setInvincible(character, invincible)
	if not character then return end
	local isInvincible = character:FindFirstChild("IsInvincible")
	if isInvincible then
		isInvincible.Value = invincible
	end
end



function CombatSystem.isBusy(character)
	if not character then return false end
	local isBusy = character:FindFirstChild("IsBusy")
	if isBusy then
		return isBusy.Value
	end
	return false
end

function CombatSystem.isStun(character)
	if not character then return false end
	local isStun = character:FindFirstChild("IsStun")
	if isStun then
		return isStun.Value
	end
	return false
end

function CombatSystem.isBlocking(character)
	if not character then return false end
	local isBlocking = character:FindFirstChild("IsBlocking")
	if isBlocking then
		return isBlocking.Value
	end
	return false
end

function CombatSystem.isCountering(character)
	if not character then return false end
	local isCountering = character:FindFirstChild("IsCountering")
	if isCountering then
		return isCountering.Value
	end
	return false
end

function CombatSystem.isInvincible(character)
	if not character then return false end
	local isInvincible = character:FindFirstChild("IsInvincible")
	if isInvincible then
		return isInvincible.Value
	end
	return false
end


function CombatSystem.applyStun(character, stunDuration, stunType, attacker)
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return end


	CombatSystem.setStun(character, true)

	if activeMoves then
		local player = Players:GetPlayerFromCharacter(character)
		if player and activeMoves[player.UserId] and not CombatSystem.isInvincible(character) then
			local moveData = activeMoves[player.UserId]
			if moveData.cancelFunction then
				moveData.cancelFunction()
			end
			activeMoves[player.UserId] = nil
		end
	end


	local originalWalkSpeed = humanoid:GetAttribute("OriginalWS") or 16
	stunType = stunType or "light"

	if stunType == "heavy" then

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0


		local stunAnim = AnimationModule and AnimationModule.PlayAnimation(character, "HeavyStun")

	
		local bodyPosition = Instance.new("BodyPosition")
		bodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bodyPosition.Position = rootPart.Position
		bodyPosition.D = 2000
		bodyPosition.P = 10000
		bodyPosition.Parent = rootPart

		spawn(function()
			wait(stunDuration)
			if bodyPosition and bodyPosition.Parent then
				bodyPosition:Destroy()
			end
			if stunAnim then
				stunAnim:Stop()
			end
			CombatSystem.setStun(character, false)
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalWalkSpeed
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end
		end)

	elseif stunType == "light" then
	
		humanoid.WalkSpeed = originalWalkSpeed * 0.3

	
		local stunAnim = AnimationModule and AnimationModule.PlayAnimation(character, "LightStun")

		spawn(function()
			wait(stunDuration)
			if stunAnim then
				stunAnim:Stop()
			end
			CombatSystem.setStun(character, false)
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalWalkSpeed
			end
		end)

	elseif stunType == "blockbreak" then

		humanoid.WalkSpeed = 0
		CombatSystem.setBlocking(character, false)


		local breakAnim = AnimationModule and AnimationModule.PlayAnimation(character, "BlockBreak")


		if game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents") and 
			game:GetService("ReplicatedStorage").RemoteEvents:FindFirstChild("DashClient") then
			game:GetService("ReplicatedStorage").RemoteEvents.DashClient:FireAllClients({
				type = "BlockBreak",
				Player = Players:GetPlayerFromCharacter(character),
				Position = rootPart.Position
			})
		end

		spawn(function()
			wait(stunDuration)
			if breakAnim then
				breakAnim:Stop()
			end
			CombatSystem.setStun(character, false)
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = originalWalkSpeed
			end
		end)

	else

		spawn(function()
			wait(stunDuration)
			CombatSystem.setStun(character, false)
		end)
	end
end


function CombatSystem.handleCombatHit(attacker, victim, damage, canBreakBlock, stunDuration, stunType)
	if not victim or not attacker then return false end

	stunDuration = stunDuration or 0.5
	stunType = stunType or "light"


	if CombatSystem.isInvincible(victim) then
		return false
	end


	if CombatSystem.isBlocking(victim) then
		if canBreakBlock then
		
			CombatSystem.applyStun(victim, stunDuration * 1.5, "blockbreak", attacker)
			return true
		else
		
			return false
		end
	end


	CombatSystem.applyStun(victim, stunDuration, stunType, attacker)

	return true 
end


function CombatSystem.canUseMove(character)
	if not character then return false end


	if CombatSystem.isBusy(character) or CombatSystem.isStun(character) then 
		return false 
	end

	return true
end


function CombatSystem.cleanup(player)
	-- Not done.
end


Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		wait(1) 
		CombatSystem.setupPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	CombatSystem.cleanup(player)
end)

return CombatSystem
