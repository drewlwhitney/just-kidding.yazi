# 😆 just-kidding.yazi

Just kidding! A [Yazi](https://github.com/sxyazi/yazi) plugin to undo the latest change (currently the latest move, copy, rename, bulk-rename, or trash operation, more on the way).

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
- `shorten_home`: Whether to shorten paths like `/home/USER/my_file.txt` to `~/my_file.txt` in notifications.
