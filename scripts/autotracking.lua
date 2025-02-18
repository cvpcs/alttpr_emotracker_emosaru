-- Configuration --------------------------------------
AUTOTRACKER_ENABLE_DEBUG_LOGGING = false
-------------------------------------------------------

print("")
print("Active Auto-Tracker Configuration")
print("---------------------------------------------------------------------")
print("Enable Item Tracking:        ", AUTOTRACKER_ENABLE_ITEM_TRACKING)
print("Enable Location Tracking:    ", AUTOTRACKER_ENABLE_LOCATION_TRACKING)
if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
    print("Enable Debug Logging:        ", "true")
end
print("---------------------------------------------------------------------")
print("")

function autotracker_started()
    -- Invoked when the auto-tracker is activated/connected
end

AUTOTRACKER_IS_IN_TRIFORCE_ROOM = false
AUTOTRACKER_HAS_DONE_POST_GAME_SUMMARY = false
AUTOTRACKER_DUNGEON_REWARDS_SET = false
AUTOTRACKER_DUNGEON_MEDALLIONS_SET = false

U8_READ_CACHE = 0
U8_READ_CACHE_ADDRESS = 0

U16_READ_CACHE = 0
U16_READ_CACHE_ADDRESS = 0

function InvalidateReadCaches()
    U8_READ_CACHE_ADDRESS = 0
    U16_READ_CACHE_ADDRESS = 0
end

function ReadU8(segment, address)
    if U8_READ_CACHE_ADDRESS ~= address then
        U8_READ_CACHE = segment:ReadUInt8(address)
        U8_READ_CACHE_ADDRESS = address        
    end

    return U8_READ_CACHE
end

function ReadU16(segment, address)
    if U16_READ_CACHE_ADDRESS ~= address then
        U16_READ_CACHE = segment:ReadUInt16(address)
        U16_READ_CACHE_ADDRESS = address        
    end

    return U16_READ_CACHE
end

function isInGame()
    return AutoTracker:ReadU8(0x7e0010, 0) > 0x05
end

function updateInGameStatusFromMemorySegment(segment)

    local mainModuleIdx = segment:ReadUInt8(0x7e0010)

    local wasInTriforceRoom = AUTOTRACKER_IS_IN_TRIFORCE_ROOM
    AUTOTRACKER_IS_IN_TRIFORCE_ROOM = (mainModuleIdx == 0x19 or mainModuleIdx == 0x1a)

    if AUTOTRACKER_IS_IN_TRIFORCE_ROOM and not wasInTriforceRoom then
        ScriptHost:AddMemoryWatch("LTTP Statistics", 0x7ef420, 0x46, updateStatisticsFromMemorySegment)
    end

    if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
        if mainModuleIdx > 0x05 then
            print("Current Room Index: ", segment:ReadUInt16(0x7e00a0))
            print("Current OW   Index: ", segment:ReadUInt16(0x7e008a))
        end
        return false
    end

    return true
end

function updateProgressiveItemFromByte(segment, code, address, offset)
    local item = Tracker:FindObjectForCode(code)
    if item then
        local value = ReadU8(segment, address)
        item.CurrentStage = value + (offset or 0)
    end
end

function updateAga1(segment)
    local item = Tracker:FindObjectForCode("aga1")
    local value = ReadU8(segment, 0x7ef3c5)
    if value >= 3 then
        item.Active = true
    else
        item.Active = false
    end
end

function testFlag(segment, address, flag)
    local value = ReadU8(segment, address)
    local flagTest = value & flag

    if flagTest ~= 0 then
        return true
    else
        return false
    end    
end

function updateProgressiveBow(segment)
    local item = Tracker:FindObjectForCode("bowandarrows")    
    if testFlag(segment, 0x7ef38e, 0x40) then
        item.CurrentStage = 2
    elseif testFlag(segment, 0x7ef38e, 0x80) then
        item.CurrentStage = 1
    else
        item.CurrentStage = 0
    end
end

function updateBottles(segment)
    local item = Tracker:FindObjectForCode("bottle")    
    local count = 0
    for i = 0, 3, 1 do
        if ReadU8(segment, 0x7ef35c + i) > 0 then
            count = count + 1
        end
    end
    item.CurrentStage = count
end

function updateToggleItemFromByte(segment, code, address)
    local item = Tracker:FindObjectForCode(code)
    if item then
        local value = ReadU8(segment, address)
        if value > 0 then
            item.Active = true
        else
            item.Active = false
        end
    end
