# Crit sounds

`bam.mp3` in this folder is the bundled default cue. In DoHelper's **Sounds**
tab the small **Cue** button switches between it and the built-in raid warning;
a blank path means the built-in warning.

Place your own `.ogg` or `.mp3` file here **before starting WoW**, then enter its
path in the Sounds tab, for example:

`Interface\AddOns\DoHelper\Sounds\bam.ogg`

Click **Apply + Test sound**. Use audio you have permission to use; no Bruce Lee
audio is included or downloaded. WoW cannot play a web URL or an arbitrary file
outside its game folders. A custom file does not need a TOC entry.

Automatic crit playback requires readable player-sourced crit data. On a
restricted Forever / Midnight client the combat log is not subscribed by
default; **Try crit detection** in the Sounds tab is an explicit, session-only
opt-in (the same guarded path as `/euihot observe on`). Registration is not
delivery — the tab's counters show what actually arrived and whether the last
playback was attempted.
