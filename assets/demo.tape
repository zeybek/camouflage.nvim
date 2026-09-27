# Recording for assets/demo.gif, the short demo at the top of the README
#
#   vhs assets/demo.tape
#
# Uses the repo's own fixtures and assets/demo/init.lua, so it can be
# re-recorded after a change without setting anything up by hand. The longer
# tour is assets/demo-full.tape.
#
# vhs 0.12.0 runs the tape and then writes nothing (charmbracelet/vhs#787).
# Record with 0.11.0 until that is fixed.

Output assets/demo.gif

Require nvim

Set Shell "bash"
Set FontSize 15
Set FontFamily "BlexMono Nerd Font Mono, JetBrains Mono, Menlo, monospace"
Set Width 1180
Set Height 660
Set Padding 18
Set Framerate 20
Set TypingSpeed 45ms
Set Theme { "background": "#1d2021", "foreground": "#ebdbb2", "cursor": "#ebdbb2", "selection": "#504945", "black": "#282828", "red": "#cc241d", "green": "#98971a", "yellow": "#d79921", "blue": "#458588", "magenta": "#b16286", "cyan": "#689d6a", "white": "#a89984", "brightBlack": "#928374", "brightRed": "#fb4934", "brightGreen": "#b8bb26", "brightYellow": "#fabd2f", "brightBlue": "#83a598", "brightMagenta": "#d3869b", "brightCyan": "#8ec07c", "brightWhite": "#ebdbb2" }

# Start with the file already open, so the first frame (the one a link preview
# shows) is the masked file and not an empty prompt.
Hide
Type "cd $(git rev-parse --show-toplevel 2>/dev/null || pwd)" Enter
Type "clear" Enter
Type "nvim -u assets/demo/init.lua tests/fixtures/test.env" Enter
Sleep 4s
Show

# ── 1. A .env opens already masked, weak values flagged ──────────────────────
Sleep 2500ms

# ── 2. A value typed now is masked now, before the frame is drawn ────────────
Type "G"
Type "o"
Sleep 300ms
Type "STRIPE_SECRET_KEY=sk_live_51HxQpLkW9vT2mZ8"
Sleep 1500ms
Escape
Sleep 600ms

# ── 3. Reveal one line on purpose, it hides again when you move away ────────
Type "5G0"
Sleep 300ms
Type ":CamouflageReveal" Enter
Sleep 1800ms
Type "j"
Sleep 1200ms

# ── 4. Not just .env ─────────────────────────────────────────────────────────
Type ":e tests/fixtures/config.yaml" Enter
Sleep 2200ms

# ── 5. Picker result rows are masked too, not only the preview ──────────────
Type@20ms ":lua Snacks.picker.grep({ cwd='tests/fixtures', glob={'*.env','*.yaml','*.json','*.tf*','*.xml'}, search='(?i)password', regex=true, live=false })" Enter
Sleep 3200ms
Down 2
Sleep 1500ms
Escape
Sleep 300ms
Escape
Sleep 800ms

Hide
Type ":qa!" Enter
