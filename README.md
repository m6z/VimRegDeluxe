# VimRegDeluxe

## What is it?

- Edit [vim registers](https://vimhelp.org/change.txt.html#registers) as if they were files (buffers).
- Use the power of vim to change vim registers in a natural and efficient way.
    - Writing changes to the register buffer automatically updates the internal buffer.
    - As vim registers are updated directly or indirectly any visible buffer windows corresponding to registers are updated automatically.
- Useful for editing the system clipboard with vim such as the '+' and '\*' registers
- Helpful for complex editing tasks and constructing or modifying recorded vim macros.

## Installation

All of the functionality is incorporated into a single vimscript file: [vimreg_deluxe.vim(vimreg_deluxe.vim)

Place the file into the vim plugins directory such as ~/.vim/plugin

Or to use the [vim packages](https://vimhelp.org/repeat.txt.html#packages) feature, can use something like the following for example:

$ mkdir -p ~/.vim/pack/github/start
$ cd ~/.vim/pack/github/start
$ git clone https://github.com/m6z/VimRegDeluxe.git

## Commands

### View

View registers a, b and c

```
:vr abc
```

This command opens any number of registers in individual buffers at the top of the editing window.  Optionally a window size can be passed as a second argument for example: ```vr a 5```

### Edit

Edit the clipboard register:

```
:vre +
```

This is like the *vr* command but positions the cursor in the buffer for editing.  Saving the buffer updates the vim register, which can then be used during vim editing by a pasting/put operation.  The *vre* is the same as the *vr* command but just takes the extra step of moving the vim cursor and focus directly to the buffer for the register.

### Close

Close any open vim register windows:

```
:vrc ab
```

This command will close the a and b register windows if they are open.  If no registers are passed as an argument then all open register windows will be closed.

### Size

Resize any open vim register windows:

```
:vrs 5
```

This will resize any currently open register windows.  Can be useful when many registers windows are open in order to manage the overall editor layout

### Refresh

Force refresh any open register windows.  Normally the open register windows should update automatically as text changes in the internal vim registers.  There are some edge cases where this does not work so the *vrr* command is supplied to force updates to all visible registers.

## Implementation Notes

The default window sizes for viewing and editing registers can be changed.  See g:vimreg_window_size_view and g:vimreg_window_size_edit in the script.

The command abbreviations *vr*, *vre*, *vrs*, etc simply call functions in the script so other command aliases can be created.

Script has been tested on console and gui versions of vim on Windows, Mac and Linux.  There are automated tests in [vimreg_deluxe_test.py](test/vimreg_deluxe_test.py) using [VimChanneler](https://github.com/m6z/VimChanneler).

## Caveats

Temporary files are created on disk corresponding to the registers.  On MS Windows and other OSes these files may not be secure or private.  The plugin attempts to clean up any temporary files that it creates but this cannot be guaranteed in the case of the vim process being killed for example.

