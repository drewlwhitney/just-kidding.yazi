-- type definitions for the plugin

---@alias PathMap table<Url, Url>

---@class FromTo
---@field from Url
---@field to Url

---@class MoveBody
---@field items FromTo[]

---@class CopyBody
---@field items FromTo[]

---@class RenameBody
---@field tab integer
---@field from Url
---@field to Url

---@class BulkRenameBody
---@field __len fun(self: self): integer
---@field __pairs fun(self: self): (Url, Url)[] -- I don't think this is quite right (type-wise)

---@class TrashBody
---@field urls Url[]

---@class State
---@field undo_operation Operation?
---@field config Config

---@alias OperationPayload PathMap | Url[]

---@class Operation
---@field payload OperationPayload
---@field kind "move" | "rename" | "restore" | "delete"

---@class Config
---@field notify boolean
---@field prompt_delete boolean
---@field shorten_home boolean

---@class Options
---@field notify boolean?
---@field prompt_delete boolean?
---@field shorten_home boolean?
