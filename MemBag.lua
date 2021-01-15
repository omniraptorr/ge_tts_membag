local Json = require("ge_tts/Json")
local Logger = require("ge_tts/Logger")
local LabeledInstance = require("UIUtils/LabeledInstance")
local TableUtils = require('ge_tts/TableUtils')

---@class MemBagInstance : LabelInstance

---@class static_MemBagInstance : static_LabelInstance
---@overload fun(savedState: MemBagInstance_SavedState): MemBagInstance
---@overload fun(object: tts__Container): MemBagInstance
---@overload fun(object: tts__Container, data: nil | MemBagData): MemBagInstance
local MemBagInstance = {}

---@shape MemBagEntry
---@field pos tts__Vector
---@field rot tts__Vector
---@field lock nil | boolean
---@field parent nil | string

---@alias MemBagEntries table<string, MemBagEntry>

---@shape MemBagConfig
---@field smoothTake nil | boolean
---@field __index nil | table

-- once we get multiple inheritance this will inherit from MemBagData as well. but for now just duplicate the fields.
---@shape MemBagInstance_SavedState : LabelInstance_SavedState
---@field entries MemBagEntries
---@field config nil | MemBagConfig

---@shape MemBagData
---@field entries nil | MemBagEntries
---@field config nil | MemBagConfig

MemBagInstance.INSTANCE_TYPE = "Absolute MemBag"

---@type MemBagConfig
MemBagInstance.defaultConfig = {
    smoothTake = true,
}
MemBagInstance.defaultConfig.__index = MemBagInstance.defaultConfig

