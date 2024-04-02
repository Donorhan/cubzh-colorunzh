Modules = {
	helpers = "github.com/Donorhan/cubzh-library/helpers:819b4e9",
	powerUpItem = "github.com/Donorhan/cubzh-library/power-up-item:8de76d1",
	uiComponents = "github.com/Donorhan/cubzh-library/ui-components:828bf2b",
}

Config = {
	Map = "dono.brawlarea_1",
	Items = {
		"dono.colorimap",
		"claire.potion",
		"buche.ducky",
		"yauyau.magic_cube",
		"wrden.frog_with_hat",
	}
}

------------------------------
-- Configuration
------------------------------
local BlocScale = Number3(15.0, 15.0, 15.0)
local GameDuration = 30 -- in seconds
local GameStates = { WAITING_PLAYERS = 0, STARTING = 1, RUNNING = 2, ENDED = 3 }
local MaxTeam = 8
local MaxSoundDistance = 8000
local NetworkEvents = {
	GAME_STATE_CHANGED = "game-state",
	MAP_INIT = "map-init",
	PLAYER_ASK_MAP = "player-ask-map",
	PLAYER_ASSIGN_TEAM = "player-team",
	PLAYER_KILLED = "player-killed",
	PLAYER_STATE_CHANGED = "player-state",
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
local PowerUpsSpawnRange = { min = 3, max = 7 }
local TeamColors = {
	RED = Color(255, 0, 0, 160),
	BLUE = Color(0, 0, 255, 160),
	GREEN = Color(0, 255, 0, 160),
	YELLOW = Color(255, 255, 0, 160),
	PINK = Color(255, 0, 255, 160),
	CYAN = Color(0, 255, 255, 160),
	ORANGE = Color(255, 128, 0, 160),
	PURPLE = Color(128, 0, 255, 160),
	GREY = Color(50, 50, 50, 160),
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
local screenMode = false
local activePowerUps = {}
local gameCount = 0
local gameState = GameStates.WAITING_PLAYERS
local gameTimeLeft = GameDuration
local mapShapesContainer = Object()
local mapState = {}
local playerSpeed = PlayerDefaultSpeed
local playersAssignedTeam = {}
local playersStates = {}
local PowerUps = {
	-- Add a temporary speed to the player
	["playerSpeed"] = {
		model = Items.claire.potion,
		modelScale = Number3(0.5, 0.5, 0.5),
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

			Timer(0.500, function()
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

				Timer(5, function()
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
	for id, player in pairs(Players) do
		if playersStates[player.UserID] == 1 then
			playersReadyCount = playersReadyCount + 1
		end

		playersCount = playersCount + 1
	end

	return {
		playersCount = playersCount,
		playersReadyCount = playersReadyCount,
		ready = (playersCount == playersReadyCount)
	}
end

function teamToColor(teamID)
	local shapeColor = TeamColors.GREY
	if teamID == 0 then
		shapeColor = TeamColors.RED
	elseif teamID == 1 then
		shapeColor = TeamColors.BLUE
	elseif teamID == 2 then
		shapeColor = TeamColors.GREEN
	elseif teamID == 3 then
		shapeColor = TeamColors.YELLOW
	elseif teamID == 4 then
		shapeColor = TeamColors.PINK
	elseif teamID == 5 then
		shapeColor = TeamColors.CYAN
	elseif teamID == 6 then
		shapeColor = TeamColors.ORANGE
	elseif teamID == 7 then
		shapeColor = TeamColors.PURPLE
	end

	return shapeColor
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

------------------------------
-- Client
------------------------------
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

function clientSetShapeOwner(shapeID, userID)
	local userTeamID = playersAssignedTeam[userID]
	if mapState[shapeID].team == userTeamID then
		tagComboCounter = 0
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
		tagComboCounter = tagComboCounter + 1
	else
		-- avoid audio spam with players far away
		local distance = (shapePosition - Player.Position).SquaredLength
		if distance < MaxSoundDistance then
			local volume = helpers.math.remap(distance, 0, MaxSoundDistance, 0.1, 0.75)
			sfx("waterdrop_2", { Position = shapePosition, Pitch = 1.1 + math.random() * 0.5, Volume = 0.65 - volume })
		end
	end

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
	playersStates = {}
	clientDropPlayer(Player)
	uiShowPlayersPreparationScreen()

	local e = Event()
	e.action = NetworkEvents.PLAYER_ASK_MAP
	e.shapeID = shapeID
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
	mainMusic.Volume = 0.6
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
		playersStates[event.userID] = event.state
		uiShowPlayersPreparationScreen()
	elseif event.action == NetworkEvents.PLAYER_KILLED then
		if event.Sender ~= Player then
			onPlayerKilled(event.Sender, event.source)
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
local serverNextTeamId = 0
local serverTimeElapsedSinceLastPowerUp = 0
local serverNextPowerUpIn = 0
local serverNextPowerUpId = 1
local serverMapSize = { x = 0, z = 0 }


-- note: simple map for now
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

function serverSetPlayerTeam(player, removeTeam)
	local sendEvent = function()
		local e = Event()
		e.action = NetworkEvents.PLAYERS_INIT
		e.state = JSON:Encode(playersAssignedTeam)
		e:SendTo(Players)
	end

	if removeTeam then
		helpers.table.removeKey(playersAssignedTeam, player.UserID)
		sendEvent()
		return
	end

	if playersAssignedTeam[player.UserID] then
		sendEvent()
		return
	end

	local teamId = serverNextTeamId
	playersAssignedTeam[player.UserID] = teamId
	sendEvent()

	serverNextTeamId = serverNextTeamId + 1
	if serverNextTeamId >= MaxTeam then
		serverNextTeamId = 0
	end
end

function serverClearGame()
	for index in pairs(playersStates) do
		playersStates[index] = nil
	end
	playersStates = {}

	gameState = GameStates.WAITING_PLAYERS
	serverNextTeamId = 0
	serverTimeElapsedSinceLastPowerUp = 0
	serverNextPowerUpId = 1
	serverCalculateNextPowerUpIn()
end

function serverOnPlayerStateChanged(player, state)
	playersStates[player.UserID] = state
	local playersStates = computePlayersStates()

	local e = Event()
	e.action = NetworkEvents.PLAYER_STATE_CHANGED
	e.userID = player.UserID
	e.state = state
	e:SendTo(Players)

	if playersStates.ready == true then
		gameState = GameStates.STARTING
		gameTimeLeft = GameDuration + 3 -- + 3 for the countdown, yeah it's dirty

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

Server.OnStart = function()
	gameCount = 0
	serverClearGame()
	serverPrepareMap()
end

Server.DidReceiveEvent = function(event)
	local senderID = event.Sender.UserID;

	if event.action == NetworkEvents.SHAPE_TAG then
		if gameState ~= GameStates.RUNNING then
			return
		end

		if not mapState[event.shapeID] then
			return
		end

		local senderTeamID = playersAssignedTeam[senderID]
		mapState[event.shapeID].owner = senderID
		mapState[event.shapeID].team = senderTeamID

		local response = Event()
		response.action = NetworkEvents.SHAPE_TAG
		response.shapeID = event.shapeID
		response.teamID = senderTeamID
		response.userID = senderID
		response:SendTo(Players)
	elseif event.action == NetworkEvents.PLAYER_STATE_CHANGED then
		serverOnPlayerStateChanged(event.Sender, event.state);
	elseif event.action == NetworkEvents.PLAYER_ASK_MAP then
		serverSendMapState(event.Sender)
	elseif event.action == NetworkEvents.POWERUPS_COLLECTED then
		local response = Event()
		response.powerUpID = event.powerUpID
		response.userID = senderID
		response:SendTo(Players)
		activePowerUps[event.powerUpID] = nil
	end
end

Server.OnPlayerJoin = function(player)
	serverSetPlayerTeam(player)
	serverSendMapState(player)

	local e = Event()
	e.action = NetworkEvents.GAME_STATE_CHANGED
	e.state = gameState
	e.timeLeft = gameTimeLeft
	e:SendTo(Players[player.ID])
end

Server.OnPlayerLeave = function(player)
	serverSetPlayerTeam(player, true)
	serverOnPlayerStateChanged(player, 0);
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
		timeLeftText = nil,
		timeLeftAnimation = nil,
		previousTimeLeft = 0
	},
	["gameOverScreen"] = {
		frame = nil,
		subFrame = nil,
	},
	["playersPreparationScreen"] = {
		frame = nil,
		subFrame = nil,
		text = nil,
		button = nil,
	},
}


function uiDestroyScreens()
	for key, screen in pairs(uiElements) do
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

	if mainMusic then
		mainMusic.Volume = 0.7
	end
	Pointer:Show()

	local updateText = function(text)
		local playersStates = computePlayersStates()
		text.Text = "Players ready: " .. playersStates.playersReadyCount .. " / " .. playersStates.playersCount
	end

	if not uiElements.playersPreparationScreen.frame then
		uiDestroyScreens()

		local frame = uikit:createFrame(Color(20, 20, 20, 255))
		frame.Width = 350
		frame.Height = 120
		frame.parentDidResize = function()
			frame.LocalPosition = { Screen.Width / 2 - frame.Width / 2, Screen.Height - frame.Height -
			Screen.SafeArea.Top - 25 }
		end
		frame:parentDidResize()
		uiElements.playersPreparationScreen.frame = frame

		local subFrame = uikit:createFrame(Color(60, 60, 60, 128))
		subFrame.Width = 375
		subFrame.Height = 150
		subFrame.parentDidResize = function()
			subFrame.LocalPosition = { Screen.Width / 2 - subFrame.Width / 2, Screen.Height - frame.Height -
			Screen.SafeArea.Top - 40 }
		end
		subFrame:parentDidResize()
		uiElements.playersPreparationScreen.subFrame = subFrame

		local text = uikit:createText("initializing …", Color.White, "default")
		text:setParent(frame)
		text.object.Anchor = { 0.5, 1 }
		text.parentDidResize = function()
			text.LocalPosition = { frame.Width / 2, frame.Height - text.Height / 2 - 15 }
		end
		text:parentDidResize()
		updateText(text)
		uiElements.playersPreparationScreen.text = text

		local readyButton = uikit:createButton("I'm ready")
		readyButton.Width = 275
		readyButton:setColor(Color(0, 204, 255), Color.White)
		readyButton:setParent(frame)
		readyButton.Anchor = { 0.5, 0 }
		readyButton.parentDidResize = function()
			readyButton.LocalPosition = { frame.Width / 2 - readyButton.Width / 2, 15 }
		end
		readyButton:parentDidResize()
		readyButton.onRelease = function()
			local e = Event()
			e.action = NetworkEvents.PLAYER_STATE_CHANGED
			e.state = 1
			e:SendTo(Server)
			readyButton:disable()
		end
		uiElements.playersPreparationScreen.button = readyButton
	end

	uiElements.playersPreparationScreen.frame:show()
	updateText(uiElements.playersPreparationScreen.text)
end

function uiStartCounter()
	if gameState ~= GameStates.STARTING then
		return
	end

	if mainMusic then
		mainMusic.Volume = 0.8
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

		local frame = uikit:createFrame(Color(0, 0, 0, 0.75))
		frame.Width = 110
		frame.Height = 80
		frame.parentDidResize = function()
			frame.LocalPosition = { Screen.Width / 2 - frame.Width / 2, Screen.Height - frame.Height -
			Screen.SafeArea.Top - 25 }
		end
		frame:parentDidResize()
		uiElements.hud.frame = frame

		local text = uikit:createText("0", Color(255, 255, 255, 255), "big")
		text:setParent(frame)
		text.object.Anchor = { 0.5, 0.5 }
		text.parentDidResize = function()
			text.LocalPosition = { frame.Width / 2, frame.Height / 2 - 2 }
		end
		text.LocalPosition.Z = -1
		text:parentDidResize()
		uiElements.hud.timeLeftText = text
	end

	local timeLeftRounded = math.min(math.max(math.floor(gameTimeLeft + 0.5), 0), GameDuration)
	if timeLeftRounded ~= previousTimeLeft then
		if timeLeftRounded < 1 then
			uiElements.hud.frame.hide()
			uiElements.hud.timeLeftText.hide()
		elseif timeLeftRounded <= 5 then
			sfx("drinking_1", { Volume = 0.75 + (timeLeftRounded / 20), Pitch = 0.8 - (timeLeftRounded / 15) })
			uiElements.hud.timeLeftText.Color = Color.Red
		end

		previousTimeLeft = timeLeftRounded
	end

	uiElements.hud.timeLeftText.Text = timeLeftRounded
end

function uiShowGameOverScreen()
	uiDestroyScreens()
	Pointer:Show()
	if mainMusic then
		mainMusic.Volume = 0.6
	end
	sfx("fireworks_fireworks_child_1", { Volume = 0.75, Pitch = 1.0 })

	if not uiElements.gameOverScreen.frame then
		local frame = uikit:createFrame(Color(20, 20, 20, 255))
		frame.Width = 400
		frame.Height = 450
		frame.parentDidResize = function()
			frame.LocalPosition = { Screen.Width / 2 - frame.Width / 2, Screen.Height / 2 - frame.Height / 2 }
		end
		frame:parentDidResize()
		uiElements.gameOverScreen.frame = frame

		local subFrame = uikit:createFrame(Color(60, 60, 60, 128))
		subFrame.Width = 425
		subFrame.Height = 475
		subFrame.LocalPosition.Z = -1
		subFrame.parentDidResize = function()
			subFrame.LocalPosition = { Screen.Width / 2 - subFrame.Width / 2, Screen.Height / 2 - subFrame.Height / 2 }
		end
		subFrame:parentDidResize()
		uiElements.gameOverScreen.subFrame = subFrame

		local separator = uikit:createFrame(Color(70, 70, 70, 255))
		separator:setParent(frame)
		separator.Width = frame.Width - 50
		separator.Height = 2
		separator.object.Anchor = { 0.5, 0.5 }
		separator.parentDidResize = function()
			separator.LocalPosition = { separator.Width / 2 + 50 / 2, frame.Height - 65 }
		end
		separator:parentDidResize()

		local text = uikit:createText("Results", Color(235, 235, 235), "big")
		text:setParent(frame)
		text.LocalPosition.Z = -1
		text.object.Anchor = { 0.5, 0.5 }
		text.parentDidResize = function()
			text.LocalPosition = { frame.Width / 2, frame.Height - 35 }
		end
		text:parentDidResize()

		local createTeamResultComponent = function(teamColor, percent)
			local frameWidth = helpers.math.remap(percent, 0, 100, 1, 350)
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
		local gap = 35
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
						teamFrame.LocalPosition = { frame.Width / 2, frame.Height - 110 - offsetY }
					end
					teamFrame:parentDidResize()
					teamFrameCount = teamFrameCount + 1
				end
			end
		end

		local newGameButton = uikit:createButton("Start new game")
		newGameButton.Width = 375
		newGameButton:setColor(Color.Blue, Color.White)
		newGameButton:setParent(frame)
		newGameButton.Anchor = { 0.5, 0 }
		newGameButton.parentDidResize = function()
			newGameButton.LocalPosition = { frame.Width / 2 - newGameButton.Width / 2, 15 }
		end
		newGameButton:parentDidResize()
		newGameButton.onRelease = function()
			clientPrepareNewGame()
		end
	end
end