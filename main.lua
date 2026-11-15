-- you can use this to write an UNDO plugin

local utils = require(".utils")

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

-- used by `run_operation()`
local operations = {
    ---Move files and maybe notify.
    ---@param location_map PathMap
    ---@param config Config
    ---@return boolean? ran, string? error
    move = function(location_map, config)
        local err = utils.move_paths(location_map)
        if err then
            return nil, err
        end
        if config.notify then
            utils.notify(
                "Moved Files",
                utils.path_map_to_string(location_map, config.shorten_home)
            )
        end
        return true, nil
    end,

    ---Move files and maybe notify.
    ---@param location_map PathMap
    ---@param config Config
    ---@return boolean? ran, string? error
    rename = function(location_map, config)
        local err = utils.move_paths(location_map)
        if err then
            return nil, err
        end
        if config.notify then
            utils.notify(
                "Renamed Files",
                utils.path_map_to_string(location_map, config.shorten_home)
            )
        end
        return true, nil
    end,

    ---Restore files from the trash.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran, string? error
    restore = function(paths, config)
        local err = utils.restore_from_trash(paths)
        if err then
            return nil, err
        end
        if config.notify then
            utils.notify("Restored Files", utils.paths_to_string(paths, config.shorten_home))
        end
        return true, err
    end,

    ---Permanently delete files/folders. Cannot be undone.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran, string? error
    delete = function(paths, config)
        if config.prompt_delete then
            local proceed = ya.confirm({
                pos = { "center", w = 70, h = 20 },
                title = "Permanently delete " .. #paths .. " files?",
                body = ui.Text(
                    utils.format_path_list(paths, config.shorten_home)
                ):align(ui.Align.LEFT),
            })
            if not proceed then
                return false, nil
            end
        end
        local err = utils.delete_paths(paths)
        if err then
            return nil, err
        end
        return true, nil
    end,

    ---Send files/folders to the trash.
    ---@param paths Url[]
    ---@param config Config
    ---@return boolean? ran, string? error
    trash = function(paths, config)
        local err = utils.send_to_trash(paths)
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
---@param use_trash boolean
local function handle_copy(state, body, use_trash)
    -- discard the sources, store the destinations
    local destinations = {}
    for _, item in ipairs(body.items) do
        destinations[#destinations + 1] = item.to
    end

    state.undo_operation = {
        kind = use_trash and "trash" or "delete",
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
        use_trash = true,
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
        handle_copy(state, body, state.config.use_trash)
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
            utils.notify_err(err)
        end
        -- if the operation did not run, put it back on the stack
        if err ~= nil or not ran then
            set_undo_operation(undo_operation)
        end
    end,
}
