Modules = {
	helpers = "github.com/Donorhan/cubzh-library/helpers:819b4e9",
	powerUpItem = "github.com/Donorhan/cubzh-library/power-up-item:8de76d1",
	uiComponents = "github.com/Donorhan/cubzh-library/ui-components:828bf2b",
}

Config = {
	Map = "dono.brawlarea_1",
	Items = {
		"dono.colorimap",
		"uevoxel.potion_yellow",
		"buche.ducky",
		"yauyau.magic_cube",
		"wrden.frog_with_hat",
		"uevoxel.bomb02",
	}
}

------------------------------
-- Configuration
------------------------------
local BlocScale = Number3(15.0, 15.0, 15.0)
local GameDuration = 40 -- in seconds
local GameStates = { WAITING_PLAYERS = 0, STARTING = 1, RUNNING = 2, ENDED = 3 }
local GameMode = { SOLO = 0, TEAM = 1 }
local MaxSoundDistance = 8000
local NetworkEvents = {
	GAME_STATE_CHANGED = "game-state",
	MAP_INIT = "map-init",
	PLAYER_ASK_NEW_GAME = "player-ask-new-game",
	PLAYER_ASSIGN_TEAM = "player-team",
	PLAYER_KILLED = "player-killed",
	PLAYER_STATE_CHANGED = "player-state",
	PLAYER_RELEASE_CHARGE = "player-charge",
	PLAYERS_INIT = "players-init",
	POWERUPS_COLLECTED = "powerups-collected",
	POWERUPS_SPAWN = "powerups-spawn",
	SHAPE_TAG = "shape-tag",
}
local PlayerSpawnPosition = Number3(278, 100, 302)
local MapSize = { min = 6, max = 12 }
local MapCenter = Number3(272, 65, 302)
local PlayerKilledSource = { LAVA = 1, EXPLOSION = 2 }
local PlayerDefaultSpeed = 65
local PlayerState = { READY = 1, WAITING = 0 }
local PowerUpsSpawnRange = { min = 3, max = 7 }
local TeamColors = {
	Color(255, 0, 0, 160), -- Red
	Color(0, 0, 255, 160), -- Blue
	Color(0, 255, 0, 160), -- Green
	Color(255, 255, 0, 160), -- Yellow
	Color(255, 0, 255, 160), -- Pink
	Color(0, 255, 255, 160), -- Cyan
	Color(255, 128, 0, 160), -- Orange
	Color(128, 0, 255, 160), -- Purple
}

------------------------------
-- Helpers
------------------------------
local loadExternalFile = function(url, callback)
	HTTP:Get(url, function(res)
		if res.StatusCode ~= 200 then
			callback(res.StatusCode, obj)
		else
			local obj = res.Body
			callback(nil, obj)
		end
	end)
end


------------------------------
-- Common
------------------------------
local debug = false
local disableMusic = false
local screenMode = false
local activePowerUps = {}
local gameCount = 0
local gameMode = GameMode.SOLO
local gameState = GameStates.WAITING_PLAYERS
local gameStats = { ["teams"] = {}, ["players"] = {} }
local gameTimeLeft = GameDuration
local mapShapesContainer = Object()
local mapState = {}
local playerCharge = 0
local playerSpeed = PlayerDefaultSpeed
local playersAssignedTeam = {}
local playersStates = {}
local PowerUps = {
	-- Add a temporary speed to the player
	["playerSpeed"] = {
		model = Items.uevoxel.potion_yellow,
		modelScale = Number3(0.35, 0.35, 0.35),
		modelPosition = Number3(0, 0, -0.5),
		value = PlayerDefaultSpeed + 35,
		duration = 5, -- in seconds
		onCollected = function(player, powerUp, instance)
			if player.UserID ~= Player.UserID then
				return
			end

			playerSpeed = powerUp.value
			ease:outSine(Camera, 0.250).FieldOfView = 95
			Timer(powerUp.duration, false, function()
				playerSpeed = PlayerDefaultSpeed
				ease:inSine(Camera, 0.750).FieldOfView = 60
			end)
		end,
	},
	-- Paint all tiles around the player
	["duckBomb"] = {
		model = Items.buche.ducky,
		modelScale = Number3(0.4, 0.4, 0.4),
		modelPosition = Number3(0, 0, -0.5),
		explosionSize = 70,
		onCollected = function(player, powerUp, instance)
			if player.UserID ~= Player.UserID then
				return
			end

			local explosionArea = MutableShape()
			explosionArea:AddBlock(Color(0, 0, 0, 0), Number3.Zero)
			explosionArea.Position = instance.LocalPosition - powerUp.explosionSize / 2.0
			explosionArea.Scale = powerUp.explosionSize
			explosionArea.Physics = PhysicsMode.Trigger
			explosionArea.CollisionGroups = { 8 }
			explosionArea.CollidesWithGroups = { 3 }
			explosionArea.OnCollisionBegin = function(shape, other)
				if other.shapeID then
					if gameState == GameStates.RUNNING then
						clientSetShapeOwner(other.shapeID, Player.UserID)
					end
				end

				shape:RemoveFromParent()
			end
			mapShapesContainer:AddChild(explosionArea)
		end,
		onRemoved = function(powerUp, instance)
			sfx("water_impact_2", { Position = instance.Position, Volume = 0.7 })
		end,
	},
	-- Push player in the opposite direction
	["bumper"] = {
		model = Items.yauyau.magic_cube,
		modelScale = Number3(1, 1, 1),
		modelPosition = Number3(0, -1, 0),
		onCollected = function(player, powerUp, instance)
			if player.UserID ~= Player.UserID then
				return
			end

			sfx("whooshes_small_2", { Position = instance.Position, Pitch = 1.3, Volume = 0.7 })
			Player.Velocity = -Player.Forward * 3000
			Player.canMove = false

			Timer(0.500, false, function()
				Player.canMove = true
			end)
		end,
	},
	-- Colorize blocks in front of the player
	["friends"] = {
		model = Items.wrden.frog_with_hat,
		modelScale = Number3(0.5, 0.5, 0.5),
		modelPosition = Number3(-2.5, -2.5, -2.5),
		onCollected = function(player, powerUp, instance)
			for i = 1, 2 do
				local shape = Shape(Items.wrden.frog_with_hat)
				shape.Position = player.Position
				shape.Rotation = { 0, -1.5708, 0 }
				shape.Physics = PhysicsMode.Trigger
				shape.CollisionGroups = { 8 }
				shape.CollidesWithGroups = { 3 }
				if player.UserID == Player.UserID then
					shape.OnCollisionBegin = function(shape, other)
						if other.shapeID then
							if gameState == GameStates.RUNNING then
								clientSetShapeOwner(other.shapeID, Player.UserID)
							end
						end
					end
				end
				player.Body:AddChild(shape)

				if i == 1 then
					shape.LocalPosition = Number3(-18, -12.5, 0)
				else
					shape.LocalPosition = Number3(26, -12.5, 0)
				end

				Timer(5, false, function()
					shape:RemoveFromParent()
				end)
			end
		end,
	},
}
local tagComboCounter = 0

