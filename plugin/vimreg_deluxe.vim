" vim:ff=unix

" When viewing a register this is the default window height
if ! exists ('g:vimreg_window_size_view')
    let g:vimreg_window_size_view = 3
endif

" When editing a register this is the default window height
if ! exists ('g:vimreg_window_size_edit')
    let g:vimreg_window_size_edit = 10
endif

" TODO create new repo - VimRegDeluxe on github
" rename this file to vimreg_deluxe.vim

"----------------------------------------------------------------------
" Globals for script
let s:pending_bufnrs = {}

function! s:initialize()
    if !exists('s:initialized')
        " TODO is this a global setting?
        " set updatetime=500
        set updatetime=250  " used by CursorHold

        augroup vimreg
            autocmd!
            autocmd CursorHold * call s:AutoCursorHold()
            autocmd FocusGained * call s:AutoFocusGained()
            autocmd InsertLeave * call s:AutoInsertLeave()
            autocmd TextYankPost * call s:AutoTextYankPost()
        augroup END

        let s:initialized = v:true
    endif
endfunction

function! s:log(msg)
    " Remove or comment the following line to enable logging
    " return

    if !exists('s:logfile')
        let s:logfile = '/tmp/vimreg.log'
        if has('win32')
            let s:logfile = 'c:'.s:logfile
        endif
        if len(glob(s:logfile))
            call delete(s:logfile)
        endif
    endif
    let l:msg = a:msg
    if exists("*strftime")
        let l:msg = strftime('%Y-%m-%d %T ') . l:msg
    endif
    call writefile([l:msg], s:logfile, 'a')
endfunction

function! s:log2(msg)
    echo a:msg
    call s:log(a:msg)
endfunction

"----------------------------------------------------------------------
" scenario
" gather up the window ids for the current column
" gather up the bufinfos dictionary for any registers of interest
" if the bufinfo exists in the current column - move it to the top
" if the bufinfo exists but not in the current column
"   - open a new window to the buffer with :sb #
" if the bufinfo does not exist create a new one

" registers is a required parameter
" size an optional parameter
function! g:VimReg_View(registers, ...)
    call s:initialize()
    if len(a:registers) == 0
        echo 'parameter needed: registers'
        return 0
    endif
    let l:size = get(a:, 1, g:vimreg_window_size_view)
    call s:log('VimReg_View starting, registers='.a:registers.' l:size='.l:size)

    let l:column_winids = g:VimReg_GetCurrentWindowsInColumn()
    " let bufinfos = s:GetBufinfosForRegistersAsDict(a:registers, l:column_winids)
    let l:bufinfos = s:GetBufinfosForRegistersAsDict(a:registers, [])

    " for each register indicated, create new buffer or reposition existing buffer
    let l:start_winid = win_getid()
    let l:window_index = 0
    let l:registers_set = {}  " dictionary being used as a set
    let l:register_winids = []
    let i = 0
    while i < len(a:registers)
        let l:register = a:registers[i]
        let i += 1
        if has_key(l:registers_set, l:register)
            continue  " ignore duplicates
        endif
        let l:registers_set[l:register] = 1

        call s:log('==== l:register='.l:register.' l:window_index='.l:window_index.' current='.win_getid())

        let l:winid = 0  " window id of the register buffer, created or reused
        if has_key(l:bufinfos, l:register)
            " buffer for register already exists
            let l:bufinfo = l:bufinfos[l:register]
            let l:column_winids_index = s:Intersection(l:column_winids, l:bufinfo.windows)
            if l:column_winids_index >= 0
                " buffer does exist already in the column
                let l:winid = l:column_winids[l:column_winids_index]
                " call s:log('@ mode 1a l:register='.l:register.' winid='.l:winid)
            else
                " buffer does exist but is not in column, open another view to it
                execute 'sb '.l:bufinfo.bufnr
                let l:winid = win_getid()
                " call s:log('@ mode 1b l:register='.l:register.' winid='.l:winid.' bufnr='.l:bufinfo.bufnr)
            endif
        else
            " buffer for register does not exist anywhere
            let l:winid = g:VimReg_NewBuffer(l:register)
            " call s:log('@ mode 2 l:register='.l:register.' winid='.l:winid.' win_getid()='.win_getid())
        endif
        call add(l:register_winids, l:winid)
        let window_index += 1
    endwhile

    " call s:log('l:register_winids='.string(l:register_winids))
    " call s:log('before reorg curcol='.string(g:VimReg_GetCurrentWindowsInColumn()))

    " reorganize the windows
    " first gather up the window ids consisting of registes and otherwise
    let l:ordered_winids = copy(l:register_winids)
    for l:winid in l:column_winids
        if index(l:register_winids, l:winid) < 0
            call add(l:ordered_winids, l:winid)
        endif
    endfor
    call s:log('l:ordered_winids='.string(l:ordered_winids))

    " second swap around window positions
    let i = 1
    for l:winid in l:ordered_winids
        call win_gotoid(l:winid)
        exe "normal ".i."\<c-w>x"
        " call s:log('swap i='.i.' l:winid='.l:winid.' curcol='.string(g:VimReg_GetCurrentWindowsInColumn()))
        let i += 1
    endfor

    " third fix up the window heights
    for l:winid in l:register_winids
        call win_gotoid(l:winid)
        execute 'resize '.l:size
    endfor

    call win_gotoid(l:start_winid)
    return l:register_winids[0]
