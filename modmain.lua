local require = GLOBAL.require
local Text = require('widgets/text')
local easing = require("easing")

local MAXSOURCES = GetModConfigData("MAXSOURCES")
local SHOWTOTAL = GetModConfigData("SHOWTOTAL")
local DELTA_TYPE =
{
	EQUIPMENT = 1,
	MOISTURE = 2,
	LIGHT = 3,
	AURA = 4,
	GHOST = 5,
	EXTERNAL = 6,
}

--Some of the things that modify sanity don't have names defined so we define them here as long as a game 
-- update didn't already do that
if(GLOBAL.STRINGS.NAMES['WALTER_CAMPFIRE_STORY_PROXY'] == nil) then
	GLOBAL.STRINGS.NAMES['WALTER_CAMPFIRE_STORY_PROXY'] = "Campfire Story"
end

--Define the main variable we'll use
local deltas = {}

--Push the delta into the list as long as it's not zero
function AddDelta(value, type, source)
	if(math.abs(value) > 0) then
		local delta_array =
		{
			VALUE = value,
			TYPE = type,
			SOURCE = source
		}

		table.insert(deltas, table.getn(deltas)+1, delta_array)
	end
end

local function SanityPostConstruct(self)
	
	local OriginalRecalc = self.Recalc
    function self:Recalc(dt)
		OriginalRecalc(self, dt)
		
		--Each time we re-run this we need to set it to empty again to clear the old text
		deltas = {};

		--The below are all the things that could affect the sanity gain/loss rate (or delta)
		--These functions are taken from the components/sanity.lua file
		--This is somewhat inefficient as we are basically doing these calculations twice since
		-- individual rates aren't preserved in the original function but I'd rather do this 
		-- than completely rewrite the function. Additionally if the main code is changed, nothing
		-- will break

		--Calculate the deltas for an equipment
		if self.dapperness_mult ~= 0 then 
			local total_dapperness = self.dapperness
			for k, v in pairs(self.inst.components.inventory.equipslots) do
				local equippable = v.components.equippable
				if equippable ~= nil and (not self.only_magic_dapperness or equippable.is_magic_dapperness) then
					total_dapperness = equippable:GetDapperness(self.inst, self.no_moisture_penalty)

					local item = self.inst.components.inventory:GetEquippedItem(equippable.equipslot);
					AddDelta(total_dapperness * self.rate_modifier, DELTA_TYPE.EQUIPMENT, item.name)
				end
			end
		end

		--Calculate the deltas for wetness level
		local moisture_delta = self.no_moisture_penalty and 0 or easing.inSine(self.inst.components.moisture:GetMoisture(), 0, TUNING.MOISTURE_SANITY_PENALTY_MAX, self.inst.components.moisture:GetMaxMoisture())
		AddDelta(moisture_delta * self.rate_modifier, DELTA_TYPE.MOISTURE, "being wet")

		--Calculate the deltas for light levels
		local LIGHT_SANITY_DRAINS =
		{
			[GLOBAL.SANITY_MODE_INSANITY] = {
				DAY = TUNING.SANITY_DAY_GAIN,
				NIGHT_LIGHT = TUNING.SANITY_NIGHT_LIGHT,
				NIGHT_DIM = TUNING.SANITY_NIGHT_MID,
				NIGHT_DARK = TUNING.SANITY_NIGHT_DARK,
			},
			[GLOBAL.SANITY_MODE_LUNACY] = {
				DAY = TUNING.SANITY_LUNACY_DAY_GAIN,
				NIGHT_LIGHT = TUNING.SANITY_LUNACY_NIGHT_LIGHT,
				NIGHT_DIM = TUNING.SANITY_LUNACY_NIGHT_MID,
				NIGHT_DARK = TUNING.SANITY_LUNACY_NIGHT_DARK,
			},
		}

		local light_sanity_drain = LIGHT_SANITY_DRAINS[self.mode]
		local light_delta = 0

		if not self.light_drain_immune then
			if GLOBAL.TheWorld.state.isday and not GLOBAL.TheWorld:HasTag("cave") then
				light_delta = light_sanity_drain.DAY
			else
				local lightval = GLOBAL.CanEntitySeeInDark(self.inst) and .9 or self.inst.LightWatcher:GetLightValue()
				light_delta =
					(   (lightval > TUNING.SANITY_HIGH_LIGHT and light_sanity_drain.NIGHT_LIGHT) or
						(lightval < TUNING.SANITY_LOW_LIGHT and light_sanity_drain.NIGHT_DARK) or
						light_sanity_drain.NIGHT_DIM
					) * self.night_drain_mult
			end
		end
		AddDelta(light_delta * self.rate_modifier, DELTA_TYPE.LIGHT, "Darkness")

		--Calculate the deltas for all auras from friendlies and enemies
		local aura_delta = 0
		if not self.sanity_aura_immune then
			local x, y, z = self.inst.Transform:GetWorldPosition()
			local ents = GLOBAL.TheSim:FindEntities(x, y, z, TUNING.SANITY_AURA_SEACH_RANGE, SANITYRECALC_MUST_TAGS, SANITYRECALC_CANT_TAGS)
			for i, v in ipairs(ents) do 
				if v.components.sanityaura ~= nil and v ~= self.inst then
					local is_aura_immune = false
					if self.sanity_aura_immunities ~= nil then
						for tag, _ in pairs(self.sanity_aura_immunities) do
							if v:HasTag(tag) then
								is_aura_immune = true
								break
							end
						end
					end

					if not is_aura_immune then
						local aura_val = v.components.sanityaura:GetAura(self.inst)
						aura_val = (aura_val < 0 and (self.neg_aura_absorb > 0 and self.neg_aura_absorb * -aura_val or aura_val) * self:GetAuraMultipliers() or aura_val)
						local t =  (aura_val < 0 and self.neg_aura_immune) and 0 or aura_val
						AddDelta(self.rate_modifier * t, DELTA_TYPE.AURA, v.name)
					end
				end
			end
		end


		--Calculate the deltas for having ghosts present
		self:RecalcGhostDrain()
		local ghost_delta = TUNING.SANITY_GHOST_PLAYER_DRAIN * self.ghost_drain_mult
		AddDelta(ghost_delta * self.rate_modifier, DELTA_TYPE.GHOST, "Ghost(s)")

		--Calculate the deltas for all other things. This include things like character bonuses (for example Willow getting a bonus from fire)
		AddDelta(self.externalmodifiers:Get() * self.rate_modifier, DELTA_TYPE.EXTERNAL, "Bonus")
		if self.custom_rate_fn ~= nil then
			AddDelta(self.custom_rate_fn(self.inst, dt) * self.rate_modifier, DELTA_TYPE.EXTERNAL, "Bonus")
		end

	end

