# nano8086
A minimalist nano clone for MS-DOS, written in 8086 assembly.
It is a single 1.5 KB `.COM` file that runs on an original IBM PC (8088/8086 at 4.77 MHz).

Tested on PC-DOS 3.3. Should work on any MS-DOS / PC-DOS 2.0 or later.

## Features

- nano-style screen: title bar, 22 text lines, status line, help line
- Arrows, Home/End, PgUp/PgDn, Backspace, Del, Enter, Tab
- Tabs shown as 8 columns; long lines scroll horizontally
- Reads and writes DOS text files (CR LF), drops the trailing `^Z`
- Asks before quitting with unsaved changes
- Works with MDA (monochrome) and CGA/EGA/VGA in 80-column text mode
- 8086-only instructions, no FPU, no 186+ opcodes

## Keys

| Key | Action |
|-----|--------|
| `^S` / `^O` | Save |
| `^X` | Exit (asks `Y/N` if modified) |
| `^K` | Delete current line |

## Usage

```
NANO FILE.TXT
```

If the file does not exist, it is created when you save.

## Building

You need [NASM](https://www.nasm.us/):

```
nasm -f bin -o NANO.COM nano.asm
```

To make a 360 KB floppy image (with mtools) for an emulator such as 86Box:

```
mformat -C -i nano.img -f 360 -v NANO ::
mcopy -i nano.img NANO.COM ::
```

## Requirements

- 8086/8088 CPU or newer
- MS-DOS / PC-DOS 2.0+
- About 128 KB of free memory (program + a 64 KB text buffer)
- MDA, CGA, EGA or VGA

## Limitations

- A file name is required on the command line
- Files up to 65,000 bytes
- No search, no copy/paste (`^K` deletes the line, it is not kept)
- No CGA snow suppression, so a real IBM CGA card may show some snow while redrawing
