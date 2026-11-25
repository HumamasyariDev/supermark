# UI (storybook v2)

Owner: UI track. Everything here is code-drawn on top of the generated art in `res://assets/ui/`
(logo, HUD icons, cake wedges, book covers, parchment) and the real character GLBs.
Layout is authored at 1920x1080; the project stretches canvas items, so 1280x720 scales down uniformly.

## API for other tracks (the `UI` autoload)

| Call | What it does |
| --- | --- |
| `UI.show_dialog(speaker, lines)` | Parchment dialog with a ribbon name plate and a live 3D portrait of the speaker. `lines` are Strings or `{"speaker", "text", "voice"}`. Await `UI.dialog_finished`. Speaker -> model/colour map: `ui_speakers.gd`. |
| `UI.show_banner(title, subtitle, seconds)` | Ribbon banner (mission names on entry). |
| `UI.toast(text)` | Small parchment toast, bottom right. |
| `UI.truffle_get(truffle_id)` | TRUFFLE GET! splash (WorldRoot calls it). |
| `UI.show_page_popup(world_id, count)` | Lost Page card (also automatic on `Game.page_collected`). |
| `UI.timer_start(label, countdown)`, `UI.timer_stop()`, `UI.timer_hide()` | Time-trial plaque. A countdown ticks for the last 5 s and emits `UI.timer_expired`. |
| `UI.show_prompt(action, text)`, `UI.hide_prompt()` | Contextual button prompt above the bottom edge ("E Talk" on keyboard, a Y face button on a pad). |
| `UI.boss_bar()` | Returns a `StorybookBossBar` (same API as `BossHealthBar`: `show_bar(name, hits)`, `set_phase_title(t)`, `set_remaining(n)`, `hide_bar()`). |
| `UI.show_mission_select(world_id)` | The book opens on its cover, swings open, and lists the 8 truffles. Choosing one calls `Router.enter_world`. |
| `UI.open_pause()` | Pause menu with the Wardrobe (beanie / top hat as real 3D models). |
| `UI.is_input_blocked()` | True while a dialog, menu, splash or page turn owns the input. |
| `UI.last_device` / `UI.device_changed` | `"keyboard"` or `"gamepad"`, for prompts. |

`UIPrompts.draw_glyph(canvas, center, action, height)` draws a keycap or a controller face button for any
input action, rebinding-aware. `UIModelView` renders any GLB into a Control (own world, transparent).

## Juice events

Every UI action calls `UIFx.event(name, params)`: it plays the UI's own sound (with fallbacks to keys
that exist in `audio_index.json`) and emits `Juice.event(name, Vector3.INF, params)` with
`params.ui_sfx = true`. The juice track can add rumble or post-fx pulses; it must not add a second sound.

`ui_move, ui_accept, ui_back, ui_open, ui_close, ui_pause, ui_resume, ui_book_open, ui_book_close,
ui_mission_choose, ui_dialog_open, ui_dialog_advance, ui_dialog_close, ui_text_blip (sound only),
ui_banner, ui_toast, ui_truffle_get, ui_truffle_count, ui_acorn_count, ui_cake_lose, ui_cake_gain,
ui_cake_low, ui_page_popup, ui_timer_start, ui_timer_tick, ui_timer_end, ui_hat_change,
ui_boss_bar_show, ui_boss_hit, ui_settings_change, ui_title_start, ui_new_game`.

Sounds still wanted from the audio track (fallbacks play until they exist): `ui_pause`, `ui_toast`,
`ui_text_blip`, `ui_timer_tick`, `ui_timer_end`, `ui_hat_change`, `ui_truffle_count`, `ui_open`, `ui_close`.

## Dev arguments

- `--ui-screen=hud|damage|timer|page|dialog|banner|truffle|pause|hats|mission|settings|boss|prompt`
  runs the showcase over any scene, for example
  `python tools/godot.py capture res://scenes/worlds/w1/W1.tscn out.png --wait 300 -- --profile=ui --ui-screen=pause`.
  `--ui-world=W3` picks the book for `mission`. `--ui-device=gamepad` forces controller glyphs.
