-- you can use this to write an UNDO plugin

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

---Invert a move/rename payload.
---@param original PathMap
---@return PathMap
local function invert_rename_or_move_payload(original)
    local payload = {}
    -- swap the "to" and "from" locations
    for from, to in pairs(original) do
        payload[to] = from
    end
    return payload
end

-- used by `invert_operation()`
local inverses = {
    rename_or_move = function(original)
        return {
            kind = original.kind,
            payload = invert_rename_or_move_payload(original.payload),
        }
    end,
    trash = function(original)
        return {
            kind = "restore",
            payload = original.payload,
        }
    end,
    restore = function(original)
        return {
            kind = "trash",
            payload = original.payload,
        }
    end,
    delete = function(_)
        -- cannot undo delete operation
        return nil
    end,
}

---Invert an operation.
---@param original Operation
---@return Operation?
local function invert_operation(original)
    return inverses[original.kind](original)
end

---Get the top undo operation. TODO: replace with `pop_undo_operation()`
local get_undo_operation = ya.sync(function(state)
    local op = state.undo_operation
    -- reset the operation
    state.undo_operation = nil
    return op
end)

---Set the undo operation. TODO: replace with `push_undo_operation()`
local set_undo_operation = ya.sync(function(state, undo_operation)
    state.undo_operation = undo_operation
end)

---Get the config.
---@return Config
local get_config = ya.sync(function(state)
    return state.config
end)

---Show a notification.
---@param title string
---@param content string
local function notify(title, content)
    ya.notify({
        title = title,
        content = content,
        timeout = 4.0,
        level = "info",
    })
end

---Show an error notification.
---@param message string
local function notify_err(message)
    ya.notify({
        title = "Error",
        content = message,
        timeout = 4.0,
        level = "error",
    })
end

---Replace `/home/[USER]` with `~`.
---@param path string
local function shorten_home(path)
    local homedir = os.getenv("HOME")
    if homedir == nil then
        return path
    end

    return string.gsub(path, homedir, '~', 1)
end

---Format a location map as a newline-separated string.
---@param location_map PathMap
---@param should_shorten_home boolean
---@return string
local function format_location_map(location_map, should_shorten_home)
    local content = ""
    for from, to in pairs(location_map) do
        local from_string = tostring(from)
        local to_string = tostring(to)
        if should_shorten_home then
            from_string = shorten_home(from_string)
            to_string = shorten_home(to_string)
        end
        content = content .. string.format("%s => %s\n", from_string, to_string)
    end
    return content
end

---Format a list of paths (`Url`s) as a newline-separated string.
---@param paths Url[]
---@param should_shorten_home boolean
---@return string
local function format_path_list(paths, should_shorten_home)
    local content = ""
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        if should_shorten_home then
            path_string = shorten_home(path_string)
        end
        content = content .. path_string .. "\n"
    end
    return content
end

