-- Gen1Follower – Unified follower mod for Pokémon Red, Blue, Yellow and Gold
-- Merges:
--   • Full follower mechanics (draw/resolve overrides) from main0.0.1
--   • Red/Blue support, persistent selection, talk wrapper from main0.0.2
--   • Dex‑numbered assets, icon patches, purge logic from main0.0.3
-- All improvements are integrated without breaking the core follower behaviour.
--
-- The `__pokepc*` / `pokepcFollower*` / `ICON_POKEPC_` names below are markers
-- this mod writes onto engine and third-party tables (PikachuFollower,
-- PartyMenu, the Dramatic Shape billboard module). They keep their historical
-- names on purpose: they are the handshake a PokePC-lineage follower mod uses
-- to detect that another one already installed its wrappers. Renaming them
-- would let two lineage mods stack wrappers on the same engine functions.

return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.get()
  local generation = GameVersion.generation()
  local isGen2 = generation == 2
  local isYellow = GameVersion.isYellow()

  print(string.format("[Gen1Follower] Initializing for %s", version:upper()))

  -- Core modules
  local PaletteFX = require("src.render.PaletteFX")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Assets = require("src.render.Assets")
  local PikachuFollower = require("src.world.PikachuFollower")
  local Strings = require("src.core.Strings")
  local Sound = require("src.core.Sound")
  local TextBox = require("src.render.TextBox")
  local PartyMenu = require("src.ui.PartyMenu")
  local OverworldController = require("src.world.OverworldController")

  -- mod.game is resolved lazily by the loader. Do not cache fields from it at
  -- entry time: Gold's Game2 instance is not fully ready yet when mods load.
  local function liveGame()
    return mod.game
  end

  local function worldFor(game)
    local world = game and (game.overworld or game.world)
    if world then return world end
    local worldApi = mod.world
    return worldApi and worldApi.overworld and worldApi:overworld() or nil
  end

  local function spritesFor(game)
    local data = game and game.data
    return data and (data.sprites or data.gen2Sprites) or nil
  end

  -- Unique Menu Icons deliberately owns the party icon column when both mods
  -- are active.  Prefer its explicit capability export, while treating the
  -- released mod id as an ownership signal for older compatible builds.
  local function externalPartyIconOwner()
    if type(mod.find) ~= "function" then return false end
    local ok, handle = pcall(mod.find, mod, "unique_menu_icons")
    if not (ok and handle) then return false end
    local exports = handle.exports
    if type(exports) == "table" and exports.ownsPartyIcons ~= nil then
      return exports.ownsPartyIcons == true
    end
    return true
  end

  -- Constants
  local FALLBACK_SPECIES = "CHARMANDER"
  local SPRITE_ID = "SPRITE_PIKACHU"
  local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

  -- A human-sized 1.70 m Pokemon keeps the original 16 px follower card.
  -- Power-curve compression preserves the Pokedex ordering without letting
  -- long species such as Onix cover most of the map. A readable floor keeps
  -- the smallest species visible, and one-pixel steps keep nearby sizes
  -- visually coherent with nearest-neighbour rendering.
  local POKEDEX_REFERENCE_METERS = 1.70
  local POKEDEX_SCALE_EXPONENT = 0.40
  -- 1.0, and never below it: the sheets are 16x16 and that is all the detail
  -- there is.  Drawing one smaller does not make a small POKeMON, it deletes
  -- rows -- at the old 0.6875 floor a 16px sprite was resampled to 11px, which
  -- throws away five rows and five columns and 67 of Bulbasaur's 138 opaque
  -- pixels.  What survived read as a flat blob: the legs merged into two black
  -- bars, the bulb lost its outline, and the shading collapsed until the whole
  -- thing looked like two colours rather than the art it is.  Every small
  -- POKeMON hit that floor, so every small POKeMON was mangled.
  --
  -- Big ones still grow, which is the half of POKEDEX SIZES that costs nothing
  -- -- scaling 16px UP by a whole number keeps every pixel.  Down has no detail
  -- budget to spend, so it is not spent.
  local MIN_FOLLOWER_SCALE = 1.0
  local MAX_FOLLOWER_SCALE = 2.50
  local SCALE_QUANTUM = 0.0625

  if mod.options and mod.options.define then
    mod.options:define({
      {
        -- OFF, so every follower is the size its art was drawn at.
        --
        -- The sheets are all 16x16, so a follower at 1.0 is the sprite exactly
        -- as it was drawn, and every one of the 251 reads the way its artist
        -- meant it to.  Turning this on is a real choice with a real cost: a
        -- Pokedex-proportional Onix is worth seeing, but it is bought by
        -- making everything else relative to it, and the small end of the
        -- Pokedex has no pixels to spare.  That is a preference, not a
        -- default, so it is a row rather than the shipping state.
        --
        -- Nothing shrinks below 1.0 either way -- see MIN_FOLLOWER_SCALE.
        key = "pokedex_follower_sizes",
        type = "toggle",
        label = "POKEDEX SIZES",
        default = false,
        help = "Scale followers by Pokedex height. Off draws every sprite at "
            .. "the size it was drawn.",
      },
      {
        key = "overworld_mon_sprites",
        type = "toggle",
        label = "MAP POKEMON",
        default = true,
        help = "Draw the Pokemon standing on maps from the same 251 sheets.",
      },
      {
        key = "follower_size_percent",
        type = "number",
        label = "FOLLOWER SIZE",
        default = 100,
        min = 75,
        max = 125,
        step = 5,
        help = "Adjust every Pokedex-derived follower size.",
      },
    })
  end

  local function optionValue(key, fallback)
    if not (mod.options and mod.options.get) then return fallback end
    local ok, value = pcall(mod.options.get, mod.options, key)
    if not ok or value == nil then return fallback end
    return value
  end

  local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
  end

  -- ----------------------------------------------------------------------
  -- 1. Asset path helpers (dex-numbered files, e.g. follower_004.png)
  -- ----------------------------------------------------------------------
  local speciesToDex = {
    BULBASAUR=1, IVYSAUR=2, VENUSAUR=3, CHARMANDER=4, CHARMELEON=5, CHARIZARD=6,
    SQUIRTLE=7, WARTORTLE=8, BLASTOISE=9, CATERPIE=10, METAPOD=11, BUTTERFREE=12,
    WEEDLE=13, KAKUNA=14, BEEDRILL=15, PIDGEY=16, PIDGEOTTO=17, PIDGEOT=18,
    RATTATA=19, RATICATE=20, SPEAROW=21, FEAROW=22, EKANS=23, ARBOK=24,
    PIKACHU=25, RAICHU=26, SANDSHREW=27, SANDSLASH=28, NIDORAN_F=29, NIDORINA=30,
    NIDOQUEEN=31, NIDORAN_M=32, NIDORINO=33, NIDOKING=34, CLEFAIRY=35, CLEFABLE=36,
    VULPIX=37, NINETALES=38, JIGGLYPUFF=39, WIGGLYTUFF=40, ZUBAT=41, GOLBAT=42,
    ODDISH=43, GLOOM=44, VILEPLUME=45, PARAS=46, PARASECT=47, VENONAT=48,
    VENOMOTH=49, DIGLETT=50, DUGTRIO=51, MEOWTH=52, PERSIAN=53, PSYDUCK=54,
    GOLDUCK=55, MANKEY=56, PRIMEAPE=57, GROWLITHE=58, ARCANINE=59, POLIWAG=60,
    POLIWHIRL=61, POLIWRATH=62, ABRA=63, KADABRA=64, ALAKAZAM=65, MACHOP=66,
    MACHOKE=67, MACHAMP=68, BELLSPROUT=69, WEEPINBELL=70, VICTREEBEL=71, TENTACOOL=72,
    TENTACRUEL=73, GEODUDE=74, GRAVELER=75, GOLEM=76, PONYTA=77, RAPIDASH=78,
    SLOWPOKE=79, SLOWBRO=80, MAGNEMITE=81, MAGNETON=82, FARFETCHD=83, DODUO=84,
    DODRIO=85, SEEL=86, DEWGONG=87, GRIMER=88, MUK=89, SHELLDER=90,
    CLOYSTER=91, GASTLY=92, HAUNTER=93, GENGAR=94, ONIX=95, DROWZEE=96,
    HYPNO=97, KRABBY=98, KINGLER=99, VOLTORB=100, ELECTRODE=101, EXEGGCUTE=102,
    EXEGGUTOR=103, CUBONE=104, MAROWAK=105, HITMONLEE=106, HITMONCHAN=107, LICKITUNG=108,
    KOFFING=109, WEEZING=110, RHYHORN=111, RHYDON=112, CHANSEY=113, TANGELA=114,
    KANGASKHAN=115, HORSEA=116, SEADRA=117, GOLDEEN=118, SEAKING=119, STARYU=120,
    STARMIE=121, MR_MIME=122, SCYTHER=123, JYNX=124, ELECTABUZZ=125, MAGMAR=126,
    PINSIR=127, TAUROS=128, MAGIKARP=129, GYARADOS=130, LAPRAS=131, DITTO=132,
    EEVEE=133, VAPOREON=134, JOLTEON=135, FLAREON=136, PORYGON=137, OMANYTE=138,
    OMASTAR=139, KABUTO=140, KABUTOPS=141, AERODACTYL=142, SNORLAX=143, ARTICUNO=144,
    ZAPDOS=145, MOLTRES=146, DRATINI=147, DRAGONAIR=148, DRAGONITE=149, MEWTWO=150, MEW=151
  }

  local MAX_FOLLOWER_DEX = 251

  -- Other content mods can register additional species before this mod loads.
  -- Crystal 251 is an optional dependency, so its Johto records are visible
  -- here whenever it is enabled and has completed its ROM import.
  if mod.content and mod.content.pokemon and mod.content.pokemon.each then
    pcall(function()
      for id, def in mod.content.pokemon:each() do
        local dex = def and tonumber(def.dex)
        if type(id) == "string" and dex and dex >= 1 and dex <= MAX_FOLLOWER_DEX then
          speciesToDex[id:upper()] = math.floor(dex)
        end
      end
    end)
  end

  local function dexForSpecies(species)
    local numeric = tonumber(species)
    if numeric and numeric >= 1 and numeric <= MAX_FOLLOWER_DEX then
      return math.floor(numeric)
    end

    local key = tostring(species or FALLBACK_SPECIES):upper()
    local dex = speciesToDex[key]
    if dex then return dex end

    -- Runtime fallback for species supplied by a mod that loaded after us.
    local game = liveGame()
    local pokemon = game and game.data and game.data.pokemon
    local def = pokemon and pokemon[key]
    dex = def and tonumber(def.dex)
    if dex and dex >= 1 and dex <= MAX_FOLLOWER_DEX then
      dex = math.floor(dex)
      speciesToDex[key] = dex
      return dex
    end
    return nil
  end

  local function pokemonDefForSpecies(species)
    local game = liveGame()
    local pokemon = game and game.data and game.data.pokemon
    if type(pokemon) ~= "table" then return nil end
    local key = tostring(species or FALLBACK_SPECIES):upper()
    if pokemon[key] then return pokemon[key] end

    local dex = dexForSpecies(key)
    if not dex then return nil end
    for _, def in pairs(pokemon) do
      if type(def) == "table" and tonumber(def.dex) == dex then return def end
    end
    return nil
  end

  local function pokedexHeightMeters(species)
    local key = tostring(species or FALLBACK_SPECIES):upper()
    local def = pokemonDefForSpecies(species)
    local entry = def and def.dexEntry
    local feet = entry and tonumber(entry.heightFt)
    local inches = entry and tonumber(entry.heightIn)
    if feet == nil or inches == nil then
      local game = liveGame()
      local dex = game and game.data and game.data.gen2Pokedex
      local gen2Entry = dex and dex.entries and dex.entries[key]
      local encoded = gen2Entry and tonumber(gen2Entry.height)
      if encoded then
        feet = math.floor(encoded / 100)
        inches = encoded % 100
      end
    end
    if feet == nil or inches == nil then return nil end
    local totalInches = feet * 12 + inches
    if totalInches <= 0 then return nil end
    return totalInches * 0.0254
  end

  local function followerVisualScale(species)
    if optionValue("pokedex_follower_sizes", true) ~= true then return 1 end
    local meters = pokedexHeightMeters(species)
    if not meters then return 1 end

    local scale = (meters / POKEDEX_REFERENCE_METERS) ^ POKEDEX_SCALE_EXPONENT
    scale = clamp(scale, MIN_FOLLOWER_SCALE, MAX_FOLLOWER_SCALE)
    local percent = tonumber(optionValue("follower_size_percent", 100)) or 100
    percent = clamp(percent, 75, 125)
    scale = clamp(scale * percent / 100,
      MIN_FOLLOWER_SCALE, MAX_FOLLOWER_SCALE)
    return math.floor(scale / SCALE_QUANTUM + 0.5) * SCALE_QUANTUM
  end

  local function assetPath(species)
    local key = tostring(species or FALLBACK_SPECIES):upper()
    local dex = dexForSpecies(key)
    local filename = dex and string.format("follower_%03d.png", dex)
                  or "follower_004.png"
    return mod.path .. "/assets/sprites/" .. filename
  end

  -- Image cache (keyed by dex number string)
  local followerImgCache = {}
  local function getFollowerImage(species)
    local key = tostring(species or FALLBACK_SPECIES):upper()
    local dex = dexForSpecies(key) or 4
    local dexStr = string.format("%03d", dex)
    if not followerImgCache[dexStr] then
      local path = assetPath(key)
      local ok, img = pcall(Assets.image, path)
      followerImgCache[dexStr] = ok and img or Assets.image(assetPath(FALLBACK_SPECIES))
    end
    return followerImgCache[dexStr]
  end

  -- Every sheet in assets/sprites is the same 16x96: six 16x16 frames, in
  -- SpriteRenderer's STAND/WALK order. So one quad set serves all 251, and --
  -- unlike the renderer's own self.frames -- it does not depend on the frame
  -- count the record carried when that renderer was built. A Gold mon record
  -- is a two-frame party icon until this mod repoints it, and a renderer made
  -- before that has no quad for frame 3 to hand back.
  local followerQuads = {}
  local function followerQuad(frameIdx)
    frameIdx = tonumber(frameIdx)
    if not frameIdx or frameIdx < 0 or frameIdx > 5 then return nil end
    frameIdx = math.floor(frameIdx)
    if followerQuads[frameIdx] == nil then
      local quad
      if love and love.graphics and love.graphics.newQuad then
        local ok, made = pcall(love.graphics.newQuad,
          0, frameIdx * 16, 16, 16, 16, 96)
        quad = ok and made or nil
      end
      -- Headless (the test drivers have no graphics module) still wants the
      -- rectangle, in the plain-table shape the redraw queue accepts.
      followerQuads[frameIdx] = quad or { 0, frameIdx * 16, 16, 16 }
    end
    return followerQuads[frameIdx]
  end

  -- ----------------------------------------------------------------------
  -- 2. Helper functions: health, mon fingerprint, selection
  -- ----------------------------------------------------------------------
  local function healthy(mon)
    return type(mon) == "table" and (tonumber(mon.hp) or 0) > 0
  end

  local function monKey(mon)
    if type(mon) ~= "table" then return nil end
    local dvs = type(mon.dvs) == "table" and mon.dvs or {}
    return table.concat({
      tostring(mon.otId or -1),
      tostring(dvs.attack or -1),
      tostring(dvs.defense or -1),
      tostring(dvs.speed or -1),
      tostring(dvs.special or -1),
      tostring(mon.catchRate or -1),
    }, ":")
  end

  -- Following can also be switched off entirely. Choosing FOLLOWER on the
  -- Pokemon that is already following stops it, which leaves the player with
  -- no follower at all until another party member is picked. The switch is
  -- stored next to the selection so it survives map changes, saves and hot
  -- reloads, and so a new party lead does not quietly bring a follower back.
  --
  -- The stored value is read lazily, exactly like the selection itself: mod
  -- save data is not necessarily loaded yet while the mod is initializing.
  -- The local mirror is what answers before anything has been written, and on
  -- builds whose mod API has no save store at all.
  local followingOff = false

  local function followingDisabled()
    if mod.save then
      local ok, stored = pcall(mod.save.get, mod.save, "follower_disabled")
      if ok and stored ~= nil then
        return stored == true or stored == 1 or stored == "true"
      end
    end
    return followingOff
  end

  local function setFollowingDisabled(disabled)
    disabled = disabled and true or false
    followingOff = disabled
    if mod.save then
      pcall(mod.save.set, mod.save, "follower_disabled", disabled)
    end
  end

  -- Returns the currently selected follower mon and its party slot
  local function getActiveFollowerMon(game, needHealthy)
    -- No follower selected at all: every caller -- spawn gate, renderer,
    -- party-menu label and live sync -- reads this as "nobody follows".
    if followingDisabled() then return nil end
    if not (game and game.save and game.save.party) then return nil end
    local party = game.save.party
    if #party == 0 then return nil end

    -- 1) Persistent selection (from mod.save)
    if mod.save then
      local selKey = mod.save:get("selected_mon")
      local selSlot = tonumber(mod.save:get("selected_slot"))
      if selKey then
        local atSlot = selSlot and party[selSlot]
        if atSlot and monKey(atSlot) == selKey and (not needHealthy or healthy(atSlot)) then
          return atSlot, selSlot
        end
        for i, mon in ipairs(party) do
          if monKey(mon) == selKey and (not needHealthy or healthy(mon)) then
            return mon, i
          end
        end
      end
    end

    -- 2) Legacy followerPartyIndex (from original mod)
    local idx = game.save.followerPartyIndex
    if idx and type(idx) == "number" and party[idx] and (not needHealthy or healthy(party[idx])) then
      return party[idx], idx
    end

    -- 3) First healthy mon, or first overall if needHealthy is false
    for i, mon in ipairs(party) do
      if not needHealthy or healthy(mon) then return mon, i end
    end
    if needHealthy then return nil end
    return party[1], 1
  end

  -- ----------------------------------------------------------------------
  -- 3. Purge any follower entities from the overworld
  -- ----------------------------------------------------------------------
  local function purgeFollowerEntities(ow)
    if not ow then return end
    local function isFollower(ent)
      return ent and (ent.pikachuFollower == true or ent.id == "pikachu" or
        (ent.sprite and ent.sprite.def and ent.sprite.def.id == SPRITE_ID))
    end
    local function purge(list)
      if type(list) ~= "table" then return end
      local j = 1
      for i = 1, #list do
        local ent = list[i]
        if not isFollower(ent) then
          list[j] = ent
          j = j + 1
        end
      end
      for i = j, #list do list[i] = nil end
    end
    purge(ow.entities)
    purge(ow.npcs)
    if isFollower(ow.follower) then ow.follower = nil end
  end

  -- ----------------------------------------------------------------------
  -- 4. Register / patch the SPRITE_PIKACHU sprite definition
  -- ----------------------------------------------------------------------
  -- The sheets are full-colour art, always: 251 PNGs carrying real RGB rather
  -- than four-shade pics for the zone pass to colorize.  So every def this mod
  -- writes is a trueColor one, and the draw path already agrees -- an unscaled
  -- follower is replayed after the zone pass (PaletteFX.markSpriteRedraw)
  -- whatever the def says.
  --
  -- This used to ask an option called `color_mode` whether the answer was
  -- "gbc", which would have sent the art through the shade remap instead.
  -- Nothing has ever defined that key: not this mod, which never listed it in
  -- options:define, and not the engine, which has no such row anywhere.  The
  -- mod option API answers nil for a key it has no schema for, so the
  -- comparison was false on every boot the mod has ever had, and the branch
  -- was dead the day it was written.  Spelled as the constant it always
  -- evaluated to, so nobody reads it as a setting that went missing.
  local TRUE_COLOR_ART = true

  local followerSpriteDef = {
    id = SPRITE_ID,
    image = assetPath(FALLBACK_SPECIES),
    frames = 6,
    walker = true,
    trueColor = TRUE_COLOR_ART,
    spriteType = isGen2 and "WALKING_SPRITE" or nil,
  }

  if mod.content.sprites:get(SPRITE_ID) then
    mod.content.sprites:patch(SPRITE_ID, followerSpriteDef)
  else
    mod.content.sprites:register(SPRITE_ID, followerSpriteDef)
  end

  -- ----------------------------------------------------------------------
  -- 4b. The map POKeMON: overworld objects that ARE a Pokemon
  -- ----------------------------------------------------------------------
  -- Gen 1 draws every Pokemon standing on a map from one of five shared
  -- sheets -- MonsterSprite, BirdSprite, FairySprite, SeelSprite and the one
  -- dedicated SnorlaxSprite (pokered/data/sprites/sprites.asm). A single
  -- "monster" is Mewtwo, Bill's fused form, a Meowth and a Machop at once,
  -- and one "fairy" is the Pokemon Fan Club's Pikachu as readily as it is a
  -- Clefairy. So a game whose follower comes from this mod's own 251 sheets
  -- still walked past Pokemon wearing the cart's generic art.
  --
  -- The objects are a closed set -- 53 across Red, Blue and Yellow -- and each
  -- is named after the species it is meant to be by the `const_export` in
  -- pokered/pokeyellow's data/maps/objects/*.asm. The port keeps that name on
  -- the object (`obj.name`, read back as `npc.def.name` in src/world/NPC.lua),
  -- so the NAME picks the sheet here. The sprite id cannot: losing the species
  -- is the very thing it does.
  --
  -- Three of the 53 are deliberately absent:
  --   COPYCATSHOUSE2F_MONSTER  the three in the Copycat's room are dolls, and
  --   COPYCATSHOUSE2F_BIRD     the joke is that they are ("This is a rare
  --   COPYCATSHOUSE2F_FAIRY    #MON! Huh? It's only a doll!"). Real art gives
  --                            the punchline away before she says it.
  -- The Power Plant's Voltorb and Electrode are absent too, and not by
  -- oversight: they wear SPRITE_POKE_BALL because they are pretending to be
  -- item balls, which is the whole trap.
  --
  -- One entry below is a choice rather than a reading. Bill only ever says he
  -- "got combined with a #MON" and the cart never names it, so BILL_POKEMON is
  -- the one row here that no game data can settle. It is Kabuto by decision --
  -- the shell Bill spends his anime appearance stuck inside -- and it is a
  -- one-word edit for anyone who would rather he were something else.
  local OVERWORLD_MON_SPECIES = {
    -- Not from the game: see the note above. Bill's fused form has no species.
    BILLSHOUSE_BILL_POKEMON = "KABUTO",
    CELADONCITY_POLIWRATH = "POLIWRATH",
    CELADONMANSION1F_CLEFAIRY = "CLEFAIRY",
    CELADONMANSION1F_MEOWTH = "MEOWTH",
    CELADONMANSION1F_NIDORANF = "NIDORAN_F",
    CELADONPOKECENTER_CHANSEY = "CHANSEY",
    CERULEANCAVEB1F_MEWTWO = "MEWTWO",
    CERULEANCITY_SLOWBRO = "SLOWBRO",
    CERULEANMELANIESHOUSE_BULBASAUR = "BULBASAUR",
    CERULEANMELANIESHOUSE_ODDISH = "ODDISH",
    CERULEANMELANIESHOUSE_SANDSHREW = "SANDSHREW",
    CERULEANPOKECENTER_CHANSEY = "CHANSEY",
    CINNABARPOKECENTER_CHANSEY = "CHANSEY",
    COPYCATSHOUSE1F_CHANSEY = "CHANSEY",
    COPYCATSHOUSE2F_DODUO = "DODUO",
    FUCHSIACITY_CHANSEY = "CHANSEY",
    FUCHSIACITY_KANGASKHAN = "KANGASKHAN",
    FUCHSIACITY_LAPRAS = "LAPRAS",
    FUCHSIACITY_SLOWPOKE = "SLOWPOKE",
    FUCHSIAPOKECENTER_CHANSEY = "CHANSEY",
    INDIGOPLATEAULOBBY_CHANSEY = "CHANSEY",
    LAVENDERCUBONEHOUSE_CUBONE = "CUBONE",
    LAVENDERPOKECENTER_CHANSEY = "CHANSEY",
    MRFUJISHOUSE_NIDORINO = "NIDORINO",
    MRFUJISHOUSE_PSYDUCK = "PSYDUCK",
    MTMOONPOKECENTER_CHANSEY = "CHANSEY",
    -- Just "NIDORAN" in the name; the talk script's PlayCry says which one
    -- (data/scripts/flavor/pewter_nidoran_house.lua).
    PEWTERNIDORANHOUSE_NIDORAN = "NIDORAN_M",
    PEWTERPOKECENTER_CHANSEY = "CHANSEY",
    PEWTERPOKECENTER_JIGGLYPUFF = "JIGGLYPUFF",
    POKEMONFANCLUB_CLEFAIRY = "CLEFAIRY",
    POKEMONFANCLUB_PIKACHU = "PIKACHU",
    POKEMONFANCLUB_SEEL = "SEEL",
    POWERPLANT_ZAPDOS = "ZAPDOS",
    ROCKTUNNELPOKECENTER_CHANSEY = "CHANSEY",
    ROUTE12_SNORLAX = "SNORLAX",
    ROUTE16_SNORLAX = "SNORLAX",
    ROUTE16FLYHOUSE_FEAROW = "FEAROW",
    SAFFRONCITY_PIDGEOT = "PIDGEOT",
    SAFFRONPIDGEYHOUSE_PIDGEY = "PIDGEY",
    SAFFRONPOKECENTER_CHANSEY = "CHANSEY",
    SEAFOAMISLANDSB4F_ARTICUNO = "ARTICUNO",
    SSANNE1FROOMS_WIGGLYTUFF = "WIGGLYTUFF",
    SSANNEB1FROOMS_MACHOKE = "MACHOKE",
    SUMMERBEACHHOUSE_PIKACHU = "PIKACHU",
    VERMILIONCITY_MACHOP = "MACHOP",
    VERMILIONPIDGEYHOUSE_PIDGEY = "PIDGEY",
    VERMILIONPOKECENTER_CHANSEY = "CHANSEY",
    VICTORYROAD2F_MOLTRES = "MOLTRES",
    VIRIDIANNICKNAMEHOUSE_SPEAROW = "SPEAROW",
    VIRIDIANPOKECENTER_CHANSEY = "CHANSEY",
  }

  -- An object name is only a name: a ROM hack, or a mod that adds a map, is
  -- free to reuse one on a person. The sheet the object is ALREADY wearing is
  -- the other half of the check -- these are the only sheets the cart draws a
  -- Pokemon from, and no human NPC uses one. Yellow's per-species sheets are
  -- listed too: they name the right species already, but they are still the
  -- cart's art rather than this mod's, and matching is the point.
  local OVERWORLD_MON_SHEETS = {
    SPRITE_MONSTER = true, SPRITE_BIRD = true, SPRITE_FAIRY = true,
    SPRITE_SEEL = true, SPRITE_SNORLAX = true, SPRITE_PIKACHU = true,
    SPRITE_SANDSHREW = true, SPRITE_ODDISH = true, SPRITE_BULBASAUR = true,
    SPRITE_JIGGLYPUFF = true, SPRITE_CLEFAIRY = true, SPRITE_CHANSEY = true,
  }

  local function overworldMonsEnabled()
    return optionValue("overworld_mon_sprites", true) == true
  end

  local function monSpriteId(species)
    local dex = dexForSpecies(species)
    if not dex then return nil end
    return string.format("SPRITE_GEN1FOLLOWER_MON_%03d", dex)
  end

  -- One record per species the maps use, not one per object: two Snorlax and
  -- eleven Chansey share a sheet, so they share a record.
  local overworldMonDefs = {}
  local function registerOverworldMonDefs()
    if isGen2 or not (mod.content and mod.content.sprites) then return end
    for _, species in pairs(OVERWORLD_MON_SPECIES) do
      local id = monSpriteId(species)
      if id and not overworldMonDefs[id] then
        local def = {
          id = id,
          image = assetPath(species),
          frames = 6,
          walker = true,
          trueColor = TRUE_COLOR_ART,
          -- Read by the voxel billboard hook further down, so a map POKeMON
          -- is Pokedex-scaled in 3D exactly as it is in 2D.
          pokepcFollowerSpecies = species,
        }
        local ok = pcall(function()
          if mod.content.sprites:get(id) then
            mod.content.sprites:patch(id, def)
          else
            mod.content.sprites:register(id, def)
          end
        end)
        if ok then overworldMonDefs[id] = species end
      end
    end
  end
  registerOverworldMonDefs()

  -- The species a map object should be drawn as, or nil to leave it alone.
  local function overworldMonSpecies(objDef)
    if not (overworldMonsEnabled() and type(objDef) == "table") then return nil end
    local species = OVERWORLD_MON_SPECIES[objDef.name]
    if not species then return nil end
    if not OVERWORLD_MON_SHEETS[objDef.sprite] then return nil end
    return species
  end

  -- Gold needs none of the above. Its overworld Pokemon are SPRITE_POKEMON_*
  -- records that already name a `species` and point at that mon's shared
  -- PARTY MENU icon (src/import/RomExtractorGen2.lua extractMonSprites), so
  -- the id maps one-to-one and the record itself can carry this mod's sheet.
  -- No object table would help there: the generic art is in the record.
  local gen2MonOriginals = {}

  -- Keep the live records in step with the options. Registration runs before
  -- mod.game exists, so the Pokedex-derived size -- the one thing that needs
  -- the loaded game -- is filled in here instead, on map entry and whenever
  -- an option moves.
  local function refreshOverworldMonDefs(game)
    local sprites = spritesFor(game)
    if type(sprites) ~= "table" then return end
    local enabled = overworldMonsEnabled()
    local trueColor = TRUE_COLOR_ART
    if isGen2 then
      for id, def in pairs(sprites) do
        if type(def) == "table" and def.spriteType == "POKEMON_SPRITE"
           and type(def.species) == "string" then
          local saved = gen2MonOriginals[id]
          if not saved then
            saved = { image = def.image, frames = def.frames,
                      walker = def.walker, trueColor = def.trueColor }
            gen2MonOriginals[id] = saved
          end
          if enabled and dexForSpecies(def.species) then
            def.image = assetPath(def.species)
            def.frames = 6
            def.walker = false
            def.trueColor = trueColor
            def.pokepcFollowerSpecies = def.species
            def.pokepcFollowerVisualScale = followerVisualScale(def.species)
          else
            def.image, def.frames = saved.image, saved.frames
            def.walker, def.trueColor = saved.walker, saved.trueColor
            def.pokepcFollowerSpecies = nil
            def.pokepcFollowerVisualScale = nil
          end
        end
      end
      return
    end
    if not enabled then return end
    for id, species in pairs(overworldMonDefs) do
      local def = sprites[id]
      if type(def) == "table" then
        def.trueColor = trueColor
        def.pokepcFollowerSpecies = species
        def.pokepcFollowerVisualScale = followerVisualScale(species)
      end
    end
  end

  -- Gen 1 builds one NPC per map object and hands SpriteRenderer the sheet the
  -- object names (src/world/NPC.lua). Swapping the RENDERER afterwards, rather
  -- than the object's `sprite` field or the shared record, leaves the map data
  -- and every other object on that sheet exactly as they were -- which is what
  -- keeps the Copycat's dolls and the Power Plant's item balls out of this.
  local overworldNPCModule, origNPCNew, wrappedNPCNew
  local function overworldMonRenderer(data, npc, objDef)
    local species = overworldMonSpecies(objDef)
    local id = species and monSpriteId(species)
    local def = id and data and data.sprites and data.sprites[id]
    if not def then return nil end
    local ok, sprite = pcall(SpriteRenderer.new, def, npc and npc.id)
    return ok and sprite or nil
  end

  -- NPCs are pooled and built once (OverworldState.pooledNPC), so turning the
  -- option off mid-game has to reach the ones already standing on the map
  -- rather than wait for the next map load.
  local function resyncOverworldMons(game, ow)
    if isGen2 or not (ow and ow.npcs) then return end
    local data = game and game.data
    for _, npc in ipairs(ow.npcs) do
      if type(npc) == "table" and npc.def then
        local sprite = overworldMonRenderer(data, npc, npc.def)
        if sprite then
          npc.pokepcVanillaSprite = npc.pokepcVanillaSprite or npc.sprite
          npc.sprite = sprite
        elseif npc.pokepcVanillaSprite then
          npc.sprite = npc.pokepcVanillaSprite
        end
      end
    end
  end

  -- Declared here, installed below the hot-reload teardown.
  local gen2NPCModule, origBounceFrame, wrappedBounceFrame
  -- ----------------------------------------------------------------------
  -- 5. Icon patching (for party menu and UI)
  -- ----------------------------------------------------------------------
  -- Patch mod.content.icons for each species
  if mod.content and mod.content.icons then
    local icons = mod.content.icons
    local function replaceOrRegister(id, value)
      if icons:get(id) ~= nil then
        icons:override(id, value)
      else
        icons:register(id, value)
      end
    end
    for species, dex in pairs(speciesToDex) do
      local dexStr = string.format("%03d", dex)
      local path = mod.path .. "/assets/sprites/follower_" .. dexStr .. ".png"
      pcall(function()
        if isGen2 then
          local iconId = "ICON_POKEPC_" .. dexStr
          replaceOrRegister(iconId, {
            id = iconId, image = path, width = 16, height = 16, frames = 1,
          })
          replaceOrRegister(species, iconId)
        else
          local iconDef = { image = path, frames = 1 }
          replaceOrRegister(species, iconDef)
          replaceOrRegister(dex, iconDef)
          replaceOrRegister(dexStr, iconDef)
        end
      end)
    end
    -- Also patch generic icon IDs used by the engine
    -- These are Gen 1 assignment keys. On Gold the ICON_* ids are shared
    -- sheets, so overriding them would also change unrelated species.
    if not isGen2 then
      local fallbacks = {
        "ICON_MON", "ICON_BIRD", "ICON_QUADRUPED", "ICON_PIKACHU",
        "ICON_FAIRY", "ICON_WATER", "ICON_BUG", "ICON_SNAKE",
        "ICON_BALL", "ICON_HELIX", "ICON_GRASS"
      }
      for _, id in ipairs(fallbacks) do
        pcall(function()
          replaceOrRegister(id, {
            image = mod.path .. "/assets/sprites/follower_CHARMANDER.png",
            frames = 1,
          })
        end)
      end
    end
  end

  -- Also patch the generated.icons table (used by some UI elements)
  local ok, baseIcons = pcall(require, "generated.icons")
  if baseIcons and baseIcons.byDex and baseIcons.icons then
    for species, dex in pairs(speciesToDex) do
      local dexStr = string.format("%03d", dex)
      local iconKey = "FOLLOWER_" .. species
      local path = mod.path .. "/assets/sprites/follower_" .. dexStr .. ".png"
      baseIcons.byDex[dex] = iconKey
      baseIcons.icons[iconKey] = path
    end
  end

  -- ----------------------------------------------------------------------
  -- 6. Core follower sprite configuration and live sync
  -- ----------------------------------------------------------------------
  local function configureSpriteDef(game, mon)
    local sprites = spritesFor(game)
    local def = sprites and sprites[SPRITE_ID]
    if not def or not mon then return nil end
    local species = mon.species or FALLBACK_SPECIES
    def.image = assetPath(species)
    def.frames = 6
    def.walker = true
    def.trueColor = TRUE_COLOR_ART
    def.pokepcFollowerSpecies = species
    def.pokepcFollowerVisualScale = followerVisualScale(species)
    return def, species
  end

  local function syncLiveFollowerDef(game, ow)
    if not (game and ow) then return nil end
    local mon = getActiveFollowerMon(game, true)
    if not mon then
      purgeFollowerEntities(ow)
      return nil
    end

    local def, species = configureSpriteDef(game, mon)
    if not def then return nil end

    local npc = PikachuFollower.current(ow)
    if not npc then return nil end

    local newImage = getFollowerImage(species)
    local newScale = followerVisualScale(species)
    if npc._pokepcFollowerSpecies ~= species or not npc.sprite or npc.sprite.image ~= newImage then
      npc.sprite = SpriteRenderer.new(def, npc.id)
      npc._pokepcFollowerSpecies = species
    else
      -- Update the definition in case trueColor or path changed
      npc.sprite.def.image = assetPath(species)
      npc.sprite.def.frames = 6
      npc.sprite.def.walker = true
      npc.sprite.def.trueColor = TRUE_COLOR_ART
      npc.sprite.def.pokepcFollowerSpecies = species
      npc.sprite.def.pokepcFollowerVisualScale = newScale
    end
    npc._pokepcFollowerVisualScale = newScale
    return npc
  end

  -- ----------------------------------------------------------------------
  -- 7. Upvalue patching (shouldSpawn, starterInParty)
  -- ----------------------------------------------------------------------
  local function replaceUpvalue(fn, wanted, replacement)
    if type(fn) ~= "function" or not (debug and debug.getupvalue and debug.setupvalue) then
      return false
    end
    local i = 1
    while true do
      local name, old = debug.getupvalue(fn, i)
      if not name then return false end
      if name == wanted then
        debug.setupvalue(fn, i, replacement)
        return true, old
      end
      i = i + 1
    end
  end

  -- Hot‑reload cleanup
  local previous = PikachuFollower.__pokepcFollowersUniversal
  if previous and type(previous.restore) == "function" then
    pcall(previous.restore)
  end

  -- Installed here, below the teardown above: a hot reload has to unwrap the
  -- previous copy of this mod BEFORE this one wraps anything, or each reload
  -- leaves another layer behind and `restore` never reaches vanilla again.
  if not isGen2 then
    local okNPC, NPCModule = pcall(require, "src.world.NPC")
    if okNPC and type(NPCModule) == "table"
       and type(NPCModule.new) == "function" then
      origNPCNew = NPCModule.new
      wrappedNPCNew = function(data, mapId, objDef, ...)
        local npc = origNPCNew(data, mapId, objDef, ...)
        if type(npc) == "table" then
          local sprite = overworldMonRenderer(data, npc, objDef)
          if sprite then
            npc.pokepcVanillaSprite = npc.pokepcVanillaSprite or npc.sprite
            npc.sprite = sprite
          end
        end
        return npc
      end
      NPCModule.new = wrappedNPCNew
      overworldNPCModule = NPCModule
    end
  end

  -- OBJECT_ACTION_BOUNCE alternates a Gold mon object between frames 0 and 1
  -- of its sheet. On a party icon those two are the bob; on a 251 sheet they
  -- are "stand down" and "stand UP", which reads as the mon spinning on the
  -- spot, so the raised half of the bounce is moved to the down-facing STEP
  -- frame instead.
  if isGen2 then
    local okNPC, NPCModule = pcall(require, "src.world.gen2.Npc")
    if okNPC and type(NPCModule) == "table"
       and type(NPCModule.bounceFrame) == "function" then
      origBounceFrame = NPCModule.bounceFrame
      wrappedBounceFrame = function(self, ...)
        local frame = origBounceFrame(self, ...)
        local def = self and self.sprite and self.sprite.def
        if frame == 1 and type(def) == "table"
           and def.id ~= SPRITE_ID and def.pokepcFollowerSpecies then
          return (SpriteRenderer.WALK and SpriteRenderer.WALK.down) or 3
        end
        return frame
      end
      NPCModule.bounceFrame = wrappedBounceFrame
      gen2NPCModule = NPCModule
    end
  end

  local originalUpdate = PikachuFollower.update
  local originalOnMapEntered = PikachuFollower.onMapEntered
  local originalTalk = PikachuFollower.talk
  local originalStarterInParty = PikachuFollower.starterInParty
  local vanillaShouldSpawn
  local vanillaOnMapEnteredShouldSpawn
  local usedShouldSpawnSetter = false

  -- New shouldSpawn: works for all versions and checks our selection
  local function shouldSpawn(game, ow)
    local save = game and game.save
    if not (save and ow) then return false end
    if not save.party or #save.party == 0 then return false end
    local playerState = ow.playerState
    if save.onBike or (ow.player and ow.player.surfing)
       or playerState == "bike" or playerState == "surf"
       or playerState == "surf_pika" then return false end
    local sprites = spritesFor(game)
    if not (sprites and sprites[SPRITE_ID]) then
      return false
    end
    return getActiveFollowerMon(game, true) ~= nil
  end

  -- Gold exposes a named seam. Gen 1 still needs the legacy upvalue fallback.
  if type(PikachuFollower.setShouldSpawn) == "function" then
    vanillaShouldSpawn = PikachuFollower.setShouldSpawn(shouldSpawn)
    usedShouldSpawnSetter = true
  elseif originalUpdate then
    local _, oldSpawn = replaceUpvalue(originalUpdate, "shouldSpawn", shouldSpawn)
    vanillaShouldSpawn = oldSpawn
  end
  -- Also patch onMapEntered directly in case it has its own closure
  if not usedShouldSpawnSetter and originalOnMapEntered then
    pcall(function()
      local replaced, oldSpawn = replaceUpvalue(
        originalOnMapEntered, "shouldSpawn", shouldSpawn)
      if replaced then vanillaOnMapEnteredShouldSpawn = oldSpawn end
    end)
  end

  -- starterInParty – return any healthy mon, not just Pikachu
  local function wrappedStarterInParty(save, needHealthy)
    -- With following switched off there is no follower mon to report, so the
    -- native spawn path finds nothing to put behind the player either.
    if followingDisabled() then return nil end
    local game = liveGame()
    local active = getActiveFollowerMon(game, needHealthy)
    if active then return active end
    -- fallback: first healthy in party
    for _, mon in ipairs(save and save.party or {}) do
      if not needHealthy or healthy(mon) then return mon end
    end
    return nil
  end
  PikachuFollower.starterInParty = wrappedStarterInParty

  -- ----------------------------------------------------------------------
  -- 8. SpriteRenderer overrides (for dynamic texture and 3D voxel)
  -- ----------------------------------------------------------------------
  local origResolveImage = SpriteRenderer.resolveImage
  local wrappedResolveImage
  wrappedResolveImage = function(self, ...)
    if self and self.def and self.def.id == SPRITE_ID then
      -- Healthy-only, to match shouldSpawn. Resolving with needHealthy=false
      -- honours a stored selection that has since fainted, which drew a 0 HP
      -- mon walking behind the player. The selection itself is kept, so the
      -- mon resumes following once it is revived.
      local activeMon = getActiveFollowerMon(liveGame(), true)
      if activeMon then
        return getFollowerImage(activeMon.species)
      end
    end
    return origResolveImage(self, ...)
  end
  SpriteRenderer.resolveImage = wrappedResolveImage

  -- A dark cave paints every OBJ on screen with the darkest shade it owns.
  -- Gen 1 arms PaletteFX.DARK_BGP for the frame (home/fade.asm's FadePal2
  -- also writes rOBP0 = `dc 3,3,3,2`, so every sprite colour lands on shade
  -- 3) and Gen 2 loads the DARKNESS palette set, whose sprite rows are black
  -- -- the player, NPCs and item balls are silhouettes until FLASH. Full
  -- colour follower art skipped both: it is replayed unshaded on top of the
  -- colorized pass, or exempted from it by a trueColor rect, so the follower
  -- walked around Rock Tunnel in daylight colours next to a blacked-out
  -- player. Paint it with the shade the engine leaves the player instead.
  local function darkFrame()
    if isGen2 then
      -- No wMapPalOffset here: a PALETTE_DARK map FLASH has not lit yet
      -- simply reads as the DARK time of day (Palettes.daytimeFor).
      local world = worldFor(liveGame())
      return (world and world.daytime == "DARK") or false
    end
    -- The shade map is armed per frame -- OverworldState:drawWorld sets it
    -- while it draws a dark map and leaves it nil for a battle drawn over
    -- one, which is lit -- so it tracks the frame, not the map.
    if type(PaletteFX.shadeMap) == "function" then
      return PaletteFX.shadeMap() ~= nil
    end
    return type(PaletteFX.darkWorld) == "function" and PaletteFX.darkWorld()
      or false
  end

  -- Shade 3 of the palette this frame paints objects with. Gen 1 draws into
  -- a DMG-shade canvas that the zone shader colorizes, so shade 3 is plain
  -- black there and comes back out of the shader as the very colour the
  -- player's silhouette wears. Gen 2 bakes real colour into the sheet
  -- instead and hands the renderer the OBJ palette it baked.
  local function darkObjectShade(sprite)
    local colors = sprite and sprite.objColors
    local c = type(colors) == "table" and colors[4] or nil
    if type(c) == "table" then
      return (tonumber(c[1]) or 0) / 255, (tonumber(c[2]) or 0) / 255,
        (tonumber(c[3]) or 0) / 255
    end
    return 0, 0, 0
  end

  -- Which species' follower art this renderer paints, and whether it is the
  -- follower's own sprite. The follower resolves live from the party; a map
  -- POKeMON's record names one fixed species and never changes.
  local function followerArtSpecies(self)
    local def = self and self.def
    if type(def) ~= "table" then return nil, false end
    if def.id == SPRITE_ID then
      -- Healthy-only: a fainted follower must not be drawn. With no healthy
      -- party mon at all there is nothing to draw and shouldSpawn is already
      -- false, so a nil species here simply leaves the tile empty.
      local activeMon = getActiveFollowerMon(liveGame(), true)
      return activeMon and activeMon.species or nil, true
    end
    -- Field first, option second: this runs for every sprite on screen every
    -- frame, and all but a handful of them fail on the field alone.
    local species = def.pokepcFollowerSpecies
    if not species or not overworldMonsEnabled() then return nil, false end
    return species, false
  end

  local origSpriteDraw = SpriteRenderer.draw
  local wrappedSpriteDraw
  wrappedSpriteDraw = function(self, px, py, camX, camY, facing, walkPhase,
      stepFlip, topHalf, forceFlip, frameOverride)
    local artSpecies, isFollowerSprite = followerArtSpecies(self)
    if isFollowerSprite and not artSpecies then return end
    if artSpecies then
      local followerImg = getFollowerImage(artSpecies)

      local x = math.floor(px - camX)
      local y = math.floor(py - camY) - 4

      -- SpriteRenderer's own pose rules, followed exactly. The mirror in
      -- particular: the engine flips an up- or down-facing sprite only on the
      -- STEPPING half of a stride, and `stepFlip` is not a stride -- an NPC
      -- toggles it when a step ENDS and then stands there holding it. Mirror
      -- on the flag alone and a standing POKeMON sits mirrored until its next
      -- step turns it back, which reads as the thing trying to walk on the
      -- spot. Right-facing is the flip of left-facing at any phase.
      local STAND = SpriteRenderer.STAND or {}
      local WALK = SpriteRenderer.WALK or {}
      local stepping = walkPhase == 1
      local dirMap = (self.def.walker and stepping) and WALK or STAND
      local frameIdx = dirMap[facing] or 0
      local flip = facing == "right"
        or (stepping and stepFlip and (facing == "up" or facing == "down"))
      -- The engine's own frame/mirror overrides, in the order :draw applies
      -- them: a caller-picked frame poses itself (Gold's bounce), and a
      -- forced flip is the mirrored copy of whatever frame was chosen.
      if frameOverride and followerQuad(frameOverride) then
        frameIdx, flip = frameOverride, false
      end
      if forceFlip then flip = true end
      local quad = followerQuad(frameIdx) or followerQuad(0)

      local drawX = flip and (x + 16) or x
      local flipSx = flip and -1 or 1

      local scale = followerVisualScale(artSpecies)
      local unscaled = math.abs(scale - 1) < 0.0001
      local canDraw = love and love.graphics and love.graphics.draw
        and love.graphics.setColor and love.graphics.getColor and true or false
      local dark = canDraw and darkFrame()

      if not dark and (unscaled or not canDraw) then
        PaletteFX.markSpriteRedraw(followerImg, quad, drawX, y, flipSx, nil, false)
        return
      end

      -- Pivot around the feet so changing size never makes the follower float
      -- or sink into the map. The logical entity remains one 16x16 cell.
      local anchorX, anchorY = x + 8, y + 16
      local w, h = 16 * scale, 16 * scale
      local sx = flip and -scale or scale

      if dark then
        -- Straight onto the world canvas, with neither a trueColor rect nor
        -- a post-zone replay: both exist to keep the art out of the colorize
        -- pass, and in the dark that pass is exactly what has to reach it.
        -- The alpha in hand carries any fade the frame is already under.
        local r, g, b, a = love.graphics.getColor()
        local dr, dg, db = darkObjectShade(self)
        love.graphics.setColor(dr, dg, db, a)
        if unscaled then
          love.graphics.draw(followerImg, quad, drawX, y, 0, flipSx, 1)
        else
          love.graphics.draw(followerImg, quad, anchorX, anchorY,
            0, sx, scale, 8, 16)
        end
        love.graphics.setColor(r, g, b, a)
        return
      end

      if self.def.trueColor and PaletteFX.markTrueColor then
        PaletteFX.markTrueColor(math.floor(anchorX - w / 2),
          math.floor(anchorY - h), math.ceil(w), math.ceil(h))
      end
      love.graphics.draw(followerImg, quad, anchorX, anchorY,
        0, sx, scale, 8, 16)
      return
    end
    return origSpriteDraw(self, px, py, camX, camY, facing, walkPhase, stepFlip,
      topHalf, forceFlip, frameOverride)
  end
  SpriteRenderer.draw = wrappedSpriteDraw

  -- Dramatic Shape and its maintained forks bypass SpriteRenderer.draw in
  -- voxel mode and build a billboard directly from the sprite definition.
  -- Compose a narrowly tagged mesh hook with any existing mount-size hook so
  -- Gen1Follower, Dramatic Sky Ride and the voxel provider can coexist.
  local function dramaticModule(name)
    if not mod.find then return nil end
    local providerIds = {
      "BATTLE_ART_VOXEL_FORK", "DRAMALESS_SHAPE", "DRAMATIC_SHAPE"
    }
    for _, id in ipairs(providerIds) do
      local okHandle, handle = pcall(mod.find, mod, id)
      local lib = okHandle and handle and handle.exports and handle.exports.lib
      if type(lib) == "table" and type(lib.require) == "function" then
        local okModule, value = pcall(lib.require, name)
        if okModule then return value end
      end
    end
    return nil
  end

  local function installFollowerVoxelSizeHook()
    local billboards = dramaticModule("SpriteBillboards")
    local voxel3D = dramaticModule("Voxel3D")
    if not (billboards and voxel3D and voxel3D.newMesh
            and voxel3D.pushQuad) then return false end

    local previousHook = billboards.pokepcFollowerSizeHook
    if previousHook then
      if previousHook.clear then pcall(previousHook.clear) end
      return true
    end

    local meshes = {}
    local function clearMeshes()
      for _, mesh in pairs(meshes) do
        if mesh and mesh.release then pcall(mesh.release, mesh) end
      end
      meshes = {}
    end

    local function buildCard(def, frame, scale)
      local okImage, image = pcall(Assets.image, def.image)
      if not (okImage and image) then return nil end
      local iw, ih = image:getDimensions()
      local fy = (tonumber(frame) or 0) * 16
      if fy + 16 > ih then fy = 0 end
      local u0, u1 = 0.02 / iw, (16 - 0.02) / iw
      local v0, v1 = (fy + 0.05) / ih, (fy + 15.95) / ih
      local halfWidth = 8 * scale
      local x0, x1 = 8 - halfWidth, 8 + halfWidth
      local y1 = 16 * scale
      local vertices = {
        { x0, 0,  0, u0, v1, 1 }, { x1, 0,  0, u1, v1, 1 },
        { x1, y1, 0, u1, v0, 1 }, { x0, y1, 0, u0, v0, 1 },
      }
      local indices = {}
      voxel3D.pushQuad(indices, 0)
      local okMesh, mesh = pcall(voxel3D.newMesh, vertices, indices)
      return okMesh and mesh or nil
    end

    local rawMesh = billboards.mesh
    local rawShadowQuad = billboards.shadowQuad
    local function scaledMesh(def, frame, fallback)
      local species = def and def.pokepcFollowerSpecies
      local scale = def and tonumber(def.pokepcFollowerVisualScale)
      if not species or not scale or math.abs(scale - 1) < 0.0001 then
        return fallback(def, frame)
      end
      local key = table.concat({ tostring(def.image), tostring(frame),
        tostring(species), string.format("%.4f", scale) }, "#")
      if meshes[key] == nil then
        meshes[key] = buildCard(def, frame, scale) or false
      end
      return meshes[key] or fallback(def, frame)
    end

    billboards.mesh = function(def, frame)
      return scaledMesh(def, frame, rawMesh)
    end
    billboards.shadowQuad = function(def, frame)
      return scaledMesh(def, frame, rawShadowQuad)
    end
    billboards.pokepcFollowerSizeHook = { clear = clearMeshes }
    if Assets.register then Assets.register(clearMeshes) end
    return true
  end

  -- ----------------------------------------------------------------------
  -- 9. PikachuFollower function wrappers
  -- ----------------------------------------------------------------------
  local function wrappedOnMapEntered(game, ow, opts)
    -- Before the map's own objects are built: the sheet a map POKeMON gets is
    -- read at NPC construction, and this is what puts it in the record.
    pcall(refreshOverworldMonDefs, game)
    local mon = getActiveFollowerMon(game, true)
    if mon then configureSpriteDef(game, mon) end
    local result = originalOnMapEntered and originalOnMapEntered(game, ow, opts)
    if ow and not shouldSpawn(game, ow) then
      purgeFollowerEntities(ow)
    else
      syncLiveFollowerDef(game, ow)
    end
    return result
  end

  local function wrappedUpdate(game, ow, ...)
    local mon = getActiveFollowerMon(game, true)
    if mon then configureSpriteDef(game, mon) end
    local result = originalUpdate and originalUpdate(game, ow, ...)
    pcall(syncLiveFollowerDef, game, ow)
    return result
  end

  -- Talk wrapper for Red/Blue (and fallback for Yellow if needed)
  local function wrappedTalk(a, b, c, d)
    -- Normalise arguments
    local game = type(a) == "table" and a.save and a or liveGame()
    local ow = type(b) == "table" and b.entities and b or worldFor(game)
    local done = type(c) == "function" and c or d

    local npc = PikachuFollower.current(ow)
    local mon = getActiveFollowerMon(game, true)

    if not mon then
      if originalTalk then return originalTalk(a, b, c, d) end
      if done then done() end
      return
    end

    -- For Yellow's Pikachu, keep vanilla behaviour
    if isYellow and mon.species == "PIKACHU" and originalTalk then
      return originalTalk(a, b, c, d)
    end

    -- Finish any movement and face player
    if npc then
      if npc.moving then
        npc.cellX = npc.targetX or npc.cellX
        npc.cellY = npc.targetY or npc.cellY
        npc.targetX, npc.targetY = nil, nil
        npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
        npc.moving, npc.marching = false, false
        npc.progress, npc.hopStep = 0, nil
      end
      npc.idle, npc.goalX, npc.goalY = nil, nil, nil
      if npc.facePlayer and ow and ow.player then
        pcall(npc.facePlayer, npc, ow.player)
      end
      if ow and ow.player and npc.facing then
        ow.player.facing = OPPOSITE[npc.facing] or ow.player.facing
      end
    end

    -- Play cry and show message
    pcall(Sound.playCry, game.data, mon.species)
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    local name = mon.nickname or (def and def.name) or mon.species
    local text = Strings("%s is following\nyou!", name)
    game.stack:push(TextBox.new(game, text, done))
  end

  -- Gen 1 dispatches its stock follower before OverworldController.talkTo.
  -- Gold resolves every facing NPC through the adapter's talkTo seam instead,
  -- so bridge that seam to the same follower dialogue.
  local originalWorldTalkTo = OverworldController.talkTo
  local wrappedWorldTalkTo = function(ow, npc, ...)
    if npc and npc.pikachuFollower then
      wrappedTalk(liveGame(), ow, npc)
      return true
    end
    return originalWorldTalkTo(ow, npc, ...)
  end

  -- Apply wrappers
  if originalOnMapEntered then PikachuFollower.onMapEntered = wrappedOnMapEntered end
  if originalUpdate then PikachuFollower.update = wrappedUpdate end
  if originalTalk then PikachuFollower.talk = wrappedTalk end
  OverworldController.talkTo = wrappedWorldTalkTo

  -- ----------------------------------------------------------------------
  -- 10. PartyMenu enhancements (true‑color and sync)
  -- ----------------------------------------------------------------------
  -- Keep one stable wrapper for the lifetime of the process.  Its callbacks
  -- are refreshed on every mod reload, so a later wrapper (for example Unique
  -- Menu Icons) can remain outside it without causing this mod to stack another
  -- copy underneath on the next reload.
  local partyMenuState = PartyMenu.__pokepcFollowersPartyMenu
  if not partyMenuState then
    partyMenuState = {
      originalDraw = PartyMenu.draw,
      originalUpdate = PartyMenu.update,
    }

    partyMenuState.wrapperDraw = function(self, ...)
      local result = partyMenuState.originalDraw and partyMenuState.originalDraw(self, ...)
      if partyMenuState.afterDraw then pcall(partyMenuState.afterDraw, self) end
      return result
    end
    partyMenuState.wrapperUpdate = function(self, dt)
      local result = partyMenuState.originalUpdate and partyMenuState.originalUpdate(self, dt)
      if partyMenuState.afterUpdate then pcall(partyMenuState.afterUpdate, self) end
      return result
    end

    PartyMenu.draw = partyMenuState.wrapperDraw
    PartyMenu.update = partyMenuState.wrapperUpdate
    PartyMenu.__pokepcFollowersPartyMenu = partyMenuState
  end

  partyMenuState.afterDraw = function(self)
    if not externalPartyIconOwner() then
      local party = (self.game and self.game.save and self.game.save.party) or {}
      for i = 1, #party do
        PaletteFX.markTrueColor(0, (i - 1) * 16, 32, 16)
      end
    end
  end

  partyMenuState.afterUpdate = function(self)
    local game = self.game
    local ow = worldFor(game)
    if not game or not ow then return end
    local follower = PikachuFollower.current(ow)
    if not follower then return end
    local active = getActiveFollowerMon(game, true)
    if not active then
      -- Following was just switched off (or the whole party fainted) while the
      -- menu is open: drop the entity now so backing out shows an empty tile.
      purgeFollowerEntities(ow)
      return
    end
    if follower._pokepcFollowerSpecies ~= active.species then
      syncLiveFollowerDef(game, ow)
    end
  end

  -- ----------------------------------------------------------------------
  -- 11. Party submenu hook (FOLLOW? / FOLLOWER toggle)
  -- ----------------------------------------------------------------------
  local function selectFollower(mon, game, quiet)
    if not (mon and game and healthy(mon)) then return false end
    local party = game.save and game.save.party or {}
    local slot
    for i, candidate in ipairs(party) do
      if candidate == mon then slot = i break end
    end
    if not slot then return false end

    setFollowingDisabled(false)
    if mod.save then
      mod.save:set("selected_mon", monKey(mon))
      mod.save:set("selected_slot", slot)
    end
    game.save.followerPartyIndex = slot
    game.save.followerSpecies = mon.species

    syncLiveFollowerDef(game, worldFor(game))

    if not quiet then
      pcall(Sound.play, game.data, "Swap")
      local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
      local name = mon.nickname or (def and def.name) or mon.species
      local text = Strings("%s is now\nyour follower!", name)
      game.stack:push(TextBox.new(game, text))
    end
    return true
  end

  -- Choosing FOLLOWER on the Pokemon that is already following turns the
  -- follower off instead of re-selecting the mon that is already selected.
  -- The stored selection is cleared with it, so nothing stale can resurface:
  -- the switch is the only thing that decides there is no follower, and any
  -- FOLLOW? afterwards both clears the switch and stores a fresh selection.
  local function stopFollowing(mon, game, quiet)
    if not game then return false end
    local was = mon or getActiveFollowerMon(game, true)

    setFollowingDisabled(true)
    if mod.save then
      pcall(mod.save.set, mod.save, "selected_mon", nil)
      pcall(mod.save.set, mod.save, "selected_slot", nil)
    end
    if game.save then
      game.save.followerPartyIndex = nil
      game.save.followerSpecies = nil
    end

    -- Remove the entity now rather than waiting for the next follower update:
    -- on Yellow the native spawn gate still passes with a healthy Pikachu in
    -- the party, so the follower has to be taken out of the world explicitly.
    purgeFollowerEntities(worldFor(game))

    if not quiet then
      pcall(Sound.play, game.data, "Swap")
      local text
      if was then
        local def = game.data and game.data.pokemon
          and game.data.pokemon[was.species]
        local name = was.nickname or (def and def.name) or was.species
        text = Strings("%s stopped\nfollowing you!", name)
      else
        text = Strings("No POKeMON is\nfollowing you!")
      end
      game.stack:push(TextBox.new(game, text))
    end
    return true
  end

  -- One action for both menu paths, resolved when the player presses A
  -- rather than when the list was built: FOLLOWER on the mon that is
  -- currently following stops it, anything else starts following that mon.
  local function followerAction(mon, game)
    local current = getActiveFollowerMon(game, true)
    if current and current == mon then
      return stopFollowing(mon, game, false)
    end
    return selectFollower(mon, game, false)
  end

  -- Use mod.hooks:wrap to add the menu item (preferred method)
  if mod.hooks then
    mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
      local out = next(game, items, mon, ctx)
      if type(out) ~= "table" or (ctx and ctx.battle) or not healthy(mon) then
        return out
      end
      local active = getActiveFollowerMon(game, true)
      -- The submenu box clips at 8 characters, so the old 9-character
      -- active-follower label lost its final glyph. FOLLOWER (8) now marks
      -- the active follower and FOLLOW? (7) prompts on every other member.
      local label = Strings(active == mon and "FOLLOWER" or "FOLLOW?")
      out[#out + 1] = {
        label = label,
        onSelect = function(selected, selectedGame)
          followerAction(selected, selectedGame or game)
        end,
      }
      return out
    end)
  end

  -- Fallback event listener (for older mod API)
  if mod.events then
    mod.events:on("ui.party.submenu", function(e)
      if not e.ctx or e.ctx.battle or not e.items or not e.mon or not e.game then return end
      if not healthy(e.mon) then return end
      local active = getActiveFollowerMon(e.game, true)
      local isCurrent = (active == e.mon)
      local label = Strings(isCurrent and "FOLLOWER" or "FOLLOW?")
      table.insert(e.items, {
        label = label,
        onSelect = function(selectedMon, game)
          followerAction(selectedMon, game or e.game)
        end
      })
    end)
  end

  -- ----------------------------------------------------------------------
  -- 12. Yellow's starter is Pikachu
  -- ----------------------------------------------------------------------
  -- Nothing to do. Yellow's own starter story is left exactly as the cart
  -- tells it: Oak's lines, the species you are handed, and its name are the
  -- game's, not this mod's. A follower mod has no business rewriting them --
  -- what it changes is which Pokemon walks behind you, and on Yellow that
  -- still starts as the Pikachu Oak gives you.

  -- ----------------------------------------------------------------------
  -- 13. Hot‑reload restore state
  -- ----------------------------------------------------------------------
  local state = {
    originalUpdate = originalUpdate,
    originalOnMapEntered = originalOnMapEntered,
    originalTalk = originalTalk,
    originalStarterInParty = originalStarterInParty,
    wrapperUpdate = wrappedUpdate,
    wrapperOnMapEntered = wrappedOnMapEntered,
    wrapperTalk = wrappedTalk,
    originalWorldTalkTo = originalWorldTalkTo,
    wrapperWorldTalkTo = wrappedWorldTalkTo,
    wrapperStarterInParty = wrappedStarterInParty,
    originalShouldSpawn = vanillaShouldSpawn,
    originalOnMapEnteredShouldSpawn = vanillaOnMapEnteredShouldSpawn,
    wrapperResolveImage = wrappedResolveImage,
    wrapperSpriteDraw = wrappedSpriteDraw,
    originalNPCNew = origNPCNew,
    wrapperNPCNew = wrappedNPCNew,
    originalBounceFrame = origBounceFrame,
    wrapperBounceFrame = wrappedBounceFrame,
    usedShouldSpawnSetter = usedShouldSpawnSetter,
  }

  state.restore = function()
    -- Restore the second closure first. If update and onMapEntered share the
    -- same shouldSpawn upvalue, restoring update last still leaves the shared
    -- cell at the true vanilla function.
    if usedShouldSpawnSetter and vanillaShouldSpawn then
      PikachuFollower.setShouldSpawn(vanillaShouldSpawn)
    elseif originalOnMapEntered and vanillaOnMapEnteredShouldSpawn then
      replaceUpvalue(originalOnMapEntered, "shouldSpawn", vanillaOnMapEnteredShouldSpawn)
    end
    if not usedShouldSpawnSetter and originalUpdate and vanillaShouldSpawn then
      replaceUpvalue(originalUpdate, "shouldSpawn", vanillaShouldSpawn)
    end
    if PikachuFollower.update == wrappedUpdate then
      PikachuFollower.update = originalUpdate
    end
    if PikachuFollower.onMapEntered == wrappedOnMapEntered then
      PikachuFollower.onMapEntered = originalOnMapEntered
    end
    if PikachuFollower.talk == wrappedTalk then
      PikachuFollower.talk = originalTalk
    end
    if PikachuFollower.starterInParty == wrappedStarterInParty then
      PikachuFollower.starterInParty = originalStarterInParty
    end
    if OverworldController.talkTo == wrappedWorldTalkTo then
      OverworldController.talkTo = originalWorldTalkTo
    end
    -- Only remove wrappers that are still the outermost function. Mods loaded
    -- after Gen1Follower may legitimately wrap these methods and must not be erased.
    if SpriteRenderer.resolveImage == wrappedResolveImage and origResolveImage then
      SpriteRenderer.resolveImage = origResolveImage
    end
    if SpriteRenderer.draw == wrappedSpriteDraw and origSpriteDraw then
      SpriteRenderer.draw = origSpriteDraw
    end
    if overworldNPCModule and overworldNPCModule.new == wrappedNPCNew
       and origNPCNew then
      overworldNPCModule.new = origNPCNew
    end
    if gen2NPCModule and gen2NPCModule.bounceFrame == wrappedBounceFrame
       and origBounceFrame then
      gen2NPCModule.bounceFrame = origBounceFrame
    end
    -- The NPCs already standing on this map were built with a renderer of
    -- this mod's, so hand each one the sheet the cart gave it back.
    local ow = worldFor(liveGame())
    if ow and type(ow.npcs) == "table" then
      for _, npc in ipairs(ow.npcs) do
        if type(npc) == "table" and npc.pokepcVanillaSprite then
          npc.sprite = npc.pokepcVanillaSprite
          npc.pokepcVanillaSprite = nil
        end
      end
    end
    -- Gold's mon records are the game's own, patched in place, so put the
    -- party-icon art back rather than leaving this mod's sheets behind on a
    -- reload that is meant to have removed it.
    local sprites = spritesFor(liveGame())
    if type(sprites) == "table" then
      for id, saved in pairs(gen2MonOriginals) do
        local def = sprites[id]
        if type(def) == "table" then
          def.image, def.frames = saved.image, saved.frames
          def.walker, def.trueColor = saved.walker, saved.trueColor
          def.pokepcFollowerSpecies = nil
          def.pokepcFollowerVisualScale = nil
        end
      end
    end
    if PikachuFollower.__pokepcFollowersUniversal == state then
      PikachuFollower.__pokepcFollowersUniversal = nil
    end
  end
  PikachuFollower.__pokepcFollowersUniversal = state

  -- Install immediately for hot reloads, then retry after every enabled mod
  -- has published its exports during a normal startup.
  installFollowerVoxelSizeHook()
  if mod.events then
    mod.events:once("mods.loaded", installFollowerVoxelSizeHook)
    mod.events:on("mod.options_changed", function(payload)
      if not (payload and payload.mod == mod.id) then return end
      local key = tostring(payload.key or "")
      if key ~= "pokedex_follower_sizes" and key ~= "follower_size_percent"
         and key ~= "overworld_mon_sprites" then
        return
      end
      local game = liveGame()
      pcall(refreshOverworldMonDefs, game)
      pcall(resyncOverworldMons, game, worldFor(game))
      local mon = getActiveFollowerMon(game, true)
      if mon then configureSpriteDef(game, mon) end
      pcall(syncLiveFollowerDef, game, worldFor(game))
      installFollowerVoxelSizeHook()
    end)
  end

  -- ----------------------------------------------------------------------
  -- 14. Mod exports
  -- ----------------------------------------------------------------------
  if mod.exports then
    mod.exports.supported = true
    mod.exports.activeMon = function(game) return getActiveFollowerMon(game, true) end
    mod.exports.assetPath = assetPath
    mod.exports.dexForSpecies = dexForSpecies
    mod.exports.pokedexHeightMeters = pokedexHeightMeters
    mod.exports.followerVisualScale = followerVisualScale
    mod.exports.shouldSpawn = shouldSpawn
    mod.exports.sync = syncLiveFollowerDef
    mod.exports.select = selectFollower
    mod.exports.stop = function(game) return stopFollowing(nil, game, true) end
    mod.exports.followingDisabled = followingDisabled
    mod.exports.restore = state.restore
  end

  if mod.log then
    mod.log:info("Gen1Follower loaded for %s", version)
  end
  print(string.format("[Gen1Follower] Mod initialized successfully for %s.", version:upper()))
end
