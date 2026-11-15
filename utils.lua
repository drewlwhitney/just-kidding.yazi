-- utility functions for the plugin

local M = {}

---Show a notification.
---@param title string
---@param content string
function M.notify(title, content)
    ya.notify({
        title = title,
        content = content,
        timeout = 4.0,
        level = "info",
    })
end

---Show an error notification.
---@param message string
function M.notify_err(message)
    ya.notify({
        title = "Error",
        content = message,
        timeout = 4.0,
        level = "error",
    })
end

---Replace `/home/[USER]` with `~`.
---@param path string
function M.shorten_home(path)
    local homedir = os.getenv("HOME")
    if homedir == nil then
        return path
    end

    return string.gsub(path, homedir, '~', 1)
end

---Format a path map as a newline-separated string.
---@param path_map PathMap
---@param should_shorten_home boolean
---@return string
function M.path_map_to_string(path_map, should_shorten_home)
    local content = ""
    for from, to in pairs(path_map) do
        local from_string = tostring(from)
        local to_string = tostring(to)
        if should_shorten_home then
            from_string = M.shorten_home(from_string)
            to_string = M.shorten_home(to_string)
        end
        content = content .. string.format("%s => %s\n", from_string, to_string)
    end
    return content
end

---Format a list of paths (`Url`s) as a newline-separated string.
---@param paths Url[]
---@param should_shorten_home boolean
---@return string
function M.paths_to_string(paths, should_shorten_home)
    local content = ""
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        if should_shorten_home then
            path_string = M.shorten_home(path_string)
        end
        content = content .. path_string .. "\n"
    end
    return content
end

---Format a list of paths (`Url`s) as a list of `Line`s.
---@param paths Url[]
---@param should_shorten_home boolean
---@return ui.Line[]
function M.format_path_list(paths, should_shorten_home)
    local lines = {}
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        if should_shorten_home then
            path_string = M.shorten_home(path_string)
        end
        lines[#lines + 1] = ui.Line(path_string):align(ui.Align.LEFT)
    end
    return lines
end

---Restore a list of files from the trash.
---@param paths Url[]
---@return string? error
function M.restore_from_trash(paths)
    local trash_entries, list_err = fs.trash.list() -- top level of the trash
    if list_err then
        return tostring(list_err)
    end

    local entry_map = {}

    -- NOTE: this only works if the files have not been modified while
    -- in the trash bin
    -- override entries that were trashed later, so we always restore
    -- most-recently-trashed path
    for _, path in ipairs(paths) do
        local path_string = tostring(path)
        for _, entry in ipairs(trash_entries) do
            if tostring(entry.original) == path_string then
                local existing_entry = entry_map[path_string]
                if existing_entry ~= nil then
                    if entry.stat.ctime > existing_entry.stat.ctime then
                        -- replace with the more recently-trashed entry
                        entry_map[path_string] = entry
                    end
                else
                    -- it's not already present; add it
                    entry_map[path_string] = entry
                end
            end
        end
    end

    -- extract the entries from the map
    local entries_to_restore = {}
    for _, entry in pairs(entry_map) do
        entries_to_restore[#entries_to_restore + 1] = entry
    end

    local _, restore_err = fs.trash.restore(entries_to_restore)
    if restore_err then
        return tostring(restore_err)
    end
end

---Send files to the trash (currently uses `trash-cli`).
---@param paths Url[]
---@return string? error
function M.send_to_trash(paths)
    local path_strings = {}
    for _, path in ipairs(paths) do
        path_strings[#path_strings + 1] = tostring(path)
    end
    local _, error = Command("trash-put"):arg(path_strings):output()
    if error then
        return tostring(error)
    end
end

---Move (or rename) files in the map.
---@param path_map PathMap
---@return string?
function M.move_paths(path_map)
    for from, to in pairs(path_map) do
        local _, err = fs.rename(from, to)
        if err then
            return tostring(err)
        end
    end
end

---Permanently delete files/folders.
---@param paths Url[]
---@return string? error
function M.delete_paths(paths)
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

return M