endfunction

function! g:VimReg_Edit(registers, ...)
    let l:winid = g:VimReg_View(a:registers)
    if l:winid > 0
        call win_gotoid(l:winid)
        let l:size = get(a:, 1, g:vimreg_window_size_edit)
        execute 'resize '.l:size
    endif
endfunction

function! g:VimReg_NewBuffer(register)
    " Conjure up a filename for the register
    " TODO consider something like g:edit_register_dir
    let l:tempname = tempname()
    let l:tempdir = fnamemodify(l:tempname, ':p:h')
    " Mangle the temporary name to be somthing slightly human readable,
    " for when it is shown in the buffer list
    let l:filename = 'vimreg_'.s:RegisterName(a:register).'_'.fnamemodify(l:tempname, ':t')
    if ! findfile(l:filename, l:tempdir)
        " Mangled name is okay
        let l:filename = l:tempdir . '/' . l:filename
    else
        " Mangled name collision? revert to original tempname
        let l:filename = l:tempname
    endif

    " Open the new buffer, will need to position it later
    execute 'split '.l:filename
    execute 'resize '.g:vimreg_window_size_view

    setlocal noautoread
    setlocal binary
    setlocal noeol
    setlocal winfixheight     " this keeps windows from getting too big
    setlocal bufhidden=wipe
    setlocal nobuflisted
    setlocal noswapfile
    setlocal noundofile
    setlocal nomodeline

    " consider changing variable name to __vimreg_deluxe__ ??
    let b:_register_ = a:register
    call s:RefreshRegister()

    autocmd BufEnter             <buffer> call s:AutoBufEnter()
    autocmd BufWritePost         <buffer> call s:AutoBufWritePost()
    autocmd VimLeavePre          <buffer> call s:AutoVimLeavePre()
    autocmd BufWipeout           <buffer> call s:AutoBufWipeout()
    autocmd FileChangedShellPost <buffer> call s:AutoFileChangedShellPost()

    return win_getid()
endfunction

" pass size as first argument, optional
function! g:VimReg_Size(...)
    let l:size = get(a:, 1, g:vimreg_window_size_view)

    if type(l:size) == v:t_string
        if str2nr(l:size) == 0
            echo 'invalid size: '.l:size
            return
        endif
    endif

    let l:bufinfos = s:GetBufinfosForRegistersAsList('', [])
    call s:log2('g:VimReg_Size l:size='.l:size.' len(l:bufinfos)='.len(l:bufinfos))
    if len(l:bufinfos) == 0
        echo 'no register buffers'
        return
    endif

    let l:start_winid = win_getid()
    for l:bufinfo in l:bufinfos
        for l:winid in l:bufinfo.windows
            call win_gotoid(l:winid)
            let l:size0 = line('w$')-line('w0')+1
            exe 'resize '.l:size
            let l:size1 = line('w$')-line('w0')+1
            call s:log2('g:VimReg_Size winid='.l:winid.' size0='.l:size0.' size1='.l:size1)
        endfor
    endfor
    call win_gotoid(l:start_winid)