end

function updateToggleItemFromByteAndFlag(segment, code, address, flag)
    local item = Tracker:FindObjectForCode(code)
    if item then
        local value = ReadU8(segment, address)
        if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
            print(item.Name, code, flag)
        end

        local flagTest = value & flag

        if flagTest ~= 0 then
            item.Active = true
        else
            item.Active = false
        end
    end
end

function updateToggleFromRoomSlot(segment, code, slot)
    local item = Tracker:FindObjectForCode(code)
    if item then
        local roomData = ReadU16(segment, 0x7ef000 + (slot[1] * 2))
        
        if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
            print(roomData)
        end

        item.Active = (roomData & (1 << slot[2])) ~= 0
    end
end

function updateFlute(segment)
    local item = Tracker:FindObjectForCode("flute")
    local value = ReadU8(segment, 0x7ef38c)

    local fakeFlute = value & 0x02
    local realFlute = value & 0x01

    if realFlute ~= 0 then
        item.Active = true
        item.CurrentStage = 1
    elseif fakeFlute ~= 0 then
        item.Active = true
        item.CurrentStage = 0
    else
        item.Active = false
    end
end

function updateConsumableItemFromByte(segment, code, address)
    local item = Tracker:FindObjectForCode(code)
    if item then
        local value = ReadU8(segment, address)
        item.AcquiredCount = value
    else
        print("Couldn't find item: ", code)
    end
end

function updatePseudoProgressiveItemFromByteAndFlag(segment, code, address, flag, locationCode)
    local item = Tracker:FindObjectForCode(code)
    if item then
        local value = ReadU8(segment, address)
        local flagTest = value & flag

        local isCleared = false
        if locationCode then
            local location = Tracker:FindObjectForCode(locationCode)
            if location then
                if location.AvailableChestCount == 0 then
                    isCleared = true
                end
            end
        end

        if isCleared then
            item.CurrentStage = math.max(2, item.CurrentStage)
        elseif flagTest ~= 0 then
            item.CurrentStage = math.max(1, item.CurrentStage)
        else
            item.CurrentStage = 0
        end    
    end
end

function updateSectionChestCountFromByteAndFlag(segment, locationRef, address, flag, callback)
    local location = Tracker:FindObjectForCode(locationRef)
    if location then
        -- Do not auto-track this the user has manually modified it
        if location.Owner.ModifiedByUser then
            return
        end

        local value = ReadU8(segment, address)
        
        if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
            print(locationRef, value)
        end

        if (value & flag) ~= 0 then
            location.AvailableChestCount = 0
            if callback then
                callback(true)
            end
        else
            location.AvailableChestCount = location.ChestCount
            if callback then
                callback(false)
            end
        end
    elseif AUTOTRACKER_ENABLE_DEBUG_LOGGING then
        print("Couldn't find location", locationRef)
    end
end

function updateSectionChestCountFromOverworldIndexAndFlag(segment, locationRef, index, callback)
    updateSectionChestCountFromByteAndFlag(segment, locationRef, 0x7ef280 + index, 0x40, callback)
end

function updateSectionChestCountFromRoomSlotList(segment, locationRef, roomSlots, callback)
    local location = Tracker:FindObjectForCode(locationRef)
    if location then
        -- Do not auto-track this the user has manually modified it
        if location.Owner.ModifiedByUser then
            return
        end

        local clearedCount = 0
        for i,slot in ipairs(roomSlots) do
            local roomData = ReadU16(segment, 0x7ef000 + (slot[1] * 2))

            if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
                print(locationRef, roomData, 1 << slot[2])
            end
                
            if (roomData & (1 << slot[2])) ~= 0 then
                clearedCount = clearedCount + 1
            end
        end

        location.AvailableChestCount = location.ChestCount - clearedCount

        if callback then
            callback(clearedCount > 0)
        end
    end
end

function updateBombIndicatorStatus(status)
    local item = Tracker:FindObjectForCode("bombs")
    if item then
        if status then
            item.CurrentStage = 1
        else
            item.CurrentStage = 0
        end
    end
end

function updateBatIndicatorStatus(status)
    local item = Tracker:FindObjectForCode("powder")
    if item then
        if status then
            item.CurrentStage = 1
        else
            item.CurrentStage = 0
        end
    end
end

