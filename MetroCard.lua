SMODS.Atlas({key = "modicon", path = "Icon.png", px = 32, py = 32}) 
SMODS.Atlas {
    key = 'metro_jokers',
    px = 71,
    py = 95,
    path = 'MyJokers.png'
}

--Util functions
transform_joker = function(card, new_card_key)
    local new_card = SMODS.create_card({
        set = 'Joker',
        skip_materialize = true,
        key = new_card_key,
        no_edition = true,
        edition = card.edition,
        enhancement = card.enhancement,
        seal = card.seal,
        stickers = card.stickers
    })

    --Don't let us see the new card we're about to copy
    new_card.states.visible = nil

    --Turn original card into new card we just made
    copy_card(new_card, card)

    --Remove new card we made to copy
    new_card:remove()
end

resurrect_card = function(card, add_to_deck)
    if not G.graveyard or #G.graveyard.cards < 1 then return end
    card = card or G.graveyard.cards[pseudorandom('resurrect', 1, #G.graveyard.cards)]


    local new_card = copy_card(card, Card(card.T.x, card.T.y, G.CARD_W, G.CARD_H, G.P_CARDS.empty, G.P_CENTERS.c_base), nil, nil, true)
    card:remove()

    new_card:set_edition({negative = true}, false)
    new_card.states.visible = nil
    draw_card(nil, G.hand, 90,'up', nil, new_card)

    if add_to_deck then
        new_card:add_to_deck()
    else
        new_card.ability.temporary = true
    end
    G.E_MANAGER:add_event(Event({
        func = function()
            new_card:start_materialize({G.C.SECONDARY_SET.Edition})
            return true
        end,
        trigger = "after",
        delay = 0.5,
        blocking = false
    }))
end

float_card = function(next_card_spot)
    local float_joker = nil
    local res = nil
    for i = 1, #G.jokers.cards do
        res = nil
        res = G.jokers.cards[i]:calculate_joker({drawing_cards = true, floating_card = true})
        if res and res.should_float then float_joker = res.card break end
    end
    if not float_joker then return next_card_spot end
    for i = next_card_spot, 1, -1 do
        local temp = G.deck.cards[i]
        if res.func(temp) then
            G.deck.cards[i] = G.deck.cards[next_card_spot]
            G.deck.cards[next_card_spot] = temp
            next_card_spot = next_card_spot - 1

            G.E_MANAGER:add_event(Event({
                func = function()
                    play_sound('generic1')
                    float_joker:juice_up()
                    return true
                end,
                blocking = false
            }))
            local res = float_joker:calculate_joker({floated_card = true})
            break
        end
    end

    return next_card_spot
end

--Constable
SMODS.Joker {
    key = "constable",
    config = {
        extra = {
            should_stay_debuffed = false,
            last_prisoner = nil
        }
    },
    loc_txt = {
        name = 'Constable',
        text = { 'Disables {C:attention}Joker{} to the left.' },
    },
    rarity = 3,
    pos = { x = 5, y = 0 },
    atlas = "metro_jokers",
    cost = 7,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
          }
        }
    end,

    remove_from_deck = function(self, card, from_debuff)
        if card.ability.extra.last_prisoner then
            SMODS.debuff_card(card.ability.extra.last_prisoner, false, "j_metro_constable")
        end
        card.ability.extra.last_prisoner = nil
    end,

    updatePrisoner = function(card, other_joker)
        if card.ability.extra.last_prisoner and type(card.ability.extra.last_prisoner) == "table" then
            SMODS.debuff_card(card.ability.extra.last_prisoner, false, "j_metro_constable")
        end

        if other_joker then
            SMODS.debuff_card(other_joker, true, "j_metro_constable")
        end
        card.ability.extra.last_prisoner = other_joker
    end,

    update = function(self, card, dt)
        if not G or not G.jokers then return end
        if card.debuff then return end
        local position = -1

        for i = 1, #G.jokers.cards do
            if G.jokers.cards[i] == card then
                position = i
            end
        end

        local other_joker = nil

        if position > 1 then other_joker = G.jokers.cards[position - 1] end

        if other_joker ~= card.ability.extra.last_prisoner or other_joker ~= nil and not other_joker.debuff then
            self.updatePrisoner(card, other_joker)
        end
    end
}

