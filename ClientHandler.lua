--[[
	Dash / Movement Client

	This module handles the client-side presentation and movement of dash
	actions sent through DashClient. It is responsible for:

	- Applying directional dash velocity
	- Updating velocity relative to the character's facing direction
	- Creating dash-specific environmental VFX
	- Spawning temporary ground rocks based on the map surface
	- Dispatching replicated dash actions through a small move catalogue

	The server decides when a dash occurs, while this module handles the
	movement/visual side of the move when it receives the replicated event.
]]

---------------------------------------------------------------------
-- Services / dependencies
---------------------------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")



local player = Players.LocalPlayer

local MoveHandler = {}

local DashSpeed = 85

---------------------------------------------------------------------
-- Ground raycasting
---------------------------------------------------------------------

-- Rock VFX should only use actual map geometry as its surface.
-- Including only workspace.Map prevents characters, effects, or other
-- temporary objects from being mistaken for the ground.
local MapRayParams = RaycastParams.new()

MapRayParams.IgnoreWater = true
MapRayParams.RespectCanCollide = true
MapRayParams.CollisionGroup = "Map"
MapRayParams.FilterType = Enum.RaycastFilterType.Include
MapRayParams.FilterDescendantsInstances = {
	workspace.Map
}

local function raycast(origin, direction)
	return workspace:Raycast(
		origin,
		direction,
		MapRayParams
	)
end

---------------------------------------------------------------------
-- Environmental dash effects
---------------------------------------------------------------------

local RocksReplication = {

	RockTrail = function(params)

		local parent = params.parent
		local size = params.size
		local side = params.side
		local t = params.t
		local spawnrate = params.spawnrate
		local duration = params.duration

		-- Spawn rocks repeatedly for the requested duration instead of
		-- creating the entire trail in a single frame.
		for i = 1, duration / spawnrate do

			local HumRP =
				parent.Parent:FindFirstChild("HumanoidRootPart")

			local DebrisTime = 0.5

			-- Each individual trail gets its own folder so all temporary
			-- debris can be cleaned together after the effect finishes.
			local Folder = Instance.new("Folder")

			Folder.Parent = workspace.Debris or workspace
			Folder.Name = "Rocks"

			local function rocknew(finalSide)

				-- Determine the actual floor beneath the character.
				-- This allows rocks to copy the material/color of whatever
				-- surface the player is currently dashing across.
				local ray = raycast(
					parent.Position,
					Vector3.new(0, -3.5, 0)
				)

				if ray then

					local p = Instance.new("Part")

					p.Name = "RockTrailPart"
					p.Anchored = true
					p.CanCollide = false
					p.Shape = Enum.PartType.Block
					p.Material = Enum.Material.Rock
					p.Size = Vector3.new(0.1, 0.1, 0.1)

					Debris:AddItem(p, t + 1)

					DebrisTime = DebrisTime + t + 1

					-- Offset the rock to either side of the character.
					p.CFrame =
						CFrame.new(ray.Position)
						* CFrame.new(finalSide, 0, 0)

					p.Parent = Folder

					-- Copying the hit surface makes the effect blend into
					-- different map materials automatically.
					p.Color = ray.Instance.Color
					p.Material = ray.Instance.Material

					-- Rocks quickly grow into view instead of appearing
					-- instantly, making the trail feel more physical.
					TweenService:Create(
						p,
						TweenInfo.new(0.25),
						{
							Size = Vector3.new(
								size,
								size,
								size
							)
						}
					):Play()

					-- After remaining visible for t seconds, shrink the
					-- debris before Debris removes the instance.
					task.delay(t, function()

						TweenService:Create(
							p,
							TweenInfo.new(0.5),
							{
								Size = Vector3.new(0, 0, 0)
							}
						):Play()

					end)

					-- Random orientation prevents every rock from looking
					-- like an identical repeated cube.
					p.Orientation = Vector3.new(
						math.random(-180, 180),
						math.random(-180, 180),
						math.random(-180, 180)
					)

					-----------------------------------------------------
					-- Ground smoke
					-----------------------------------------------------

					-- Smoke remains active while the raycast detects a
					-- valid surface underneath the character.
					if HumRP
						and HumRP:FindFirstChild("BottomPart")
					then

						local bottomPart = HumRP.BottomPart

						if bottomPart:FindFirstChild("Smoke")
							and bottomPart.Smoke:FindFirstChild("Smoke")
						then

							if bottomPart.Smoke.Smoke.Enabled == false then
								bottomPart.Smoke.Smoke.Enabled = true
							end
						end
					end

				else

					-- Disable ground smoke when no surface exists below
					-- the character, such as when dashing through the air.
					if HumRP
						and HumRP:FindFirstChild("BottomPart")
					then

						local bottomPart = HumRP.BottomPart

						if bottomPart:FindFirstChild("Smoke")
							and bottomPart.Smoke:FindFirstChild("Smoke")
						then

							if bottomPart.Smoke.Smoke.Enabled == true then
								bottomPart.Smoke.Smoke.Enabled = false
							end
						end
					end
				end
			end

			task.spawn(function()

				-- side == 0 creates one central trail.
				-- Otherwise a mirrored pair of rocks is produced on both
				-- sides of the character.
				if side == 0 then

					rocknew(side)

				else

					rocknew(side)
					rocknew(-side)

				end

				Debris:AddItem(
					Folder,
					DebrisTime
				)
			end)

			task.wait(spawnrate)
		end

		-----------------------------------------------------------------
		-- Effect cleanup
		-----------------------------------------------------------------

		local HumRP =
			parent.Parent:FindFirstChild("HumanoidRootPart")

		-- Ensure smoke cannot remain enabled after the rock trail ends.
		if HumRP
			and HumRP:FindFirstChild("BottomPart")
		then

			local bottomPart = HumRP.BottomPart

			if bottomPart:FindFirstChild("Smoke")
				and bottomPart.Smoke:FindFirstChild("Smoke")
			then

				if bottomPart.Smoke.Smoke.Enabled == true then
					bottomPart.Smoke.Smoke.Enabled = false
				end
			end
		end
	end,
}

