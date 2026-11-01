# just-kidding.yazi

Just kidding! Undo the latest change (currently the last move operation or rename, more on the way).

## Installation

```sh
ya pkg add drewwhitney/just-kidding.yazi
```

## Usage

Add

`~/.config/yazi/init.lua`:

```lua
require("just-kidding"):setup()
```

`~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = "j"
run = "plugin just-kidding"
desc = "Undo last operation"
```
