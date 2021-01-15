local Instance = require("ge_tts/Instance")
local TableUtils = require('ge_tts/TableUtils')
local MemBagInstance = require("MemBag")
local Logger = require("ge_tts/Logger")


---@class GUIBagInstance : MemBagInstance

---@class static_GUIBagInstance : static_MemBagInstance
---@overload fun(savedState: MemBagInstance_SavedState): GUIBagInstance
---@overload fun(object: tts__Container): GUIBagInstance
---@overload fun(object: tts__Container, data: nil | GUIBagData): GUIBagInstance
local GUIBagInstance = {}

---@shape PartialGUIBagConfig: MemBagConfig
---@field gui nil | boolean
---@field blinkColor nil | tts__Color
---@field containerBlinkColor nil | tts__Color
---@field selfHighlightColor nil | tts__Color
---@field blinkDuration nil | number

-- this shape is just so luanalysis respects the default values accessed via __index
---@shape GUIBagConfig: MemBagConfig
---@field gui boolean
---@field blinkColor tts__Color
---@field containerBlinkColor tts__Color
---@field selfHighlightColor tts__Color
---@field blinkDuration number


GUIBagInstance.INSTANCE_TYPE = "GUI MemBag"

GUIBagInstance.defaultConfig = TableUtils.merge(MemBagInstance.defaultConfig, {
    gui = true,
    blinkColor = "Red",
    containerBlinkColor = "Pink",
    selfHighlightColor = "Blue",
    blinkDuration = 0.5,
})

---@alias pendingEntries table<string, number> @ a table of blink Wait.time IDs indexed by guid

---@shape GUIBagInstance_SavedState : MemBagInstance_SavedState
---@field pending pendingEntries
---@field config GUIBagConfig

---@shape GUIBagData : MemBagData
---@field pending nil | pendingEntries
---@field config nil | PartialGUIBagConfig

GUIBagInstance.defaultConfig.__index = GUIBagInstance.defaultConfig

---@param obj tts__Object
local function isContainer(obj)
    return type(obj) == "userdata" and obj ~= nil and obj.tag == "Bag" or obj.tag == "Deck"
end

setmetatable(GUIBagInstance, TableUtils.merge(getmetatable(MemBagInstance), {
    ---@param objOrSavedState tts__Object | GUIBagInstance_SavedState
    ---@param nilOrData nil | GUIBagData
    __call = function(_, objOrSavedState, nilOrData)
        ---@type GUIBagInstance
        local self

        -- instance private variables go here
        ---@type pendingEntries
        local pending = {}

        local config = setmetatable(--[[---@type GUIBagConfig]] {}, self.getDefaultConfig())

        -- handling the various overloads
        local isSavedState = GUIBagInstance.isSavedState(objOrSavedState)
        if isSavedState then
            self = --[[---@type GUIBagInstance]] MemBagInstance(--[[---@type GUIBagInstance_SavedState]] objOrSavedState)
        elseif type(objOrSavedState) == "userdata" then
            local obj = --[[---@type tts__Container]] objOrSavedState
            Logger.assert(isContainer(obj), "tried to init GUIMemBag but object is not a valid container!")
            self = --[[---@type GUIBagInstance]] MemBagInstance(obj, nilOrData)
        end

        -- todo: figure out inheritance wrapper benjamin mentioned in discord.
        -- since inheriting static methods/vars is awkward boilerplate rn. and you have to define config methods in the middle of the constructor
        function self.getDefaultConfig()
            return GUIBagInstance.defaultConfig
        end

        function self.getConfig()
            return TableUtils.copy(config)
        end

        ---@param newConfig PartialGUIBagConfig
        function self.setConfig(newConfig)
            config = --[[---@type GUIBagConfig]] setmetatable(newConfig, self.getDefaultConfig())
        end

        -- now we finish the constructor
        if isSavedState then
            local savedState = --[[---@type GUIBagInstance_SavedState]] objOrSavedState
            pending = savedState.pending -- if it's a savedState we can assign directly
            self.setConfig(savedState.config)
        elseif type(objOrSavedState) == "userdata" then
            if nilOrData then
                local data = --[[---@not nil]] nilOrData
                if data.pending then
                    pending = --[[---@not nil]] data.pending
                end
                if data.config then
                    self.setConfig( --[[---@not nil]] data.config)
                end
            end
        end

        -- then methods

        local superSave = self.save
        ---@return GUIBagInstance_SavedState
        function self.save()
            return --[[---@type GUIBagInstance_SavedState]] TableUtils.merge(superSave(), {
                config = config,
                pending = pending
            })
        end

        -- not used except as callback
        ---@param guid string
        local function blink(guid)
            local realObj = (--[[---@not nil]] Instance.getInstance(guid)).getObject()
            if guid == realObj.getGUID() then
                realObj.highlightOn(config.blinkColor, config.blinkDuration)
            else
                realObj.highlightOn(config.containerBlinkColor, config.blinkDuration)
            end
        end

        -- not used except as callback
        ---@param guid string
        local function addBlinker(guid)
            return Wait.time(function() blink(guid) end, config.blinkDuration * 2, -1)
        end

        ---@param guid string
        function self.addPendingEntry(guid)
            Logger.assert(not pending[guid], "entry already in pending!")
            pending[guid] = addBlinker(guid)
            return pending[guid]
        end

        ---@param guid string
        function self.removePendingEntry(guid)
            Logger.assert(pending[guid], "entry already not in pending!")
            Wait.stop(pending[guid])
            pending[guid] = nil
        end

        function self.clearPendingEntries()
            pending = {}
        end

        function self.writePendingEntries()
            TableUtils.map(pending, function(_, guid)
                local instance = --[[---@not nil]] Instance.getInstance(guid)
                Logger.assert(instance,"error writing pending entry: object with guid " .. guid .. "has no instance")
                return self.addEntry(instance)
            end)
        end

        function self.finishSetup()
            self.clearEntries()
            self.writePendingEntries()

            local realObj = self.getObject()
            realObj.highlightOff()
            self.actionMode()
        end

        ---@param guid string
        local function addBlinkerMapFunc(_, guid)
            return addBlinker(guid)
        end

        ---@params data {}
        function self.drawLabel()

        end

        function self.setupMode()
            local realObj = self.getObject()
            if config.selfHighlightColor then realObj.highlightOn(--[[---@not nil]] config.selfHighlightColor) end

            if next(pending) then -- only when restoring from a save
                Logger.log("restoring pending from a save", Logger.INFO)
                pending = TableUtils.map(pending, addBlinkerMapFunc)
            else -- add blinkers for everything
                pending = TableUtils.map(self.getEntries(), addBlinkerMapFunc)
            end

            self.createLabel()
        end

        function self.actionMode()
            local realObj = self.getObject()
            realObj.clearContextMenu()

            if next(self.getEntries()) then
                realObj.addContextMenuItem("Place", self.place)
                realObj.addContextMenuItem("Recall", self.recall)
            end

            realObj.addContextMenuItem("Setup", self.setupMode)
        end

        function self.drawUI()
            local realObj = self.getObject()
            if not config.gui or realObj.getGUID() ~= self.getInstanceGuid() then return end

            if not next(pending) then
                self.actionMode()
            end

        end

        function self.onSpawned()

        end

        return self
    end,
    __index = MemBagInstance,
    -- other metamethods (e.g. arithmetic, pairs, etc) go here too.
}))

return GUIBagInstance