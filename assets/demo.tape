# Recording for assets/demo.gif
#
#   vhs assets/demo.tape
#
# Uses the repo's own fixtures and assets/demo/init.lua, so it can be
# re-recorded after a change without setting anything up by hand.
#
# vhs 0.12.0 runs the tape and then writes nothing (charmbracelet/vhs#787).
# Record with 0.11.0 until that is fixed.

Output assets/demo.gif

Require nvim

Set Shell "bash"
Set FontSize 15
Set Width 1180
Set Height 660
Set Padding 18
Set Framerate 20
Set TypingSpeed 45ms
Set Theme { "background": "#1d2021", "foreground": "#ebdbb2", "cursor": "#ebdbb2", "selection": "#504945", "black": "#282828", "red": "#cc241d", "green": "#98971a", "yellow": "#d79921", "blue": "#458588", "magenta": "#b16286", "cyan": "#689d6a", "white": "#a89984", "brightBlack": "#928374", "brightRed": "#fb4934", "brightGreen": "#b8bb26", "brightYellow": "#fabd2f", "brightBlue": "#83a598", "brightMagenta": "#d3869b", "brightCyan": "#8ec07c", "brightWhite": "#ebdbb2" }

Hide
Type "cd $(git rev-parse --show-toplevel 2>/dev/null || pwd)" Enter
Type "clear" Enter
Show

# ── 1. A .env opens already masked, weak values flagged ──────────────────────
Type "nvim -u assets/demo/init.lua tests/fixtures/test.env" Enter
Sleep 4s

# ── 2. Not just .env ─────────────────────────────────────────────────────────
Type ":e tests/fixtures/config.yaml" Enter
Sleep 2500ms
Type ":e tests/fixtures/main.tf" Enter
Sleep 2500ms
Type ":e tests/fixtures/Dockerfile" Enter
Sleep 2500ms

# ── 3. A value typed now is masked now, before the frame is drawn ────────────
Type ":e tests/fixtures/test.env" Enter
Sleep 1s
Type "G"
Type "o"
Sleep 400ms
Type "STRIPE_SECRET_KEY=sk_live_51HxQpLkW9vT2mZ8"
Sleep 1800ms
Escape
Sleep 800ms

# ── 4. Reveal one line on purpose, then move away ────────────────────────────
Type "4G"
Sleep 400ms
Type ":CamouflageReveal" Enter
Sleep 2s
Type "j"
Sleep 1800ms

# ── 5. Follow cursor: only the line under the cursor is readable ─────────────
Type ":CamouflageFollowCursor" Enter
Sleep 1200ms
Type "j"
Sleep 1s
Type "j"
Sleep 1s
Type "j"
Sleep 1200ms
Type ":CamouflageFollowCursor!" Enter
Sleep 1200ms

# ── 6. Copying a value is deliberate: it asks, then clears the register ──────
Type "5G"
Sleep 400ms
Type ":CamouflageYank" Enter
Sleep 2s
Enter
Sleep 2s

# ── 7. Picker result rows are masked too, not only the preview ──────────────
Type@20ms ":lua Snacks.picker.grep({ cwd='tests/fixtures', glob={'*.env','*.yaml','*.json','*.tf*','*.xml'}, search='(?i)password', regex=true, live=false })" Enter
Sleep 3500ms
Down 2
Sleep 1500ms
Down 2
Sleep 1500ms
Escape
Sleep 300ms
Escape
Sleep 1200ms

# ── 8. Terminal output can be masked as well (opt in) ───────────────────────
Type ":terminal cat tests/fixtures/test.env" Enter
Sleep 4s
Type ":e tests/fixtures/test.env" Enter
Sleep 1s

# ── 9. Audit the workspace: keys and locations, never values ────────────────
Type ":CamouflageAudit tests/fixtures" Enter
Sleep 3500ms
Type ":cclose" Enter
Sleep 800ms

# ── 10. Presentation mode: everything masked, reveals refused ───────────────
Type ":CamouflagePresent" Enter
Sleep 2s
Type ":CamouflageReveal" Enter
Sleep 2500ms
Type ":CamouflagePresent!" Enter
Sleep 1800ms

Type ":qa!" Enter
Sleep 1s