---------------------------------------------------------------------
-- Front dash visual
---------------------------------------------------------------------

function MoveHandler.createDashVFX(rootPart)

	-- The dash ring is cloned locally because this effect does not need
	-- to exist permanently or affect gameplay state.
	local dashvfx =
		ReplicatedStorage
		:FindFirstChild("VFX")
		:FindFirstChild("Dash")
		:FindFirstChild("Ring")
		:Clone()

	dashvfx.Parent =
		workspace.VFX or workspace

	local lookDirection =
		rootPart.CFrame.LookVector

	local offsetPosition =
		rootPart.Position

	-- Align the effect with the character's current forward direction.
	dashvfx.CFrame =
		CFrame.lookAt(
			offsetPosition,
			offsetPosition + lookDirection,
			Vector3.new(0, 1, 0)
		)
		* CFrame.Angles(
			0,
			math.rad(-90),
			0
		)

	dashvfx.Transparency = 1

	task.wait()

	-- Emit only the particles needed for one dash rather than enabling
	-- continuous particle emission.
	if dashvfx.yaya then
		dashvfx.yaya:Emit(15)
	end

	if dashvfx.Attachment
		and dashvfx.Attachment.dash
	then

		dashvfx.Attachment.dash:Emit(1)
	end

	-- Remove the temporary VFX after its particles have had time to finish.
	Debris:AddItem(
		dashvfx,
		4
	)
end

---------------------------------------------------------------------
-- Dash movement
---------------------------------------------------------------------

