#!/usr/bin/env python3

import sys, time, pprint, asyncio, tempfile, unittest
from pathlib import Path

try:
    import vim_channeler
except ImportError:
    print('''
The VimChanneler package is required as a dependency.
Download from https://github.com/m6z/VimChanneler and add to PYTHONPATH
''')
    sys.exit(1)

class VimRegBasicTest(vim_channeler.VimChannelerFixture):

    async def asyncSetUp(self):
        self.vimch = await self.createVimChanneler()
        plugin_vim = Path(__file__) / '../../plugin/vimreg_deluxe.vim'
        plugin_vim = plugin_vim.resolve()
        # print(f'plugin_vim={plugin_vim}')
        await self.vimch.ex(f'source {plugin_vim}')

    async def test_plugin_loaded(self):
        scriptnames = await self.vimch.ex_redir('scriptnames')
        # print('scripts loaded:')
        # pprint.pprint([x for x in scriptnames.splitlines() if x])
        self.assertGreaterEqual(scriptnames.find('vimreg_deluxe.vim'), 0)

    async def test_basic_edits(self):
        # Work with registers
        reg_a = 'hello from register a 1\na 2\na 3'
        reg_b = 'yo from register b 1\nb 2\nb 3\nb 4'
        await self.vimch.ex(f"let @a='{reg_a}'")
        await self.vimch.ex(f"let @b='{reg_b}'")

        # open registers a and b for view
        await self.vimch.call("VimReg_View", 'ab')

        # jump to the top window - should be register a
        await self.vimch.ex("wincmd t")
        lines = await self.vimch.get_buffer_lines()
        # print('lines={} reg_a={}'.format(lines, reg_a))
        self.assertEqual(lines, reg_a.splitlines())
        bufnr = await self.vimch.expr("bufnr('%')")
        # print(f'reg a bufnr={bufnr}')

        # jump down to the 2nd window - should be register b
        await self.vimch.ex("wincmd j")
        lines = await self.vimch.get_buffer_lines()
        # print('lines={} reg_b={}'.format(lines, reg_b))
        self.assertEqual(lines, reg_b.splitlines())
        # print(f'reg b bufnr={bufnr}')

        # edit some text in buffer for register b
        await self.vimch.ex('%s;\<b\>;BB;g')
        lines = await self.vimch.get_buffer_lines()
        count_BB_in_buffer = '\n'.join(lines).count('BB')
        # print('count_BB_in_buffer={}'.format(count_BB_in_buffer))
        self.assertEqual(count_BB_in_buffer, 4)
        await self.vimch.ex('write')  # triggers register update
        reg_b_changed = await self.vimch.call('getreg', 'b')
        # print('lines={} reg_b_changed={}'.format(lines, reg_b_changed))
        count_BB_in_reg_b = reg_b_changed.count('BB')
        # print('count_BB_in_reg_b={}'.format(count_BB_in_reg_b))
        self.assertEqual(count_BB_in_reg_b, 4)

    async def test_edit_file_via_register(self):
        fn = Path(tempfile.gettempdir(), 'edit_one_register.tmp')
        fn.write_text('The quick brown fox\njumped over the lazy dogs\n')
        # print(f'edit_one_register fn={fn}')

        await self.vimch.ex(f'edit {fn}')           # open the file in vim
        await self.vimch.ex('1')                    # go to the first line
        await self.vimch.ex('normal "ayy')          # yank the line to register a
        await self.vimch.call('VimReg_Edit', 'a')   # start editing register a

        # figure out the buffer number
        bufnr = await get_bufnr_for_register(self.vimch, 'a')
        # print(f'bufnr={bufnr}')

        # verify that register has a relevant statusline
        statusline = await self.vimch.call('getbufvar', bufnr, '&statusline')
        # print(f'statusline={statusline}')
        self.assertTrue('register  "a' in statusline)

        await self.vimch.ex('%sub/quick/Quickest/')   # change some text
        await self.vimch.ex('wq')                     # write register, quit buffer
        await self.vimch.ex('$')                      # go to the last line
        await self.vimch.ex('normal "ap')             # write register a
        await self.vimch.ex('w')                      # write the file
        await asyncio.sleep(0.1)                      # pause for write to complete

        # verify that the change to the register via the buffer made it to the file
        lines = fn.read_text().splitlines()
        # print(f'lines={lines}')
        self.assertEqual(len(lines), 3)
        self.assertEqual(lines[2], 'The Quickest brown fox')

    async def test_window_management(self):
        # Exercise view, edit and close functions

        # view file -> expect file
        fn = 'temp.txt'
        await self.vimch.ex(f'view {fn}')  # view a single file
        fns = await get_files_in_column(self.vimch)
        self.assertEqual(fns, ['temp.txt'])

        # view a -> expect a, file
        await self.vimch.call("VimReg_View", 'a')  # open a single register
        fns = await get_files_in_column(self.vimch)
        self.assertTrue(fns[0].startswith('vimreg_a'))
        self.assertEqual(fns[1], 'temp.txt')
        # verify height of a as register view window
        vimreg_window_size_view = await self.vimch.expr('g:vimreg_window_size_view')
        winid = await get_winid_for_register(self.vimch, 'a')
        winheight_a = await self.vimch.expr(f'winheight({winid})')
        self.assertEqual(winheight_a, vimreg_window_size_view)

        # view b -> expect b, a, file
        # indicate a custom height for view
        await self.vimch.call("VimReg_View", 'b', vimreg_window_size_view + 1)
        fns = await get_files_in_column(self.vimch)
        self.assertTrue(fns[0].startswith('vimreg_b'))
        self.assertTrue(fns[1].startswith('vimreg_a'))
        self.assertEqual(fns[2], 'temp.txt')
        # verify view height
        winid = await get_winid_for_register(self.vimch, 'b')
        winheight_b = await self.vimch.expr(f'winheight({winid})')
        self.assertEqual(winheight_b, vimreg_window_size_view + 1)

        # view a,b,c -> expect a,b,c,file
        await self.vimch.call("VimReg_View", 'abc')
        fns = await get_files_in_column(self.vimch)
        self.assertTrue(fns[0].startswith('vimreg_a'))
        self.assertTrue(fns[1].startswith('vimreg_b'))
        self.assertTrue(fns[2].startswith('vimreg_c'))
        self.assertEqual(fns[3], 'temp.txt')

        # edit b -> expect b,a,c,file
        await self.vimch.call("VimReg_Edit", 'b')
        fns = await get_files_in_column(self.vimch)
        self.assertTrue(fns[0].startswith('vimreg_b'))
        self.assertTrue(fns[1].startswith('vimreg_a'))
        self.assertTrue(fns[2].startswith('vimreg_c'))
        self.assertEqual(fns[3], 'temp.txt')
        # verify height of b as register edit window
        vimreg_window_size_edit = await self.vimch.expr('g:vimreg_window_size_edit')
        winid = await get_winid_for_register(self.vimch, 'b')
        winheight_b = await self.vimch.expr(f'winheight({winid})')
        self.assertEqual(winheight_b, vimreg_window_size_edit)

        # close a -> expect b,c,file
        await self.vimch.call('VimReg_Close', '', 'a')
        fns = await get_files_in_column(self.vimch)
        print(f'fns={fns}')
        self.assertTrue(fns[0].startswith('vimreg_b'))
        self.assertTrue(fns[1].startswith('vimreg_c'))
        self.assertEqual(fns[2], 'temp.txt')

        # close (all) -> file
        await self.vimch.call('VimReg_Close', '', '')
        fns = await get_files_in_column(self.vimch)
        print(f'fns={fns}')
        self.assertEqual(fns[0], 'temp.txt')

