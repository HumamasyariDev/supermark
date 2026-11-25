Super Mak 64: Godot project source

Engine: Godot 4.7 stable, standard editor (Forward+ renderer on desktop).
Open: start Godot 4.7, choose Import, select SuperMak64-Godot/project.godot.
The first open imports every asset and takes a few minutes.
Play: F5 starts the game at the boot scene (res://scenes/boot/Boot.tscn).
Desktop build: Project > Export > "Windows Desktop".

This is the same project the browser version is exported from (preset "Web").
Code under OS.has_feature("web") only runs in the browser; the desktop game ignores it.
The published browser build also used a custom Godot web template, which is not included.

Source: mr-mak commit f73ccfb8e (2026-10-23).
Not included: the .godot import cache (Godot rebuilds it on first open),
raw audio and texture generation sources, test results.
