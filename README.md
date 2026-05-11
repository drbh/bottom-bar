# BottomBar

A macOS bottom status bar with hot-loadable plugins.

## Build & Run

```bash
./build.sh
open .build/debug/BottomBar.app
```

## Plugins

Plugins are `.bundle` files in `~/.bottombar/plugins/`. Build all included plugins:

```bash
cd Plugins && ./build-all.sh
```

Create your own by copying `ExamplePlugin/` and implementing the `BottomBarPlugin` protocol.

## Config

Edit `~/.bottombar/config.jsonc` to control which plugins are shown and their position. Changes apply live.

```jsonc
{
  "left": [
    "aerospace",
    "cpu",
    // "uptime",  <- disabled
    "memory"
  ],
  "right": [
    "clock"
  ]
}
```