end
AddClassPostConstruct("components/sanity", SanityPostConstruct)

local function SanityBadgePostConstruct(self)

	local params =
	{
		offset_x = -300,
		offset_y = 0,
	}

	--We can't leave this blank apparently. Set in a placeholder people will never see so we can set the align
	--Only need to do this once since it'll never change
	self:SetHoverText("Initializing", params)
	self.hovertext:SetHAlign(GLOBAL.ANCHOR_LEFT)

	function self:SetDeltaRate(deltas)

		--We only need to update this when this widget has focus since you can't see the hover when it doesn't have focus
		if self.focus then
			local max_deltas = MAXSOURCES

			--We show the deltas with the highest magnitude (positive or negative) first
			table.sort(deltas, function(left, right)
				return math.abs(left.VALUE) > math.abs(right.VALUE)
			end)

			--Generate the actual string that will be displayed
			local main_output = ""
			local other_delta_sum = 0
			local total_delta_sum = 0
			for i,v in ipairs(deltas) do
				if(i <= max_deltas) then
					if v.VALUE >= 0 then
						main_output = main_output.."+"
					end
					main_output = main_output..string.format("%.1f", v.VALUE * 60).." / min from "..v.SOURCE.. " \n"
				else
					other_delta_sum = other_delta_sum + (v.VALUE * 60)
				end

				total_delta_sum = total_delta_sum + (v.VALUE * 60)
			end

			--If there's a generic "other" we add this to the end - this helps prevent the popup from getting too big
			if(math.abs(other_delta_sum) > 0) then
				main_output = main_output..string.format("%.1f", other_delta_sum).." / min from other sources \n"
			end

			--Do we want to display the total?
			if SHOWTOTAL then
				main_output = "Currently "..((total_delta_sum >= 0) and "gaining " or "losing ")..string.format("%.1f", total_delta_sum).." / min \n"..main_output
			elseif table.getn(deltas) == 0 then
				--If a user both chooses to not show the total AND nothing is affecting their sanity, there's going to be nothing to display
				--In this case will throw in a default message
				main_output = "Nothing is affecting sanity"
			end

			--Set the hover
			self:SetHoverText(main_output, params)
		end

	end

end
AddClassPostConstruct("widgets/sanitybadge", SanityBadgePostConstruct)

local function StatusDisplaysPostConstruct(self)

	local OriginalSanityDelta = self.SanityDelta
    function self:SanityDelta(data)
		OriginalSanityDelta(self, data)
		self.brain:SetDeltaRate(deltas)
	end

end
AddClassPostConstruct("widgets/statusdisplays", StatusDisplaysPostConstruct)