- `--ui-demo` (from Boot) plays the scripted flow title -> New Game -> hub -> book -> W1 -> HUD -> TRUFFLE GET
  -> pause/wardrobe -> dialog, used for Movie Maker clips.
- `--title-diorama` forces the old pop-up diorama title instead of the hub TitleCam.
- `res://scenes/ui/UITestWorld.tscn -- --selftest` runs the scripted UI self-test (synthetic input).
- `res://scenes/ui/PortraitLineup.tscn` shows every dialog portrait.

Captures advance faster than real time, so wait 300+ frames for animated screens (the book opens in about 1.2 s).

## Round 2 fixes (critique UI r1)

- `Controls` adds controller A to `ui_accept`, B to `ui_cancel` and the d-pad to `ui_up/down/left/right` (Godot 4.7 ships them without joypad events).
- `WorldRegistry.truffle_goal(id)` gives a one-line objective per mission. The entry banner and the focused mission-select row show it.
- `Game.rebind_pad` swaps buttons instead of creating duplicates. In Settings, B / Start / Back cancel a pad capture and B / Start cancel a key capture.
- The title confirm hides the menu card and keeps focus inside the dialog; a disabled Continue is not focusable.
- `Router` sends Mak back to the library (or the title) with a banner when a world loads without a WorldRoot or player.
- `StorybookBossBar` draws Roman numerals (III, II:) in the rounded UI face, since the swash display face turns them into T shapes.

## Round 3 fixes (critique UI r1 re-run, 2026-10-18)

- `UI.bark(node, text, seconds, {"height", "speaker"})` / `UI.clear_barks(node)`: world speech bubbles in the UI style
  (parchment pill, ink border, Fredoka 28 px, tail toward the speaker, optional ribbon name tab). They hide on the
  title, under dialogs and menus, fade beyond about 18 m and stay on screen. Use this instead of Label3D barks.
- The title hides every Label3D under the hub backdrop (also ones added later) and any node in group `title_hide`.
  The title dolly eases back to the clear TitleCam pose while a pillar blocks the camera-to-Mak ray.
- Numerals use `UIStyle.number_font()` (Lilita One): HUD counters, timer, page count, mission numbers, the TRUFFLE GET
  splash. Counters are INK digits with a CREAM outline, flashing GOLD on the pop. Boss texts are written in voice
  (`StorybookBossBar.in_voice`: "Huffington the Third", "Act Two: The Puff").
- TRUFFLE GET: soft additive rays (two counter-rotating sets), the big truffle flies into the HUD counter in the last
  0.62 s, and the HUD holds the old count until it lands (`hud.truffle_arrive()`).
- Every `draw_circle` under scripts/ui/ is antialiased. Banners shrink (64 -> 48 px) or drop below the HUD plaques on
  long titles. Banner and toasts fade under the pause menu; toasts expire when a dialog opens; identical toasts replace
  each other (max two).
- Pause shows the mission goal, hides "Restart at bookmark" in the library and confirms "Return to library" and
  "Quit to title". Title Quit confirms ("Close the book?", default Keep reading). The Wardrobe is data-driven: reward hats
  (bowler, tea cosy, deerstalker) appear once their GLB exists (`Game.REWARD_HAT_MODELS`).
- Settings: visible pad capture (cream text, 6 s countdown underline), Pause fixed on Start/Back, "Stick camera speed"
  (`gamepad_sensitivity`), toggle "On" text readable, stronger slider/toggle focus band with a ribbon-red row label,
  brass scrollbar, one Back affordance (footer prompt, also clickable). The HUD hides under any `ui_modal`.
- Dialog: ribbon name plate; narrator lines (no speaker) use a compact centred card with a book mark.
- `--ui-tour=<abs dir>` (with `--ui-tour-only=a,b`, `--ui-tour-tag=`) captures every UI screen in one run
  (W1 or TitleScreen), to save memory on the shared machine.

