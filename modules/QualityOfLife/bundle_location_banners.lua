-- AREA BANNER -- the name of the place you have just walked into.
--
-- Descended from the LOCATION BANNERS feature of unxpected-uxp's Quality of
-- Life mod.  The map-watching, the name resolution and both draw seams are
-- theirs and are reproduced faithfully; what is rewritten here is what the
-- banner looks like, which is the reason this file exists at all.  It replaced
-- their qol_feature_location_banners.lua outright, so that file is no longer
-- carried.
--
-- The original drew `Font.drawBox(0, 14, 20, 4)`: twenty tiles wide, four tall,
-- flush with the bottom of the screen.  That is the exact geometry of the
-- game's dialogue box, so a one-word area name arrives looking like somebody
-- started a conversation and thought better of it -- a full-width frame,
-- mostly empty, sitting over the ground the player is walking on, in the one
-- place on screen the player has been trained to read sentences.
--
-- What it is instead:
--
--   * a plaque sized to the name.  Two tiles of frame around however many the
--     text needs, so PALLET TOWN gets a small sign and ROCK TUNNEL a slightly
--     wider one, the way Gen 2's own location sign is drawn.
--   * out of the way by default.  Top-left, where Gen 2 puts it and where
--     nothing else is drawn, instead of over the bottom of the field.
--   * on and off rather than simply appearing.  It slides in from the screen
--     edge it is anchored to and slides back out, over about a fifth of a
--     second at each end, so it reads as a sign being raised rather than a
--     box blinking on.
--
-- Position is a row, because "out of the way" depends on where the player
-- keeps their eyes, and BOTTOM is there for anyone who wants upstream's
-- placement back.

local OVERLAY_KEY = "__gen1wildAreaBannerOverlay"
local DRAW_WRAP_KEY = "__gen1wildAreaBannerDrawWrap"

-- Rock Tunnel's Pokemon Center announces itself the moment you leave the dark,
-- on a map the player has not really entered; upstream suppresses it and so
-- does this.
local SUPPRESSED_MAPS = { ROCK_TUNNEL_POKECENTER = true }

local SCREEN_W, SCREEN_H = 160, 144
local TILE = 8
local BOX_H = 3          -- top border, one line of text, bottom border
local MARGIN = 1         -- tiles between the plaque and the screen edge
local SLIDE = 0.18       -- seconds of travel at each end

local schema = {
  {
    key = "qol_location_banners",
    label = "AREA BANNER",
    type = "choice",
    default = false,
    choices = {
      { "OFF", false },
      { "ON (1 SECOND)", 1 },
      { "ON (2 SECONDS)", 2 },
      { "ON (3 SECONDS)", 3 },
    },
    -- Carries a player forward from upstream's boolean row.
    aliases = { [true] = 2 },
  },
  {
    key = "qol_banner_position",
    label = "POSITION",
    type = "choice",
    default = "top_left",
    choices = {
      { "TOP LEFT", "top_left" },
      { "TOP", "top" },
      { "BOTTOM", "bottom" },
      { "BOTTOM LEFT", "bottom_left" },
    },
  },
  {
    key = "qol_banner_slide",
    label = "SLIDE IN",
    type = "toggle",
    default = true,
  },
}

-- ---------------------------------------------------------------- geometry

local function anchorFor(position)
  if position == "top" then return "top", "center" end
  if position == "bottom" then return "bottom", "center" end
  if position == "bottom_left" then return "bottom", "left" end
  return "top", "left"
end

-- Everything the draw needs, in tiles, worked out from the name itself.
local function plaqueFor(Font, name, position)
  local textPx = Font.width(name)
  local widthTiles = math.ceil(textPx / TILE) + 2
  local maxTiles = math.floor(SCREEN_W / TILE)
  if widthTiles > maxTiles then widthTiles = maxTiles end

  local vertical, horizontal = anchorFor(position)

  local tx
  if horizontal == "center" then
    tx = math.floor((maxTiles - widthTiles) / 2)
  else
    tx = MARGIN
  end
  if tx < 0 then tx = 0 end

  local ty
  if vertical == "top" then
    ty = MARGIN
  else
    ty = math.floor(SCREEN_H / TILE) - BOX_H - MARGIN
  end

  -- Centre the text inside the frame rather than left-aligning it against the
  -- border: on a plaque this narrow the difference is the whole look.
  local innerPx = (widthTiles - 2) * TILE
  local textX = tx * TILE + TILE + math.max(0, math.floor((innerPx - textPx) / 2))

  return {
    tx = tx,
    ty = ty,
    w = widthTiles,
    h = BOX_H,
    textX = textX,
    textY = (ty + 1) * TILE,
    vertical = vertical,
  }
end

-- How far off its resting place the plaque sits right now, in pixels.  Zero
-- for all but the first and last fraction of a second of its life.
local function slideOffset(state, now, enabled)
  if not enabled then return 0 end
  local elapsed = now - state.shownAt
  local remaining = state.expiresAt - now
  local travel = (BOX_H + MARGIN) * TILE

  local progress
  if elapsed < SLIDE then
    progress = elapsed / SLIDE
  elseif remaining < SLIDE then
    progress = remaining / SLIDE
  else
    return 0
  end
  if progress < 0 then progress = 0 elseif progress > 1 then progress = 1 end

  -- Ease out: fast off the edge, settling at the end.  1-(1-t)^2.
  local eased = 1 - (1 - progress) * (1 - progress)
  return math.floor((1 - eased) * travel + 0.5)
