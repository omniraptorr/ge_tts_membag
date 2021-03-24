local Instance = require("ge_tts/Instance")
local TableUtils = require('ge_tts/TableUtils')
local   MemBagInstance = require("MemBag")
local Logger = require("ge_tts/Logger")


---@class GUIBagInstance : MemBagInstance

---@class static_GUIBagInstance : static_MemBagInstance
---@overload fun(savedState: MemBagInstance_SavedState): GUIBagInstance
---@overload fun(object: tts__Container): GUIBagInstance
---@overload fun(object: tts__Container, data: nil | GUIBagData): GUIBagInstance
local GUIBagInstance = {}

---@shape GUIBagConfig: MemBagConfig
---@field gui nil | boolean
---@field blinkColor nil | color
---@field containerBlinkColor nil | color
---@field selfHighlightColor nil | color
---@field blinkDuration nil | number
---@field labelConfig nil | LabelParams

-- used for default config
---@shape FullGUIBagConfig
---@field gui boolean
---@field blinkColor color
---@field containerBlinkColor color
---@field selfHighlightColor color
---@field blinkDuration number
---@field labelConfig LabelParams

GUIBagInstance.INSTANCE_TYPE = "GUI MemBag"

---@alias pendingEntries table<string, number> @ a table of blink Wait.time IDs indexed by guid

---@shape GUIBagInstance_SavedState : MemBagInstance_SavedState
---@field pending nil | pendingEntries
---@field config nil | GUIBagConfig

---@shape GUIBagData : MemBagData
---@field pending nil | pendingEntries
---@field config nil | GUIBagConfig

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

        -- handling the various overloads
        local isSavedState = GUIBagInstance.isSavedState(objOrSavedState)
        if isSavedState then
            self = --[[---@type GUIBagInstance]] MemBagInstance(--[[---@type GUIBagInstance_SavedState]] objOrSavedState)
        elseif type(objOrSavedState) == "userdata" then
            local obj = --[[---@type tts__Container]] objOrSavedState
            Logger.assert(isContainer(obj), "tried to init GUIMemBag but object is not a valid container!")
            self = --[[---@type GUIBagInstance]] MemBagInstance(obj, nilOrData)
        else
            error("bad arguments to GUIMemBag constructor")
        end

        -- now we finish the constructor
        if isSavedState then
            local savedState = --[[---@type GUIBagInstance_SavedState]] objOrSavedState
            if savedState.pending then
                pending = --[[---@not nil]] savedState.pending
            end
            if savedState.config then
                self.setConfig(--[[---@not nil]] savedState.config)
            end
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
                pending = next(pending) and pending or nil,
            })
        end

        local config = --[[---@type FullGUIBagConfig]] self.getConfig()

        -- not used except as callback
        ---@param guid string
        local function blink(guid)
            local realObj = (--[[---@not nil]] Instance.getInstance(guid)).getObject()
            if realObj == nil then
                self.removePendingEntry(guid)
                Logger.log("pending obj with guid " .. guid .. " has been deleted!")
                return
            end
            if guid == realObj.getGUID() then
                -- todo: submit pr to fix color shape params in tts-types, then remove all the casts to tts__Color
                realObj.highlightOn(--[[---@type tts__Color]] config.blinkColor, config.blinkDuration)
            else
                realObj.highlightOn(--[[---@type tts__Color]] config.containerBlinkColor, config.blinkDuration)
            end
        end

        -- not used except as callback
        ---@param guid string
        local function addBlinker(guid)
            return Wait.time(function() blink(guid) end, config.blinkDuration * 2, -1)
        end

        ---@param guid string
        function self.addPendingEntry(guid)
            --Logger.assert(not pending[guid], "entry already in pending!")
            pending[guid] = addBlinker(guid)
            return pending[guid]
        end

        ---@param guid string
        function self.removePendingEntry(guid)
            Logger.assert(pending[guid], "entry already not in pending!")
            Wait.stop(pending[guid])
            pending[guid] = nil
            return nil -- otherwise TableUtils.map complains about return type void :(
        end

        function self.clearPendingEntries()
            TableUtils.map(pending, function(_, guid)
                return self.removePendingEntry(guid)
            end)
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

            self.getObject().highlightOff()
            self.actionMode()
        end

        function self.cancelSetup()
            self.clearPendingEntries()
            self.getObject().highlightOff()
            self.actionMode()
        end

        ---@param guid string
        local function addBlinkerMapFunc(_, guid)
            return addBlinker(guid)
        end

        function self.reset()
            self.clearPendingEntries()
            self.clearEntries()
            self.setupMode()
        end

        function self.setupMode()
            local realObj = self.getObject()
            if config.selfHighlightColor then realObj.highlightOn(--[[---@type tts__Color]] config.selfHighlightColor) end

            if next(pending) then -- only when restoring from a save
                Logger.log("restoring pending from a save", Logger.INFO)
                pending = TableUtils.map(pending, addBlinkerMapFunc)
            else -- add blinkers for everything
                pending = TableUtils.map(self.getEntries(), addBlinkerMapFunc)
            end

            self.setLabel({
                label = "Save selection",
                click_function = self.finishSetup,
                position = {1,1},
                align = {1,-1}
            })
            self.setLabel({
                label = "Cancel setup",
                click_function = self.cancelSetup,
                position = {1,0},
                align = {1,-1}
            })

            realObj.addContextMenuItem("reset", self.reset)
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

        if next(pending) then
            self.setupMode()
        else
            self.actionMode()
        end

        return self
    end,
    __index = MemBagInstance,
    -- other metamethods (e.g. arithmetic, pairs, etc) go here too.
}))

GUIBagInstance:setReferenceConfig({
    gui = true,
    blinkColor = "Red",
    containerBlinkColor = "Pink",
    selfHighlightColor = "Blue",
    blinkDuration = 0.5,
    labelConfig = {
        color = "Blue",
        label = "",
        font_color = "Black",
        position = {1,0},
        align = {1,0},
        scale = 2,
    },
})

return GUIBagInstance