endfunction

function! g:VimReg_Refresh()
    call s:log('g:VimReg_Refresh starting')
    let l:bufinfos = s:GetBufinfosForRegistersAsList('', [])
    for l:bufinfo in l:bufinfos
        call s:RefreshOneRegister_bufinfo(l:bufinfo)
    endfor
endfunction

function! g:VimReg_Close(bang, registers)
    call s:log('g:VimReg_Close starting')
    for l:bufinfo in s:GetBufinfosForRegistersAsList(a:registers, [])
        exe 'bwipeout'.a:bang.' '.l:bufinfo.name
    endfor
endfunction

" ----------------------------------------------------------------------
" Utility functions

" Get window ids in current column
" to be used before commands like win_gotoid() or win_execute()

function! s:GetCurrentWindowsInColumnImpl(layout, winid, level)
    " look for contiguous leaf elements containing the window id
    " call s:log2('gcw level='.a:level.' layout='.string(a:layout))
    let l:context = a:layout[0]
    if l:context == 'leaf'
        if a:layout[1] == a:winid
            return [a:winid]
        endif
    else
        " this is a 'row' or 'col'
        let l:nodes = a:layout[1]
        let i = 0
        while i < len(l:nodes)
            if l:nodes[i][0] == 'leaf'
                if l:nodes[i][1] == a:winid
                    if l:context == 'col'
                        " collect up the span of leaf windows
                        let i1 = i  " start of span
                        let i2 = i  " end of span
                        while i1 > 0 && l:nodes[i1-1][0] == 'leaf'
                            let i1 -= 1
                        endwhile
                        while i2 + 1 < len(l:nodes) && l:nodes[i2+1][0] == 'leaf'
                            let i2 += 1
                        endwhile
                        let l:result = []
                        while i1 <= i2
                            call add(l:result, l:nodes[i1][1])
                            let i1 += 1
                        endwhile
                        return l:result
                    else
                        " for a row match result is just a single window
                        return [a:winid]
                    endif
                endif
            else
                let l:result = s:GetCurrentWindowsInColumnImpl(l:nodes[i], a:winid, a:level + 1)
                if len(l:result) > 0
                    return l:result
                endif
            endif
            let i += 1
        endwhile
    endif
    return []  " not found
endfunction

" This is a global
function! g:VimReg_GetCurrentWindowsInColumn()
    " returns a list of window ids
    return s:GetCurrentWindowsInColumnImpl(winlayout(), win_getid(), 0)
endfunction

" ----------------------------------------------------------------------

function! s:FilterBufinfo(registers, winids, bufinfo_index, bufinfo)
    if ! has_key(a:bufinfo.variables, '_register_')
        return v:false  " not a register based buffer
    endif

    " filter by string of registers, if provided
    if len(a:registers) > 0
        if stridx(a:registers, a:bufinfo.variables._register_) < 0
            return v:false  " not a buffer of interest
        endif
    endif
    if len(a:winids) == 0
        return v:true  " not filtering by winids -> success
    endif

    " at this point check that the bufinfo corresponds to a winid of interest
    let i = 0
    while i < len(a:winids)
        if index(a:bufinfo.windows, a:winids[i]) >= 0
            return v:true  " winid found
        endif
        let i += 1
    endwhile
    return v:false  " could not find any winids of interest
endfunction

function! s:GetBufinfosForRegistersAsList(registers, winids)
    let l:Fn = function('s:FilterBufinfo', [a:registers, a:winids])
    return filter(getbufinfo({'buflisted':1}), l:Fn)
endfunction

function! s:GetBufinfosForRegistersAsDict(registers, winids)
    let l:bufinfos = s:GetBufinfosForRegistersAsList(a:registers, a:winids)
    let l:result = {}
    for l:bufinfo in l:bufinfos
        let l:result[l:bufinfo.variables._register_] = l:bufinfo
    endfor
    return l:result
endfunction

