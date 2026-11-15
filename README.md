# 😆 just-kidding.yazi

Just kidding! A [Yazi](https://github.com/sxyazi/yazi) plugin to undo the latest change. Currently supports:

- `rename`
- `bulk-rename`
- `create`
- `bulk-create`
- `copy`
- `move`
- `trash`

More supported operations are on the way, such as `symlink` and `hardlink`!

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
    use_trash = true,

    operations = {
        move = true,
        rename = true,
        bulk_rename = true,
        trash = true,
        copy = true,
        create = true,
        bulk_create = true,
    },
})
```

> [!NOTE]
> Settings use the default values unless overridden.

- `notify`: Whether to send a notification when an operation is undone.
- `prompt_delete`: Whether to prompt for confirmation on permanent deletions.
- `shorten_home`: Whether to shorten paths like `/home/USER/my_file.txt` to `~/my_file.txt` in notifications. This only works on Linux for now.
- `use_trash`: Whether deletion operations should instead send items to the trash. This makes such operations undo-able.
- `operations`: For each operation, specify whether it is tracked in the undo/redo history.