setmetatable(MemBagInstance, TableUtils.merge(getmetatable(LabeledInstance), {
    ---@param objOrSavedState tts__Container | MemBagInstance_SavedState
    ---@param nilOrBagData nil | MemBagData
    __call = function(_, objOrSavedState, nilOrBagData)

        local self = --[[---@type MemBagInstance]] LabeledInstance(objOrSavedState)

        ---@type MemBagEntries
        local entries = {}
        ---@type MemBagConfig
        local config = setmetatable({}, self.getDefaultConfig())

        ---@type MemBagData
        local bagData
        if MemBagInstance.isSavedState(objOrSavedState) then
            bagData = (--[[---@type MemBagInstance_SavedState]] objOrSavedState)
        elseif type(nilOrBagData) == "table" then
            bagData = --[[---@not nil]] TableUtils.copy(nilOrBagData)
        end

        if bagData.config then
            self.setConfig( --[[---@not nil]] bagData.config)
        end
        if bagData.entries then
            TableUtils.map(--[[---@not nil]] bagData.entries, function(entry, guid)
                return self.addEntry(self.initInstance(guid), entry)
            end)
        end

        -- done with constructor, now to define public member functions

        local superSave = self.save
        ---@return MemBagInstance_SavedState
        function self.save()
            return --[[---@type MemBagInstance_SavedState]] TableUtils.merge(superSave(), {
                entries = entries,
                config = config
            })
        end

        self.getInstanceType()
        self.getType()

        function self.getDefaultConfig()
            return MemBagInstance.defaultConfig
        end

        function self.getConfig()
            return TableUtils.copy(config)
        end

        -- this needs to be overridden for each descendant that adds config fields since they all need new defaults.
        ---@param newConfig MemBagConfig
        function self.setConfig(newConfig)
            config = setmetatable(TableUtils.copy(newConfig), self.getDefaultConfig())
        end

        ---@return string
        function self.getInstanceType()
            return MemBagInstance.INSTANCE_TYPE
        end

        local superGetObject = self.getObject
        ---This overload is really just for Luanalysis, i didn't feel like casting to container every time
        ---@return tts__Container
        function self.getObject()
            return superGetObject()
        end

        ---Fetches existing entry data
        ---@param guid string
        ---@return nil | MemBagEntry
        function self.getEntry(guid)
            return TableUtils.copy(entries[guid], true)
        end

        function self.getEntries()
            return TableUtils.copy(entries)
        end

        function self.clearEntries()
            entries = {}
        end

        ---This is basically ripped from Instance constructor, i just added extra asserts cuz i'm paranoid.
        ---Looks for guid in the scene and in container (or self if no container provided), then creates an Instance from it
        ---@overload fun(guid: string): ge_tts__Instance
        ---@param guid string
        ---@param nilOrContainer nil | tts__Container
        ---@return ge_tts__Instance
        function self.initInstance(guid, nilOrContainer)
            local existingInstance = LabeledInstance.getInstance(guid)
            if existingInstance then
                return --[[---@not nil]] existingInstance
            end

            local container = --[[---@not nil]] nilOrContainer or self.getObject()
            local selfGUID, containerGUID = container.getGUID(), self.getInstanceGuid()
            Logger.assert(nilOrContainer ~= nil,
                    string.format("MemBag %s: container %s of new entry %s doesn't exist", selfGUID, containerGUID, guid))
            Logger.assert(container.getObjects,
                    string.format("MemBag %s: container %s of new entry %s is not a container", selfGUID, containerGUID, guid))

            local nilOrState, _ = TableUtils.detect(container.getObjects(), function(objectState)
                return objectState.guid == guid
            end)

            local nilOrObj = getObjectFromGUID(guid)

            Logger.assert(nilOrState or nilOrObj,
                    string.format("MemBag %s: object with guid %s not found!", selfGUID, guid))
            Logger.assert(not (nilOrState and nilOrObj),
                    string.format("MemBag %s: objects with guid %s exist both in and out of parent!", selfGUID, guid))

            if nilOrObj then
                local obj = --[[---@not nil]] nilOrObj
                local decodedState = Json.decode(--[[---@not nil]] obj.script_state)
                if LabeledInstance.isSavedState(decodedState) then
                    return LabeledInstance(--[[---@type ge_tts__Instance_SavedState]] decodedState)
                else
                    return LabeledInstance(obj)
                end
            else
                -- then nilOrState exists
                local state = --[[---@not nil]] nilOrState
                local decodedState = Json.decode(--[[---@not nil]] state.lua_script_state)
                if LabeledInstance.isSavedState(decodedState) then
                    return LabeledInstance(--[[---@type ge_tts__Instance_SavedState]] decodedState)
                else
                    return LabeledInstance(guid, --[[---@not nil]] nilOrContainer)
                end
            end
        end

        ---Gets bag position from real-world position, used when adding entries
        ---This one is straightforward but meant to be overridden.
        ---@param pos tts__CharVectorShape
        ---@param rot tts__CharVectorShape
        ---@return tts__Vector, tts__Vector
        function self.getTransform(pos, rot)
            return Vector(pos), Vector(rot)
        end

        ---Reverse of getTransform- gets real-world position from bag position. Used when placing entries
        ---@param entry MemBagEntry
        ---@return tts__Vector, tts__Vector
        function self.applyTransform(entry)
            return entry.pos, entry.rot
        end

        ---Looks inside and outside self for matching object and makes an Instance for it, then adds it to entries.
        ---Errors if matching object does not exist either directly in the scene or inside selfObj.
        ---@overload fun(entryInstance: ge_tts__Instance)
        ---@param entryInstance ge_tts__Instance
        ---@param nilOrEntryData nil | MemBagEntry
        function self.addEntry(entryInstance, nilOrEntryData)
            local entryObj = entryInstance.getObject()
            local guid = entryInstance.getInstanceGuid()

            if nilOrEntryData then
                -- when setting data directly, the transform step should be done in advance by the caller
                entries[guid] = TableUtils.copy(--[[---@not nil]] nilOrEntryData)
            else
                local pos, rot = self.getTransform(entryObj.getPosition(), entryObj.getRotation())
                entries[guid] = {
                    pos = pos,
                    rot = rot,
                    lock = entryObj.getLock()
                }
            end

            self.invalidateSavedState()

            return entries[guid]
        end

        ---@param guid string
        function self.removeEntry(guid)
            entries[guid] = nil
            self.invalidateSavedState()
        end

        --- callback after taking an entry and getting its obj reference. fancy animations etc. will go here
        ---@param entry ge_tts__Instance
        function self.onEntryPlace(entry)
            local lock = entries[entry.getInstanceGuid()].lock or false
            entry.getObject().setLock(lock)
        end

        ---@param guid string
        ---@param nilOrSmoothTake nil | boolean
        function self.placeEntry(guid, nilOrSmoothTake)
            Logger.assert(entries[guid], "no entry with guid " .. guid)
            local entry = entries[guid]

            local smoothTake = (nilOrSmoothTake == nil) and config.smoothTake or nilOrSmoothTake

            local pos, rot = self.applyTransform(entry)

            local entryInstance = --[[---@not nil]] LabeledInstance.getInstance(guid)
            Logger.assert(entryInstance, "instance for entry " .. guid .. " not found!")

            ---@type ge_tts__Instance_TakeObjectOptions
            local params = {
                guid = guid,
                position = pos,
                rotation = rot,
                smooth = smoothTake,
                callback = function()
                    return self.onEntryPlace(entryInstance)
                end,
            }
            entryInstance.takeObject(params)
        end

        ---@param entryInstance ge_tts__Instance
        function self.onEntryRecall(entryInstance)
            self.getObject().putObject(entryInstance.getObject())
        end

        ---@param guid string
        function self.recallEntry(guid)
            ---@type nil | number

            local entryInstance = --[[---@not nil]] LabeledInstance.getInstance(guid)
            Logger.assert(entryInstance, self.getInstanceGuid() .. " tried to recall a non-existing instance of guid " .. guid)

            ---@type ge_tts__Instance_TakeObjectOptions
            local params = {
                guid = guid,
                position = entryInstance.getObject().getPosition() + Vector(0, 1, 0),
                smooth = false, -- smooth is always false here because any fanciness should happen in the callback
                callback = function()
                    self.onEntryRecall(entryInstance)
                end
            }
            entryInstance.takeObject(params)
        end

        ---@param nilOrSmoothTake nil | boolean
        ---@overload fun(nilOrSmoothTake: nil | number)
        ---@overload fun(): any
        function self.place(nilOrSmoothTake)
            local smoothTake = (nilOrSmoothTake == nil) and config.smoothTake or nilOrSmoothTake

            return TableUtils.map(entries, function(_, guid)
                self.placeEntry(guid, smoothTake)
                return guid
            end)
        end

        function self.recall()
            TableUtils.map(entries, function(_, guid)
                self.recallEntry(guid)
                return guid
            end)
        end

        return self
    end,
    __index = LabeledInstance,
}))

return MemBagInstance