function! s:Intersection(list1, list2)
    " only for short lists
    " returns the index of first element in list1 found in list2
    let i = 0
    while i < len(a:list1)
        if index(a:list2, a:list1[i]) >= 0
            return i
        endif
        let i += 1
    endwhile
    return -1
endfunction

function! s:isReadOnly(register)
    if a:register == ':'
        return v:true
    elseif a:register == '.'
        return v:true
    elseif a:register == '%'
        return v:true
    elseif a:register == '#'
        return v:true
    endif
    return v:false
endfunction

" ----------------------------------------------------------------------
" Abbreviation shortcuts

command! -nargs=+ VimRegView :call g:VimReg_View(<f-args>)
cabbrev vr <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'VimRegView' : 'vr')<CR>

command! -nargs=+ VimRegEdit :call g:VimReg_Edit(<f-args>)
cabbrev vre <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'VimRegEdit' : 'vre')<CR>

command! -nargs=? VimRegSize :call g:VimReg_Size(<f-args>)
cabbrev vrs <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'VimRegSize' : 'vrs')<CR>

command! -nargs=0 VimRegRefresh :call g:VimReg_Refresh()
cabbrev vrr <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'VimRegRefresh' : 'vrr')<CR>

command! -nargs=? -bang VimRegClose :call g:VimReg_Close("<bang>", "<args>")
cabbrev vrc <c-r>=(getcmdtype()==':' && getcmdpos()==1 ? 'VimRegClose' : 'vrc')<CR>

function! s:AutoBufEnter()
    " let l:abuf=expand('<abuf>')
    " let l:afile=expand('<afile>')

    " When buftype is nofile this is an indication that there was
    " a yank operation which modified the register.
    " Need to get back to the file being associated with the register
    " before anything in the buffer is changed and saved.
    if &buftype == 'nofile'
        set buftype=
        write!
    endif

    call s:RefreshRegister()
endfunction

function! s:AutoTextYankPost()

    let l:bufinfos = s:GetBufinfosForRegistersAsList(v:event.regname, [])
    if len(l:bufinfos)
        let l:bufinfo = l:bufinfos[0]
        if l:bufinfo.loaded && !l:bufinfo.hidden
            let s:pending_bufnrs[l:bufinfo.bufnr] = 1
        endif
    endif
    " call s:log('s:AutoTextYankPost 1 s:pending_bufnrs='.string(keys(s:pending_bufnrs)))

    " TODO optimize this?
    " These registers get updated during yank/delete operations
    let l:bufinfos = s:GetBufinfosForRegistersAsList('0123456789.-="', [])
    for l:bufinfo in l:bufinfos
        let s:pending_bufnrs[l:bufinfo.bufnr] = 1
    endfor
    call s:log('s:AutoTextYankPost 2 s:pending_bufnrs='.string(keys(s:pending_bufnrs)))

endfunction

function! s:AutoCursorHold()
    if len(s:pending_bufnrs) == 0
        return
    endif
    call s:log('s:AutoCursorHold s:pending_bufnrs='.string(keys(s:pending_bufnrs)))
    try
        call s:RefreshPendingRegisters()
        " need to check the search register specifically
        " there may be a more efficient way to do this
        call s:RefreshOneRegister_bufinfo(s:GetBufinfosForRegistersAsList('/', []))
    catch
        call s:log('s:AutoCursorHold Exception: '.v:exception)
    endtry
endfunction

function! s:AutoInsertLeave()
    try
        " refresh the dot register if it is being viewed
        call s:RefreshOneRegister_bufinfo(s:GetBufinfosForRegistersAsList('.', []))
    catch
        call s:log('s:AutoInsertLeave Exception: '.v:exception)
    endtry
endfunction

function! s:AutoFocusGained()
    try
        " refresh the clipboard + and * registers if they are being viewed
        let l:bufinfos = s:GetBufinfosForRegistersAsList('+*', [])
        for l:bufinfo in l:bufinfos
            call s:RefreshOneRegister_bufinfo(l:bufinfo)
        endfor
    catch
        call s:log('s:AutoFocusGained Exception: '.v:exception)
    endtry
endfunction