function computePlayersStates()
	local playersCount = 0
	local playersReadyCount = 0
	local soloModeVote = 0
	local teamModeVote = 0

	for _, player in pairs(Players) do
		local playerState = playersStates[player.UserID]
		if playerState then
			if playerState.state == PlayerState.READY then
				playersReadyCount = playersReadyCount + 1
			end

			if playerState.vote == GameMode.SOLO then
				soloModeVote = soloModeVote + 1
			elseif playerState.vote == GameMode.TEAM then
				teamModeVote = teamModeVote + 1
			end
		end

		playersCount = playersCount + 1
	end

	return {
		playersCount = playersCount,
		playersReadyCount = playersReadyCount,
		soloModeVote = soloModeVote,
		teamModeVote = teamModeVote,
		ready = (playersCount == playersReadyCount)
	}
end

function teamToColor(teamID)
	return TeamColors[teamID] or Color(0, 0, 0, 0)
end

function calculateTeamScores()
	local teamScores = {}
	local mapObjectCount = 0
	local mapObjectColoredCount = 0
	for index in pairs(mapState) do
		local mapObject = mapState[index]
		if mapObject.team then
			local teamScore = teamScores[mapObject.team]
			if not teamScore then
				teamScore = 0
			end

			teamScores[mapObject.team] = teamScore + 1
			mapObjectColoredCount = mapObjectColoredCount + 1
		end

		mapObjectCount = mapObjectCount + 1
	end

	local sortedTeamScores = {}
	for index, value in pairs(teamScores) do
		local scorePercent = math.floor((value / mapObjectColoredCount) * 100 + 0.5)
		table.insert(sortedTeamScores, { index, value, scorePercent })
	end
	table.sort(sortedTeamScores, function(a, b)
		return a[2] > b[2]
	end)

	return sortedTeamScores
end

function updateGameStats(userID, shapeID)
	local shapeNewTeamID = playersAssignedTeam[userID]
	local shapeCurrentTeamID = mapState[userID].team

	if shapeCurrentTeamID ~= nil then
		shapeCurrentTeamID = tostring(shapeCurrentTeamID)
	end

	if shapeNewTeamID ~= nil then
		shapeNewTeamID = tostring(shapeNewTeamID)
	end

	-- ensures stat objects are not null
	if shapeCurrentTeamID and not gameStats.teams[shapeCurrentTeamID] then
		gameStats.teams[shapeCurrentTeamID] = 0
	end

	if shapeNewTeamID and not gameStats.teams[shapeNewTeamID] then
		gameStats.teams[shapeNewTeamID] = 0
	end

	if not gameStats.players[userID] then
		gameStats.players[userID] = { ["stealer"] = 0, ["amount"] = 0 }
	end

	-- Player stats
	if shapeCurrentTeamID then
		gameStats.players[userID].stealer = gameStats.players[userID].stealer + 1
	end
	gameStats.players[userID].amount = gameStats.players[userID].amount + 1

	-- Team stats
	if shapeCurrentTeamID then
		gameStats.teams[shapeCurrentTeamID] = gameStats.teams[shapeCurrentTeamID] - 1
	end
	if shapeNewTeamID then
		gameStats.teams[shapeNewTeamID] = gameStats.teams[shapeNewTeamID] + 1
	end
end

------------------------------
-- Client
------------------------------
function togglePlayersUserNames(show)
	for id, player in pairs(Players) do
		if show then
			player:ShowHandle()
		else
			player:HideHandle()
		end
	end
end

function clientUpdateShapeState(shape, color, animate)
	local thickness = 0.1
	if not shape.spawnedShape then
		local spawnPosition = Number3(
			shape.Position.X,
			shape.Position.Y + 0.5 + thickness,
			shape.Position.Z
		)

		local spawnedShape = MutableShape()
		spawnedShape.Pivot = Number3(0.5, 0.5, 0.5)
		shape:AddChild(spawnedShape)
		shape.spawnedShape = spawnedShape

		spawnedShape.Position = spawnPosition
		spawnedShape.Physics = PhysicsMode.Disabled
		spawnedShape.Palette:AddColor(color)
		spawnedShape:AddBlock(1, Number3.Zero)
		spawnedShape.Scale = 0
	end

	local blocScale = Number3(BlocScale.X, thickness, BlocScale.Z) * 2
	if animate then
		if shape.spawnedShape.easeScale then
			ease:cancel(shape.spawnedShape.easeScale)
		end

		shape.spawnedShape.Scale = 0
		shape.spawnedShape.easeScale = ease:outElastic(shape.spawnedShape, 1.0)
		shape.spawnedShape.easeScale.Scale = blocScale
		helpers.shape.easeColorLinear(shape.spawnedShape, Color.White, color, 0.75)
	else
		shape.spawnedShape.Scale = blocScale
		local bloc = shape.spawnedShape:GetBlock(0, 0, 0)
		bloc:Replace(color)
	end
end

function clientUpdatePlayerCharge(value)
	playerCharge = playerCharge + value
	playerCharge = helpers.math.clamp(playerCharge, 0, 100)

	if playerCharge >= 100 then
		clientReleasePlayerCharge()
	end
end

function clientSetShapeOwner(shapeID, userID)
	local userTeamID = playersAssignedTeam[userID]
	if mapState[shapeID].team == userTeamID then
		-- reset combo
		if userID == Player.UserID then
			tagComboCounter = 0
		end

		return
	end

	-- Update shape
	local shapeColor = teamToColor(userTeamID)
	clientUpdateShapeState(mapState[shapeID].shape, shapeColor, true)

	-- Notify server
	local shapePosition = mapState[shapeID].shape.Position
	if userID == Player.UserID then
		local pitch = math.min(1.1 + (tagComboCounter / 8.0), 2.8)
		local e = Event()
		e.action = NetworkEvents.SHAPE_TAG
		e.shapeID = shapeID
		e:SendTo(Server)
		sfx("waterdrop_2", { Position = shapePosition, Pitch = pitch, Volume = 0.65 })
		Client:HapticFeedback()

		clientUpdatePlayerCharge(1 * (tagComboCounter / 2))
		tagComboCounter = tagComboCounter + 1
	else
		-- avoid audio spam with players far away
		local distance = (shapePosition - Player.Position).SquaredLength
		if distance < MaxSoundDistance then
			local volume = helpers.math.remap(distance, 0, MaxSoundDistance, 0.1, 0.75)
			sfx("waterdrop_2", { Position = shapePosition, Pitch = 1.1 + math.random() * 0.5, Volume = 0.65 - volume })
		end
	end

	updateGameStats(userID, shapeID)
	mapState[shapeID].team = userTeamID
