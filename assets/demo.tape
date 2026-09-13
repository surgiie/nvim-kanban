# VHS tape for the nvim-kanban README demo.
#
# Regenerate with (VHS + a Nerd Font, via an ephemeral nix shell):
#   nix-shell -p vhs nerd-fonts.jetbrains-mono --run "vhs assets/demo.tape"
#
# Run from the repository root. See https://github.com/charmbracelet/vhs
#
# Records against a scratch copy of assets/demo/.kanban so the committed
# fixture is never mutated by the actions performed in the recording
# (adding/editing/moving cards, toggling done, writing a note, ...).

Output assets/demo.gif

Set Shell "bash"
Set FontSize 15
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set Width 1200
Set Height 720
Set Padding 20
Set Theme "MaterialOcean"
Set TypingSpeed 60ms

Hide
Type "REPO=$(pwd); rm -rf /tmp/kanban-demo && mkdir -p /tmp/kanban-demo && cp -r assets/demo/.kanban /tmp/kanban-demo/.kanban && cd /tmp/kanban-demo && clear"
Enter
Type "nvim -u $REPO/assets/demo/init.lua"
Enter
Sleep 1500ms
Show

# Open the board
Type "\kb"
Sleep 1500ms

# --- Add a new card to "To Do" ---
Type "l"
Sleep 800ms
Type "a"
Sleep 800ms
Type "Ship v1.0 #release"
Sleep 500ms
Ctrl+S
Sleep 1500ms

# --- Move it into "In Progress" ---
Enter
Sleep 1500ms

# --- Reorder it within the column ---
Type "K"
Sleep 500ms
Type "K"
Sleep 500ms
Type "J"
Sleep 800ms

# --- Edit its title / tags ---
Type "e"
Sleep 800ms
Type " #launch"
Sleep 500ms
Ctrl+S
Sleep 1500ms

# --- Give it a due date ---
Type "D"
Sleep 1000ms
Type "jjl"
Sleep 500ms
Enter
Sleep 1500ms

# --- Attach a note ---
Type "n"
Sleep 800ms
Type "i"
Sleep 300ms
Type "Coordinate with marketing on launch day timing."
Sleep 500ms
Escape
Type ":wq"
Enter
Sleep 1500ms

# --- Card detail shows title, due date, tags and note together ---
Type "o"
Sleep 1800ms
Type "q"
Sleep 500ms

# --- Mark it done and move it into "Done" ---
Space
Sleep 800ms
Enter
Sleep 1500ms

# Help popup
Type "?"
Sleep 1500ms
Type "q"
Sleep 500ms

# Close the board
Type "q"
Sleep 600ms

Type ":qa!"
Enter
Sleep 300ms
Hide
Type "clear"
Enter
Show
Sleep 200ms
