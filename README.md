# 😆 just-kidding.yazi

Just kidding! A [Yazi](https://github.com/sxyazi/yazi) plugin to undo the latest change (currently the latest move, copy, rename, bulk-rename, or trash operation, more on the way (such as file creation, bulk file creation, symlink creation, and bulk symlink creation)).

## Installation

```sh
ya pkg add drewlwhitney/just-kidding
```

## Usage

`~/.config/yazi/init.lua`:

```lua
require("just-kidding"):setup({
    --config
})
```

`~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = "j"
run = "plugin just-kidding"
desc = "Undo last operation"
```

## Config

Below are the default settings:

```lua
require("just-kidding"):setup({
    notify = true,
    prompt_delete = true,
    shorten_home = false,
})
```

> [!NOTE]
> Settings use the default values unless overridden.

- `notify`: Whether to send a notification when an operation is undone.
- `prompt_delete`: Whether to prompt for confirmation on permanent deletions.
- `shorten_home`: Whether to shorten paths like `/home/USER/my_file.txt` to `~/my_file.txt` in notifications. This only works on Linux for now.

## TODO

- [ ] Implement "redo" to undo an undo
    - [ ] Use `trash-cli` to send files to the trash for the `trash` redo operation
        - [ ] Open an issue in Yazi to get a Lua API for this instead
        - [ ] Replace with Lua API (if it is implemented)
- [ ] Add setup option for custom undo-able operations so other plugins can hook into this one
    - [ ] Figure out how this will work with notifications and the `Config`
    - [ ] Test this with `to-folder.yazi`
- [ ] Implement additional undo-able operations (need to open an issue in Yazi for this)
- [ ] Allow configuration of which operations are tracked for undoing
- [ ] Store multiple undo-able operations in a stack (requires solving the DDS delay issue)
    - [ ] Open a discussion asking for help with DDS delay
    - [ ] Allow configuration of the stack size