end

function clientRemovePowerUp(id, userID)
	if not activePowerUps[id] then
		return
	end

	local powerUpInstance = activePowerUps[id]
	local powerUp = PowerUps[powerUpInstance.Name]
	if powerUp.onRemoved then
		powerUp.onRemoved(powerUp, powerUpInstance)
	end

	powerUpInstance:RemoveFromParent()

	activePowerUps[id] = nil
end

function clientRemoveAllPowerUps()
	for index in pairs(activePowerUps) do
		local powerUpInstance = activePowerUps[index]
		if powerUpInstance then
			powerUpInstance:RemoveFromParent()
		end
	end

	activePowerUps = {}
end

function clientSpawnPowerUp(id, name, powerUp, position)
	sfx("whooshes_medium_3", { Position = position, Volume = 0.80, Pitch = 1.2 })

	local color = Color(220, 220, 255, 140)
	if name == "bumper" then
		color = Color(255, 120, 120, 140)
	end

	local powerUpContainer = powerUpItem.create({
		color = color,
		model = powerUp.model,
		modelScale = powerUp.modelScale,
		modelPosition = powerUp.modelPosition,
		onCollected = function(shape, other)
			if powerUp.onCollected then
				powerUp.onCollected(other, powerUp, shape)
			end

			if other.UserID == Player.UserID then
				local e = Event()
				e.action = NetworkEvents.POWERUPS_COLLECTED
				e.powerUpID = id
				e:SendTo(Server)
			end

			clientRemovePowerUp(id, Player.userID, true)
		end
	})
	powerUpContainer.Position = Number3(position.X, position.Y + 8.5, position.Z)
	mapShapesContainer:AddChild(powerUpContainer)

	activePowerUps[id] = powerUpContainer
end

function clientDropPlayer(player)
	player.Position = PlayerSpawnPosition
	player.Rotation = { 0, 0, 0 }
	player.Velocity = { 0, 0, 0 }
end

function clientSpawnPlayer()
	Player.Head:AddChild(AudioListener)
	Player.OnCollisionBegin = function(player, other)
		if other.shapeID then
			if gameState == GameStates.RUNNING then
				clientSetShapeOwner(other.shapeID, Player.UserID)
			end
		end
	end

	World:AddChild(Player)
	clientDropPlayer(Player)

	Camera:SetModeThirdPerson(Player)
	Player.IsHidden = false
	Player.canMove = true

	if screenMode then
		Player.IsHidden = true
		Player.Acceleration = -Config.ConstantAcceleration
	end
end

function clientDisablePlayer(value)
	Player.canMove = value
end

local easeColorLinear = function(shape, startColor, color, duration, paletteIndexes)
	if shape.easeColor then
		ease:cancel(shape.easeColor)
	end

	local startColors = {}
	for _, index in ipairs(paletteIndexes or { 1 }) do
		startColors[index] = startColor or shape.Palette[index].Color
	end

	local conf = {
		onUpdate = function(obj)
			for _, index in ipairs(paletteIndexes or { 1 }) do
				shape.Palette[index].Color:Lerp(startColors[index], color, obj.easeLerp)
			end
		end
	}

	shape.easeLerp = 0.0
	shape.easeColor = ease:linear(shape, duration, conf)
	shape.easeColor.easeLerp = 1.0
end

function clientSpawnBomb(endPosition, teamID)
	sfx("drinking_1", { Position = endPosition, Pitch = 0.8 + (math.random(1, 3) / 10.0), Volume = 0.7 })

	local color = teamToColor(teamID) or Color(255, 255, 255, 255)

	local bomb = Shape(Items.uevoxel.bomb02)
	bomb.Physics = PhysicsMode.Disabled
	bomb.Scale = Number3(0.5, 0.5, 0.5)
	bomb.CollisionGroups = Player.CollisionGroups
	mapShapesContainer:AddChild(bomb)
	bomb.Position = endPosition + Number3(0, 5, 0)
	bomb.Palette[1].Color = color

	local velocity = 100
	local acceleration = Config.ConstantAcceleration.Y
	local updateBomb = true
	bomb.Tick = function(o, dt)
		if not updateBomb then
			bomb.Position.Y = endPosition.Y
			return
		end

		local bombPosition = o.Position

		bombPosition.Y = bombPosition.Y + (dt * (velocity + dt * acceleration / 2))
		velocity = velocity + (dt * acceleration);

		if bombPosition.Y < endPosition.Y then
			velocity = -velocity * 0.5
			bomb.Position.Y = endPosition.Y
			if velocity > 10 then
				sfx("drinking_1", { Position = endPosition, Pitch = 0.3, Volume = 0.35 })
			end

			if velocity < 0.55 then
				updateBomb = false
			end
		end
	end

	-- animations
	bomb.anim = function()
		ease:inOutSine(bomb, 0.2, {
			onDone = function()
				ease:inOutSine(bomb, 0.2, {
					onDone = function()
						bomb.anim()
					end,
				}).Scale = Number3(0.5, 0.48, 0.4)
			end,
		}).Scale = Number3(0.4, 0.52, 0.5)
	end
	bomb.anim()

	-- particles
	local bombParticles = particles:newEmitter({
		life = function()
			return 0.25
		end,
		velocity = function()
			return Number3(5 * math.random(-1, 1), math.random(5, 9), 5 * math.random(-1, 1))
		end,
		color = function()
			return Color(255, math.random(0, 100), 0)
		end,
		scale = function()
			return 0.75
		end,
		acceleration = function()
			return -Config.ConstantAcceleration
		end,
	})
	bomb:AddChild(bombParticles)
	bombParticles.Position = bomb.Position - Number3(1, -3.8, 0)

	local t = 0.0
	local spawnDt = 0.05
	bombParticles.Tick = function(o, dt)
		t = t + dt
		while t > spawnDt do
			t = t - spawnDt
			bombParticles:spawn(2)
		end
	end

	-- will explode animation
	local explosionSize = 70
	Timer(3, false, function()
		easeColorLinear(bomb, nil, Color.Red, 1.5, { 1, 2, 3, 4, 5, 6, 7 })
		Timer(1, false, function()
			bomb:RemoveFromParent()
			bombParticles:RemoveFromParent()
			sfx("small_explosion_3", { Position = bomb.Position, Pitch = 1.0, Volume = 0.75 })

			local explosionArea = MutableShape()
			explosionArea:AddBlock(Color(255, 255, 255, 255), Number3.Zero)
			explosionArea.Position = bomb.LocalPosition - explosionSize / 2.0
			explosionArea.Scale = explosionSize
			explosionArea.Physics = PhysicsMode.Trigger
			explosionArea.CollisionGroups = { 9 }
			explosionArea.CollidesWithGroups = Player.CollisionGroups
			explosionArea.OnCollisionBegin = function(_, other)
				if other.UserID and not other.isDead then
					if teamID ~= playersAssignedTeam[other.UserID] then
						onPlayerKilled(other, PlayerKilledSource.EXPLOSION)
					end
				end
			end
			mapShapesContainer:AddChild(explosionArea)

			-- particles
			local explosionParticles = particles:newEmitter({
				life = function()
					return 0.35
				end,
				velocity = function()
					return Number3(90 * math.random(-1, 1), math.random(0, 120), 90 * math.random(-1, 1))
				end,
				color = function()
					return Color(255, math.random(0, 100), 0)
				end,
				scale = function()
					return math.random(4, 7)
				end,
				acceleration = function()
					return -Config.ConstantAcceleration
				end,
			})
			mapShapesContainer:AddChild(explosionParticles)
			explosionParticles.Position = endPosition
			explosionParticles:spawn(30)

			Timer(0.01, false, function()
				explosionArea:RemoveFromParent()
			end)

			Timer(0.5, false, function()
				explosionParticles:RemoveFromParent()
			end)
		end)
	end)