--Grim Reaper
SMODS.Joker {
    key = "grim_reaper",
    config = {
        extra = {
            xmult = 3
        }
    },
    loc_txt = {
        name = 'Grim Reaper',
        text = { 'Played {C:attention}face cards{}', 'give {X:mult,C:white}x#1#{} Mult', 'then are {C:attention}destroyed{}'},
    },
    rarity = 3,
    pos = { x = 6, y = 0 },
    atlas = "metro_jokers",
    cost = 7,
    unlocked = true,
    discovered = true,
    blueprint_compat = true,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
            card.ability.extra.xmult
          }
        }
    end,

    calculate = function(self, card, context)
        if context.individual and context.cardarea == G.play and context.other_card:is_face() then
            return {
                card = card,
                xmult = card.ability.extra.xmult
            }
        end

        if context.destroy_card and context.cardarea == G.play and context.destroying_card:is_face() then
            return { 
                card = card,
                message = "Reaped!",
                sound = "slice1",
                colour = G.C.inactive,
                remove = true
            }
        end
    end,

    in_pool = function(self, args)
        return G.GAME.mr_bones_extinct == true, {}
    end
}

--Traffic Lights
--Because all played cards check jokers for effects at the same time, each stoplight needs to have all the logic for each other stoplight and keep track of 
--"which light" it is.

stoplight_calculate = function(self, card, context)
    if context.blueprint then return end
    local stoplight_keys = {"j_metro_green_light", "j_metro_yellow_light", "j_metro_red_light"}

    if context.cardarea == G.play and context.repetition and card.ability.extra.current_light == 2 then
        --If the card that turned us yellow is now asking for repetitions on the same rep it turned us, ignore
        if context.other_card == card.ability.extra.triggering_card and context.repetition_number == card.ability.extra.triggering_rep then return {} end
        card.ability.extra.triggering_card = nil
        card.ability.extra.triggering_rep = nil
        card.ability.extra.sped_card = context.other_card
        return {
            message = "Floor it!",
            repetitions = card.ability.extra.repetitions,
            card = card
        }
    end

    if context.cardarea == G.play and context.individual then
        -- If green light fails to trigger, don't jiggle or do anything
        if (card.ability.extra.current_light == 1 and pseudorandom('j_metro_green_light') >= G.GAME.probabilities.normal/card.ability.extra.odds) then
            return {}
        --If we're yellow light, only move on to next light color once our chosen "sped card" does its last repetition
        elseif card.ability.extra.current_light == 2 and (context.other_card ~= card.ability.extra.sped_card or context.other_card == card.ability.extra.sped_card and context.repetition_number < context.total_repetitions) then
            return {}
        end

        if card.ability.extra.current_light == 1 then
            card.ability.extra.triggering_card = context.other_card
            card.ability.extra.triggering_rep = context.repetition_number
        end

        local next_key = (card.ability.extra.current_light % 3) + 1

        local should_apply_debuff = card.ability.extra.current_light == 3

        local other_card = context.other_card

        G.E_MANAGER:add_event(Event({
            func = function()
                transform_joker(card, stoplight_keys[next_key])
                card:juice_up()
                -- Visually debuff card once red light becomes red light
                if (should_apply_debuff) then other_card.debuff = true end
                return true
            end
        }))

        card.ability.extra.current_light = next_key
        card.ability.extra.sped_card = nil

        return {
            debuff = should_apply_debuff,
            silence_debuff = true,
            card = card
        }
    end
end

