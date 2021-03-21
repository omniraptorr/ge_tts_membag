local Logger = require("ge_tts/Logger")
local Instance = require("ge_tts/Instance")
local TableUtils = require("ge_tts/TableUtils")

---@class MyInstance : ge_tts__Instance

---@alias myData number[] -- can be anything ofc, as long as it's JSON.encode-able

---@shape MyInstance_SavedState : ge_tts__Instance_SavedState
---@field data nil | myData

-- overloads for how the class will be constructed
---@class static_MyInstance : ge_tts__static_Instance
---@overload fun(savedState: MyInstance_SavedState): MyInstance
---@overload fun(object: tts__Object): MyInstance
---@overload fun(object: tts__Object, nilOrData: nil | myData,): MyInstance
---@overload fun(guid: string, object: tts__Container): MyInstance
---@overload fun(guid: string, object: tts__Container, nilOrData: nil | myData): MyInstance
local MyInstance = {}

MyInstance.INSTANCE_TYPE = "My Instance Type"

-- private functions go here as local functions so they won't show up in the return
---@param obj any
local function isContainer(obj)
    return type(obj) == "userdata" and (--[[---@type tts__Object]] obj).tag == "Bag" or (--[[---@type tts__Object]] obj).tag == "Deck"
end

setmetatable(MyInstance, TableUtils.merge((Instance), {
    ---@param objOrGUIDOrSavedState tts__Object | string | MyInstance_SavedState
    ---@param nilOrDataOrContainer nil | myData | tts__Container
    ---@param nilOrData nil | myData
    __call = function(_, objOrGUIDOrSavedState, nilOrDataOrContainer, nilOrData)
        ---@type MyInstance
        local self

        -- instance private variables go here
        ---@type nil | myData
        local data

        -- handling the various overloads
        if MyInstance.isSavedState(objOrGUIDOrSavedState) then
            local savedState = --[[---@type MyInstance_SavedState]] objOrGUIDOrSavedState
            self = --[[---@type MyInstance]] Instance(savedState)
            data = savedState.data
        elseif type(objOrGUIDOrSavedState) == "string" and isContainer(nilOrDataOrContainer) and MyInstance.checkValidData(nilOrData) then
            local guid = --[[---@type string]] objOrGUIDOrSavedState
            self = --[[---@type MyInstance]] Instance(guid, --[[---@type tts__Container]] nilOrDataOrContainer)
            Logger.assert(self.getContainerPosition(), "Instance(): guid " .. guid .. " doesn't exist in container!") -- todo: move this check to Instance and make it optional
            data = --[[---@type myData]] nilOrData
        elseif type(objOrGUIDOrSavedState) == "userdata" and MyInstance.checkValidData(nilOrDataOrContainer) then
            self =  --[[---@type MyInstance]] Instance(--[[---@type tts__Object]] objOrGUIDOrSavedState)
            data = --[[---@type myData]] nilOrDataOrContainer
        else
            error("bad arguments to constructor!")
        end

        -- member functions go here

        function self.getMyData()
            return TableUtils.copy(data)
        end

        return self
    end,
    __index = Instance,
    -- other metamethods (e.g. arithmetic, pairs, etc) go here too.
}))

-- public class (i.e. not tied to an instance) functions go here
function MyInstance.checkValidData(data) -- insert own data checking here
    return type(data) == "nil" or
            type(data) == "table" and
            TableUtils.isArray(data) and
            type(next(data)) == "number"
end

return MyInstance