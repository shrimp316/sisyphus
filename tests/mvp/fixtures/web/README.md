# Browser QA save fixtures

These are artificial arrival states built by `tests/mvp/create_web_fixtures.gd` using the actual scene, EXP/purchase/prestige APIs, and strict `MasterySave.validate` before and after JSON serialization. They do not demonstrate a played full climb.

- `milestone250.json`: first 250m unlock modal, 150 EXP, no purchases; moving physical state pauses while the board is open.
- `prestige-commit.json`: summit at the PRESTIGE_COMMIT journal phase before the first commit, with STR01/END01/BRE01 purchased and 510 EXP. Reloading must commit once and proceed through the presentation.
- `after-prestige.json`: first prestige finished and the next run installed; 0 EXP, no purchased nodes, all 35 purchase qualifications retained, one thread, Malkuth x5. Special node eligibility does not override the feature flags.

The payload has no path field. The browser QA importer must write only the MVP namespace using `user://sisyphus-mvp-v1.json` and the existing URL-scoped `sisyphus:mastery-mvp:v1:` localStorage key. Never write the legacy game's save key.

Regenerate with a fresh isolated filename:

```
.tools/godot/Godot_v4.5.1-stable_win64_console.exe --headless --path . --script res://tests/mvp/create_web_fixtures.gd -- --save-path=user://mvp-web-fixture-builder-UNIQUE.json
```