function MoveHandler.DashCharacter(params)

	local DashType = params.Type
	local Character = params.Character

	local HumRP =
		Character.HumanoidRootPart

	local Humanoid =
		Character:FindFirstChild("Humanoid")

	-----------------------------------------------------------------
	-- Forward dash
	-----------------------------------------------------------------

	if DashType == "Front" then

		-- Remove old BodyVelocity instances so multiple movement forces
		-- do not fight against each other.
		for _, velocity in pairs(HumRP:GetChildren()) do

			if velocity:IsA("BodyVelocity") then
				velocity:Destroy()
			end
		end

		-- Forward dashes create a wider rock trail on both sides.
		task.spawn(function()

			RocksReplication.RockTrail({
				parent = HumRP,
				size = 0.5,
				side = 2.5,
				t = 5,
				height = 5,
				spawnrate = 0.15,
				duration = 0.65
			})

		end)

		local dashVelocity =
			Instance.new("BodyVelocity")

		dashVelocity.Name = "Dash Velocity"

		-- No vertical force is used so the dash does not pull the
		-- character upward or downward.
		dashVelocity.MaxForce =
			Vector3.new(1, 0, 1) * 40000

		dashVelocity.P = 1250
		dashVelocity.Parent = HumRP

		-- NumberValue is used because TweenService can smoothly modify
		-- its value, creating gradual dash deceleration.
		local Speed =
			Instance.new("NumberValue")

		Speed.Value = 160

		-- Recalculate LookVector every rendered frame. This lets the dash
		-- continue following the character's current facing direction.
		local connection =
			RunService.RenderStepped:Connect(function()

				if dashVelocity.Parent ~= nil
					and Speed ~= nil
				then

					dashVelocity.Velocity =
						HumRP.CFrame.LookVector
						* Speed.Value
				end
			end)

		-- Rapid initial movement decelerates toward normal movement speed.
		local tn =
			TweenService:Create(
				Speed,
				TweenInfo.new(0.40),
				{
					Value = 20
				}
			)

		tn:Play()

		task.delay(0.40, function()

			connection:Disconnect()

			if dashVelocity
				and dashVelocity.Parent
			then

				dashVelocity:Destroy()
			end

			if Speed
				and Speed.Parent
			then

				Speed:Destroy()
			end

			if Humanoid then
				Humanoid.WalkSpeed = 0
			end
		end)

		-- WalkSpeed is temporarily delayed to prevent normal character
		-- movement from immediately overriding the end of the dash.
		task.delay(0.7, function()

			if Humanoid then
				Humanoid.WalkSpeed = 16
			end
		end)

	-----------------------------------------------------------------
	-- Side dash
	-----------------------------------------------------------------

	elseif DashType == "Side" then

		for _, bodyVelocity in pairs(HumRP:GetChildren()) do

			if bodyVelocity:IsA("BodyVelocity") then
				bodyVelocity:Destroy()
			end
		end

		-- Side dashes use a shorter centered debris trail because the
		-- character moves laterally rather than through the full effect.
		task.spawn(function()

			RocksReplication.RockTrail({
				parent = HumRP,
				size = 0.5,
				side = 0,
				t = 2.5,
				height = 5,
				spawnrate = 0.1,
				duration = 0.25
			})

		end)

		-- The same side-dash code can handle left and right.
		-- Mult simply reverses the RightVector direction.
		local Mult = -1

		if params.Right == true then
			Mult = 1
		end

		local dashVelocity =
			Instance.new("BodyVelocity")

		dashVelocity.Name = "Dash Velocity"

		dashVelocity.MaxForce =
			Vector3.new(
				100000,
				0,
				100000
			)

		dashVelocity.Parent = HumRP

		local Speed =
			Instance.new("NumberValue")

		Speed.Value = DashSpeed

		local connection =
			RunService.RenderStepped:Connect(function()

				if dashVelocity.Parent ~= nil
					and Speed ~= nil
				then

					dashVelocity.Velocity =
						HumRP.CFrame.RightVector
						* (Speed.Value * Mult)
				end
			end)

		-- Hold most of the dash speed briefly before easing back toward
		-- walking speed.
		task.delay(0.25, function()

			TweenService:Create(
				Speed,
				TweenInfo.new(0.25),
				{
					Value = 16
				}
			):Play()

		end)

		Debris:AddItem(
			Speed,
			0.5
		)

		Debris:AddItem(
			dashVelocity,
			0.5
		)

		task.delay(0.5, function()
			connection:Disconnect()
		end)

	-----------------------------------------------------------------
	-- Back dash
	-----------------------------------------------------------------

	elseif DashType == "Back" then

		for _, bodyVelocity in pairs(HumRP:GetChildren()) do

			if bodyVelocity:IsA("BodyVelocity") then
				bodyVelocity:Destroy()
			end
		end

		task.spawn(function()

			RocksReplication.RockTrail({
				parent = HumRP,
				size = 0.5,
				side = 2,
				t = 3,
				height = 5,
				spawnrate = 0.1,
				duration = 0.4
			})

		end)

		local Speed =
			Instance.new("NumberValue")

		local dashVelocity =
			Instance.new("BodyVelocity")

		dashVelocity.Name = "Dash Velocity"

		dashVelocity.MaxForce =
			Vector3.new(
				100000,
				0,
				100000
			)

		dashVelocity.Parent = HumRP

		Debris:AddItem(
			Speed,
			0.951
		)

		Debris:AddItem(
			dashVelocity,
			0.951
		)

		-- Back dash is split into two separate bursts. Each burst starts
		-- fast and eases toward zero, giving it a different movement
		-- profile from the continuous forward dash.
		for i = 1, 2 do

			Speed.Value = 85

			local connection =
				RunService.RenderStepped:Connect(function()

					if dashVelocity.Parent ~= nil
						and Speed ~= nil
					then

						dashVelocity.Velocity =
							-HumRP.CFrame.LookVector
							* Speed.Value
					end
				end)

			local tweenTime = 0.234

			if i == 2 then

				tweenTime =
					0.075 + 0.20

				task.wait(0.25)

			else

				task.wait(0.233)

			end

			TweenService:Create(
				Speed,
				TweenInfo.new(
					tweenTime,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.Out
				),
				{
					Value = 0
				}
			):Play()

			task.wait(0.234)

			if i == 2 then
				connection:Disconnect()
			end
		end
	end
