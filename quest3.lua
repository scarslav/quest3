-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false
Logs = Logs or {}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end


function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end
-- Improved decideNextAction function with dynamic behavior
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange, closestTarget = findClosestTarget(player)

  -- Evasion strategy: If low on health, prioritize moving away from the closest target
  if player.health < 30 then
    print(colors.blue .. "Low health detected. Attempting to evade." .. colors.reset)
    local evasionDirection = getEvasionDirection(player, closestTarget)
    ao.send({Target = Game, Action = "PlayerMove", Direction = evasionDirection})
  -- Attack strategy: If a target is in range and player has enough energy, attack
  elseif player.energy > 5 and targetInRange then
    print(colors.red .. "Player in range. Attacking." .. colors.reset)
    ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(player.energy)})
  -- Defense strategy: If no target is in range, move towards a strategic position or recharge energy
  else
    print(colors.green .. "No player in range or insufficient energy. Moving strategically or recharging." .. colors.reset)
    local strategicDirection = getStrategicDirection(player)
    ao.send({Target = Game, Action = "PlayerMove", Direction = strategicDirection})
  end
  InAction = false
end

-- Function to find the closest target to the player
function findClosestTarget(player)
  local minDistance = Width + Height -- Initialize with max possible distance
  local closestTarget = nil
  local targetInRange = false

  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id then
      local distance = calculateDistance(player.x, player.y, state.x, state.y)
      if distance < minDistance then
        minDistance = distance
        closestTarget = target
      end
      if inRange(player.x, player.y, state.x, state.y, 1) then
        targetInRange = true
      end
    end
  end
  return targetInRange, closestTarget
end

-- Function to calculate distance between two points
function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Function to determine the best direction to evade the closest target
function getEvasionDirection(player, closestTarget)
  local targetState = LatestGameState.Players[closestTarget]
  local dx = player.x - targetState.x
  local dy = player.y - targetState.y
  local directionMap = {
    Up = {x = 0, y = -1}, Down = {x = 0, y = 1},
    Left = {x = -1, y = 0}, Right = {x = 1, y = 0}
  }
  local evasionDirection = "Up" -- Default direction

  -- Choose the direction that increases the distance from the closest target
  if math.abs(dx) > math.abs(dy) then
    evasionDirection = dx > 0 and "Right" or "Left"
  else
    evasionDirection = dy > 0 and "Down" or "Up"
  end
  return evasionDirection
end

-- Function to determine a strategic direction for movement or recharging
function getStrategicDirection(player)
  -- Placeholder for a more complex strategy
  -- Currently returns a random direction
  local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
  local randomIndex = math.random(#directionMap)
  return directionMap[randomIndex]
end
-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
-- Handler to perform a sophisticated return attack when hit by another player
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerState = LatestGameState.Players[ao.id]
      local playerEnergy = playerState.energy
      local playerHealth = playerState.health
      local attackerId = msg.From
      local attackerState = LatestGameState.Players[attackerId]
      local distanceToAttacker = calculateDistance(playerState.x, playerState.y, attackerState.x, attackerState.y)

      -- Check if the player has enough energy and health to consider a return attack
      if playerEnergy == undefined or playerHealth == undefined then
        print(colors.red .. "Unable to read energy or health." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy or health."})
      elseif playerEnergy > 0 and playerHealth > 20 then
        -- Use only a portion of energy for the return attack, saving some for defense
        local attackEnergy = math.floor(playerEnergy / 2)
        -- Consider distance to attacker in the decision to return attack or evade
        if distanceToAttacker <= 2 then
          print(colors.red .. "Close to attacker. Returning attack with " .. attackEnergy .. " energy." .. colors.reset)
          ao.send({Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(attackEnergy)})
        else
          print(colors.blue .. "Attacker is far. Evading instead of attacking." .. colors.reset)
          local evasionDirection = getEvasionDirection(playerState, attackerId)
          ao.send({Target = Game, Action = "PlayerMove", Direction = evasionDirection})
        end
      else
        print(colors.red .. "Player has insufficient energy or health." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Insufficient energy or health."})
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Function to calculate distance between two points
function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Function to determine the best direction to evade the closest attacker
function getEvasionDirection(playerState, attackerId)
  local attackerState = LatestGameState.Players[attackerId]
  local dx = playerState.x - attackerState.x
  local dy = playerState.y - attackerState.y
  local directionMap = {
    Up = {x = 0, y = -1}, Down = {x = 0, y = 1},
    Left = {x = -1, y = 0}, Right = {x = 1, y = 0}
  }
  local evasionDirection = "Up" -- Default direction

  -- Choose the direction that increases the distance from the attacker
  if math.abs(dx) > math.abs(dy) then
    evasionDirection = dx > 0 and "Right" or "Left"
  else
    evasionDirection = dy > 0 and "Down" or "Up"
  end
  return evasionDirection
end
