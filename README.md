# Pyrevalley

An ink-drawn action game made in Godot. You play Veyl, who woke in the ash at the edge of Emberwood with an old sword and no memory, and the creature waiting at the heart of it all is the Ashbound.

The game has been rebuilt several times. Each version lives in its own folder and is a complete Godot project that runs on its own. **v7 is the newest.**

## Play in your browser

**[▶ Play v7 in your browser](https://noirpixels.github.io/Pyrevalley/)**. Nothing to install, and it works on Chromebooks. Use Chrome or Edge. The first load is about 45 MB. Your progress saves in that browser. Co-op only works in the desktop version.

## Play it in Godot

1. Install **[Godot 4.7](https://godotengine.org/download/)** (the standard build, not .NET). It's free and you don't need to install anything else.
2. Download this repo: the green **Code** button → **Download ZIP**, then unzip it. You can also run `git clone https://github.com/noirpixels/Pyrevalley.git`.
3. Open Godot, click **Import**, and pick the `project.godot` file inside the version you want, e.g. `v7/project.godot`.
4. Press **F5** (or the ▶ button at the top right) to play.

The first time you open a version, Godot spends a minute importing its art and sound. That only happens once.

## Versions

| Folder | What it is |
|---|---|
| [`v7/`](v7) | **Pyrevalley: side-on metroidvania.** A new world is pieced together from hand-made rooms for every seed. It has juggle combat, digging through smooth ground, ember shrines that heal and save, crafting, an inked map, the Ashbound's arena, and co-op over LAN. |
| [`v6/`](v6) | **Pyrevalley: open world and multiplayer.** A new 3D forest for every world, with gathering, mining, gear, crafting stations and the blood moon. It also has co-op and PvP multiplayer, a Local Duel mode for two players on one keyboard, and a duel bot. |
| [`v5/`](v5) | **Embervale: graphic-novel overhaul.** Adds the ink post-process look, readable attack telegraphs, a dressed-up Emberwood, synthesised sound and music, and inked menus. |
| [`v4/`](v4) | **Embervale: combat feel.** Mouse-button combat, procedural animation, Veyl as a cut-out puppet with a real sword swing, and controller support. |
| [`v3/`](v3) | **Embervale: directional combat.** Drag attacks, dizziness, launches and Max Combo, plus a fairer Ashbound fight. |
| [`v2/`](v2) | **Embervale: depth pass.** 3D pines, an animated menu, Rowan, and a data-driven codex. |
| [`v1/`](v1) | **Embervale: the first prototype.** An isometric Emberwood built from the design doc. |

## v7 controls

| | Keyboard and mouse | Controller |
|---|---|---|
| Move | A / D (or arrow keys) | Left stick / D-pad |
| Jump | Space | A |
| Dash | Shift | B |
| Strike | Left click / J | X |
| Heavy | Right click / K | Y |
| Launch / slam | Hold W or S while striking (or scroll up / down) | Hold up or down while striking |
| Drop through a ledge | Hold S (or S + Space) | Hold down |
| Dig | F | LB |
| Use / talk | E | RB |
| Map | M / Tab | View / Back |
| Pack (crafting and gear) | I | D-pad up |
| Pause | Esc | Start |

**Co-op (v7):** one player picks **Co-op → Host my world**. Everyone else picks **Co-op**, and games on the same network show up as a list to click. You can also type the host's address and press **Join**. It uses ports 24600–24601 (UDP).

The older versions show their controls in-game.

## Project layout

Every version folder is a standalone Godot 4.7 project:

```
vN/
  project.godot     open this in Godot
  *.gd / *.tscn     game code and scenes
  audio/  Fonts/  Veyl/  Creatures/  NPCs/  Menu/  …   art and sound
```

v1 to v6 share one history; v7 started fresh and its commits were merged in. The `v7.0.0` tag marks the first v7 release.
