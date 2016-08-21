--[[
BigBrother
Concept and original mod: Cryect
Currently maintained by: oscarucb
Additional thanks:
    * All of the translators
    * Other wowace developers for assistance and bug fixes
    * Ahti and the other members of Cohors Praetoria (Vek'nilash US) for beta testing new versions of the mod
    * Thanks to vhaarr for helping Cryect out with reducing the length of code
    * Thanks to pastamancer for fixing the issues with Supreme Power Flasks and pointing in right direction for others
    * Window Resizing code based off the dragbar from violation
    * And also thanks to all those in #wowace for the various suggestions
]]
local addonName, vars = ...
local L = vars.L
if AceLibrary:HasInstance("FuBarPlugin-2.0") then
	BigBrother = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0","AceDB-2.0","AceEvent-2.0","FuBarPlugin-2.0")
else
	BigBrother = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0","AceDB-2.0","AceEvent-2.0")
end

local addon = BigBrother
local profile
addon.vars = vars
vars.svnrev["BigBrother.lua"] = tonumber(("$Revision: 405 $"):match("%d+"))

local bit, math, date, string, select, table, time, tonumber, unpack, wipe, pairs, ipairs =
      bit, math, date, string, select, table, time, tonumber, unpack, wipe, pairs, ipairs
local IsInInstance, UnitName, UnitBuff, UnitExists, UnitGUID, GetSpellLink, GetUnitName, GetPlayerInfoByGUID, GetRealZoneText, GetNumGroupMembers, IsInGuild, GetTime, UnitGroupRolesAssigned, GetPartyAssignment =
      IsInInstance, UnitName, UnitBuff, UnitExists, UnitGUID, GetSpellLink, GetUnitName, GetPlayerInfoByGUID, GetRealZoneText, GetNumGroupMembers, IsInGuild, GetTime, UnitGroupRolesAssigned, GetPartyAssignment
	local COMBATLOG_OBJECT_RAIDTARGET_MASK, COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_TYPE_NPC, COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_TYPE_GUARDIAN, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_REACTION_HOSTILE, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER =
      COMBATLOG_OBJECT_RAIDTARGET_MASK, COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_TYPE_NPC, COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_TYPE_GUARDIAN, COMBATLOG_OBJECT_REACTION_FRIENDLY, COMBATLOG_OBJECT_REACTION_HOSTILE, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER

local AceEvent = AceLibrary("AceEvent-2.0")
local RL = AceLibrary("Roster-2.1")

local function convertIDstoNames(spellIDs)
  local result = {}
  local uiversion = select(4,GetBuildInfo())
  local ignoreMissing = {
    [60210] = uiversion >= 40000, -- Freezing Arrow Effect, removed 4.x (replaced with Freezing Trap)
    [59671] = uiversion >= 40000, -- Challenging Howl (Warlock), removed 4.x
  }
  for _, v in ipairs(spellIDs) do
	local spellName = GetSpellInfo(v)
	if (not spellName) then
	  if not ignoreMissing[v] then BigBrother:Print("MISSING SPELLID: "..v) end
	else
	  result[spellName] = true
	end
  end
  return result
end

-- Create a set out of the CC spell ID
local ccSpellNames = convertIDstoNames(vars.SpellData.ccspells)
local ccSafeAuraNames = convertIDstoNames(vars.SpellData.ccsafeauras)
local rezSpellNames = convertIDstoNames(vars.SpellData.rezSpells)
local brezSpellNames = convertIDstoNames(vars.SpellData.brezSpells)
for k,_ in pairs(brezSpellNames) do rezSpellNames[k] = nil end
local tauntSpellNames = convertIDstoNames(vars.SpellData.tauntSpells)
local aoetauntSpellNames = convertIDstoNames(vars.SpellData.aoetauntSpells)
for k,_ in pairs(aoetauntSpellNames) do tauntSpellNames[k] = nil end
local deathgrip = GetSpellInfo(49576)

local color = "|cffff8040%s|r"
local outdoor_bg = {}

-- FuBar stuff
addon.name = "BigBrother"
addon.hasIcon = true
addon.hasNoColor = true
addon.clickableTooltip = false
addon.independentProfile = true
addon.cannotDetachTooltip = true
addon.hideWithoutStandby = true

function addon:OnClick(button)
	self:ToggleBuffWindow()
end

function addon:OnTextUpdate()
	self:SetText("BigBrother")
  local f = addon.minimapFrame;
  if f then -- ticket #14
    f.SetFrameStrata(f,"MEDIUM") -- ensure the minimap icon isnt covered by others
  end
end

-- AceDB stuff
addon:RegisterDB("BigBrotherDB")
addon:RegisterDefaults("profile", {
  PolyBreak = true,
  Misdirect = true,
  CombatRez = true,
  NonCombatRez = true,
  Groups = {true, true, true, true, true, true, true, true},
  PolyOut = {true, false, false, false, false, false, false, false},
  GroupOnly = true,
  ReportTanks = true,
  ReadyCheckMine = true,
  ReadyCheckOther = true,
  ReadyCheckToSelf = true,
  ReadyCheckToRaid = false,
  ReadyCheckBuffWinMine = false,
  ReadyCheckBuffWinOther = false,
  ReadyCheckIgnoreLFG = true,
  BuffWindowCombatClose = true,
  CheckFlasks = true,
  CheckElixirs = true,
  CheckFood = true,
  Taunt = false,
  Interrupt = false,
  Dispel = false,
})

-- ACE options menu
local options = {
  type = 'group',
  handler = BigBrother,
  args = {
    flaskcheck = {
      name = L["Flask Check"],
      desc = L["Checks for flasks, elixirs and food buffs."],
      type = 'group',
      args = {
        self = {
          name = L["Self"],
          desc = L["Reports result only to yourself."],
          type = 'execute',
          func = "FlaskCheck",
          passValue = "SELF",
        },
        party = {
          name = L["Party"],
          desc = L["Reports result to your party."],
          type = 'execute',
          func = "FlaskCheck",
          disabled = function() return GetNumGroupMembers()==0 end,
          passValue = "PARTY",
        },
        raid = {
          name = L["Raid"],
          desc = L["Reports result to your raid."],
          type = 'execute',
          func = "FlaskCheck",
          disabled = function() return not IsInRaid() end,
          passValue = "RAID",
        },
        instance = {
          name = L["Instance"],
          desc = L["Reports result to LFG/LFR instance group."],
          type = 'execute',
          func = "FlaskCheck",
          disabled = function() return not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end,
          passValue = "INSTANCE_CHAT",
        },
        guild = {
          name = L["Guild"],
          desc = L["Reports result to guild chat."],
          type = 'execute',
          func = "FlaskCheck",
          passValue = "GUILD",
        },
        officer = {
          name = L["Officer"],
          desc = L["Reports result to officer chat."],
          type = 'execute',
          func = "FlaskCheck",
          passValue = "OFFICER",
        },
        whisper = {
          name = L["Whisper"],
          desc = L["Reports result to the currently targeted individual."],
          type = 'execute',
          func = "FlaskCheck",
          passValue = "WHISPER",
        }
      }
    },
    quickcheck = {
      name = L["Quick Check"],
      desc = L["A quick report that shows who does not have flasks, elixirs or food."],
      type = 'group',
      args = {
        self = {
          name = L["Self"],
          desc = L["Reports result only to yourself."],
          type = 'execute',
          func = "QuickCheck",
          passValue = "SELF",
        },
        party = {
          name = L["Party"],
          desc = L["Reports result to your party."],
          type = 'execute',
          func = "QuickCheck",
          disabled = function() return GetNumGroupMembers()==0 end,
          passValue = "PARTY",
        },
        raid = {
          name = L["Raid"],
          desc = L["Reports result to your raid."],
          type = 'execute',
          func = "QuickCheck",
          disabled = function() return not IsInRaid() end,
          passValue = "RAID",
        },
        instance = {
          name = L["Instance"],
          desc = L["Reports result to LFG/LFR instance group."],
          type = 'execute',
          func = "QuickCheck",
          disabled = function() return not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end,
          passValue = "INSTANCE_CHAT",
        },
        guild = {
          name = L["Guild"],
          desc = L["Reports result to guild chat."],
          type = 'execute',
          func = "QuickCheck",
          passValue = "GUILD",
        },
        officer = {
          name = L["Officer"],
          desc = L["Reports result to officer chat."],
          type = 'execute',
          func = "QuickCheck",
          passValue = "OFFICER",
        },
        whisper = {
          name = L["Whisper"],
          desc = L["Reports result to the currently targeted individual."],
          type = 'execute',
          func = "QuickCheck",
          passValue = "WHISPER",
        }
      }
    },
    settings = {
      name = L["Settings"],
      desc = L["Mod Settings"],
      type = 'group',
      args = {
     events = {
      name = L["Events"],
      desc = L["Events"],
      type = 'group',
      args = {
        grouponly = {
          name  = L["Group Members Only"],
          desc = L["Only reports events about players in my party/raid"],
          type = 'toggle',
          get = function() return addon.db.profile.GroupOnly end,
          set = function(v)
            addon.db.profile.GroupOnly=v
          end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
	reporttanks = {
	  name = L["Report Tanks"],
          desc = L["Report events caused by tanks"],
          type = 'toggle',
          get = function() return addon.db.profile.ReportTanks end,
          set = function(v)
            addon.db.profile.ReportTanks=v
          end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
	},
        polymorph = {
          name  = L["Polymorph"],
          desc = L["Reports if and which player breaks crowd control effects (like polymorph, shackle undead, etc.) on enemies."],
          type = 'toggle',
          get = function() return addon.db.profile.PolyBreak end,
          set = function(v)
            addon.db.profile.PolyBreak=v
          end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        misdirect = {
          name  = L["Misdirect"],
          desc = L["Reports who gains misdirection."],
          type = 'toggle',
          get = function() return addon.db.profile.Misdirect end,
          set = function(v) addon.db.profile.Misdirect = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        taunt = {
          name  = L["Taunt"],
          desc = L["Reports when players taunt mobs."],
          type = 'toggle',
          get = function() return addon.db.profile.Taunt end,
          set = function(v) addon.db.profile.Taunt = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        interrupt = {
          name  = L["Interrupt"],
          desc = L["Reports when players interrupt mob spell casts."],
          type = 'toggle',
          get = function() return addon.db.profile.Interrupt end,
          set = function(v) addon.db.profile.Interrupt = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        dispel = {
          name  = L["Dispel"],
          desc = L["Reports when players remove or steal mob buffs."],
          type = 'toggle',
          get = function() return addon.db.profile.Dispel end,
          set = function(v) addon.db.profile.Dispel = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        brez = {
          name  = L["Resurrection - Combat"],
          desc = L["Reports when Combat Resurrection is performed."],
          type = 'toggle',
          get = function() return addon.db.profile.CombatRez end,
          set = function(v) addon.db.profile.CombatRez = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        rez = {
          name  = L["Resurrection - Non-combat"],
          desc = L["Reports when Non-combat Resurrection is performed."],
          type = 'toggle',
          get = function() return addon.db.profile.NonCombatRez end,
          set = function(v) addon.db.profile.NonCombatRez = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
       }, }, -- end events
       eventsoutput = {
          name = L["Events Output"],
          desc = L["Set where the output for selected events is sent"],
          type = 'group',
          args = {
            self = {
              name = L["Self"],
              desc = L["Reports result only to yourself."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[1] end,
              set = function(v) addon.db.profile.PolyOut[1] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            party = {
              name = L["Party"],
              desc = L["Reports result to your party."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[2] end,
              set = function(v) addon.db.profile.PolyOut[2] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            raid = {
              name = L["Raid"],
              desc = L["Reports result to your raid."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[3] end,
              set = function(v) addon.db.profile.PolyOut[3] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            guild = {
              name = L["Guild"],
              desc = L["Reports result to guild chat."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[4] end,
              set = function(v) addon.db.profile.PolyOut[4] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            officer = {
              name = L["Officer"],
              desc = L["Reports result to officer chat."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[5] end,
              set = function(v) addon.db.profile.PolyOut[5] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            custom = {
              name = L["Custom"],
              desc = L["Reports result to your custom channel."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[6] end,
              set = function(v) addon.db.profile.PolyOut[6] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            battleground = {
              name = L["Battleground"],
              desc = L["Reports result to your battleground."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[7] end,
              set = function(v) addon.db.profile.PolyOut[7] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            instance = {
              name = L["Instance"],
              desc = L["Reports result to LFG/LFR instance group."],
              type = 'toggle',
              get = function() return addon.db.profile.PolyOut[8] end,
              set = function(v) addon.db.profile.PolyOut[8] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
          }
        },
        checks = {
          name = L["Checks"],
          desc = L["Set whether Flasks, Elixirs and Food are included in flaskcheck/quickcheck"],
          type = 'group',
          args = {
            flask = {
              name  = L["Flasks"],
              desc = L["Flasks"],
              type = 'toggle',
              get = function() return addon.db.profile.CheckFlasks end,
              set = function(v) addon.db.profile.CheckFlasks = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            elixir = {
              name  = L["Elixirs"],
              desc = L["Elixirs"],
              type = 'toggle',
              get = function() return addon.db.profile.CheckElixirs end,
              set = function(v) addon.db.profile.CheckElixirs = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            food = {
              name  = L["Food Buffs"],
              desc = L["Food Buffs"],
              type = 'toggle',
              get = function() return addon.db.profile.CheckFood end,
              set = function(v) addon.db.profile.CheckFood = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
          },
        },
        ready = {
          name = L["Ready check auto-check"],
          desc = L["Perform a quickcheck automatically on ready check"],
          type = 'group',
          args = {
            ignorelfg = {
              name  = L["Ignore Ready checks in LFG/LFR"],
              desc = L["Ignore Ready checks in LFG/LFR"],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckIgnoreLFG end,
              set = function(v) addon.db.profile.ReadyCheckIgnoreLFG = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            fromself = {
              name  = L["Ready checks from self"],
              desc = L["Ready checks from self"],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckMine end,
              set = function(v) addon.db.profile.ReadyCheckMine = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            fromother = {
              name  = L["Ready checks from others"],
              desc = L["Ready checks from others"],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckOther end,
              set = function(v) addon.db.profile.ReadyCheckOther = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            toraid = {
              name  = L["Reports result to your raid."],
              desc = L["Reports result to your raid."],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckToRaid end,
              set = function(v) addon.db.profile.ReadyCheckToRaid = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            toself = {
              name  = L["Reports result only to yourself."],
              desc = L["Reports result only to yourself."],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckToSelf end,
              set = function(v) addon.db.profile.ReadyCheckToSelf = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
          },
        },
        readywin = {
          name = L["Ready check Buff Window"],
          desc = L["Open the Buff Window automatically on ready check"],
          type = 'group',
          args = {
            fromself = {
              name  = L["Ready checks from self"],
              desc = L["Ready checks from self"],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckBuffWinMine end,
              set = function(v) addon.db.profile.ReadyCheckBuffWinMine = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            fromother = {
              name  = L["Ready checks from others"],
              desc = L["Ready checks from others"],
              type = 'toggle',
              get = function() return addon.db.profile.ReadyCheckBuffWinOther end,
              set = function(v) addon.db.profile.ReadyCheckBuffWinOther = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
          },
        },
        combatbuffwin = {
          name  = L["Close Buff Window on Combat"],
          desc = L["Close Buff Window when entering combat"],
          type = 'toggle',
          get = function() return addon.db.profile.BuffWindowCombatClose end,
          set = function(v) addon.db.profile.BuffWindowCombatClose = v end,
          map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
        },
        scalebuffwin = {
          name  = L["Scale Buff Window"],
          desc = L["Scale the size of the Buff Window"],
          type = 'range',
          get = function() return addon.db.profile.BuffWindowScale or 1 end,
          set = function(v)
	    addon.db.profile.BuffWindowScale = v
	    if not (BigBrother_BuffWindow and BigBrother_BuffWindow:IsShown()) then
	       BigBrother:ToggleBuffWindow()
	    end
	    BigBrother_BuffWindow:SetScale(v)
	  end,
	  min = 0.1,
	  max = 10,
	  bigStep = 0.1,
        },
        customchannel = {
          name  = L["Custom Channel"],
          desc = L["Name of custom channel to use for output"],
          type = 'text',
          usage = '',
          validate = function(v) return true end,
          get = function() return addon.db.profile.CustomChannel end,
          set = function(v) addon.db.profile.CustomChannel = v end,

        },
        groups = {
          name = L["Raid Groups"],
          desc = L["Set which raid groups are checked for buffs"],
          type = 'group',
          args = {
            group1 = {
              name  = L["Group"].." 1",
              desc = L["Group"].." 1",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[1] end,
              set = function(v) addon.db.profile.Groups[1] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group2 = {
              name  = L["Group"].." 2",
              desc = L["Group"].." 2",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[2] end,
              set = function(v) addon.db.profile.Groups[2] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group3 = {
              name  = L["Group"].." 3",
              desc = L["Group"].." 3",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[3] end,
              set = function(v) addon.db.profile.Groups[3] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group4 = {
              name  = L["Group"].." 4",
              desc = L["Group"].." 4",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[4] end,
              set = function(v) addon.db.profile.Groups[4] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group5 = {
              name  = L["Group"].." 5",
              desc = L["Group"].." 5",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[5] end,
              set = function(v) addon.db.profile.Groups[5] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group6 = {
              name  = L["Group"].." 6",
              desc = L["Group"].." 6",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[6] end,
              set = function(v) addon.db.profile.Groups[6] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group7 = {
              name  = L["Group"].." 7",
              desc = L["Group"].." 7",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[7] end,
              set = function(v) addon.db.profile.Groups[7] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
            group8 = {
              name  = L["Group"].." 8",
              desc = L["Group"].." 8",
              type = 'toggle',
              get = function() return addon.db.profile.Groups[8] end,
              set = function(v) addon.db.profile.Groups[8] = v end,
              map = { [false] = "|cffff4040Disabled|r", [true] = "|cff40ff40Enabled|r" }
            },
          }
        },
      }
    },
    buffcheck = {
      name = L["BuffCheck"],
      desc = L["Pops up a window to check various raid/elixir buffs (drag the bottom to resize)."],
      type = 'execute',
      func = function() BigBrother:ToggleBuffWindow() end,
    }
  }
}

addon.OnMenuRequest = options

function addon:SetupVersion()
   local svnrev = 0
   local files = vars.svnrev
   files["X-Build"] = tonumber((GetAddOnMetadata(addon.name, "X-Build") or ""):match("%d+"))
   files["X-Revision"] = tonumber((GetAddOnMetadata(addon.name, "X-Revision") or ""):match("%d+"))
   for _,v in pairs(files) do -- determine highest file revision
     if v and v > svnrev then
       svnrev = v
     end
   end
   addon.revision = svnrev

   files["X-Curse-Packaged-Version"] = GetAddOnMetadata(addon.name, "X-Curse-Packaged-Version")
   files["Version"] = GetAddOnMetadata(addon.name, "Version")
   addon.version = files["X-Curse-Packaged-Version"] or files["Version"] or "@"
   if string.find(addon.version, "@") then -- dev copy uses "@.project-version.@"
      addon.version = "r"..svnrev
   end
   addon:BroadcastVersion()
end

function addon:BroadcastVersion(force)
   if not addon.version then return end
   if select(2, IsInInstance()) == "pvp" then return end
   local files = vars.svnrev
   if (not files["X-Curse-Packaged-Version"] or
      string.match(addon.version, "^r") or
      files["X-Build"] ~= addon.revision)
      and not force then
     return -- not a packaged release
   end
   local msg = "revision "..addon.revision.." version "..addon.version
   if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
     SendAddonMessage(addon.name, msg, "INSTANCE_CHAT")
   elseif IsInRaid() then
     SendAddonMessage(addon.name, msg, "RAID")
   elseif GetNumGroupMembers() ~= 0 then
     SendAddonMessage(addon.name, msg, "PARTY")
   end
   if IsInGuild() then
     SendAddonMessage(addon.name, msg, "GUILD")
   end
end
RegisterAddonMessagePrefix(addon.name)
local upgrade_warned = false
function addon:CHAT_MSG_ADDON(prefix, message, channel, sender)
  if prefix ~= addon.name then return end
  local revision, version = message:match("^revision (.+) version (.+)$")
  revision = tonumber(revision)
  if not revision or not version or not addon.revision then return end
  if revision > addon.revision and not upgrade_warned then
    BigBrother:Print(string.format(L["A new version of Big Brother (%s) is available for download at:"], version)..
                     "\n     http://www.curse.com/addons/wow/big-brother")
    upgrade_warned = true
  end
end

function addon:OnInitialize()
  -- AddonLoader support
  SLASH_BIGBROTHER1 = nil
  SlashCmdList["BIGBROTHER"] = nil
  hash_SlashCmdList["/bigbrother"] = nil
  SLASH_BB1 = nil
  SlashCmdList["BB"] = nil
  hash_SlashCmdList["/bb"] = nil
  GameTooltip:Hide()
  addon:SetupVersion()

  self:RegisterChatCommand("/bb", "/bigbrother", options, "BIGBROTHER")
end

local LDB
function addon:OnEnable()
  self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  self:RegisterEvent("READY_CHECK")
  self:RegisterEvent("CHAT_MSG_ADDON")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("GROUP_ROSTER_UPDATE")
  self:OnProfileEnable()

  if LDB then
    return
  end
  if AceLibrary:HasInstance("LibDataBroker-1.1") then
    LDB = AceLibrary("LibDataBroker-1.1")
  elseif LibStub then
    LDB = LibStub:GetLibrary("LibDataBroker-1.1",true)
  end
  if LDB then
    local dataobj = LDB:GetDataObjectByName("BigBrother") or
      LDB:NewDataObject("BigBrother", {
        type = "launcher",
        label = "BigBrother",
        icon = "Interface\\AddOns\\BigBrother\\icon",
      })
    dataobj.OnClick = function(self, button)
	        if button == "RightButton" then
	                BigBrother:OpenMenu(self,addon)
	        else
	                BigBrother:ToggleBuffWindow()
	        end
        end
    dataobj.OnTooltipShow = function(tooltip)
                if tooltip and tooltip.AddLine then
                        tooltip:SetText("BigBrother")
                        tooltip:AddLine(L["|cffff8040Left Click|r to toggle the buff window"])
                        tooltip:AddLine(L["|cffff8040Right Click|r for menu"])
                        tooltip:Show()
                end
        end
    -- if AceLibrary:HasInstance("LibDBIcon-1.0") then
    --   AceLibrary("LibDBIcon-1.0"):Register("BigBrother", LDB, self.db.profile.minimap)
    -- end
  end

  for i = 1,2 do
       local _,n = GetWorldPVPAreaInfo(i)
       outdoor_bg[n] = i
  end

  DEFAULT_CHAT_FRAME:HookScript("OnHyperlinkEnter", function(self, linkData, olink)
        if string.match(linkData,"^player::BigBrother:") then
          GameTooltip:SetOwner(self, "ANCHOR_CURSOR");
          GameTooltip:SetText(L["Click to add this event to chat"])
          GameTooltip:Show()
        end
  end)
  DEFAULT_CHAT_FRAME:HookScript("OnHyperlinkLeave", function(self, linkData, link)
        if string.match(linkData,"^player::BigBrother:") then
          GameTooltip:Hide()
        end
  end)
end

function addon:OnDisable()
  if BigBrother_BuffWindow and BigBrother_BuffWindow:IsShown() then
    BigBrother:ToggleBuffWindow()
  end
end

function addon:OnProfileDisable()
end

function addon:OnProfileEnable()
  profile = self.db.profile
end

function addon:SendMessageList(Pre,List,Where)
  if #List > 0 then
    if Where == "SELF" then
      self:Print(string.format(color, Pre..":") .. " " .. table.concat(List, ", "))
    elseif Where == "WHISPER" then
      local theTarget = UnitName("playertarget")
      if theTarget == nil then
         theTarget = UnitName("player")
      end
      SendChatMessage(Pre..": "..table.concat(List, ", "),Where,nil,theTarget)
    else
      SendChatMessage(Pre..": "..table.concat(List, ", "),Where)
    end
  end
end

function addon:HasBuff(player,MissingBuffList)
  for k, v in pairs(MissingBuffList) do
    if v==player then
      table.remove(MissingBuffList,k)
    end
  end
end

function addon:FlaskCheck(Where)
  self:ConsumableCheck(Where, true)
end

function addon:QuickCheck(Where)
  self:ConsumableCheck(Where, false)
end


function addon:ConsumableCheck(Where,Full)
  local numElixirs = 0
  local MissingFlaskList={}
  local MissingElixirList={}
  local MissingFoodList={}

  if not (self.db.profile.CheckFlasks or self.db.profile.CheckElixirs or self.db.profile.CheckFood) then
    self:Print(L["No checks selected!"])
    return
  end

	-- Fill up the food and flask lists with the raid roster names
	-- We wil remove those that are "ok" later
  for unit in RL:IterateRoster(false) do
    if self.db.profile.Groups[unit.subgroup] then
      table.insert(MissingFlaskList,unit.name)
      table.insert(MissingFoodList,unit.name)
    end
  end
  if #MissingFlaskList == 0 then
    self:Print(L["No units in selected raid groups!"])
    return
  end

  -- Print the flask list and determine who has no flask
  for i, v in ipairs(vars.Flasks) do
      local spellName, spellIcon = unpack(v)
      local t = self:BuffPlayerList(spellName,MissingFlaskList)
      if Full and self.db.profile.CheckFlasks then
        self:SendMessageList(spellName, t, Where)
      end
  end

  --use this to print out who has what elixir, and who has no elixirs
  if self.db.profile.CheckElixirs then
    for i, v in ipairs(vars.Elixirs) do
      local spellName, spellIcon = unpack(v)
      local t = self:BuffPlayerList(spellName, MissingFlaskList)
      if Full then
        self:SendMessageList(spellName, t, Where)
      end
    end

    --now figure out who has only one elixir
    for unit in RL:IterateRoster(false) do
      if self.db.profile.Groups[unit.subgroup] then
        numElixirs = 0
        for i, v in ipairs(vars.Elixirs) do
            local spellName, spellIcon = unpack(v)
            if UnitBuff(unit.unitid, spellName) then
              numElixirs = numElixirs + 1
            end
        end
        if numElixirs == 1 then
            table.insert(MissingElixirList,unit.name)
        end
      end
    end

    self:SendMessageList(L["Only One Elixir"], MissingElixirList, Where)
    self:SendMessageList(L["No Flask or Elixir"], MissingFlaskList, Where)
  elseif self.db.profile.CheckFlasks then -- user wants flasks only, not elixers
    self:SendMessageList(L["No Flask"], MissingFlaskList, Where)
  end

	--check for missing food
	if self.db.profile.CheckFood then
		for i, v in ipairs(vars.Foodbuffs) do
			local spellName, spellIcon = unpack(v)
			local t = self:BuffPlayerList(spellName, MissingFoodList)
		end
		self:SendMessageList(L["No Food Buff"], MissingFoodList, Where)
	end
end

local petToOwner = {}
local tanklist = {}
local tankcnt = 0
addon.petToOwner = petToOwner

local function nospace(str)
  if not str then return "" end
  return str:gsub("%s","")
end

function addon:IsTank(name)
  if not name then return nil end
  if tankcnt == 0 then
    RL:ScanFullRoster()
    for unit in RL:IterateRoster(false) do
      if GetPartyAssignment("MAINTANK", unit.unitid) or
         UnitGroupRolesAssigned(unit.unitid) == "TANK" then
        tanklist[nospace(unit.name)] = true -- bare name
        tanklist[nospace(unit.unitid)] = true -- bare name
        tanklist[nospace(GetUnitName(unit.unitid,false))] = true
        tanklist[nospace(GetUnitName(unit.unitid,true))] = true -- with server name
	tankcnt = tankcnt + 1
	--print("detected tank: "..unit.name)
      end
    end
  end
  local retval = tanklist[nospace(name)] or tanklist[nospace(GetUnitName(name, true))]
  if BigBrother.debug then
    print("IsTank('"..name.."') => "..(retval and "true" or "false").." "..(tankcnt > 0))
  end
  return retval, tankcnt > 0
end
function addon:clearTankList()
  --print("Wiping "..tankcnt.." tanks")
  wipe(tanklist)
  tankcnt = 0
end
function addon:GROUP_ROSTER_UPDATE()
  addon:clearTankList()
  addon:BroadcastVersion()
end

function addon:BuffPlayerList(buffname,MissingBuffList)
  local list = {}
  for unit in RL:IterateRoster(false) do
    if UnitBuff(unit.unitid, buffname) then
      table.insert(list, unit.name)
      self:HasBuff(unit.name,MissingBuffList)
    end
  end
  return list
end

local iconlookup = {
  [COMBATLOG_OBJECT_RAIDTARGET1] = "{rt1}",
  [COMBATLOG_OBJECT_RAIDTARGET2] = "{rt2}",
  [COMBATLOG_OBJECT_RAIDTARGET3] = "{rt3}",
  [COMBATLOG_OBJECT_RAIDTARGET4] = "{rt4}",
  [COMBATLOG_OBJECT_RAIDTARGET5] = "{rt5}",
  [COMBATLOG_OBJECT_RAIDTARGET6] = "{rt6}",
  [COMBATLOG_OBJECT_RAIDTARGET7] = "{rt7}",
  [COMBATLOG_OBJECT_RAIDTARGET8] = "{rt8}",
  }

local srcGUID, srcname, srcflags, srcRaidFlags,
      dstGUID, dstname, dstflags, dstRaidFlags

local SRC = "<<<SRC>>>"
local DST = "<<<DST>>>"
local EMBEGIN = "<<<EM>>>"
local EMEND = "<<</EM>>>"
local function SPELL(id)
  return "<<<SPELL:"..id..">>>"
end
local function SPELLDECODE_helper(s)
  local l
  l = s and GetSpellLink(s)
  if l then return l
  else return GetSpellLink(2382)
  end
end
local function SPELLDECODE(spam)
   return string.gsub(spam, "<<<SPELL:(%d+)>>>", SPELLDECODE_helper)
end

local function iconize(flags,chatoutput)
  local iconflag = bit.band(flags or 0, COMBATLOG_OBJECT_RAIDTARGET_MASK)

  if chatoutput then
    return (iconlookup[iconflag] or "")
  elseif iconflag then
    local check, iconidx = math.frexp(iconflag)
    --iconidx = iconidx - 20
    if check == 0.5 and iconidx >= 1 and iconidx <= 8 then
      return "|Hicon:"..iconflag..":dest|h|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_"..iconidx..".blp:0|t|h"
    end
  end

  return ""
end

local function unitColor(guid, flags, name)
  local color
  local class = guid and select(3,pcall(GetPlayerInfoByGUID, guid)) -- ticket 34
  if bit.band(flags or 0,COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0 then
    color = "ff0000"
  elseif bit.band(flags or 0,COMBATLOG_OBJECT_TYPE_NPC) > 0 then
    color = "6666ff"
  elseif bit.band(flags or 0,COMBATLOG_OBJECT_TYPE_PET) > 0 then
    color = "40ff40"
  elseif bit.band(flags or 0,COMBATLOG_OBJECT_TYPE_GUARDIAN) > 0 then
    color = "40ff40"
  elseif class and RAID_CLASS_COLORS[class] then
    local c = RAID_CLASS_COLORS[class]
    color = string.format("%02x%02x%02x", c.r*255, c.g*255, c.b*255)
  else -- unknown
    color = "666666"
  end
  if bit.band(flags or 0,COMBATLOG_OBJECT_TYPE_PLAYER) then
    name = "\124Hplayer:"..name.."::"..name.."\124h"..name.."\124h"
  end
  return "\124cff"..color..name.."\124r"
end

function addon:unitOwner(petGUID, petFlags, usecolor)
  --print("unitOwner"..petGUID.." "..petFlags)
  if not petGUID or not petFlags then
    return ""
  end
  if bit.band(petFlags,COMBATLOG_OBJECT_TYPE_PET) == 0 and
     bit.band(petFlags,COMBATLOG_OBJECT_TYPE_GUARDIAN) == 0 then
    return ""
  end
  local ownerGUID = petToOwner[petGUID]
  if not ownerGUID then -- try a refresh
    for unit in RL:IterateRoster(true) do
      local ownerid,tag = unit.unitid:match("^(.*)pet(%d*)$") -- raid1pet or raidpet1
      if ownerid == "" then ownerid = "player" end
      ownerid = (ownerid or "")..(tag or "")
      if ownerid and UnitExists(ownerid) and UnitExists(unit.unitid) then
        local guid = UnitGUID(unit.unitid)
        local ownerguid = UnitGUID(ownerid)
        petToOwner[guid] = ownerguid
      end
    end
    ownerGUID = petToOwner[petGUID]
  end
  if not ownerGUID then
    return ""
  end
  local name,realm = select(6,GetPlayerInfoByGUID(ownerGUID))
  name = name or "Unknown"
  if realm and #realm > 0 then
    name = name.."-"..realm
  end
  if usecolor then
    local colored = unitColor(ownerGUID, bit.bor(COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_REACTION_FRIENDLY), name)
    return " <"..colored..">"
  else
    return " <"..name..">"
  end
end

local function SYMDECODE(spam,chatoutput)
  local x = iconize(COMBATLOG_OBJECT_RAIDTARGET7,chatoutput)
  spam = string.gsub(spam, EMBEGIN, x..x..x.." ")
  spam = string.gsub(spam, EMEND, " "..x..x..x)
  local srctxt = srcname or "Unknown"
  local dsttxt = dstname or "Unknown"
  if not chatoutput then
    srctxt = unitColor(srcGUID, srcflags, srctxt)
    dsttxt = unitColor(dstGUID, dstflags, dsttxt)
  end
  local srcowner = addon:unitOwner(srcGUID, srcflags, not chatoutput)
  local dstowner = addon:unitOwner(dstGUID, dstflags, not chatoutput)
  srctxt = iconize(srcRaidFlags,chatoutput)..srctxt..srcowner
  dsttxt = iconize(dstRaidFlags,chatoutput)..dsttxt..dstowner
  spam = string.gsub(spam, SRC, srctxt)
  spam = string.gsub(spam, DST, dsttxt)
  return spam
end

local function spamchannel(spam, channel, chanid)
   local output = spam
   output = SPELLDECODE(output)
   output = SYMDECODE(output, true)
   SendChatMessage(output, channel, nil, chanid)
end

local function sendspam(spam,channels,tankunit)
  local channels = channels or addon.db.profile.PolyOut
  if not spam then return end

  if tankunit then
    local istank, havetanks = addon:IsTank(tankunit)
    if istank and not addon.db.profile.ReportTanks then
      return
    end
    if not istank and havetanks and addon.db.profile.ReportTanks then
      spam = EMBEGIN..spam..EMEND
    end
  end

  if channels[1] then
    local output = SYMDECODE(spam, false)
    output = SPELLDECODE(output)
    local data = SYMDECODE(spam, true)
    local link = "\124Hplayer::BigBrother:"..time()..":"..data.."\124h\124cff8888ff[Big Brother]\124r\124h\124h: "
    --addon:Print(output)
    print(link..output)
  end

  local it = select(2, IsInInstance())
  local inbattleground = (it == "pvp")
  local inoutdoorbg = false
  local inarena = (it == "arena")

  local id = outdoor_bg[GetRealZoneText()]
  if id then
      local _,_, isActive = GetWorldPVPAreaInfo(id)
      if isActive then
        inoutdoorbg = true
      end
  end

  -- BG reporting - never spam bg unless specifically requested, and dont spam anyone else
  if inbattleground then
    if channels[7] then
      spamchannel(spam, "INSTANCE_CHAT")
    end
    return
  elseif inoutdoorbg then
    if channels[7] then
      spamchannel(spam, "RAID")
    end
    return
  elseif inarena then
    if channels[2] or channels[7] then
      spamchannel(spam, "PARTY")
    end
    return
  end

  -- raid/party reporting
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
     if channels[8] then
       spamchannel(spam, "INSTANCE_CHAT")
     end
  elseif IsInRaid() and channels[3] then
     spamchannel(spam, "RAID")
  elseif GetNumGroupMembers() ~= 0 and channels[2] then
     spamchannel(spam, "PARTY")
  end

  -- guild reporting - dont spam both channels
  if IsInGuild() and channels[4] then
     spamchannel(spam, "GUILD")
  elseif IsInGuild() and channels[5] then
     spamchannel(spam, "OFFICER")
  end

	-- custom reporting
  if channels[6] and addon.db.profile.CustomChannel then
     local chanid = GetChannelName(addon.db.profile.CustomChannel)
     if chanid then
        spamchannel(spam, "CHANNEL", chanid)
     end
  end
end

local clickchan = {false, true, true, false, false, false, true, true}
hooksecurefunc("SetItemRef",function(link,text,button,chatFrame)
  local time, data = string.match(link,"^player::BigBrother:(%d+):(.+)$")
  if time then
      data = SPELLDECODE(data)
      data = "["..date("%H:%M:%S",time).."]: "..data
      if ChatEdit_GetActiveWindow() then
        ChatEdit_InsertLink(data)
      else
        sendspam(data, clickchan)
      end
  end
end)


function addon:PLAYER_REGEN_DISABLED()
  addon:clearTankList()
  if addon.db.profile.BuffWindowCombatClose then
    if BigBrother_BuffWindow and BigBrother_BuffWindow:IsShown() then
      BigBrother:ToggleBuffWindow()
    end
  end
end

function addon:READY_CHECK(sender)
  local doquickcheck = false
  local dowindisplay = false

  if addon.IsDisabled(addon) then
    return
  end

  if UnitIsUnit(sender, "player") then
    if addon.db.profile.ReadyCheckMine then doquickcheck = true end
    if addon.db.profile.ReadyCheckBuffWinMine then dowindisplay = true end
  else
    if addon.db.profile.ReadyCheckOther then doquickcheck = true end
    if addon.db.profile.ReadyCheckBuffWinOther then dowindisplay = true end
  end

  if addon.db.profile.ReadyCheckIgnoreLFG and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    doquickcheck = false
  end

  if dowindisplay then
    if not BigBrother_BuffWindow or not BigBrother_BuffWindow:IsShown() then
      BigBrother:ToggleBuffWindow()
    end
  end

  if doquickcheck then
    if addon.db.profile.ReadyCheckToRaid then
      if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
          addon:ConsumableCheck("INSTANCE_CHAT")
      elseif IsInRaid() then
          addon:ConsumableCheck("RAID")
      elseif GetNumGroupMembers() > 0 then
          addon:ConsumableCheck("PARTY")
      end
    elseif addon.db.profile.ReadyCheckToSelf then
      addon:ConsumableCheck("SELF")
    end
  end
end

local ccinfo = {
  spellid = {},       -- GUID -> cc spell id
  time = {},          -- GUID -> time when it expires
  dmgspellid = {},    -- GUID -> spell ID that caused damage
  dmgspellamt = {},   -- GUID -> spell ID that caused damage
  dmgunitname = {},   -- GUID -> last unit to damage it
  dmgunitguid = {},   -- GUID -> last unit to damage it
  dmgunitflags = {},  -- GUID -> last unit to damage it
  dmgunitrflags = {}, -- GUID -> last unit to damage it
  postponetime = {},  -- GUID -> time of breakage postponed
}
local function ccinfoClear(dstGUID)
      ccinfo.spellid[dstGUID] = nil
      ccinfo.time[dstGUID] = nil
      ccinfo.dmgspellid[dstGUID] = nil
      ccinfo.dmgspellamt[dstGUID] = nil
      ccinfo.dmgunitname[dstGUID] = nil
      ccinfo.dmgunitguid[dstGUID] = nil
      ccinfo.dmgunitflags[dstGUID] = nil
      ccinfo.dmgunitrflags[dstGUID] = nil
      ccinfo.postponetime[dstGUID] = nil
end

local playersrcmask = bit.bor(bit.bor(COMBATLOG_OBJECT_TYPE_PLAYER,
                              COMBATLOG_OBJECT_TYPE_PET),
                              COMBATLOG_OBJECT_TYPE_GUARDIAN) -- totems

function addon:COMBAT_LOG_EVENT_UNFILTERED(timestamp, subevent, hideCaster, ...)
  local spellID, spellname, spellschool,
     extraspellID
  srcGUID, srcname, srcflags, srcRaidFlags,
  dstGUID, dstname, dstflags, dstRaidFlags,
  spellID, spellname, spellschool,
  extraspellID = ...

  srcflags = srcflags or 0
  dstflags = dstflags or 0

  if profile.GroupOnly and
     bit.band(srcflags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 and
     bit.band(dstflags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 and
     not ccinfo.spellid[dstGUID] then
     -- print("skipped event from "..(srcname or "nil").." on "..(dstname or "nil"))
    return
  end

  local is_playersrc = bit.band(srcflags, playersrcmask) > 0
  local is_playerdst = bit.band(dstflags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
  local is_hostiledst = bit.band(dstflags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
  if addon.debug then
    print((spellname or "nil")..":"..(spellID or "nil")..":"..(subevent or "nil")..":"..
       (srcname or "nil")..":"..(srcGUID or "nil")..":"..(srcflags or "nil")..":"..(srcRaidFlags or "nil")..":"..
       (dstname or "nil")..":"..(dstGUID or "nil")..":"..(dstflags or "nil")..":"..(dstRaidFlags or "nil")..":"..
       "is_playersrc:"..((is_playersrc and "true") or "false")..":"..(extraspellID or "nil"))
  end
  if subevent == "SPELL_SUMMON" and is_playersrc then
    petToOwner[dstGUID] = srcGUID
    return
  elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
    petToOwner[dstGUID] = nil
    return
  end
  local PolyBreak = profile.PolyBreak
  if PolyBreak
	  and dstGUID and ccinfo.time[dstGUID]
	  and (string.find(subevent, "_DAMAGE") or  -- newest direct damage
	       (subevent == "SPELL_AURA_APPLIED" -- newest dot application with no prev direct damage
	        and (not ccinfo.dmgspellamt[dstGUID] or ccinfo.dmgspellamt[dstGUID] == 0)
	        and not ccSpellNames[spellname]
		and not ccSafeAuraNames[spellname]
		and not tauntSpellNames[spellname]
		and not aoetauntSpellNames[spellname]
		)
	      )
	  and spellID ~= 66070 then -- ignore roots dmg
	  local new_dmgspellid, new_dmgspellamt
	  if subevent == "SWING_DAMAGE" then
	    new_dmgspellid = 6603
	    new_dmgspellamt = spellID -- swing damage
	  elseif subevent == "SPELL_AURA_APPLIED" then
	    new_dmgspellid = spellID
	    new_dmgspellamt = 0 -- spelldmg
	  else
	    new_dmgspellid = spellID
	    new_dmgspellamt = extraspellID -- spelldmg
	  end
	  ccinfo.dmgspellamt[dstGUID] = ccinfo.dmgspellamt[dstGUID] or 0
	  if (ccinfo.dmgspellamt[dstGUID] == 0 and new_dmgspellamt > 0) or -- first direct dmg
	     (new_dmgspellamt > 0 and -- newer direct dmg overwrites older direct dmg, except
	      not (addon:IsTank(ccinfo.dmgunitname[dstGUID]) and not addon:IsTank(srcname))) -- non-tanks dont overwrite tanks
	  then
	    ccinfo.dmgspellid[dstGUID] = new_dmgspellid
	    ccinfo.dmgspellamt[dstGUID] = new_dmgspellamt
	    ccinfo.dmgunitname[dstGUID] = srcname
	    ccinfo.dmgunitguid[dstGUID] = srcGUID
	    ccinfo.dmgunitflags[dstGUID] = srcflags
	    ccinfo.dmgunitrflags[dstGUID] = srcRaidFlags
	  end
	  if ccinfo.dmgspellamt[dstGUID] > 0 and ccinfo.postponetime[dstGUID] then
	     if (GetTime() - ccinfo.postponetime[dstGUID]) < 0.5 then -- this target just broke SPELL_AURA_REMOVED
	       subevent = "SPELL_AURA_BROKEN_SPELL"
	       extraspellID = spellID
	     else -- give up
	       subevent = "SPELL_AURA_REMOVED"
	     end
	     spellID = ccinfo.spellid[dstGUID]
	     spellname = GetSpellInfo(spellID)
	  end
  elseif PolyBreak and is_playersrc and is_hostiledst
	  and (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH")
	  and spellID ~= 24131 -- ignore the dot component of wyvern sting
	  and ccSpellNames[spellname] then
	    local expires
	    local now = GetTime()
	    profile.cctime = profile.cctime or {}
	    for _,unit in pairs({srcname.."-target", "target", "focus", "mouseover" }) do
	      if UnitExists(unit) and UnitGUID(unit) == dstGUID then
	        expires = select(7, UnitDebuff(unit, spellname))
		break
	      end
	    end
            local usualtime = profile.cctime[spellname]
	    if expires then
	      local duration = expires - now
	      if not usualtime or duration > usualtime then
	        profile.cctime[spellname] = duration
	      end
	    else
	      expires = now + (usualtime or 60)
	      --print("Guessing CC expiration")
	    end
	    if expires and ( not ccinfo.time[dstGUID] or ccinfo.time[dstGUID] < expires ) then
	      -- print(spellname.." applied for "..(expires - now).." sec")
	      ccinfoClear(dstGUID)
	      ccinfo.time[dstGUID] = expires
	      ccinfo.spellid[dstGUID] = spellID
	    end
  end
  if PolyBreak
	  and (subevent == "SPELL_AURA_BROKEN" or subevent == "SPELL_AURA_BROKEN_SPELL" or subevent == "SPELL_AURA_REMOVED")
	  and is_hostiledst
	  and spellID ~= 24131 -- ignore the dot component of wyvern sting
	  and ccSpellNames[spellname] then

		local throttleResetTime = 15;
		local now = GetTime();
		local expired = false

		-- Reset the spam throttling cache if it isn't initialized or
		-- if it's been more than 15 seconds since any CC broke
		if (nil == self.spamCache or (nil ~= self.spamCacheLastTimeMax and now - self.spamCacheLastTimeMax > throttleResetTime)) then
			self.spamCache = {};
			self.spamCacheLastTimeMax = nil;
		end

                if spellID == ccinfo.spellid[dstGUID] then
		  if ccinfo.time[dstGUID] and (ccinfo.time[dstGUID] - now < 1) then
		      expired = true
		  elseif spellID == 710 then -- banish can't be broken, don't inspect nearby damage
		      -- src indicates caster, not remover
		      subevent = "SPELL_AURA_REMOVED"
		  elseif ccinfo.time[dstGUID] and (ccinfo.time[dstGUID] - now > 1) and -- poly ended more than a sec early
		     ccinfo.dmgspellid[dstGUID] and
		     subevent ~= "SPELL_AURA_BROKEN_SPELL" then -- add the missing info
                      subevent = "SPELL_AURA_BROKEN_SPELL"
		      srcname = ccinfo.dmgunitname[dstGUID]
		      srcGUID = ccinfo.dmgunitguid[dstGUID]
		      srcflags = ccinfo.dmgunitflags[dstGUID]
		      srcRaidFlags = ccinfo.dmgunitrflags[dstGUID]
		      extraspellID = ccinfo.dmgspellid[dstGUID]
		  elseif subevent == "SPELL_AURA_REMOVED" and not ccinfo.postponetime[dstGUID] then
		      -- src exists but is not reliable (indicates caster, not breaker)
		      -- no dmg seen yet, postpone until next dmg on target
		      -- most likely the next combat event will be SPELL_AURA_BROKEN_SPELL or SPELL_*DAMAGE on it
		      ccinfo.postponetime[dstGUID] = now
		      return
		  end
		  ccinfoClear(dstGUID)
		end


		local spam

		if subevent == "SPELL_AURA_BROKEN" then
		  spam = (L["%s on %s removed by %s"]):format(SPELL(spellID), DST, SRC)
		elseif subevent == "SPELL_AURA_BROKEN_SPELL" then
		  spam = (L["%s on %s removed by %s's %s"]):format(SPELL(spellID), DST, SRC, SPELL(extraspellID))
		elseif expired then
		  spam = (L["%s on %s expired"]):format(SPELL(spellID), DST)
		elseif subevent == "SPELL_AURA_REMOVED" then
		  spam = (L["%s on %s removed"]):format(SPELL(spellID), DST)
		end

		-- Should we throttle the spam?
		if self.spamCache[dstGUID] and now - self.spamCache[dstGUID]["lasttime"] < throttleResetTime then
			-- If we've been broken 3 or more times without a 15 second reprieve (spam breakage),
			-- or twice withing 2 seconds (duplicate combat log breakage events)
			-- then supress the spam
			if (self.spamCache[dstGUID]["count"] > 3 or
			    now - self.spamCache[dstGUID]["lasttime"] < 2) then
				spam = nil;
			end

			-- Increment the cache entry
			self.spamCache[dstGUID]["count"] = self.spamCache[dstGUID]["count"] + 1;
			self.spamCache[dstGUID]["lasttime"] = now;
		else
			-- Reset the cache entry
			self.spamCache[dstGUID] = {["count"] = 1, ["lasttime"] = now};
		end
		self.spamCacheLastTimeMax = now;

		if spam then
		   local tname = srcname
		   if expired or subevent == "SPELL_AURA_REMOVED" then
		     tname = nil
		   end
		   sendspam(spam, nil, tname)
		end
  elseif not is_playersrc then -- rest is all direct player actions
     return
  elseif subevent == "SPELL_CAST_SUCCESS" and (spellID == 34477 or spellID == 57934 or spellID == 110588) and profile.Misdirect then
	sendspam(L["%s cast %s on %s"]:format(SRC, SPELL(spellID), DST), nil, dstname)
  elseif subevent == "SPELL_RESURRECT" then
  	if brezSpellNames[spellname] and profile.CombatRez then
	  sendspam(L["%s cast %s on %s"]:format(SRC, SPELL(spellID), DST))
	elseif rezSpellNames[spellname] and profile.NonCombatRez then
	  -- would like to report at spell cast start, but unfortunately the SPELL_CAST_SUCCESS combat log event for all rezzes has a nil target
	  sendspam(L["%s cast %s on %s"]:format(SRC, SPELL(spellID), DST))
	end
  elseif ((subevent == "SPELL_CAST_SUCCESS" and tauntSpellNames[spellname] and spellname ~= deathgrip) or
	 (subevent == "SPELL_AURA_APPLIED" and spellname == deathgrip)) and -- trigger off death grip "taunted" debuff, which is not applied with Glyph of Tranquil Grip
         profile.Taunt and not is_playerdst then
	sendspam(L["%s taunted %s with %s"]:format(SRC, DST, SPELL(spellID)), nil, srcname)
  elseif subevent == "SPELL_AURA_APPLIED" and aoetauntSpellNames[spellname] and profile.Taunt and not is_playerdst then
	sendspam(L["%s aoe-taunted %s with %s"]:format(SRC, DST, SPELL(spellID)), nil, srcname)
  elseif subevent == "SPELL_MISSED" and (tauntSpellNames[spellname] or aoetauntSpellNames[spellname])
	  and not (spellID == 49576 and extraspellID == "IMMUNE") -- ignore immunity messages from death grip caused by mobs immune to the movement component
	  and not spellID == 2649 -- ignore hunter pet growl
          and profile.Taunt and not is_playerdst  then
    	local missType = extraspellID
	sendspam(L["%s taunt FAILED on %s (%s)"]:format(SRC, DST, missType), nil, srcname)
  elseif subevent == "SPELL_INTERRUPT" and profile.Interrupt then
	sendspam(L["%s interrupted %s casting %s"]:format(SRC, DST, SPELL(extraspellID)))
  elseif subevent == "SPELL_DISPEL" and profile.Dispel and is_hostiledst then
        local extra = ""
	if spellID and spellID > 0 then
	  extra = " ("..SPELL(spellID)..")"
	end
	sendspam(L["%s dispelled %s on %s"]:format(SRC, SPELL(extraspellID or spellID), DST)..extra)
  elseif subevent == "SPELL_STOLEN" and profile.Dispel and is_hostiledst then
	sendspam(L["%s stole %s from %s"]:format(SRC, SPELL(extraspellID or spellID), DST))
  end
end