end

function clientReleasePlayerCharge()
	--if gameState ~= GameStates.RUNNING or playerCharge < 100 then
	--	return
	--end

	-- reset charge
	playerCharge = 0

	-- animation
	local bombPosition = Number3(Player.Position.X, mapShapesContainer.Position.Y + 4.5, Player.Position.Z)
	clientSpawnBomb(bombPosition, playersAssignedTeam[Player.UserID])

	local event = Event()
	event.action = NetworkEvents.PLAYER_RELEASE_CHARGE
	event.position = bombPosition
	event:SendTo(Players)
end

function onPlayerKilled(player, sourceType)
	player.IsHidden = true
	player.isDead = true
	player.canMove = false
	explode:shapes(player.Body)

	if player == Player then
		local event = Event()
		event.action = NetworkEvents.PLAYER_KILLED
		event.source = sourceType
		event:SendTo(Players)
	end

	if sourceType == PlayerKilledSource.LAVA then
		sfx("punch_2", { Position = player.Position, Pitch = 0.3, Volume = 0.7 })
	elseif sourceType == PlayerKilledSource.EXPLOSION then
		-- do nothing, explosion's sound is enough
	else
		sfx("punch_2", { Position = player.Position, Pitch = 0.7, Volume = 0.7 })
	end

	respawnPlayer(player, 2)
end

function respawnPlayer(player, time)
	Timer(time, function()
		clientDropPlayer(player)
		player.IsHidden = false
		player.isDead = false
		player.canMove = true
	end)
end

function clientClearMap()
	for index in pairs(mapState) do
		local mapObject = mapState[index]
		if mapObject.shape then
			mapObject.shape:RemoveFromParent()
		end

		mapState[index] = nil
	end
	mapState = {}
end

function clientSpawnMap(map)
	clientClearMap()

	mapShapesContainer.Physics = PhysicsMode.Disabled
	mapShapesContainer.Position = MapCenter
	World:AddChild(mapShapesContainer)

	for index in pairs(map) do
		local shapeData = map[index]

		local shape = Shape(Items.dono.colorimap)
		shape.Scale = Number3(0.52, 1, 0.52)
		shape.Position = Number3(shapeData.x * BlocScale.X, shapeData.y, shapeData.z * BlocScale.Z)
		shape.shapeID = index
		shape.Physics = PhysicsMode.Static
		mapShapesContainer:AddChild(shape)

		mapState[index] = { ["shape"] = shape, ["team"] = shapeData.team }

		if shapeData.team then
			local color = teamToColor(shapeData.team)
			clientUpdateShapeState(shape, color, false)
		end
	end
end

function clientStartGame(timeLeft)
	gameTimeLeft = timeLeft
	gameState = GameStates.RUNNING
	Pointer:Hide()
end

function clientEndGame()
	uiShowGameOverScreen()
	clientRemoveAllPowerUps()
end

function clientPrepareNewGame()
	gameState = GameStates.WAITING_PLAYERS
	gameStats = { ["teams"] = {}, ["players"] = {} }
	playerCharge = 0
	clientDropPlayer(Player)
	uiShowPlayersPreparationScreen()

	local e = Event()
	e.action = NetworkEvents.PLAYER_ASK_NEW_GAME
	e:SendTo(Server)
end

Client.OnStart = function()
	Dev.DisplayColliders = debug

	ambience = require("ambience")
	ease = require("ease")
	explode = require("explode")
	multi = require("multi")
	particles = require("particles")
	sfx = require("sfx")
	uikit = require("uikit")

	ambience:set(ambience.noon)
	ambience.pauseCycle()
	Clouds.On = false
	Fog.On = false

	Camera:SetModeFree()
	Camera.Position = PlayerSpawnPosition
	Player.IsHidden = true
	Player.canMove = false

	-- init music
	mainMusic = AudioSource()
	mainMusic:SetParent(Camera)
	if not disableMusic then
		mainMusic.Volume = 0.4
	else
		mainMusic.Volume = 0
	end
	mainMusic.Loop = true

	if not debug then
		local musicURL = "https://raw.githubusercontent.com/Donorhan/cubzh-colorunzh/main/shutter-love-waterflame.mp3"
		loadExternalFile(musicURL, function(error, stream)
			if not error then
				mainMusic.Sound = stream
				mainMusic:Play()
			else
				print("Failed to load music")
			end
		end)
	end
end

Client.Action1 = function()
	if Player.IsOnGround then
		Player.Velocity.Y = 80
	end
