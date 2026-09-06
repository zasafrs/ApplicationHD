local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")



local BMS = {}

function BMS:Knockback(Character, Data)
	local Bodymover

	for _, BodyMover: BodyVelocity in Character:GetDescendants() do
		if BodyMover:IsA('BodyVelocity') or BodyMover:IsA('LinearVelocity') then
			BodyMover:Destroy()
		end
	end

	if Data.KnockbackType == "Velocity" then
		Bodymover = Instance.new("BodyVelocity")
		Bodymover.MaxForce = Data.MaxForce
		Bodymover.Velocity = Data.Velocity
		if Data.P then
			Bodymover.P = Data.P
		end
		if Data.D  then
			Bodymover.D = Data.D
		end
	elseif Data.KnockbackType == "Position" then
		Bodymover = Instance.new("BodyPosition")
		Bodymover.MaxForce = Data.MaxForce 
		Bodymover.Position = Data.Position
		if Data.P then
			Bodymover.P = Data.P
		end
		if Data.D  then
			Bodymover.D = Data.D
		end
	elseif Data.KnockbackType == "Linear" then
		Bodymover = Instance.new("LinearVelocity")
		Bodymover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		Bodymover.MaxAxesForce = Data.MaxForce
		Bodymover.VectorVelocity = Data.Velocity
		if Data.P then
			Bodymover.P = Data.P
		end
		if Data.D  then
			Bodymover.D = Data.D
		end
		Bodymover.Attachment0 = Character.HumanoidRootPart.RootAttachment
	elseif Data.KnockbackType == "VelocityTweenDown" then
		Bodymover = Instance.new("BodyVelocity")
		Bodymover.MaxForce = Data.MaxForce
		Bodymover.Velocity = Data.Velocity
		if Data.P then
			Bodymover.P = Data.P
		end
		if Data.D  then
			Bodymover.D = Data.D
		end

		local TweenFX = game:GetService("TweenService"):Create(Bodymover, TweenInfo.new(Data.Time, Enum.EasingStyle.Sine,Enum.EasingDirection.Out), { Velocity = Vector3.new(0,0,0) })
		TweenFX:Play()
	end

	if Character:FindFirstChild('Humanoid') then
		Bodymover.Parent = Character.HumanoidRootPart
	else
		Bodymover.Parent = Character
	end


	if Data.Time then
		Debris:AddItem(Bodymover, Data.Time)
	else
		Debris:AddItem(Bodymover, .1)
	end
end

function BMS:makeEnemyFaceCharacter(Enemy, Character)
	Enemy.HumanoidRootPart.CFrame = CFrame.lookAlong(Enemy.HumanoidRootPart.Position, Character.HumanoidRootPart.CFrame.LookVector) * CFrame.Angles(0, math.rad(180), 0)
end

return BMS