end

-- ---------------------------------------------------------------- drawing

local function drawPlaque(mod, state, position, sliding)
  local Font = mod.ui.Font
  local plaque = plaqueFor(Font, state.name, position)
  local offset = slideOffset(state, love.timer.getTime(), sliding)
  if plaque.vertical == "top" then offset = -offset end

  love.graphics.push()
  love.graphics.translate(0, offset)
  Font.drawBox(plaque.tx, plaque.ty, plaque.w, plaque.h)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(state.name, plaque.textX, plaque.textY)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.pop()
end

-- ---------------------------------------------------------------- names

local function locationNameGen1(game, mapId, map)
  local townMap = game.data.field and game.data.field.townMap
  local locations = townMap and (townMap.locations or townMap)
  local entry = type(locations) == "table" and locations[mapId]
  local name = type(entry) == "table" and (entry.name or entry.label)
  local def = map and map.def or game.data.maps and game.data.maps[mapId]
  if not name and def and type(def.label) == "string" then
    name = def.label:gsub("(%l)(%u)", "%1 %2")
  end
  return (name or tostring(mapId):gsub("_", " ")):upper()
end

-- ---------------------------------------------------------------- install

local function tracker(mod, read)
  local states = setmetatable({}, { __mode = "k" })
  local lastNames = setmetatable({}, { __mode = "k" })

  local function show(owner, name)
    local duration = read("qol_location_banners")
    if type(duration) ~= "number" then return false end
    if lastNames[owner] == name then return false end
    lastNames[owner] = name
    local now = love.timer.getTime()
    states[owner] = { name = name, shownAt = now, expiresAt = now + duration }
    return true
  end

  local function clear(owner) states[owner] = nil end

  local function current(owner)
    local state = states[owner]
    if not state then return nil end
    if read("qol_location_banners") == false
       or love.timer.getTime() >= state.expiresAt then
      states[owner] = nil
      return nil
    end
    return state
  end

  return { show = show, clear = clear, current = current }
end

-- Red/Blue/Yellow: the overworld has a drawUI seam, and by the time it runs
-- the 160x144 game canvas is already set up.
local function installGen1(mod, read)
  local track = tracker(mod, read)

  local function draw(ow)
    local state = track.current(ow)
    if not state then return end
    drawPlaque(mod, state, read("qol_banner_position"), read("qol_banner_slide"))
  end

  mod.events:on("map.entered", function(event)
    local game = mod.world.game
    if not event or not event.mapId then return end
    local ow = mod.world:overworld()
    if not ow then return end
    if SUPPRESSED_MAPS[event.mapId] then track.clear(ow) return end
    if not track.show(ow, locationNameGen1(game, event.mapId, event.map)) then
      return
    end

    local overlay = rawget(ow, OVERLAY_KEY)
    if not overlay and type(ow.drawUI) == "function" then
      overlay = {}
      ow[OVERLAY_KEY] = overlay
      local drawUI = ow.drawUI
      ow.drawUI = function(self, ...)
        drawUI(self, ...)
        local live = rawget(self, OVERLAY_KEY)
        if live and live.draw then live.draw(self) end
      end
    end
    if overlay then overlay.draw = draw end
  end)
end

-- Gold has no drawUI seam, so this rides World.draw, which returns with every
-- tilt/pipeline/pokepic push popped back to plain window pixels.  That is why
-- the fit-scale translate is done here rather than assumed -- the same one
-- World:draw uses for its own pokePic block.
local function installGen2(mod, read)
  local World = require("src.world.gen2.World")
  local track = tracker(mod, read)

  local function draw(world)
    local state = track.current(world)
    if not state then return end
    local G = love.graphics
    local scale = world:fitScale()
    local w, h = G.getDimensions()
    G.push()
    G.translate(math.floor((w - SCREEN_W * scale) / 2),
                math.floor((h - SCREEN_H * scale) / 2))
    G.scale(scale, scale)
    drawPlaque(mod, state, read("qol_banner_position"), read("qol_banner_slide"))
    G.pop()
  end

  if not rawget(World, DRAW_WRAP_KEY) then
    local base = World.draw
    World.draw = function(self, ...)
      base(self, ...)
      draw(self)
    end
    World[DRAW_WRAP_KEY] = true
  end

  mod.events:on("map.entered", function(event)
    if not event or not event.mapId then return end
    local world = mod.world and mod.world:overworld()
    if not world then return end
    local name = (world.landmarkName and world:landmarkName())
      or tostring(event.mapId):gsub("_", " ")
    track.show(world, name:gsub("\n", " "):upper())
  end)
end

return function(mod)
  mod.options:define(schema)

  local aliases = {}
  for _, row in ipairs(schema) do
    if row.aliases then aliases[row.key] = row.aliases end
  end

  local function read(key)
    local value = mod.options:get(key)
    local map = aliases[key]
    if map and map[value] ~= nil then return map[value] end
    return value
  end

  local GameVersion = require("src.core.GameVersion")
  local ok, generation = pcall(GameVersion.generation)
  if not ok or type(generation) ~= "number" then generation = 1 end

  if generation == 2 then
    installGen2(mod, read)
  else
    installGen1(mod, read)
  end

  mod.exports.plaqueFor = plaqueFor
end