#----------------------------------------------------------------------
# utilities

async def get_bufnr_for_register(vimch, register):
    bufinfos = await vimch.expr('getbufinfo()')
    for bufinfo in bufinfos:
        try:
            if bufinfo['variables']['_register_'] == register:
                return bufinfo['bufnr']
        except KeyError:
            pass
    return 0  # not found

async def get_winid_for_register(vimch, register):
    # returns the first winid in case of multiple instances
    bufinfos = await vimch.expr('getbufinfo()')
    for bufinfo in bufinfos:
        try:
            if bufinfo['variables']['_register_'] == register:
                return bufinfo['windows'][0]
        except KeyError:
            pass
    return 0  # not found

async def get_files_in_column(vimch):
    # return the basenames of the files in column order
    bufinfos = await vimch.expr('getbufinfo()')
    filenames = {}  # key is window id, value is file basename
    for bufinfo in bufinfos:
        filename = Path(bufinfo['name']).name
        for winid in bufinfo['windows']:
            filenames[winid] = filename
    column_winids = await vimch.call('VimReg_GetCurrentWindowsInColumn')
    result = []  # list of file basenames
    for winid in column_winids:
        result.append(filenames.get(winid))
    return result

#----------------------------------------------------------------------

# TODO put in usage tip for VimChanneler
# if vim call is wrong, run script with -l /tmp/vimch.log and look for error message in that file
# since this is the file that vim itself creates

if __name__ == '__main__':
    parser = vim_channeler.vim_channeler_argparser()
    # separate vim scenario args and unit test args
    vimch_args, unittest_args = parser.parse_known_args()
    print(f'vimch_args={vimch_args}')
    print(f'unittest_args={unittest_args}')

    # relevant for windows os
    vim_channeler.set_vim_channeler_event_loop_policy()

    vim_channeler.VimChannelerFixture.vim_channeler_args = vimch_args
    unittest.main(argv=[sys.argv[0]] + unittest_args)
    time.sleep(0.1)

# vim: ff=unix