--Generic card that stands in for others in the collection
--Never found in-game
SMODS.Joker {
    key = "traffic_light",
    config = {
        extra = {
            odds = 4.0,
            repetitions = 4
        }
    },
    loc_txt = {
        name = 'Traffic Light',
        text = { 'Switches between {C:green}Green Light,{}', '{C:attention}Yellow Light{}, and', '{C:red}Red Light{}'},
    },
    rarity = 2,
    pos = { x = 1, y = 0 },
    atlas = "metro_jokers",
    cost = 5,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        info_queue[#info_queue+1] = {key = 'o_short_green_light', set = 'Other'}
        info_queue[#info_queue+1] = {key = 'o_short_yellow_light', set = 'Other'}
        info_queue[#info_queue+1] = {key = 'o_short_red_light', set = 'Other'}
        return {
          vars = {
            G.GAME and G.GAME.probabilities.normal or 1,
            card.ability.extra.odds
          }
        }
    end,

    calculate = function(self, card, context)
        return stoplight_calculate(self, card, context)
    end,

    --If we ever get this card, immediately switch to green light
    add_to_deck = function(self, card, from_debuff)
        transform_joker(card, "j_metro_green_light")
    end,

    in_pool = function(self, args)
        return false, {}
    end
}

--Green Light
SMODS.Joker {
    key = "green_light",
    config = {
        extra = {
            current_light = 1,
            odds = 4.0,
            repetitions = 4
        }
    },
    loc_txt = {
        name = 'Green Light',
        text = { '{C:green}#1# in #2#{} chance to become', '{C:attention}Yellow Light{} when a', 'played card scores.'},
    },
    rarity = 2,
    pos = { x = 1, y = 0 },
    atlas = "metro_jokers",
    cost = 5,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,
    no_collection = true,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
            G.GAME and G.GAME.probabilities.normal or 1,
            card.ability.extra.odds
          }
        }
    end,

    calculate = function(self, card, context)
        return stoplight_calculate(self, card, context)
    end
}

--Yellow Light
SMODS.Joker {
    key = "yellow_light",
    config = {
        extra = {
            current_light = 2,
            odds = 4.0,
            repetitions = 4
        }
    },
    loc_txt = {
        name = 'Yellow Light',
        text = { 'Retrigger {C:attention}next{} played', 'card used in scoring', '{C:attention}#1#{} additional times,', 'then become {C:red}Red Light{}.' },
    },
    rarity = 2,
    pos = { x = 2, y = 0 },
    atlas = "metro_jokers",
    cost = 5,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,
    no_collection = true,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
            card.ability.extra.repetitions
          }
        }
    end,

    calculate = function(self, card, context)
        return stoplight_calculate(self, card, context)
    end,

    in_pool = function(self, args)
        return false, {}
    end
}

--Red Light
SMODS.Joker {
    key = "red_light",
    config = {
        extra = {
            current_light = 3,
            odds = 4.0,
            repetitions = 4
        }
    },
    loc_txt = {
        name = 'Red Light',
        text = { '{C:red}Debuff{} {C:attention}next{} played', 'card used in scoring,', 'then become {C:green}Green Light{}.'},
    },
    rarity = 2,
    pos = { x = 3, y = 0 },
    atlas = "metro_jokers",
    cost = 5,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,
    no_collection = true,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
          }
        }
    end,

    calculate = function(self, card, context)
        return stoplight_calculate(self, card, context)
    end,

    in_pool = function(self, args)
        return false, {}
    end
}