function updateShovelIndicatorStatus(status)
    local item = Tracker:FindObjectForCode("shovel")
    if item then
        if status then
            item.CurrentStage = 1
        else
            item.CurrentStage = 0
        end
    end
end

function updateMushroomStatus(status)
    local item = Tracker:FindObjectForCode("mushroom")
    if item then
        if status then
            item.CurrentStage = 1
        else
            item.CurrentStage = 0
        end
    end
end

function updateNPCItemFlagsFromMemorySegment(segment)

    if not isInGame() then
        return false
    end

    if not AUTOTRACKER_ENABLE_LOCATION_TRACKING then
        return true
    end

    InvalidateReadCaches()

    updateSectionChestCountFromByteAndFlag(segment, "@Old Man/Bring Him Home", 0x7ef410, 0x01)
    updateSectionChestCountFromByteAndFlag(segment, "@Zora Area/King Zora", 0x7ef410, 0x02)
    updateSectionChestCountFromByteAndFlag(segment, "@Sick Kid/By The Bed", 0x7ef410, 0x04)
    updateSectionChestCountFromByteAndFlag(segment, "@Haunted Grove/Stumpy", 0x7ef410, 0x08)
    updateSectionChestCountFromByteAndFlag(segment, "@Sahasrala's Hut/Shabbadoo", 0x7ef410, 0x10)
    updateSectionChestCountFromByteAndFlag(segment, "@Catfish/Ring of Stones", 0x7ef410, 0x20)
    -- 0x40 is unused
    updateSectionChestCountFromByteAndFlag(segment, "@Library/On The Shelf", 0x7ef410, 0x80)

    updateSectionChestCountFromByteAndFlag(segment, "@Ether Tablet/Tablet", 0x7ef411, 0x01)
    updateSectionChestCountFromByteAndFlag(segment, "@Bombos Tablet/Tablet", 0x7ef411, 0x02)
    updateSectionChestCountFromByteAndFlag(segment, "@Dwarven Smiths/Bring Him Home", 0x7ef411, 0x04)
    -- 0x08 is no longer relevant
    updateSectionChestCountFromByteAndFlag(segment, "@Lost Woods/Mushroom Spot", 0x7ef411, 0x10)
    updateSectionChestCountFromByteAndFlag(segment, "@Witch's Hut/Assistant", 0x7ef411, 0x20, updateMushroomStatus)
    -- 0x40 is unused
    updateSectionChestCountFromByteAndFlag(segment, "@Magic Bat/Magic Bowl", 0x7ef411, 0x80, updateBatIndicatorStatus)    

end

function updateOverworldEventsFromMemorySegment(segment)
    
    if not isInGame() then
        return false
    end

    if not AUTOTRACKER_ENABLE_LOCATION_TRACKING then
        return true
    end    

    InvalidateReadCaches()

    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Spectacle Rock/Up On Top",              3)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Floating Island/Island",                5)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Race Game/Take This Trash",             40)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Grove Digging Spot/Hidden Treasure",    42, updateShovelIndicatorStatus)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Desert Ledge/Ledge",                    48)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Lake Hylia Island/Island",              53)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Dam/Outside",                           59)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Bumper Cave/Ledge",                     74)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Pyramid Ledge/Ledge",                   91)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Digging Game/Dig For Treasure",         104)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Master Sword Pedestal/Pedestal",        128)    
    updateSectionChestCountFromOverworldIndexAndFlag(segment, "@Zora Area/Ledge",                       129)    
end