" TODO instead get bufinfo for register?
function! s:GetBufferNumberForRegister(register)
    for buf in getbufinfo()
        if has_key(buf, 'variables')
            if has_key(buf.variables, '_register_')
                if buf.variables._register_ == a:register
                    return buf.bufnr
                endif
            endif
        endif
    endfor
    return -1
endfunction

function! s:GetBufinfosForRegisters(registers)
    " returns an empty list if no bufinfos not found
    let l:result = []
    for l:bufinfo in getbufinfo()
        if has_key(l:bufinfo.variables, '_register_')
            if stridx(a:registers, l:bufinfo.variables._register_) >= 0
                let l:result += [l:bufinfo]
            endif
        endif
    endfor
    return l:result
endfunction

function! s:RegisterName(register)
    if a:register =~ '[a-zA-Z0-9]'
        return a:register
    elseif a:register == '"'
        return 'unnamed'
    elseif a:register == '-'
        return 'small-delete'
    elseif a:register == ':'
        return 'read-only_colon'
    elseif a:register == '.'
        return 'read-only_dot'
    elseif a:register == '%'
        return 'read-only_percent'
    elseif a:register == '#'
        return 'read-only_alternate-buffer'
    elseif a:register == '='
        return 'expression'
    elseif a:register == '*'
        return 'selection_star'
    elseif a:register == '+'
        return 'selection_plus'
    elseif a:register == '~'
        return 'drop'
    elseif a:register == '_'
        return 'black-hole'
    elseif a:register == '/'
        return 'search-pattern'
    endif
    return 'unknown'
endfunction

function! s:RegisterStatusline_bufinfo(bufinfo)
    " call s:log('s:RegisterStatusline_bufinfo bufinfo='.string(a:bufinfo))

    " Can this code block be a function?
    if type(a:bufinfo) == v:t_dict
        let l:bufinfo = a:bufinfo
    elseif type(a:bufinfo) == v:t_list && len(a:bufinfo) > 0
        let l:bufinfo = a:bufinfo[0]
    else
        return
    endif

    if !has_key(l:bufinfo.variables, '_register_')
        return
    endif
    let l:register = l:bufinfo.variables._register_

    " Instead of setlocal statusline, set a local variable.
    " Then call setbufvar on the bufname for variable name statusline with the local variable.

    " put in descriptive register name
    let l:statusline = '[ register  "'.l:register
    if l:register == '%'
        let l:statusline .= '%'  " repeat the percent sign
    endif
    if l:register !~ '[a-zA-Z0-9]'
        let l:regname=s:RegisterName(l:register)
        let l:statusline .= ' '.l:regname
    endif
    let l:statusline .= ' ] %m%r'

    if len(getreg(l:register, 1, v:true)) == 0
        let l:statusline .= ' empty'
    else
        let l:regtype = getregtype(l:register)
        if l:regtype ==# 'v'
            let l:statusline .= ' characterwise byte %o'
            let l:statusline .= ' of %{string(wordcount()["bytes"]-1)}'
        elseif l:regtype ==# 'V'
            let l:statusline .= ' linewise'
            let l:statusline .= ' lines=%L'
        elseif len(l:regtype) != 0
            let l:statusline .= ' blockwise-visual'
            let l:statusline .= ' width='.l:regtype[1:]
        endif
    endif

    " add buffer number, mostly as a kind of debugging
    let l:statusline .= '%=bufnr='.l:bufinfo.bufnr
    let l:statusline .= ' winid='.win_getid()

    " finally set the statusline in the buffer
    call setbufvar(l:bufinfo.name, '&statusline', l:statusline)
    " call s:log('s:RegisterStatusline_bufinfo: "'.l:statusline.'"')
    call s:log('s:RegisterStatusline_bufinfo register='.l:register.' bufnr='.l:bufinfo.bufnr.' winid='.win_getid())
endfunction

function! s:RefreshRegister()
    " TODO convert to using buffer number from <abuf>
    call s:log('s:RefreshRegister '.b:_register_.' v:event='.string(v:event))
    let l:bufinfo = getbufinfo('%')[0]
    if !l:bufinfo.changed
        " If the buffer has not been modified by the user,
        " refresh the contents from the register
        " in case the register has been modified elsewhere.
        call writefile(split(getreg(b:_register_), '\n'), expand('%'))
        call s:RegisterStatusline_bufinfo(l:bufinfo)

        edit!

        if s:isReadOnly(b:_register_)
            setlocal readonly
        endif
    endif