end

Client.Tick = function(dt)
	if not Player.isDead and Player.canMove and Player.Position.Y < 10 then
		onPlayerKilled(Player, PlayerKilledSource.LAVA)
	end

	if gameState == GameStates.RUNNING then
		gameTimeLeft = gameTimeLeft - dt
		clientUpdatePlayerCharge(6 * dt)
		uiRefreshHUD()
	end
end

Client.OnChat = function(payload)
	local msg = payload.message
	Player:TextBubble(msg, 3, true)
	sfx("waterdrop_2", { Position = Player.Position, Pitch = 1.1 + math.random() * 0.5 })
end

Client.DidReceiveEvent = function(event)
	if event.action == NetworkEvents.SHAPE_TAG then
		if event.userID ~= Player.UserID then
			clientSetShapeOwner(event.shapeID, event.userID)
		end
	elseif event.action == NetworkEvents.MAP_INIT then
		clientSpawnMap(JSON:Decode(event.mapState))

		if gameCount == 0 then
			clientSpawnPlayer()
		end
	elseif event.action == NetworkEvents.PLAYERS_INIT then
		playersAssignedTeam = JSON:Decode(event.state)
		uiShowPlayersPreparationScreen()
	elseif event.action == NetworkEvents.PLAYER_STATE_CHANGED then
		playersStates = JSON:Decode(event.state)
		uiShowPlayersPreparationScreen()
	elseif event.action == NetworkEvents.PLAYER_KILLED then
		if event.Sender ~= Player then
			onPlayerKilled(event.Sender, event.source)
		end
	elseif event.action == NetworkEvents.PLAYER_RELEASE_CHARGE then
		if event.Sender ~= Player then
			clientSpawnBomb(event.position, playersAssignedTeam[event.Sender.UserID])
		end
	elseif event.action == NetworkEvents.GAME_STATE_CHANGED then
		gameState = event.state

		if event.state == GameStates.STARTING then
			uiStartCounter()
			gameCount = gameCount + 1
		elseif event.state == GameStates.ENDED then
			clientEndGame()
		elseif event.state == GameStates.RUNNING then
			clientStartGame(event.timeLeft)
		elseif event.state == GameStates.WAITING_PLAYERS then
			uiShowPlayersPreparationScreen()
		end
	elseif event.action == NetworkEvents.POWERUPS_SPAWN then
		clientSpawnPowerUp(event.id, event.value, PowerUps[event.value], event.position)
	elseif event.action == NetworkEvents.POWERUPS_COLLECTED then
		clientRemovePowerUp(event.powerUpID, event.userID)
	end
end

Client.OnPlayerJoin = function(player)
	if gameState == GameStates.WAITING_PLAYERS then
		uiShowPlayersPreparationScreen()
	end

	togglePlayersUserNames(false)
end

Client.OnPlayerLeave = function(player)
	playersStates[player.UserID] = nil
	uiShowPlayersPreparationScreen()
end

Client.AnalogPad = function(dx, dy)
	if not Player.canMove then
		Player.Motion = Number3(0, 0, 0)
		return
	end

	Player.LocalRotation = Rotation(0, dx * 0.01, 0) * Player.LocalRotation
	Player.Head.LocalRotation = Rotation(-dy * 0.01, 0, 0) * Player.Head.LocalRotation

	local dpad = require("controls").DirectionalPadValues
	Player.Motion = (Player.Forward * dpad.Y + Player.Right * dpad.X) * playerSpeed
end


Client.DirectionalPad = function(x, y)
	if not Player.canMove then
		Player.Motion = Number3(0, 0, 0)
		return
	end

	Player.Motion = (Player.Forward * y + Player.Right * x) * playerSpeed
end


------------------------------
-- Server code
------------------------------
local serverTimeElapsedSinceLastPowerUp = 0
local serverNextPowerUpIn = 0
local serverNextPowerUpId = 1
local serverMapSize = { x = 0, z = 0 }


function serverPrepareMap()
	for index in pairs(mapState) do
		mapState[index] = nil
	end
	mapState = {}

	local holePercent = 0
	if gameCount > 0 then
		holePercent = (gameCount * 2)
		holePercent = math.min(75, holePercent)
	end

	local mapRandomSize = math.floor(math.random() * (MapSize.max - MapSize.min))
	local mapWidth = MapSize.min + mapRandomSize
	local mapHeight = MapSize.min + mapRandomSize
	if gameCount == 0 then
		mapWidth = MapSize.min
		mapHeight = MapSize.min
	end

	serverMapSize.x = mapWidth
	serverMapSize.z = mapHeight

	local index = 0
	local team = nil
	for i = -mapWidth, mapWidth, 1
	do
		for j = -mapHeight, mapHeight, 1
		do
			local spawnTile = (i == 0 and j == 0) or math.random() * 100 >= holePercent
			if spawnTile then
				if screenMode then
					team = math.random(0, 5)
					if team > 7 then
						team = nil
					end
				end

				mapState[index] = { ["x"] = i, ["y"] = 0, ["z"] = j, ["team"] = team }
				index = index + 1
			end
		end
	end

	gameCount = gameCount + 1

	return mapState
end

function serverSendMapState(player)
	local e = Event()
	e.action = NetworkEvents.MAP_INIT
	e.mapState = JSON:Encode(mapState)
	e:SendTo(Players[player.ID])
end

function serverSendPlayersAssignedTeams()
	local e = Event()
	e.action = NetworkEvents.PLAYERS_INIT
	e.state = JSON:Encode(playersAssignedTeam)
	e:SendTo(Players)
end

function serverSetPlayerTeam(player, removeTeam)
	if removeTeam then
		playersAssignedTeam[player.UserID] = nil
		return
	end

	local getUsersPerTeam = function()
		local usersPerTeam = {}

		local teamCount = 0
		for _ in pairs(TeamColors) do
			teamCount = teamCount + 1
		end

		for i = 0, teamCount do
			usersPerTeam[i] = 0
		end

		for index, value in pairs(playersAssignedTeam) do
			usersPerTeam[value] = usersPerTeam[value] + 1
		end

		return usersPerTeam
	end

	local findTeamWithLessUsers = function(usersPerTeam, teamLimit)
		local userCount = 99
		local selectedTeamID = 0
		for index, value in pairs(usersPerTeam) do
			if index < teamLimit and value < userCount then
				selectedTeamID = index
				userCount = value
			end
		end

		return selectedTeamID
	end

	local teamLimit = 99
	if gameMode == GameMode.TEAM then
		teamLimit = 2
	end

	local selectedTeamID = findTeamWithLessUsers(getUsersPerTeam(), teamLimit)
	playersAssignedTeam[player.UserID] = selectedTeamID