function updateRoomsFromMemorySegment(segment)

    if not isInGame() then
        return false
    end

    InvalidateReadCaches()

    if AUTOTRACKER_ENABLE_ITEM_TRACKING then
        updateToggleFromRoomSlot(segment, "ep", { 200, 11 })
        updateToggleFromRoomSlot(segment, "dp", { 51, 11 })
        updateToggleFromRoomSlot(segment, "toh", { 7, 11 })
        updateToggleFromRoomSlot(segment, "pod", { 90, 11 })
        updateToggleFromRoomSlot(segment, "sp", { 6, 11 })
        updateToggleFromRoomSlot(segment, "sw", { 41, 11 })
        updateToggleFromRoomSlot(segment, "tt", { 172, 11 })
        updateToggleFromRoomSlot(segment, "ip", { 222, 11 })
        updateToggleFromRoomSlot(segment, "mm", { 144, 11 })
        updateToggleFromRoomSlot(segment, "tr", { 164, 11 })
    end

    if not AUTOTRACKER_ENABLE_LOCATION_TRACKING then
        return true
    end    

    -- updateSectionChestCountFromRoomSlotList(segment, "@Link's House/By The Door", { { 0, 10 } })
    updateSectionChestCountFromRoomSlotList(segment, "@The Well/Cave", { { 47, 5 }, { 47, 6 }, { 47, 7 }, { 47, 8 } })
    updateSectionChestCountFromRoomSlotList(segment, "@The Well/Bombable Wall", { { 47, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Hookshot Cave/Bonkable Chest", { { 60, 7 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Hookshot Cave/Back", { { 60, 4 }, { 60, 5 }, { 60, 6 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Castle Secret Entrance/Hallway", { { 85, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Lost Woods/Forest Hideout", { { 225, 9 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Lumberjack Cave/Cave", { { 226, 9 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Spectacle Rock/Cave", { { 234, 10 } })        
    updateSectionChestCountFromRoomSlotList(segment, "@Paradox Cave/Top", { { 239, 4 }, { 239, 5 }, { 239, 6 }, { 239, 7 }, { 239, 8 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Super-Bunny Cave/Cave", { { 248, 4 }, { 248, 5 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Spiral Cave/Cave", { { 254, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Paradox Cave/Bottom", { { 255, 4 }, { 255, 5 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Tavern/Back Room", { { 259, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Link's House/By The Door", { { 260, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Sahasrala's Hut/Back Room", { { 261, 4 }, { 261, 5 }, { 261, 6 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Bombable Shack/Downstairs", { { 262, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Treasure Game/Prize", { { 262, 10 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Chicken House/Bombable Wall", { { 264, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Aginah's Cave/Cave", { { 266, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Dam/Inside", { { 267, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Mimic Cave/Cave", { { 268, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Mire Shack/Shack", { { 269, 4 }, { 269, 5 } })
    updateSectionChestCountFromRoomSlotList(segment, "@King's Tomb/The Crypt", { { 275, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Waterfall Fairy/Waterfall Cave", { { 276, 4 }, { 276, 5 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Fat Fairy/Big Bomb Spot", { { 278, 4 }, { 278, 5 } }, updateBombIndicatorStatus)
    updateSectionChestCountFromRoomSlotList(segment, "@Spike Cave/Cave", { { 279, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Graveyard Ledge/Cave", { { 283, 9 } })
    updateSectionChestCountFromRoomSlotList(segment, "@South of Grove/Circle of Bushes", { { 283, 10 } })
    updateSectionChestCountFromRoomSlotList(segment, "@C-Shaped House/House", { { 284, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Blind's House/Basement", { { 285, 5 }, { 285, 6 }, { 285, 7 }, { 285, 8 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Blind's House/Bombable Wall", { { 285, 4 } })   
    updateSectionChestCountFromRoomSlotList(segment, "@Hype Cave/Cave", { { 286, 4 }, { 286, 5 }, { 286, 6 }, { 286, 7 }, { 286, 10 } }) 
    updateSectionChestCountFromRoomSlotList(segment, "@Ice Rod Cave/Cave", { { 288, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Mini Moldorm Cave/Cave", { { 291, 4 }, { 291, 5 }, { 291, 6 }, { 291, 7 }, { 291, 10 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Bonk Rocks/Cave", { { 292, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Checkerboard Cave/Cave", { { 294, 9 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Hammer Pegs/Cave", { { 295, 10 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Sanctuary/Back", { { 18, 4 } })

    -- dungeons
    updateSectionChestCountFromRoomSlotList(segment, "@Hyrule Castle/Dungeon", { { 114, 4 }, { 113, 4 }, { 128, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Hyrule Castle/Sewer Dark Cross", { { 50, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Hyrule Castle/Sewer Bombable Wall", { { 17, 4 }, { 17, 5 }, { 17, 6 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Eastern Palace/Dungeon", { { 185, 4 }, { 170, 4 }, { 168, 4 }, { 169, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Eastern Palace/Anti-Fairies", { { 184, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Eastern Palace/Armos", { { 200, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Desert Palace/Dungeon", { { 116, 4 }, { 133, 4 }, { 117, 4 }, { 115, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Desert Palace/Torch", { { 115, 10 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Desert Palace/Lanmolas", { { 51, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Tower of Hera/Dungeon", { { 119, 4 }, { 135, 10 }, { 39, 5 }, { 39, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Tower of Hera/Basement", { { 135, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Tower of Hera/Moldorm", { { 7, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Palace of Darkness/Dungeon", { { 9, 4 }, { 42, 5 }, { 10, 4 }, { 26, 5 }, { 26, 6 }, { 58, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Palace of Darkness/Bow Side", { { 43, 4 }, { 42, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Palace of Darkness/Dark Rooms", { { 25, 4 }, { 25, 5 }, { 26, 4 }, { 106, 4 }, { 106, 5 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Palace of Darkness/Helmasaur King", { { 90, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Swamp Palace/Dungeon", { { 40, 4 }, { 55, 4 }, { 70, 4 }, { 52, 4 }, { 53, 4 }, { 54, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Swamp Palace/Back", { { 118, 4 }, { 118, 5 }, { 102, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Swamp Palace/Arrgus", { { 6, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Skull Woods/Dungeon", { { 103, 4 }, { 87, 5 }, { 88, 5 }, { 104, 4 }, { 87, 4 }, { 88, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Skull Woods/Back", { { 89, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Skull Woods/Mothula", { { 41, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Thieves Town/Dungeon", { { 219, 4 }, { 203, 4 }, { 220, 4 }, { 219, 5 }, { 101, 4 }, { 69, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Thieves Town/Big Chest", { { 68, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Thieves Town/Blind", { { 172, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Ice Palace/Dungeon", { { 46, 4 }, { 63, 4 }, { 126, 4 }, { 174, 4 }, { 158, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Ice Palace/Spikes", { { 95, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Ice Palace/Moles", { { 31, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Ice Palace/Khold", { { 222, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Misery Mire/Dungeon", { { 162, 4 }, { 194, 4 }, { 193, 4 }, { 195, 5 }, { 195, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Misery Mire/Spikes", { { 179, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Misery Mire/Torch Cutscene", { { 209, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Misery Mire/Vitreous", { { 144, 11 } })

    updateSectionChestCountFromRoomSlotList(segment, "@Turtle Rock/Dungeon", { { 214, 4 }, { 182, 4 }, { 20, 4 }, { 36, 4 }, { 4, 4 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Turtle Rock/Roller Room", { { 183, 4 }, { 183, 5 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Turtle Rock/Laser Bridge", { { 213, 4 }, { 213, 5 }, { 213, 6 }, { 213, 7 } })
    updateSectionChestCountFromRoomSlotList(segment, "@Turtle Rock/Trinexx", { { 164, 11 } })

end

function updateItemsFromMemorySegment(segment)

    if not isInGame() then
        return false
    end

    InvalidateReadCaches()

    if AUTOTRACKER_ENABLE_ITEM_TRACKING then

        updateProgressiveItemFromByte(segment, "sword",  0x7ef359, 1)
        updateProgressiveItemFromByte(segment, "shield", 0x7ef35a, 0)
        updateProgressiveItemFromByte(segment, "armor",  0x7ef35b, 0)
        updateProgressiveItemFromByte(segment, "gloves", 0x7ef354, 0)

        updateToggleItemFromByte(segment, "hookshot",  0x7ef342)
        updateToggleItemFromByte(segment, "bombs",     0x7ef343)
        updateToggleItemFromByte(segment, "firerod",   0x7ef345)
        updateToggleItemFromByte(segment, "icerod",    0x7ef346)
        updateToggleItemFromByte(segment, "bombos",    0x7ef347)
        updateToggleItemFromByte(segment, "ether",     0x7ef348)
        updateToggleItemFromByte(segment, "quake",     0x7ef349)
        updateToggleItemFromByte(segment, "lamp",      0x7ef34a)
        updateToggleItemFromByte(segment, "hammer",    0x7ef34b)
        updateToggleItemFromByte(segment, "net",       0x7ef34d)
        updateToggleItemFromByte(segment, "book",      0x7ef34e)
        updateToggleItemFromByte(segment, "somaria",   0x7ef350)
        updateToggleItemFromByte(segment, "byrna",     0x7ef351)
        updateToggleItemFromByte(segment, "cape",      0x7ef352)
        updateToggleItemFromByte(segment, "boots",     0x7ef355)
        updateToggleItemFromByte(segment, "flippers",  0x7ef356)
        updateToggleItemFromByte(segment, "pearl",     0x7ef357)
        updateToggleItemFromByte(segment, "halfmagic", 0x7ef37b)

        updateToggleItemFromByteAndFlag(segment, "blue_boomerang", 0x7ef38c, 0x80)
        updateToggleItemFromByteAndFlag(segment, "red_boomerang",  0x7ef38c, 0x40)
        updateToggleItemFromByteAndFlag(segment, "shovel", 0x7ef38c, 0x04)
        updateToggleItemFromByteAndFlag(segment, "powder", 0x7ef38c, 0x10)
        updateToggleItemFromByteAndFlag(segment, "mushroom", 0x7ef38c, 0x20)
        updateToggleItemFromByteAndFlag(segment, "np_bow", 0x7ef38e, 0x80)
        updateToggleItemFromByteAndFlag(segment, "np_silvers", 0x7ef38e, 0x40)
        updateToggleItemFromByteAndFlag(segment, "mirror", 0x7ef353, 0x02)

        updateProgressiveBow(segment)
        updateBottles(segment)
        updateFlute(segment)
        updateAga1(segment)

        updateToggleItemFromByteAndFlag(segment, "gt_bigkey",  0x7ef366, 0x04)
        updateToggleItemFromByteAndFlag(segment, "tr_bigkey",  0x7ef366, 0x08)
        updateToggleItemFromByteAndFlag(segment, "tt_bigkey",  0x7ef366, 0x10)
        updateToggleItemFromByteAndFlag(segment, "toh_bigkey", 0x7ef366, 0x20)
        updateToggleItemFromByteAndFlag(segment, "ip_bigkey",  0x7ef366, 0x40)    
        updateToggleItemFromByteAndFlag(segment, "sw_bigkey",  0x7ef366, 0x80)
        updateToggleItemFromByteAndFlag(segment, "mm_bigkey",  0x7ef367, 0x01)
        updateToggleItemFromByteAndFlag(segment, "pod_bigkey", 0x7ef367, 0x02)
        updateToggleItemFromByteAndFlag(segment, "sp_bigkey",  0x7ef367, 0x04)
        updateToggleItemFromByteAndFlag(segment, "dp_bigkey",  0x7ef367, 0x10)
        updateToggleItemFromByteAndFlag(segment, "ep_bigkey",  0x7ef367, 0x20)

        -- Pending small key from chests tracking update
        -- updateConsumableItemFromByte(segment, "hc_smallkey",  0x7ef37c)
        -- updateConsumableItemFromByte(segment, "dp_smallkey",  0x7ef37f)
        -- updateConsumableItemFromByte(segment, "at_smallkey",  0x7ef380)
        -- updateConsumableItemFromByte(segment, "sp_smallkey",  0x7ef381)
        -- updateConsumableItemFromByte(segment, "pod_smallkey", 0x7ef382)
        -- updateConsumableItemFromByte(segment, "mm_smallkey",  0x7ef383)
        -- updateConsumableItemFromByte(segment, "sw_smallkey",  0x7ef384)
        -- updateConsumableItemFromByte(segment, "ip_smallkey",  0x7ef385)
        -- updateConsumableItemFromByte(segment, "toh_smallkey", 0x7ef386)
        -- updateConsumableItemFromByte(segment, "tt_smallkey",  0x7ef387)
        -- updateConsumableItemFromByte(segment, "tr_smallkey",  0x7ef388)
        -- updateConsumableItemFromByte(segment, "gt_smallkey",  0x7ef389)
       
    end

    if not AUTOTRACKER_ENABLE_LOCATION_TRACKING then
        return true
    end    

    --  It may seem unintuitive, but these locations are controlled by flags stored adjacent to the item data,
    --  which makes it more efficient to update them here.
    updateSectionChestCountFromByteAndFlag(segment, "@Castle Secret Entrance/Uncle", 0x7ef3c6, 0x01)    
    updateSectionChestCountFromByteAndFlag(segment, "@Hobo/Under The Bridge", 0x7ef3c9, 0x01)
    updateSectionChestCountFromByteAndFlag(segment, "@Bottle Vendor/This Jerk", 0x7ef3c9, 0x02)
    updateSectionChestCountFromByteAndFlag(segment, "@Purple Chest/Show To Gary", 0x7ef3c9, 0x10)

end

function updateHeartPiecesFromMemorySegment(segment)

    if not isInGame() then
        return false
    end

    InvalidateReadCaches()

    if AUTOTRACKER_ENABLE_ITEM_TRACKING then
        updateConsumableItemFromByte(segment, "heartpiece", 0x7ef448)
    end
end

function updateHeartContainersFromMemorySegment(segment)

    if not isInGame() then
        return false
    end

    InvalidateReadCaches()

    if AUTOTRACKER_ENABLE_ITEM_TRACKING then

        local pieces = Tracker:FindObjectForCode("heartpiece")
        local containers = Tracker:FindObjectForCode("heartcontainer")

        if pieces and containers then
            
            local maxHealth = (ReadU8(segment, 0x7ef36c) // 8) - 3
            
            if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
                print("Pieces: ", pieces.AcquiredCount)
                print("Max Health: ", maxHealth)
            end

            containers.AcquiredCount = maxHealth - (pieces.AcquiredCount // 4)
        end
    end
end

AUTOTRACKER_STATS_MARKDOWN_FORMAT = [===[
### Post-Game Summary

Stat | Value
--|-
**Collection Rate** | %d/216
**Deaths** | %d
**Bonks** | %d
**Total Time** | %02d:%02d:%02d.%02d
]===]

function read32BitTimer(segment, baseAddress)
    local timer = 0;
    timer = timer | (ReadU8(segment, baseAddress + 3) << 24)
    timer = timer | (ReadU8(segment, baseAddress + 2) << 16)
    timer = timer | (ReadU8(segment, baseAddress + 1) << 8)
    timer = timer | (ReadU8(segment, baseAddress + 0) << 0)

    local hours = timer // (60 * 60 * 60)
    local minutes = (timer % (60 * 60 * 60)) // (60 * 60)
    local seconds = (timer % (60 * 60)) // (60)
    local frames = timer % 60

    return hours, minutes, seconds, frames
end

function updateStatisticsFromMemorySegment(segment)

    if not isInGame() then
        return false
    end

    InvalidateReadCaches()

    if not AUTOTRACKER_HAS_DONE_POST_GAME_SUMMARY then
        -- Read completion timer
        local hours, minutes, seconds, frames = read32BitTimer(segment, 0x7ef43e)

        local collection_rate = ReadU8(segment, 0x7ef423)
        local deaths = ReadU8(segment, 0x7ef449)
        local bonks = ReadU8(segment, 0x7ef420)

        local markdown = string.format(AUTOTRACKER_STATS_MARKDOWN_FORMAT, collection_rate, deaths, bonks, hours, minutes, seconds, frames)
        ScriptHost:PushMarkdownNotification(NotificationType.Celebration, markdown)
    end

    AUTOTRACKER_HAS_DONE_POST_GAME_SUMMARY = true

    return true
end

function updateDungeonReward(segment, code, offset)
    local reward = ReadU16(segment, offset)

    local dungeon = Tracker:FindObjectForCode(code)

    if dungeon then
        if reward == 0x6238 then
            dungeon.CurrentStage = 3
        elseif reward == 0x6034 then
            dungeon.CurrentStage = 2
        elseif reward == 0x6032 then
            dungeon.CurrentStage = 2
        elseif reward == 0x6434 then
            dungeon.CurrentStage = 0
        elseif reward == 0x6432 then
            dungeon.CurrentStage = 1
        end

        if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
            print(code, " reward state:  ", dungeon.CurrentStage, " (", reward, ")")
        end
    elseif AUTOTRACKER_ENABLE_DEBUG_LOGGING then
        print("Couldn't find dungeon: ", code)
    end
end

function updateDungeonRewards(segment)
    if not isInGame() or AUTOTRACKER_DUNGEON_REWARDS_SET then
        return false
    end

    InvalidateReadCaches()

    local isDisplayingMap = (ReadU16(segment, 0x7e0010) == 0x070E)
    local isLightWorld = (ReadU16(segment, 0x7e008a) < 0x0040)
    local isFullMap = (ReadU16(segment, 0x7e0636) == 0x2100)

    if isDisplayingMap and isFullMap then
        if isLightWorld then
            __Data["map_viewed_lightworld"] = true
        else
            __Data["map_viewed_darkworld"] = true
        end
    end

    if __Data["map_viewed_lightworld"] then
        updateDungeonReward(segment, "ep", 0x853ef8)
        updateDungeonReward(segment, "dp", 0x853f1c)
        updateDungeonReward(segment, "toh", 0x853f0a)
    end
    if __Data["map_viewed_darkworld"] then
        updateDungeonReward(segment, "pod", 0x853f00)
        updateDungeonReward(segment, "sp", 0x853f6c)
        updateDungeonReward(segment, "sw", 0x853f12)
        updateDungeonReward(segment, "tt", 0x853f36)
        updateDungeonReward(segment, "ip", 0x853f5a)
        updateDungeonReward(segment, "mm", 0x853f48)
        updateDungeonReward(segment, "tr", 0x853f24)
    end

    AUTOTRACKER_DUNGEON_REWARDS_SET = (__Data["map_viewed_lightworld"] and __Data["map_viewed_darkworld"])

    return true
end

function updateMedallionIcon(code, index)
    local medallion = Tracker:FindObjectForCode(code)

    if medallion then
        medallion.CurrentStage = index

        if AUTOTRACKER_ENABLE_DEBUG_LOGGING then
            print("Set medallion index:", code, index)
        end
    end
end

function updateDungeonMedallions(segment)
    if not isInGame() or AUTOTRACKER_DUNGEON_MEDALLIONS_SET then
        return false
    end

    InvalidateReadCaches()
    
    -- check if we are outside, otherwise area is not valid
    local isOutside = (ReadU8(segment, 0x7e001b) == 0x00)
    if isOutside then
        -- ensure we are in either of the necessary dark world areas before bothering to calculate link's position
        local overworldArea = ReadU16(segment, 0x7e008a)
        local isAtMiseryMire = (overworldArea == 0x70)
        local isAtTurtleRock = (overworldArea == 0x47)
        if isAtMiseryMire or isAtTurtleRock then
            -- calculate link's position in the relevant area. this calculation changes slightly depending on whether he's in the light or dark world
            local pX = (ReadU16(segment, 0x7e0022) -           ( ( overworldArea - 0x40 ) % 8 ) * 512)
            local pY = (ReadU16(segment, 0x7e0020) - math.floor( ( overworldArea - 0x40 ) / 8 ) * 512)

            if isAtMiseryMire and pX >= 180 and pX <= 435 and pY >= 130 and pY <= 350 then
                __Data["map_viewed_medallion_mm"] = true
            elseif isAtTurtleRock and pX >= 135 and pY >= 140 and pY <= 365 then
                __Data["map_viewed_medallion_tr"] = true
            end
        end
    end

    -- reqs are 0x00 = bombos, 0x01 = ether, 0x02 = quake
    local mmReq = 0x03
    if __Data["map_viewed_medallion_mm"] then
        mmReq = ReadU8(segment, 0x980022)
    end
    local trReq = 0x03
    if __Data["map_viewed_medallion_tr"] then
        trReq = ReadU8(segment, 0x980023)
    end

    -- indices are [1] = bombos, [2] = ether, [3] = quake, [4] = none
    -- values are 0 = none, 1 = mm, 2 = tr, 3 = both
    local icons = { 0, 0, 0, 0 }

    -- add 1 to index for mm
    icons[mmReq + 1] = icons[mmReq + 1] + 1
    -- add 2 to index for tr
    icons[trReq + 1] = icons[trReq + 1] + 2

    updateMedallionIcon("bombos", icons[1])
    updateMedallionIcon("ether", icons[2])
    updateMedallionIcon("quake", icons[3])

    AUTOTRACKER_DUNGEON_MEDALLIONS_SET = (__Data["map_viewed_medallion_mm"] and __Data["map_viewed_medallion_tr"])

    return true
end

-- Run the in-game status check more frequently (every 250ms) to catch save/quit scenarios more effectively
ScriptHost:AddMemoryWatch("LTTP In-Game status", 0x7e0010, 0x90, updateInGameStatusFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP Item Data", 0x7ef340, 0x90, updateItemsFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP Room Data", 0x7ef000, 0x250, updateRoomsFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP Overworld Event Data", 0x7ef280, 0x82, updateOverworldEventsFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP NPC Item Data", 0x7ef410, 2, updateNPCItemFlagsFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP Heart Piece Data", 0x7ef448, 1, updateHeartPiecesFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP Heart Container Data", 0x7ef36c, 1, updateHeartContainersFromMemorySegment, 250)
ScriptHost:AddMemoryWatch("LTTP Dungeon Rewards", 0x7e0000, 0x73fff, updateDungeonRewards, 250)
ScriptHost:AddMemoryWatch("LTTP Dungeon Medallion Reqs", 0x7e0000, 0x1a0030, updateDungeonMedallions, 250)