endfunction

function! s:RefreshOneRegister_bufinfo(bufinfo)
    " input can be a bufinfo array of length zero or one as returned from getbufinfo()
    if type(a:bufinfo) == v:t_list
        if len(a:bufinfo) == 0
            return
        endif
        let l:bufinfo = a:bufinfo[0]
    else
        let l:bufinfo = a:bufinfo
    endif

    if l:bufinfo.loaded && !l:bufinfo.hidden
        call s:log('s:RefreshOneRegister_bufinfo l:bufinfo.bufnr: '.l:bufinfo.bufnr.' _register_='.l:bufinfo.variables._register_)

        " Since the register has been changed and the buffer is
        " visible, then swich to kind of a "view" of the register
        " by setting buftype to nofile.
        " If the buffer is subsequently entered by the user then
        " unset the buftype and allow for direct editing through
        " the vim buffer window once again.
        let l:bufname = bufname(l:bufinfo.bufnr)
        call setbufvar(l:bufname, '&buftype', 'nofile')
        call deletebufline(l:bufname, 1, l:bufinfo.linecount)
        call setbufline(l:bufname, 1, split(getreg(l:bufinfo.variables._register_), '\n'))

        call s:RegisterStatusline_bufinfo(l:bufinfo)
    endif
endfunction

function! s:RefreshPendingRegisters()
    if len(s:pending_bufnrs) > 0
        call s:log('s:RefreshPendingRegisters s:pending_bufnrs='.string(keys(s:pending_bufnrs)))
        let l:bufnrs = keys(s:pending_bufnrs)
        for l:bufnr in l:bufnrs
            let l:reg_bufnr = str2nr(l:bufnr)
            " call s:log('s:RefreshPendingRegisters type(l:bufnr)='.type(l:bufnr).' l:bufnr='.l:bufnr)
            call s:RefreshOneRegister_bufinfo(getbufinfo(l:reg_bufnr))
            unlet s:pending_bufnrs[bufnr]
        endfor
    endif
endfunction

function! g:VimRegRefresh()
    call s:log('g:VimRegRefresh starting')
    let l:count = 0
    let l:registers = ''
    for buf in getbufinfo()
        if has_key(buf, 'variables')
            if has_key(buf.variables, '_register_')
                call s:RefreshOneRegister_bufinfo(buf)
                let l:count += 1
                let l:registers .= buf.variables._register_
            endif
        endif
    endfor
    call s:log('g:VimRegRefresh finished l:count='.l:count.' l:registers='.l:registers)
endfunction

function! s:AutoBufWritePost()
    call s:log('s:AutoBufWritePost <afile>: '.expand('<afile>'))
    let l:text = join(readfile(bufname('%'), 'b'), nr2char(10))
    let l:regtype = getregtype(b:_register_)
    if l:regtype ==# 'v' " characterwise
        let l:text = l:text[:-2]
    endif
    call s:log('call setreg('.b:_register_.')')
    call setreg(b:_register_, l:text, l:regtype)
    call s:RegisterStatusline_register(b:_register_)
endfunction

function! s:AutoFileChangedShellPost()
    call s:log('xx s:AutoFileChangedShellPost <afile>: '.expand('<afile>'))

    " TODO have to decide what to do here
    " If the file has been changed externally, and user okays the loading of
    " the file, then need to somehow detect that and then call setreg.
    " call s:RefreshRegister()
endfunction

function! s:AutoBufWipeout()
    let l:filename = expand('<afile>')
    call s:log('s:AutoBufWipeout l:filename='.l:filename)
    call s:DeleteRegisterFile(l:filename)
endfunction

function! s:AutoVimLeavePre()
    let l:filename = expand('<afile>')
    call s:log('s:AutoVimLeavePre l:filename='.l:filename)
    call s:DeleteRegisterFile(l:filename)
endfunction

function! s:DeleteRegisterFile(filename)
    call s:log('s:DeleteRegisterFile a:filename='.a:filename)
    call delete(a:filename)
endfunction