--Override SMODS.score_card for stoplight effects
SMODS.score_card = function(card, context)
    local reps = { 1 }
    local j = 1
    while j <= #reps do
        if reps[j] ~= 1 then
            local _, eff = next(reps[j])
            SMODS.calculate_effect(eff, eff.card)
            percent = percent + percent_delta
        end

        context.main_scoring = true
        local effects = { eval_card(card, context) }
        SMODS.calculate_quantum_enhancements(card, effects, context)
        context.main_scoring = nil
        context.individual = true
        context.other_card = card

        context.repetition_number = j
        context.total_repetitions = #reps

        local got_debuffed = false
        if next(effects) then
            for _, area in ipairs(SMODS.get_card_areas('jokers')) do
                for _, _card in ipairs(area.cards) do
                    --calculate the joker individual card effects
                    local eval, post = eval_card(_card, context)

                    if eval.jokers and eval.jokers.debuff then
                        if not eval.jokers.silence_debuff then scoring_hand[i].debuff = true end
                        got_debuffed = true
                        card_eval_status_text(card, 'debuff')
                        effects = {}
                        break
                    end

                    if next(eval) then
                        eval.juice_card = eval.card
                        table.insert(effects, eval)
                        for _, v in ipairs(post) do effects[#effects+1] = v end
                        if eval.retriggers then
                            context.retrigger_joker = true
                            for rt = 1, #eval.retriggers do
                                local rt_eval, rt_post = eval_card(_card, context)
                                table.insert(effects, { eval.retriggers[rt] })
                                table.insert(effects, rt_eval)
                                for _, v in ipairs(rt_post) do effects[#effects+1] = v end
                            end
                            context.retrigger_joker = nil
                        end
                    end
                end
            end
        end

        if got_debuffed then break end

        SMODS.trigger_effects(effects, card)
        local deck_effect = G.GAME.selected_back:trigger_effect(context)
        if deck_effect then SMODS.calculate_effect(deck_effect, G.deck.cards[1] or G.deck) end

        context.individual = nil
        if reps[j] == 1 and effects.calculated then
            context.repetition = true
            context.card_effects = effects
            SMODS.calculate_repetitions(card, context, reps)
            context.repetition = nil
            context.card_effects = nil
        end
        j = j + (effects.calculated and 1 or #reps)
        context.other_card = nil
        card.lucky_trigger = nil
        context.repetition_number = nil
        context.total_repetitions = nil
    end
    card.extra_enhancements = nil
end

--Metro Card
SMODS.Joker {
    key = "metro_card",
    config = {
        extra = {
            cash_increment = 1,
            loaded_cash = 0,
            cash_maximum = 100
        }
    },
    loc_txt = {
        name = 'Metro Card',
        text = { 'Click to load {C:money}cash{}', 'Whenever a card is drawn,', 'draw a {C:green}Face Card{} if able', 'and spend ${C:attention}#1#{} of loaded {C:money}cash{}', '{C:inactive}(Currently ${C:attention}#2#{C:inactive}){}' },
    },
    rarity = 2,
    pos = { x = 4, y = 0 },
    atlas = "metro_jokers",
    cost = 1,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
            card.ability.extra.cash_increment,
            card.ability.extra.loaded_cash,
            card.ability.extra.cash_maximum
          }
        }
    end,

    calculate = function(self, card, context)
        if context.blueprint then return end
        if context.drawing_cards and context.floating_card and card.ability.extra.loaded_cash >= card.ability.extra.cash_increment then
            return {
                card = card,
                should_float = true,
                func = function(candidate)
                    return candidate:is_face()
                end
                }
        end

        if context.floated_card then
            card.ability.extra.loaded_cash = card.ability.extra.loaded_cash - card.ability.extra.cash_increment
            --TODO: add money sounds
            return {card = card}
        end
    end
}

G.FUNCS.can_load_metro_card = function(e)
    local card = e.config.ref_table
    local amount = G.GAME.dollars - G.GAME.bankrupt_at
    if amount >= card.ability.extra.cash_increment and card.ability.extra.loaded_cash < card.ability.extra.cash_maximum then
        e.config.colour = G.C.MONEY
        e.config.button = 'load_metro_card'
    else
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

G.FUNCS.load_metro_card = function(e)
    local card = e.config.ref_table
    G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2,func = function()
        card:juice_up(0.3, 0.4)
        return true
    end}))
    G.E_MANAGER:add_event(Event({func = function()
        ease_dollars(-card.ability.extra.cash_increment)
        return true
    end}))
    card.ability.extra.loaded_cash = card.ability.extra.loaded_cash + card.ability.extra.cash_increment

    local new_amount = G.GAME.dollars - G.GAME.bankrupt_at
    if new_amount < card.ability.extra.cash_increment or card.ability.extra.loaded_cash >= card.ability.extra.cash_maximum then
        e.config.colour = G.C.UI.BACKGROUND_INACTIVE
        e.config.button = nil
    end
end

--Protanopia
SMODS.Joker {
    key = "protanopia",
    config = {
        extra = {
        }
    },
    loc_txt = {
        name = 'Protanopia',
        text = { '{C:red}Red Seals{} and {C:money}Gold Seals{}', 'count as each other', '{C:blue}Blue Seals{} and {C:purple}Purple Seals{}', 'count as each other' },
    },
    rarity = 3,
    pos = { x = 9, y = 0 },
    atlas = "metro_jokers",
    cost = 6,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
          }
        }
    end
}