end

function serverClearGame()
	for index in pairs(playersStates) do
		playersStates[index] = nil
	end
	playersStates = {}

	gameState = GameStates.WAITING_PLAYERS
	gameStats = { ["teams"] = {}, ["players"] = {} }
	serverTimeElapsedSinceLastPowerUp = 0
	serverNextPowerUpId = 1
	playersAssignedTeam = {}
	serverCalculateNextPowerUpIn()
end

function serverSendPlayersStates()
	local e = Event()
	e.action = NetworkEvents.PLAYER_STATE_CHANGED
	e.state = JSON:Encode(playersStates)
	e:SendTo(Players)
end

function serverOnPlayerStateChanged(player, state)
	playersStates[player.UserID] = state
	serverSendPlayersStates()

	local computedStates = computePlayersStates()
	if computedStates.ready == true then
		gameState = GameStates.STARTING
		gameTimeLeft = GameDuration + 3 -- + 3 for the countdown, yeah it's dirty

		-- set game mode
		gameMode = GameMode.SOLO
		if computedStates.teamModeVote > computedStates.soloModeVote then
			gameMode = GameMode.TEAM
		end

		-- assign teams depending votes
		for _, player in pairs(Players) do
			serverSetPlayerTeam(player)
		end
		serverSendPlayersAssignedTeams()

		Timer(1, false, function()
			local e = Event()
			e.action = NetworkEvents.GAME_STATE_CHANGED
			e.state = gameState
			e:SendTo(Players)
			gameState = GameStates.RUNNING

			Timer(gameTimeLeft, false, function()
				gameState = GameStates.ENDED

				local e = Event()
				e.action = NetworkEvents.GAME_STATE_CHANGED
				e.state = gameState
				e:SendTo(Players)

				serverClearGame()
				serverPrepareMap()
			end)
		end)
	end
end

function serverCalculateNextPowerUpIn()
	serverNextPowerUpIn = math.random(PowerUpsSpawnRange.min, PowerUpsSpawnRange.max)
end

