# BottomBar

<img width="2056" height="1329" alt="bottom-bar-masked" src="https://github.com/user-attachments/assets/1e4fcff3-76ee-4585-a18b-6ee67b0b757a" />

note: the example above has two bottom bars stacked for more space - default case is a single bottom bar

### What is this?

A macOS bottom status bar with hot-loadable plugins.

#### Build & Run

```bash
./build.sh
open .build/debug/BottomBar.app
```

#### Plugins

Plugins are `.bundle` files in `~/.bottombar/plugins/`. Build all included plugins:

```bash
cd Plugins && ./build-all.sh
```

Create your own by copying `ExamplePlugin/` and implementing the `BottomBarPlugin` protocol.

#### Config

Copy `config.example.jsonc` to `~/.bottombar/config.jsonc` to control which plugins are shown and where. Changes apply live.

Some plugins need external tools: `aerospace` needs [AeroSpace](https://github.com/nikitabobko/AeroSpace), `prs` needs `gh auth login`, and `minime` needs a `minime` binary on your PATH.

Plugins run as native code inside the app, only install ones you trust.

Note: this app is primarily intended for personal use and may not be suitable for your machine, please feel free to contribute back, or point your agent at this project and using it as a starting point for your own bottom bar implementation.