end

---------------------------------------------------------------------
-- Direction conversion / dash entry point
---------------------------------------------------------------------

function MoveHandler.handleDash(character, dashDirection)

	if not character then
		return
	end

	local humanoid =
		character:FindFirstChild("Humanoid")

	local rootPart =
		character:FindFirstChild("HumanoidRootPart")

	if not humanoid
		or not rootPart
	then
		return
	end

	-- Only the forward dash uses the ring burst.
	if dashDirection == "Front" then
		MoveHandler.createDashVFX(rootPart)
	end

	local params = {
		Character = character,
		Type = dashDirection
	}

	-- Left/right share one Side implementation so movement behavior is
	-- not duplicated unnecessarily.
	if dashDirection == "Left" then

		params.Type = "Side"
		params.Right = false

	elseif dashDirection == "Right" then

		params.Type = "Side"
		params.Right = true
	end

	MoveHandler.DashCharacter(params)
end

---------------------------------------------------------------------
-- Replicated move catalogue
---------------------------------------------------------------------

-- Incoming actions are looked up through this table instead of a large
-- chain of if-statements. Additional replicated movement effects can be
-- added here without changing the event listener itself.
MoveHandler.moves = {

	Dash = function(params)

		local targetPlayer =
			params.Player

		if targetPlayer then

			MoveHandler.handleDash(
				targetPlayer.Character,
				params.Direction
			)
		end
	end,

	ResetPose = function(params)

		local character =
			params.Character

		if not character then
			return
		end

		-- Motor6D.Transform may still contain temporary animation offsets.
		-- Resetting it over several simulation frames makes sure the pose
		-- remains cleared after the previous animation state finishes.
		for _ = 1, 8 do

			RunService.PreSimulation:Wait()

			for _, motor in ipairs(character:GetDescendants()) do

				if motor:IsA("Motor6D") then
					motor.Transform = CFrame.identity
				end
			end
		end
	end
}

---------------------------------------------------------------------
-- Server -> client move replication
---------------------------------------------------------------------

ReplicatedStorage
	.RemoteEvents
	.DashClient
	.OnClientEvent
	:Connect(function(params)

		local moveType =
			params.type

		-- Ignore unknown replicated action types rather than attempting
		-- to execute arbitrary data received through the event.
		if MoveHandler.moves[moveType] then
			MoveHandler.moves[moveType](params)
		end
	end)

return MoveHandler