function serverCheckPowerUpSpawn()
	if serverTimeElapsedSinceLastPowerUp < serverNextPowerUpIn then
		return
	end

	-- pick random power-up
	local keys = {}
	for k in pairs(PowerUps) do
		table.insert(keys, k)
	end
	local powerUpId = serverNextPowerUpId
	local powerUpSelected = keys[math.random(1, #keys)]

	-- spawn
	local positionX = math.random(-serverMapSize.x * BlocScale.X, serverMapSize.x * BlocScale.X)
	local positionZ = math.random(-serverMapSize.z * BlocScale.Z, serverMapSize.z * BlocScale.Z)

	local e = Event()
	e.action = NetworkEvents.POWERUPS_SPAWN
	e.id = powerUpId
	e.value = powerUpSelected
	e.position = Number3(positionX, 0, positionZ)
	e:SendTo(Players)
	activePowerUps[powerUpId] = powerUpSelected

	-- prepare next item spawn
	serverTimeElapsedSinceLastPowerUp = 0
	serverNextPowerUpId = serverNextPowerUpId + 1
	serverCalculateNextPowerUpIn()
end

function serverOnShapeTagged(player, shapeID)
	if gameState ~= GameStates.RUNNING then
		return
	end

	if not mapState[shapeID] then
		return
	end

	local senderID = player.UserID
	local senderTeamID = playersAssignedTeam[senderID]
	mapState[shapeID].owner = senderID
	mapState[shapeID].team = senderTeamID

	local response = Event()
	response.action = NetworkEvents.SHAPE_TAG
	response.shapeID = shapeID
	response.teamID = senderTeamID
	response.userID = senderID
	response:SendTo(Players)
end

Server.OnStart = function()
	gameCount = 0
	serverClearGame()
	serverPrepareMap()
end

Server.DidReceiveEvent = function(event)
	local senderID = event.Sender.UserID;

	if event.action == NetworkEvents.SHAPE_TAG then
		serverOnShapeTagged(event.Sender, event.shapeID)
	elseif event.action == NetworkEvents.PLAYER_STATE_CHANGED then
		serverOnPlayerStateChanged(event.Sender, { ["state"] = event.state, ["vote"] = event.vote });
	elseif event.action == NetworkEvents.PLAYER_ASK_NEW_GAME then
		serverSendMapState(event.Sender)
		serverSendPlayersStates()
	elseif event.action == NetworkEvents.POWERUPS_COLLECTED then
		local response = Event()
		response.powerUpID = event.powerUpID
		response.userID = senderID
		response:SendTo(Players)
		activePowerUps[event.powerUpID] = nil
	end
end

Server.OnPlayerJoin = function(player)
	if gameState == GameStates.RUNNING then
		serverSetPlayerTeam(player)
		serverSendPlayersAssignedTeams()
	end
	serverSendMapState(player)

	local e = Event()
	e.action = NetworkEvents.GAME_STATE_CHANGED
	e.state = gameState
	e.timeLeft = gameTimeLeft
	e:SendTo(Players[player.ID])
end

Server.OnPlayerLeave = function(player)
	serverSetPlayerTeam(player, true)
	serverOnPlayerStateChanged(player, nil);
end

Server.Tick = function(dt)
	if gameState == GameStates.RUNNING then
		gameTimeLeft = gameTimeLeft - dt

		serverTimeElapsedSinceLastPowerUp = serverTimeElapsedSinceLastPowerUp + dt
		serverCheckPowerUpSpawn()
	end
end


------------------------------
-- UI
------------------------------
local uiElements = {
	["hud"] = {
		frame = nil,
		subFrame = nil,
		leadingTeamFrame = nil,
		timeLeftText = nil,
		previousTimeLeft = 0,
	},
	["gameOverScreen"] = {
		frame = nil,
	},
	["playersPreparationScreen"] = {
		frame = nil,
		playersCountText = nil,
		soloButton = nil,
		teamButton = nil,
	},
}


function uiDestroyScreens()
	for _, screen in pairs(uiElements) do
		if screen.frame then
			screen.frame:remove()
			screen.frame = nil
		end

		if screen.subFrame then
			screen.subFrame:remove()
			screen.subFrame = nil
		end
	end
end

function uiShowPlayersPreparationScreen()
	if gameState ~= GameStates.WAITING_PLAYERS or screenMode then
		return
	end

	if mainMusic and not disableMusic then
		mainMusic.Volume = 0.5
	end
	Pointer:Show()

	local updateTexts = function()
		local playersStates = computePlayersStates()
		uiElements.playersPreparationScreen.playersCountText.Text = playersStates.playersReadyCount ..
			" / " .. playersStates.playersCount
		uiElements.playersPreparationScreen.soloButton.Text = "Solo (" .. playersStates.soloModeVote .. ")"
		uiElements.playersPreparationScreen.teamButton.Text = "Team (" .. playersStates.teamModeVote .. ")"
	end

	if not uiElements.playersPreparationScreen.frame then
		uiDestroyScreens()

		local onVoteButtonPressed = function(mode)
			local e = Event()
			e.action = NetworkEvents.PLAYER_STATE_CHANGED
			e.state = PlayerState.READY
			e.vote = mode
			e:SendTo(Server)

			uiElements.playersPreparationScreen.soloButton:disable()
			uiElements.playersPreparationScreen.teamButton:disable()
		end

		local frame = uikit:createFrame(Color(42, 50, 61))
		frame.Width = 350
		frame.Height = 150
		frame.parentDidResize = function()
			frame.LocalPosition = { Screen.Width / 2 - frame.Width / 2, Screen.Height - frame.Height -
			Screen.SafeArea.Top - 25 }
		end
		frame:parentDidResize()
		uiElements.playersPreparationScreen.frame = frame

		-- header
		local titleFrame = uikit:createFrame(Color(27, 36, 43))
		titleFrame:setParent(frame)
		titleFrame.Width = 348
		titleFrame.Height = 45
		titleFrame.parentDidResize = function()
			titleFrame.LocalPosition = { frame.Width / 2 - titleFrame.Width / 2, frame.Height - titleFrame.Height - 1 }
		end
		titleFrame:parentDidResize()

		local text = uikit:createText("Ready?", Color(203, 206, 209), "default")
		text:setParent(titleFrame)
		text.object.Anchor = { 0, 0.5 }
		text.parentDidResize = function()
			text.LocalPosition = { 15, titleFrame.Height / 2 }
		end
		text:parentDidResize()

		local playersCountText = uikit:createText("0 / 0", Color(203, 206, 209), "small")
		playersCountText:setParent(titleFrame)
		playersCountText.object.Anchor = { 1, 0.5 }
		playersCountText.parentDidResize = function()
			playersCountText.LocalPosition = { titleFrame.Width - 15, titleFrame.Height / 2 }
		end
		playersCountText:parentDidResize()
		uiElements.playersPreparationScreen.playersCountText = playersCountText

		local voteText = uikit:createText("Vote for the mode", Color(109, 119, 131), "default")
		voteText:setParent(frame)
		voteText.object.Anchor = { 0.5, 0.5 }
		voteText.parentDidResize = function()
			voteText.LocalPosition = { frame.Width / 2, frame.Height - titleFrame.Height - 27 }
		end
		voteText:parentDidResize()

		local soloButton = uikit:createButton("Solo (0)")
		soloButton.Width = 152.5
		soloButton:setColor(Color(0, 129, 213), Color.White)
		soloButton:setParent(frame)
		soloButton.Anchor = { 0, 0 }
		soloButton.parentDidResize = function()
			soloButton.LocalPosition = { 15, 15 }
		end
		soloButton:parentDidResize()
		soloButton.onRelease = function() onVoteButtonPressed(GameMode.SOLO) end
		uiElements.playersPreparationScreen.soloButton = soloButton

		local teamButton = uikit:createButton("Team (0)")
		teamButton.Width = 152.5
		teamButton:setColor(Color(0, 129, 213), Color.White)
		teamButton:setParent(frame)
		teamButton.Anchor = { 1, 0 }
		teamButton.parentDidResize = function()
			teamButton.LocalPosition = { frame.Width - teamButton.Width - 15, 15 }
		end
		teamButton:parentDidResize()
		teamButton.onRelease = function() onVoteButtonPressed(GameMode.TEAM) end
		uiElements.playersPreparationScreen.teamButton = teamButton
	end

	uiElements.playersPreparationScreen.frame:show()
	updateTexts()
end

function uiStartCounter()
	if gameState ~= GameStates.STARTING then
		return
	end

	if mainMusic and not disableMusic then
		mainMusic.Volume = 0.6
	end
	uiDestroyScreens()
	Pointer:Hide()
	uiComponents.countDownAnimated({ Screen.Width / 2, Screen.Height / 2 }, function()
		clientStartGame(GameDuration)
	end)
end

function uiRefreshHUD()
	if not uiElements.hud.frame then
		uiDestroyScreens()

		local leadingTeamFrameHeight = 6

		local mainFrame = uikit:createFrame(Color(0, 0, 0, 0))
		mainFrame.Width = Screen.Width
		mainFrame.Height = 75
		mainFrame.parentDidResize = function()
			mainFrame.LocalPosition = { 0, Screen.Height - mainFrame.Height - Screen.SafeArea.Top }
		end
		mainFrame:parentDidResize()
		uiElements.hud.frame = mainFrame

		local textBackground = uikit:createFrame(Color(42, 50, 61, 0.75))
		textBackground:setParent(mainFrame)
		textBackground.Width = 110
		textBackground.Height = 45
		textBackground.parentDidResize = function()
			textBackground.LocalPosition = { mainFrame.Width / 2 - textBackground.Width / 2, mainFrame.Height -
			textBackground.Height - 15 }
		end
		textBackground:parentDidResize()

		local text = uikit:createText("0", Color(255, 255, 255, 255), "default")
		text:setParent(textBackground)
		text.object.Anchor = { 0.5, 0.5 }
		text.parentDidResize = function()
			text.LocalPosition = { textBackground.Width / 2, textBackground.Height / 2 - 2 }
		end
		text.LocalPosition.Z = -1
		text:parentDidResize()
		uiElements.hud.timeLeftText = text

		local leadingTeamFrame = uikit:createFrame(Color(255, 0, 0, 255))
		leadingTeamFrame:setParent(textBackground)
		leadingTeamFrame.Width = textBackground.Width
		leadingTeamFrame.Height = leadingTeamFrameHeight
		leadingTeamFrame.parentDidResize = function()
			leadingTeamFrame.LocalPosition = { 0, -leadingTeamFrame.Height }
		end
		leadingTeamFrame:parentDidResize()
		uiElements.hud.leadingTeamFrame = leadingTeamFrame

		local playerChargeHeight = Screen.Height / 2
		local playerChargeFrame = uikit:createFrame(Color(42, 50, 61, 0.75))
		playerChargeFrame.Width = 15
		playerChargeFrame.Height = playerChargeHeight
		playerChargeFrame.parentDidResize = function()
			playerChargeFrame.LocalPosition = { Screen.Width - playerChargeFrame.Width - 15, Screen.Height / 2 -
			playerChargeFrame.Height / 2 }
		end
		playerChargeFrame.Anchor = { 0.5, 0 }
		playerChargeFrame:parentDidResize()
		uiElements.hud.subFrame = playerChargeFrame

		local playerCharge = uikit:createFrame(Color(255, 50, 61, 0.75))
		playerCharge:setParent(playerChargeFrame)
		playerCharge.Width = playerChargeFrame.Width - 4
		playerCharge.Height = playerChargeFrame.Height - 4 - 50
		playerCharge.parentDidResize = function()
			playerCharge.LocalPosition = { 2, 2 }
		end
		playerCharge.Anchor = { 0.5, 0 }
		playerCharge:parentDidResize()
		uiElements.hud.playerCharge = playerCharge
	end

	-- time left
	local timeLeftRounded = math.min(math.max(math.floor(gameTimeLeft + 0.5), 0), GameDuration)
	if timeLeftRounded ~= previousTimeLeft then
		if timeLeftRounded < 1 then
			uiElements.hud.frame.IsHidden = true
		elseif timeLeftRounded <= 5 then
			sfx("drinking_1", { Volume = 0.75 + (timeLeftRounded / 20), Pitch = 0.8 - (timeLeftRounded / 15) })
			uiElements.hud.timeLeftText.Color = Color.Red
		end

		previousTimeLeft = timeLeftRounded
	end
	uiElements.hud.timeLeftText.Text = timeLeftRounded

	-- show leading team
	if gameStats.teams ~= nil then
		local maxScore = 0
		local leadingTeamID = nil
		helpers.table.forEach(gameStats.teams, function(teamScore, teamID)
			if teamScore > maxScore then
				leadingTeamID = teamID
				maxScore = teamScore
			end
		end)

		if leadingTeamID == nil or maxScore == 0 then
			uiElements.hud.leadingTeamFrame.IsHidden = true
		else
			local teamColor = teamToColor(tonumber(leadingTeamID))
			uiElements.hud.leadingTeamFrame.Color = teamColor
			uiElements.hud.leadingTeamFrame.IsHidden = false
		end
	else
		uiElements.hud.leadingTeamFrame.hide()
	end

	-- update player's charge
	uiElements.hud.playerCharge.Height = helpers.math.remap(playerCharge, 0, 100, 0, uiElements.hud.subFrame.Height - 4)
end

function uiShowGameOverScreen()
	uiDestroyScreens()
	Pointer:Show()
	if mainMusic and not disableMusic then
		mainMusic.Volume = 0.4
	end
	sfx("fireworks_fireworks_child_1", { Volume = 0.75, Pitch = 1.0 })

	if not uiElements.gameOverScreen.frame then
		local frame = uikit:createFrame(Color(42, 50, 61))
		frame.Width = 400
		frame.parentDidResize = function()
			frame.LocalPosition = { Screen.Width / 2 - frame.Width / 2, Screen.Height / 2 - frame.Height / 2 -
			Screen.SafeArea.Top }
		end
		frame:parentDidResize()
		uiElements.gameOverScreen.frame = frame

		-- header
		local titleFrame = uikit:createFrame(Color(27, 36, 43))
		titleFrame:setParent(frame)
		titleFrame.Width = 398
		titleFrame.Height = 45
		titleFrame.parentDidResize = function()
			titleFrame.LocalPosition = { frame.Width / 2 - titleFrame.Width / 2, frame.Height - titleFrame.Height - 1 }
		end
		titleFrame:parentDidResize()

		local text = uikit:createText("Results", Color(203, 206, 209), "default")
		text:setParent(titleFrame)
		text.object.Anchor = { 0, 0.5 }
		text.parentDidResize = function()
			text.LocalPosition = { 15, titleFrame.Height / 2 }
		end
		text:parentDidResize()

		local createTeamResultComponent = function(teamColor, percent)
			local frameWidth = helpers.math.remap(percent, 0, 100, 1, 380)
			local colorFrame = uikit:createFrame(teamColor)
			colorFrame.Width = frameWidth
			colorFrame.Height = 30
			colorFrame.object.Anchor = { 0.5, 0.5 }
			colorFrame:setParent(frame)

			local teamTextPercent = uikit:createText(percent .. "%", Color.White, "default")
			teamTextPercent:setParent(colorFrame)
			teamTextPercent.LocalPosition.Z = -1
			teamTextPercent.object.Anchor = { 0.5, 0.5 }
			teamTextPercent.parentDidResize = function()
				teamTextPercent.LocalPosition = { 0, 0 }
			end
			teamTextPercent:parentDidResize()

			return colorFrame
		end

		local teamResults = calculateTeamScores()
		local gap = 40
		local teamFrameCount = 0
		for key, teamResult in pairs(teamResults) do
			local teamColor = teamToColor(teamResult[1])
			local score = teamResult[3]
			if score > 0 then
				local teamFrame = createTeamResultComponent(Color(teamColor.Red, teamColor.Green, teamColor.Blue, 100),
					score)
				if teamFrame then
					local offsetY = teamFrameCount * gap
					teamFrame.parentDidResize = function()
						teamFrame.LocalPosition = { frame.Width / 2, frame.Height - 70 - offsetY }
					end
					teamFrame:parentDidResize()
					teamFrameCount = teamFrameCount + 1
				end
			end
		end

		local newGameButton = uikit:createButton("New game")
		newGameButton.Width = 380
		newGameButton:setColor(Color.Blue, Color.White)
		newGameButton:setParent(frame)
		newGameButton.Anchor = { 0.5, 0 }
		newGameButton.parentDidResize = function()
			newGameButton.LocalPosition = { frame.Width / 2 - newGameButton.Width / 2, 10 }
		end
		newGameButton:parentDidResize()
		newGameButton.onRelease = function()
			clientPrepareNewGame()
		end

		local totalFrameHeight = titleFrame.Height + newGameButton.Height
		totalFrameHeight = totalFrameHeight + 10 + 10          -- top & bottom paddings
		totalFrameHeight = totalFrameHeight + (gap * teamFrameCount) -- team results
		totalFrameHeight = math.max(totalFrameHeight, 100)
		frame.Height = totalFrameHeight
	end
end
