--[[
	Move Server
	
	This script owns server-side execution of character moves.
	The client only tells the server which move was requested; the
	server validates state/cooldowns and performs hit detection/damage.

	Each active move gets a context object. The context owns temporary
	state and connections so that interruption, death, or respawning
	can cleanly restore everything the move changed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local MoveUtils = require(ReplicatedStorage.Modules.MoveHandler)
local AnimationModule = require(ServerScriptService.Modules.AnimInfo2)
local BodymoverService = require(ServerScriptService.Modules.BodymoverService)
local RagdollHandler = require(ServerScriptService.Modules.RagdollHandler2)
local CombatSystem = require(ServerScriptService.Modules.CombatSystem)

local MoveInput = ReplicatedStorage:WaitForChild("MoveInput")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local DashClient = RemoteEvents:WaitForChild("DashClient")

local AliveFolder = workspace:WaitForChild("Alive")

local HitVFXSource = ServerStorage
	:WaitForChild("Assets")
	:WaitForChild("VFX")
	:WaitForChild("hit vfx")

local activeMoves = {}

local VALID_DASH_DIRECTIONS = {
	Front = true,
	Back = true,
	Left = true,
	Right = true,
}

local DASH_ANIMATIONS = {
	Front = "DashFront",
	Back = "DashBack",
	Left = "DashLeft",
	Right = "DashRight",
}

---------------------------------------------------------------------
-- Character helpers
---------------------------------------------------------------------

local function getCharacterData(player)
	local character = player.Character

	if not character or not character.Parent then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return nil
	end

	if humanoid.Health <= 0 then
		return nil
	end

	return {
		character = character,
		humanoid = humanoid,
		rootPart = rootPart,
	}
end

local function getOriginalWalkSpeed(humanoid)
	return humanoid:GetAttribute("OriginalWS") or 16
end

local function getEffectPart(character)
	-- R6 characters have Torso, while R15 generally has UpperTorso.
	-- HRP is kept as a final fallback so effects still function.
	return character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------
-- Move context
---------------------------------------------------------------------

local function createMoveContext(player, moveName)
	local context = {
		player = player,
		moveName = moveName,

		closed = false,
		connections = {},
		cleanupCallbacks = {},
	}

	function context:isActive()
		return not self.closed
			and activeMoves[player.UserId] == self
	end

	function context:addConnection(connection)
		table.insert(self.connections, connection)
		return connection
	end

	function context:addCleanup(callback)
		table.insert(self.cleanupCallbacks, callback)
	end

	function context:close(reason)
		if self.closed then
			return
		end

		self.closed = true

		-- Disconnect events first. This prevents animation events from
		-- firing while the move is currently restoring its state.
		for _, connection in ipairs(self.connections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end

		table.clear(self.connections)

		-- Run cleanup in reverse order because later setup often depends
		-- on state established earlier in the move.
		for index = #self.cleanupCallbacks, 1, -1 do
			self.cleanupCallbacks[index](reason)
		end

		table.clear(self.cleanupCallbacks)

		if activeMoves[player.UserId] == self then
			activeMoves[player.UserId] = nil
		end
	end

	activeMoves[player.UserId] = context

	return context
end

local function cancelMove(player, expectedMoveName)
	local context = activeMoves[player.UserId]

	if not context then
		return
	end

	if expectedMoveName and context.moveName ~= expectedMoveName then
		return
	end

	context:close("cancelled")
end

---------------------------------------------------------------------
-- Temporary state helpers
---------------------------------------------------------------------

local function setCollisionGroup(character, newGroup)
	local originalGroups = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			originalGroups[descendant] = descendant.CollisionGroup
			descendant.CollisionGroup = newGroup
		end
	end

	return originalGroups
end

local function restoreCollisionGroups(originalGroups)
	for part, collisionGroup in pairs(originalGroups) do
		if part.Parent then
			part.CollisionGroup = collisionGroup
		end
	end
end

local function emitHitVFX(character)
	local targetPart = getEffectPart(character)

	if not targetPart then
		return
	end

	-- Only the attachment is needed. Cloning the entire VFX container
	-- every hit would leave unnecessary objects around.
	local sourceAttachment = HitVFXSource:FindFirstChildOfClass("Attachment")

	if not sourceAttachment then
		warn("Hit VFX does not contain an Attachment")
		return
	end

	local attachment = sourceAttachment:Clone()
	attachment.Parent = targetPart

	for _, object in ipairs(attachment:GetChildren()) do
		if object:IsA("ParticleEmitter") then
			if object.Name == "debrie" then
				object:Emit(20)
			else
				object:Emit(1)
			end
		end
	end

	-- Particles can continue rendering after Emit(), but the attachment
	-- itself should eventually be removed.
	Debris:AddItem(attachment, 3)
end

local function createSound(parent, soundId, volume)
	local sound = Instance.new("Sound")

	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = parent

	return sound
end

local function replaySound(sound, volume)
	if not sound or not sound.Parent then
		return
	end

	if volume then
		sound.Volume = volume
	end

	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

---------------------------------------------------------------------
-- Dash
---------------------------------------------------------------------

local function executeDash(player, direction)
	if not VALID_DASH_DIRECTIONS[direction] then
		return false
	end

	if activeMoves[player.UserId] then
		return false
	end

	local data = getCharacterData(player)

	if not data then
		return false
	end

	local character = data.character
	local humanoid = data.humanoid

	if MoveUtils.isBusy(character) then
		return false
	end

	local context = createMoveContext(player, "dash")

	local originalWalkSpeed = getOriginalWalkSpeed(humanoid)

	MoveUtils.setBusy(character, true)
	MoveUtils.setInvincible(character, true)

	humanoid.WalkSpeed = 0.1

	local animationName = DASH_ANIMATIONS[direction]
	local animationTrack = AnimationModule.PlayAnimation(
		character,
		animationName
	)

	context:addCleanup(function(reason)
		if animationTrack and animationTrack.IsPlaying then
			animationTrack:Stop()
		end

		if character.Parent then
			MoveUtils.setBusy(character, false)
			MoveUtils.setInvincible(character, false)
		end

		if humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
		end

		-- The client only needs an explicit cancellation packet when
		-- another action interrupted the dash.
		if reason == "cancelled" then
			DashClient:FireClient(player, {
				type = "Cancel",
				Player = player,
			})
		end
	end)

	DashClient:FireAllClients({
		type = "Dash",
		Player = player,
		Direction = direction,
	})

	-----------------------------------------------------------------
	-- Dash hit
	-----------------------------------------------------------------

	task.delay(0.4, function()
		if not context:isActive() then
			return
		end

		if not character.Parent then
			context:close("invalid")
			return
		end

		local targets = CombatSystem.createHitbox(
			character,
			Vector3.new(8, 8, 8),
			Vector3.new(0, 0, -4)
		)

		local attacked = {}

		for _, victimCharacter in ipairs(targets) do
			if attacked[victimCharacter] then
				continue
			end

			attacked[victimCharacter] = true

			if victimCharacter == character then
				continue
			end

			local victimRoot = victimCharacter:FindFirstChild(
				"HumanoidRootPart"
			)

			CombatSystem.takeDamage(
				victimCharacter,
				5,
				"dash_punch",
				character
			)

			if CombatSystem.isStun(victimCharacter) and victimRoot then
				-- Knockback is based on the victim's facing direction.
				-- This mirrors the behavior of the original move while
				-- keeping the vector calculation explicit.
				local directionVector = -victimRoot.CFrame.LookVector

				BodymoverService:Knockback(victimCharacter, {
					KnockbackType = "Velocity",

					MaxForce = Vector3.new(
						50000,
						0,
						50000
					),

					Velocity = Vector3.new(
						directionVector.X * 60,
						0,
						directionVector.Z * 60
					),

					Time = 0.2,
				})

				local victimTrack =
					AnimationModule.GetAnimationTrack(
						victimCharacter,
						"DashBacked"
					)

				if victimTrack then
					victimTrack:Play()
				end
			end

			DashClient:FireAllClients({
				type = "DashPunchVFX",
				Victim = victimCharacter,
			})
		end
	end)

	-----------------------------------------------------------------
	-- Normal dash completion
	-----------------------------------------------------------------

	task.delay(0.7, function()
		if context:isActive() then
			context:close("finished")
		end
	end)

	return true
end

---------------------------------------------------------------------
-- Beatdown
---------------------------------------------------------------------

local function executeBeatdown(player)
	if activeMoves[player.UserId] then
		return false
	end

	local data = getCharacterData(player)

	if not data then
		return false
	end

	local character = data.character
	local humanoid = data.humanoid
	local rootPart = data.rootPart

	if MoveUtils.isBusy(character) then
		return false
	end

	local context = createMoveContext(player, "beatdown")

	local originalWalkSpeed = getOriginalWalkSpeed(humanoid)

	MoveUtils.setBusy(character, true)
	MoveUtils.setInvincible(character, true)

	humanoid.WalkSpeed = 0

	-- Attacker state is always restored regardless of whether this
	-- becomes a miss, completes normally, or gets cancelled.
	context:addCleanup(function()
		if character.Parent then
			MoveUtils.setBusy(character, false)
			MoveUtils.setInvincible(character, false)
		end

		if humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
		end
	end)

	local targets = CombatSystem.createHitbox(
		character,
		Vector3.new(4, 6, 6),
		Vector3.new(0, 0, -3)
	)

	local victimCharacter

	for _, possibleVictim in ipairs(targets) do
		if possibleVictim ~= character then
			victimCharacter = possibleVictim
			break
		end
	end

	-----------------------------------------------------------------
	-- Miss
	-----------------------------------------------------------------

	if not victimCharacter then
		local missTrack =
			AnimationModule.GetAnimationTrack(character, "MissBD")

		if not missTrack then
			context:close("invalid")
			return false
		end

		context:addCleanup(function()
			if missTrack.IsPlaying then
				missTrack:Stop()
			end
		end)

		context:addConnection(
			missTrack.Ended:Connect(function()
				if context:isActive() then
					context:close("finished")
				end
			end)
		)

		missTrack:Play()

		-- Failsafe in case an incorrectly configured animation never
		-- sends Ended for some reason.
		task.delay(3, function()
			if context:isActive() then
				context:close("timeout")
			end
		end)

		return true
	end

	-----------------------------------------------------------------
	-- Validate victim
	-----------------------------------------------------------------

	local victimHumanoid =
		victimCharacter:FindFirstChildOfClass("Humanoid")

	local victimRoot =
		victimCharacter:FindFirstChild("HumanoidRootPart")

	if not victimHumanoid or not victimRoot then
		context:close("invalid")
		return false
	end

	if victimHumanoid.Health <= 0 then
		context:close("invalid")
		return false
	end

	local victimOriginalWalkSpeed =
		getOriginalWalkSpeed(victimHumanoid)

	local victimOriginalAnchored = victimRoot.Anchored

	-----------------------------------------------------------------
	-- Collision setup
	-----------------------------------------------------------------

	local attackerCollisionGroups =
		setCollisionGroup(character, "test")

	local victimCollisionGroups =
		setCollisionGroup(victimCharacter, "test")

	context:addCleanup(function()
		restoreCollisionGroups(attackerCollisionGroups)
		restoreCollisionGroups(victimCollisionGroups)
	end)

	-----------------------------------------------------------------
	-- Lock victim into cinematic state
	-----------------------------------------------------------------

	MoveUtils.setBusy(victimCharacter, true)
	MoveUtils.setInvincible(victimCharacter, true)

	victimHumanoid.WalkSpeed = 0

	context:addCleanup(function()
		if victimCharacter.Parent then
			MoveUtils.setBusy(victimCharacter, false)
			MoveUtils.setInvincible(victimCharacter, false)
		end

		if victimHumanoid.Parent then
			victimHumanoid.WalkSpeed = victimOriginalWalkSpeed
		end

		-- Critical fix:
		-- The original script only unanchored the victim during the
		-- normal ending. Cancelling the move could leave them anchored.
		if victimRoot.Parent then
			victimRoot.Anchored = victimOriginalAnchored
		end
	end)

	-----------------------------------------------------------------
	-- Position synchronization
	-----------------------------------------------------------------

	local relativeOffset = CFrame.new(
		0,
		0.02,
		-0.333
	)

	victimRoot.CFrame = rootPart.CFrame * relativeOffset
	victimRoot.Anchored = true

	local positionConnection

	positionConnection = RunService.Heartbeat:Connect(function()
		if not context:isActive() then
			return
		end

		if not rootPart.Parent or not victimRoot.Parent then
			context:close("invalid")
			return
		end

		victimRoot.CFrame = rootPart.CFrame * relativeOffset
	end)

	context:addConnection(positionConnection)

	-----------------------------------------------------------------
	-- Animations
	-----------------------------------------------------------------

	local victimTrack =
		AnimationModule.GetAnimationTrack(
			victimCharacter,
			"BDVictim"
		)

	local attackerTrack =
		AnimationModule.GetAnimationTrack(
			character,
			"BeatdownUser"
		)

	if not victimTrack or not attackerTrack then
		context:close("invalid")
		return false
	end

	context:addCleanup(function()
		attackerTrack:Stop(0)
		victimTrack:Stop(0)
	end)

	-----------------------------------------------------------------
	-- Sounds
	-----------------------------------------------------------------

	local hitSound = createSound(
		victimRoot,
		"rbxassetid://86794672753231",
		0.5
	)

	local hitSound2 = createSound(
		victimRoot,
		"rbxassetid://84693540110481",
		0.5
	)

	context:addCleanup(function(reason)
		if reason == "cancelled" then
			hitSound:Stop()
			hitSound2:Stop()
		end

		-- Sounds do not need to remain in the character forever.
		Debris:AddItem(hitSound, 3)
		Debris:AddItem(hitSound2, 3)
	end)

	-----------------------------------------------------------------
	-- Damage helpers
	-----------------------------------------------------------------

	local deferredKill = false

	local function applyCinematicDamage(amount, sound, volume)
		if not context:isActive() then
			return
		end

		if not victimCharacter.Parent then
			context:close("invalid")
			return
		end

		if victimHumanoid.Health <= 0 then
			return
		end

		emitHitVFX(victimCharacter)
		replaySound(sound, volume)

		-- Beatdown is a cinematic attack. Earlier hits intentionally
		-- avoid killing the target so the full sequence can finish.
		if victimHumanoid.Health > amount then
			CombatSystem.takeDamage(
				victimCharacter,
				amount,
				"beatdown",
				character
			)
		else
			deferredKill = true
		end
	end

	-----------------------------------------------------------------
	-- Animation markers
	--
	-- Connections are used instead of MarkerSignal:Wait().
	-- A coroutine waiting on a marker can hang forever if the move is
	-- cancelled before that marker is reached.
	-----------------------------------------------------------------

	context:addConnection(
		attackerTrack:GetMarkerReachedSignal("FIRSTHIT"):Connect(
			function()
				applyCinematicDamage(
					10,
					hitSound,
					0.5
				)
			end
		)
	)

	context:addConnection(
		attackerTrack:GetMarkerReachedSignal("SECONDHIT"):Connect(
			function()
				applyCinematicDamage(
					5,
					hitSound2,
					0.5
				)
			end
		)
	)

	context:addConnection(
		attackerTrack:GetMarkerReachedSignal("KICK"):Connect(
			function()
				if not context:isActive() then
					return
				end

				applyCinematicDamage(
					15,
					hitSound,
					1.2
				)

				if deferredKill
					and victimHumanoid.Parent
					and victimHumanoid.Health > 0
				then
					CombatSystem.takeDamage(
						victimCharacter,
						victimHumanoid.Health,
						"beatdown",
						character
					)
				end

				-----------------------------------------------------
				-- Release victim before applying physics
				-----------------------------------------------------

				if positionConnection.Connected then
					positionConnection:Disconnect()
				end

				if victimRoot.Parent then
					local finalCFrame =
						rootPart.CFrame * relativeOffset

					victimRoot.CFrame = finalCFrame
					victimRoot.Anchored = false

					local knockbackDirection =
						finalCFrame.RightVector

					RagdollHandler.ragdoll(
						victimCharacter,
						2
					)

					BodymoverService:Knockback(
						victimCharacter,
						{
							KnockbackType = "Velocity",

							MaxForce = Vector3.new(
								10000,
								10000,
								10000
							),

							Velocity =
								knockbackDirection * 30
								+ Vector3.new(
									0,
									-12,
									0
								),

							Time = 0.6,
						}
					)
				end

				context:close("finished")
			end
		)
	)

	-- If the animation unexpectedly ends before KICK, don't leave either
	-- character locked in a combat state.
	context:addConnection(
		attackerTrack.Ended:Connect(function()
			if context:isActive() then
				context:close("animation-ended")
			end
		end)
	)

	victimTrack:Play()
	attackerTrack:Play()

	-- Final safety net for malformed animations / missing markers.
	task.delay(10, function()
		if context:isActive() then
			context:close("timeout")
		end
	end)

	return true
end

---------------------------------------------------------------------
-- Move catalogue
---------------------------------------------------------------------

local Moves = {
	dash = {
		cooldown = 2,

		execute = function(player, direction)
			return executeDash(player, direction)
		end,
	},

	beatdown = {
		cooldown = 10,

		execute = function(player)
			return executeBeatdown(player)
		end,
	},
}

---------------------------------------------------------------------
-- Public cancellation hook
---------------------------------------------------------------------

local function onPlayerHit(player)
	cancelMove(player)
end

---------------------------------------------------------------------
-- Remote handling
---------------------------------------------------------------------

local function executeMove(player, moveName, extra)
	if typeof(moveName) ~= "string" then
		return
	end

	local move = Moves[moveName]

	if not move then
		return
	end

	if not MoveUtils.canUseMove(player, moveName) then
		return
	end

	-- execute() returns true only when the move actually started.
	-- This prevents a rejected move from consuming its cooldown.
	local started = move.execute(player, extra)

	if not started then
		return
	end

	MoveUtils.setCooldown(
		player,
		moveName,
		move.cooldown
	)
end

MoveInput.OnServerEvent:Connect(function(player, moveName, extra)
	-- Never trust arbitrary client input. Move names are restricted by
	-- the Moves catalogue and dash direction has its own whitelist.
	if moveName == "dash" then
		if typeof(extra) ~= "string"
			or not VALID_DASH_DIRECTIONS[extra]
		then
			return
		end
	end

	executeMove(player, moveName, extra)
end)

---------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------

local function setupCharacter(player, character)
	character.Parent = AliveFolder

	MoveUtils.createBodyVelocity(player)

	local humanoid =
		character:WaitForChild("Humanoid", 5)

	if not humanoid then
		return
	end

	humanoid.BreakJointsOnDeath = false

	humanoid.Died:Connect(function()
		-- Cancelling before ragdoll ensures any victim being held by
		-- this player's move is released.
		cancelMove(player)

		if character.Parent then
			RagdollHandler.ragdoll(
				character,
				math.huge
			)
		end
	end)
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function()
		cancelMove(player)
	end)

	-- PlayerAdded can fire after Roblox already created the player's
	-- initial character. Handle that character as well instead of only
	-- handling future respawns.
	if player.Character then
		task.defer(
			setupCharacter,
			player,
			player.Character
		)
	end
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	cancelMove(player)
	activeMoves[player.UserId] = nil
end)

-- Useful when Studio starts the script while players already exist.
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(setupPlayer, player)
end

return {
	cancelMove = cancelMove,
	onPlayerHit = onPlayerHit,
}