--Jack-O-Lantern
SMODS.Joker {
    key = "jack_o_lantern",
    config = {
        extra = {
            chip_scaler = 10
        }
    },
    loc_txt = {
        name = 'Jack-O-Lantern',
        text = { 'Each {C:attention}Jack{} held', 'in hand gives {C:chips}+#1# chips{}', 'per card in {C:inactive}Graveyard{}', '{C:inactive}(currently {C:chips}+#2#{C:inactive}){}'},
    },
    rarity = 2,
    pos = { x = 7, y = 0 },
    atlas = "metro_jokers",
    cost = 5,
    unlocked = true,
    discovered = true,
    blueprint_compat = true,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        info_queue[#info_queue+1] = {key = 'o_graveyard', set = 'Other'}
        return {
          vars = {
            card.ability.extra.chip_scaler,
            card.ability.extra.chip_scaler * (G.graveyard and #G.graveyard.cards or 0.0)
          }
        }
    end,

    calculate = function(self, card, context)
        if context.cardarea == G.hand and not context.end_of_round == true and context.individual and context.other_card and context.other_card:get_id() == 11 then
            return {
                card = card,
                chips = card.ability.extra.chip_scaler * (G.graveyard and #G.graveyard.cards or 0.0)
            }
        end
    end
}

--Mistigris
SMODS.Joker {
    key = "mistigris",
    config = {
        extra = {
        }
    },
    loc_txt = {
        name = 'Mistigris',
        text = { '{C:attention}Jacks{} count as', '{C:attention}any card{} for', 'making poker hands'},
    },
    rarity = 3,
    pos = { x = 8, y = 0 },
    atlas = "metro_jokers",
    cost = 7,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
          }
        }
    end
}

-- Can't patch this cause it's in SMODS
-- But we can do this instead
function metro_get_straight(hand)
	local ret = {}
	local four_fingers = next(SMODS.find_card('j_four_fingers'))
	local can_skip = next(SMODS.find_card('j_shortcut'))
    local mistigris = next(SMODS.find_card('j_metro_mistigris'))
	if #hand < (5 - (four_fingers and 1 or 0)) then return ret end
	local t = {}
	local RANKS = {}
	for i = 1, #hand do
		if hand[i]:get_id() > 0 then
			local rank = hand[i].base.value
            RANKS[rank] = RANKS[rank] or {}
            RANKS[rank][#RANKS[rank] + 1] = hand[i]
		end
	end
	local straight_length = 0
	local straight = false
	local skipped_rank = false
	local vals = {}
	for k, v in pairs(SMODS.Ranks) do
		if v.straight_edge then
			table.insert(vals, k)
		end
	end
	local init_vals = {}
	for _, v in ipairs(vals) do
		init_vals[v] = true
	end
	if not next(vals) then table.insert(vals, 'Ace') end
	local initial = true
	local br = false
	local end_iter = false
	local i = 0
    local next_usable_jack = 1
	while 1 do
		end_iter = false
		if straight_length >= (5 - (four_fingers and 1 or 0)) then
			straight = true
		end
		i = i + 1
        -- Effectively turns this infinite loop into for i = 1, #SMODS.Rank
		if br or (i > #SMODS.Rank.obj_buffer + 1) then break end
		if not next(vals) then break end
		for _, val in ipairs(vals) do
            -- vals starts out as equal to edges
			if init_vals[val] and not initial then br = true end
			if RANKS[val] or (mistigris and RANKS['Jack'] and RANKS['Jack'][next_usable_jack] and (not init_vals[val]) ) then

                if (val ~= 'Jack' or RANKS['Jack'][next_usable_jack]) then
                    -- Runs for each card inserted into RANKS
                    straight_length = straight_length + 1
                    skipped_rank = false

                    if RANKS[val] then
                        for _, vv in ipairs(RANKS[val]) do
                            t[#t + 1] = vv
                        end
                        if val == 'Jack' then
                            next_usable_jack = next_usable_jack + 1
                        end
                    else
                        t[#t + 1] = RANKS['Jack'][next_usable_jack]
                        next_usable_jack = next_usable_jack + 1
                    end
                    vals = SMODS.Ranks[val].next
                    initial = false
                    end_iter = true
                    break
                end
			end
		end
		if not end_iter then
			local new_vals = {}
			for _, val in ipairs(vals) do
				for _, r in ipairs(SMODS.Ranks[val].next) do
					table.insert(new_vals, r)
				end
			end
			vals = new_vals
			if can_skip and not skipped_rank then
				skipped_rank = true
			else
				straight_length = 0
				skipped_rank = false
                next_usable_jack = 1
				if not straight then t = {} end
				if straight then break end -- Only happens when we actually have a straight
			end
		end
	end
	if not straight then return ret end
	table.insert(ret, t)
	return ret
end

SMODS.PokerHandParts['_straight'].func = function(hand) return metro_get_straight(hand) end

--Same thing here
SMODS.PokerHands['Full House'].evaluate = function(parts)
    if #parts._3 < 1 or #parts._2 < 2 then return {} end

    --Make sure the same card isn't being counted for multiple parts in the full house
    local requisite_non_matching = false
    for k3, v3 in ipairs(parts._3) do
        for k2, v2 in ipairs(parts._2) do
            local unmatched_cards = 0
            for y = 1, #v2 do
                local no_match = true
                for x = 1, #v3 do
                    if v3[x] == v2[y] then no_match = false end
                end
                if no_match then unmatched_cards = unmatched_cards + 1 end
            end
            requisite_non_matching = ( unmatched_cards >= 2 ) or requisite_non_matching
        end
    end

    if not requisite_non_matching then return {} end

    return parts._all_pairs
end

--Same thing here
SMODS.PokerHands['Flush House'].evaluate = function(parts)
    if #parts._3 < 1 or #parts._2 < 2 or not next(parts._flush) then return {} end

    --Make sure the same card isn't being counted for multiple parts in the full house
    local requisite_non_matching = false
    for k3, v3 in ipairs(parts._3) do
        for k2, v2 in ipairs(parts._2) do
            local unmatched_cards = 0
            for y = 1, #v2 do
                local no_match = true
                for x = 1, #v3 do
                    if v3[x] == v2[y] then no_match = false end
                end
                if no_match then unmatched_cards = unmatched_cards + 1 end
            end
            requisite_non_matching = ( unmatched_cards >= 2 ) or requisite_non_matching
        end
    end

    if not requisite_non_matching then return {} end

    return { SMODS.merge_lists(parts._all_pairs, parts._flush) }
end

get_first_hand = function(hand_name, size)
    size = size or 5
    local parts = {}
	for _, v in ipairs(SMODS.PokerHandPart.obj_buffer) do
		parts[v] = SMODS.PokerHandParts[v].func(G.deck.cards) or {}
	end
    local hand_data = SMODS.PokerHands[hand_name].evaluate(parts)

    hand_data = hand_data or {}

    -- Shuffle parts so we don't always get the highest one
    pseudoshuffle(hand_data, 783740073720)

    local big_list = SMODS.merge_lists(hand_data)

    for i = 1, #big_list - size + 1 do
        local cards = {}
        for j = 0, size - 1 do
            cards[#cards + 1] = big_list[i + j]
        end
        local new_parts = {}
        for _, v in ipairs(SMODS.PokerHandPart.obj_buffer) do
            new_parts[v] = SMODS.PokerHandParts[v].func(cards) or {}
        end
        local new_hand = SMODS.merge_lists(SMODS.PokerHands[hand_name].evaluate(new_parts))

        if #new_hand > 0 then return new_hand end
    end

    return {}
end

one_two_punch_hands = {"High Card", "Pair", "Three of a Kind", "Four of a Kind", "Five of a Kind"}

--One-Two Punch
SMODS.Joker {
    key = "one_two_punch",
    config = {
        extra = {
            current_req_hand = 1,
            card_queue = {}
        }
    },
    loc_txt = {
        name = 'One-Two Punch',
        text = { 'If {C:attention}first{} played hand in blind', 'is a {C:green}#1#{},', 'draw a {C:green}#2#{}', '{C:attention}Next first hand{} must be a', 'a {C:green}#2#{}', '{C:inactive}(Resets if combo is broken){}'},
    },
    rarity = 1,
    pos = { x = 0, y = 1 },
    atlas = "metro_jokers",
    cost = 4,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
            one_two_punch_hands[card.ability.extra.current_req_hand],
            one_two_punch_hands[( card.ability.extra.current_req_hand + 1 <= #one_two_punch_hands and G.GAME.hands[one_two_punch_hands[card.ability.extra.current_req_hand + 1]].visible) and card.ability.extra.current_req_hand + 1 or card.ability.extra.current_req_hand]
          }
        }
    end,

    calculate = function(self, card, context)
        if context.blueprint then return end


        if context.final_scoring_step and G.GAME.current_round and G.GAME.current_round.hands_played == 0 then
            if G.GAME.last_hand_played == one_two_punch_hands[card.ability.extra.current_req_hand] then
                card.ability.extra.current_req_hand = ( card.ability.extra.current_req_hand + 1 <= #one_two_punch_hands and G.GAME.hands[one_two_punch_hands[card.ability.extra.current_req_hand + 1]].visible) and card.ability.extra.current_req_hand + 1 or card.ability.extra.current_req_hand
                if #context.full_hand >= card.ability.extra.current_req_hand then
                    card.ability.extra.card_queue = get_first_hand(one_two_punch_hands[card.ability.extra.current_req_hand], card.ability.extra.current_req_hand)
                end
            else
                if card.ability.extra.current_req_hand > 1 then
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            play_sound('other1')
                            attention_text({
                                text = 'Reset!',
                                scale = 1, 
                                hold = 0.2,
                                backdrop_colour = G.C.White,
                                align = 'bm',
                                major = card,
                                offset = {x = 0, y = 0.05*card.T.h}
                            })
                            card:juice_up()
                            return true
                        end,
                        blocking = false
                    }))
                end
                card.ability.extra.current_req_hand = 1
            end
        end

        if context.drawing_cards and context.floating_card and G.GAME.current_round and G.GAME.current_round.hands_played == 1 then
            if #card.ability.extra.card_queue < 1 then return {card = card, should_float = false} end
            return {
                card = card,
                should_float = true,
                func = function(candidate)
                    if card.ability.extra.card_queue[1] == candidate then
                        table.remove(card.ability.extra.card_queue, 1)
                        return true 
                    end
                    return false
                end
            }
        end

        if context.floated_card then
            local index = 0
            return {card = card}
        end

        if context.hand_drawn then
            card.ability.extra.card_queue = {}
        end
    end
}

--Desperado
SMODS.Joker {
    key = "desperado",
    config = {
        extra = {
            sell_value_scalar = 3
        }
    },
    loc_txt = {
        name = 'Desperado',
        text = {'Gains {C:money}$#1#{} of sell value', 'whenever a played card {C:attention}scores{}', 'Resets at {C:attention}end of round{}'},
    },
    rarity = 1,
    pos = { x = 0, y = 0 },
    atlas = "metro_jokers",
    cost = 4,
    unlocked = true,
    discovered = true,
    blueprint_compat = false,
    eternal_compat = true,
    soul_pos = nil,

    loc_vars = function(self, info_queue, card)
        return {
          vars = {
            card.ability.extra.sell_value_scalar
          }
        }
    end,

    calculate = function(self, card, context)
        if context.blueprint then return end
        if context.individual and context.cardarea == G.play then
            card.ability.extra_value = card.ability.extra_value + card.ability.extra.sell_value_scalar
            card:set_cost()
            return {
                message = localize('k_val_up'),
                message_card = card,
                colour = G.C.MONEY,
                card = card
            }
        end

        if context.end_of_round and context.cardarea == G.jokers then
            card.ability.extra_value = 0
            card:set_cost()
            return {
                message = localize('k_reset'),
                colour = G.C.RED,
                card = card
            }
        end
    end
}