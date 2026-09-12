# VHS tape for the nvim-kanban README demo.
#
# Regenerate with (VHS + a Nerd Font, via an ephemeral nix shell):
#   nix-shell -p vhs nerd-fonts.jetbrains-mono --run "vhs assets/demo.tape"
#
# Run from the repository root. See https://github.com/charmbracelet/vhs

Output assets/demo.gif

Set Shell "bash"
Set FontSize 15
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set Width 1200
Set Height 720
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

Hide
Type "cd assets/demo && clear"
Enter
Show

Type "nvim -u init.lua"
Enter
Sleep 800ms

# Open the board
Type "\kb"
Sleep 1200ms

# Walk across columns and cards
Type "l"
Sleep 400ms
Type "j"
Sleep 400ms
Type "k"
Sleep 400ms
Type "l"
Sleep 500ms

# Card detail popup
Type "o"
Sleep 1500ms
Type "q"
Sleep 500ms

# Due date picker
Type "D"
Sleep 1200ms
Escape
Sleep 500ms

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
Sleep 500ms