## Round 4 fixes (critique UI r1 fix stage, 2026-10-18 11:27-15:30 Bangkok)

- **Title blocker:** the title marks its hub backdrop (`meta title_backdrop`, group `title_backdrop`) and builds it
  under a transient, never-saved `hub_intro_seen` flag (`Game.has_flag` / `Game.set_transient_flag`; `HubKit.flag`
  reads `has_flag`). The Wolf intro no longer runs behind the logo and plays for real after New Game.
  `UI.set_title_active(on)` (held by TitleScreen) ignores `set_hud_visible(true)`, `set_gameplay(true)`, banners,
  toasts and barks while the title owns the frame. `UI.is_title_active()` for other tracks.
- Title camera dollies along its ray to Mr. Mak until he stands 320 px tall at 1080p (right third); small props
  closer than 4.5 m to the lens hide on the title. The logo's brown ball truffle is covered at runtime by the game's
  Golden Truffle icon on the logo rim (no asset change). Quit confirm: "Leave the library?" / Quit game /
  Keep reading, in the menu card's slot, with chip-style unfocused buttons and its own A/B footer.
- **Type:** `UIStyle.display_font()` is Lilita One. `UIStyle.title_label(text, size)` and
  `UIStyle.draw_title(ci, pos, text, fs)` give the logo treatment (cream fill, 5 px ribbon-dark rim, 3 px ink drop).
  Cherry Swash stays only for in-book voices: `UIStyle.book_font()` (cover-page book title) and
  `display_font_regular()` (narrator lines, epigraphs). INK/PARCHMENT match ART_V2 (#3B2416, #F3E6C4).
- **Banner:** pinned at top 28 px; it drops to the lower third only when that covers less of Mak's on-screen box.
- **Book:** the cover swings around the spine in perspective (front face rendered once into a SubViewport, drawn as
  24 strips), with a procedural marbled endpaper inside, a board edge, a sweeping shadow and a landing thud/squash.
- **Settings:** the list sits in an alpha mask with 40 px fades; focus scrolling keeps the focused row clear of them.
  Key capture reads "Press a key (Esc cancels)" in a 460 px button. Backspace is on `ui_cancel`.
- **Boss bar / timer:** the boss name uses the logo treatment; the phase title sits on a parchment tag that drops in;
  the timer moves beside the bar while it shows. The timer is a cream pill with ink digits (GOLD pulse in the last 10 s).
- **HUD:** both counter pills share one width (at least two digits), right edges aligned, width eases.
  `UI.set_objective(text)` / `UI.clear_objective()` draw one persistent objective tag under the counters
  (cleared on every `set_gameplay`).
- **Pause:** pause card and Wardrobe are two parchment pages of one leather spread, same top and bottom; hats sit on
  cushions (`UIModelView.seat_bottom`). The menu list wraps; hat cards keep vertical focus; Left from the first card
  returns to the last menu button; the confirm footer reads Choose / Keep reading.
- `UI.show_mission_select` waits for an open dialog or TRUFFLE GET splash; `UI.open_pause` refuses while one is up.
- `UI.last_device` also listens to `Window.window_input`, so consumed pad input still switches glyphs.
- Mission goals are capped at 40 characters; the focused row shrinks to 19 px and trims at a word boundary.
- TRUFFLE GET: a 2-frame radial burst instead of the full-screen flash, rays end at 60% of the screen height, the
  word uses the logo treatment with a travelling gold glint. Barks: parchment texture, 3 px ink offset shadow,
  gilt rule, 28 px tail. Narrator card keeps 120 px clear for the keycap.
- Checks: `python tools/godot.py script res://scripts/ui/tests/goal_fit_check.gd` and
  `python tools/godot.py script res://scripts/ui/tests/ui_flow_check.gd -- --profile=ui_check`.