---Restore a list of files from the trash.
---@param paths Url[]
---@return string? error
local function restore_from_trash(paths)
    local trash_entries, list_err = fs.trash.list() -- top level of the trash
    if list_err then
        return tostring(list_err)
    end

    local entries_to_restore = {}

    -- TODO: sort by either birth time or modification time so you restore the right item
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        for _, entry in ipairs(trash_entries) do
            if tostring(entry.original) == path_string then
                entries_to_restore[#entries_to_restore + 1] = entry
                break
            end
        end
    end

    local _, restore_err = fs.trash.restore(entries_to_restore)
    if restore_err then
        return tostring(restore_err)
    end
end

---Move (or rename) files in the map.
---@param location_map PathMap
---@return string?
local function move_paths(location_map)
    for from, to in pairs(location_map) do
        local _, err = fs.rename(from, to)
        if err then
            return tostring(err)
        end
    end
end

---Permanently delete files/folders.
---@param paths Url[]
---@return string? error
local function delete_paths(paths)
    for _, path in pairs(paths) do
        local cha, cha_err = fs.cha(path)
        if cha_err then
            return tostring(cha_err)
        end

        ---@cast cha Cha already checked the error

        local _, remove_err = fs.remove(cha.is_dir and "dir_all" or "file", path)
        if remove_err then
            return tostring(remove_err)
        end
    end
end

-- used by `run_operation()`
local operations = {
    ---Move files and maybe notify.
    ---@param location_map PathMap
    ---@param config Config
    ---@return boolean? ran,string? error
    move = function(location_map, config)
        local err = move_paths(location_map)
        if err then
            return nil, err
        end
        if config.notify then
            notify("Moved Files", format_location_map(location_map, config.shorten_home))
        end
        return true, nil
    end,

    ---Move files and maybe notify.
    ---@param location_map PathMap
    ---@param config Config
    ---@return boolean? ran,string? error
    rename = function(location_map, config)
        local err = move_paths(location_map)
        if err then
            return nil, err
        end
        if config.notify then
            notify("Renamed Files", format_location_map(location_map, config.shorten_home))
        end
        return true, nil
    end,

    ---Restore files from the trash.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran,string? error
    restore = function(paths, config)
        local err = restore_from_trash(paths)
        if err then
            return nil, err
        end
        if config.notify then
            notify("Restored Files", format_path_list(paths, config.shorten_home))
        end
        return true, err
    end,

    ---Permanently delete files/folders.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran,string? error
    delete = function(paths, config)
        if config.prompt_delete then
            local proceed = ya.confirm({
                pos = { "center", w = 70, h = 20 },
                title = "Permanently delete " .. #paths .. " files?",
                body = ui.Line(format_path_list(paths, config.shorten_home)):align(ui.Align.LEFT),
            })
            if not proceed then
                return false, nil
            end
        end
        local err = delete_paths(paths)
        if err then
            return nil, err
        end
        return true, nil
    end,
}

---Run an operation.
---@param operation Operation
---@param config Config
---@return boolean? ran, string? error
local function run_operation(operation, config)
    local ran, err = operations[operation.kind](operation.payload, config)
    if err then
        return nil, err
    end
    return ran, nil
end

---Handle files being moved (i.e. cut/paste).
---@param state State
---@param body MoveBody
local function handle_move(state, body)
    local payload = {}
    for _, item in ipairs(body.items) do
        payload[item.to] = item.from
    end

    -- store the "from-to" path map in reverse
    state.undo_operation = {
        kind = "move",
        payload = payload,
    }
end

---Handle a single file being renamed.
---@param state State
---@param body RenameBody
local function handle_rename(state, body)
    local payload = {}
    payload[body.to] = body.from
    -- store the "from" and "to" paths in reverse
    state.undo_operation = {
        kind = "rename",
        -- using the same payload as a bulk rename
        payload = payload,
    }
end

---Handle multiple files being renamed at once.
---@param state State
---@param body BulkRenameBody
local function handle_bulk_rename(state, body)
    -- store the "from" and "to" paths in reverse
    local payload = {}
    for from, to in pairs(body) do
        payload[to] = from
    end
    state.undo_operation = {
        kind = "rename",
        payload = payload,
    }
end

---Handle files being trashed.
---@param state State
---@param body TrashBody
local function handle_trash(state, body)
    -- store the trashed paths
    state.undo_operation = {
        kind = "restore",
        payload = body.urls,
    }
end

---Handle files being copied.
---@param state State
---@param body CopyBody
local function handle_copy(state, body)
    -- discard the sources, store the destinations
    local destinations = {}
    for _, item in ipairs(body.items) do
        destinations[#destinations + 1] = item.to
    end

    state.undo_operation = {
        kind = "delete",
        payload = destinations,
    }
end

---Create the config, overriding any options provided.
---@param opts Options
---@return Config
local function create_config(opts)
    local config = {
        notify = true,
        prompt_delete = true,
        shorten_home = false,
    }
    for key, value in pairs(opts) do
        if config[key] == nil then
            error("Unknown config option: " .. key)
        end
        if value ~= nil then
            config[key] = value
        end
    end
    return config
end

---Setup.
---@param state State
---@param opts Options?
local function setup(state, opts)
    state.undo_operation = nil

    state.config = create_config(opts or {})

    -- handle file moves (i.e. cut/paste)
    ps.sub("move", function(body)
        ---@cast body MoveBody
        handle_move(state, body)
    end)

    -- handle single-file renames
    ps.sub("rename", function(body)
        ---@cast body RenameBody
        handle_rename(state, body)
    end)

    -- handle multi-file renames
    ps.sub("bulk-rename", function(body)
        ---@cast body BulkRenameBody
        handle_bulk_rename(state, body)
    end)

    -- handle files being sent to the trash
    ps.sub("trash", function(body)
        ---@cast body TrashBody
        handle_trash(state, body)
    end)

    -- handle files being copied
    ps.sub("duplicate", function(body)
        ---@cast body CopyBody
        handle_copy(state, body)
    end)
end

return {
    setup = setup,
    entry = function(_self, _job)
        local undo_operation = get_undo_operation()
        ---@cast undo_operation Operation

        if undo_operation == nil then
            return
        end

        local config = get_config()

        local ran, err = run_operation(undo_operation, config)
        if err then
            notify_err(err)
            return
        end
        -- if the operation did not run, put it back on the stack
        if not ran then
            set_undo_operation(undo_operation)
        end
    end,
}
