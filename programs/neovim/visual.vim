"" Visual Changes
set number norelativenumber " line numberings
set hlsearch incsearch " highlighting when using find
set cc=80
set cursorline

" https://shapeshed.com/vim-statuslines/
set statusline=
set statusline+=\ %f
set statusline+=%m
set statusline+=%=
set statusline+=\ %y
set statusline+=\ %p%%
set statusline+=\ %c:%l
set statusline+=\

" Hiding the UI
" https://unix.stackexchange.com/questions/140898/vim-hide-status-line-in-the-bottom
let s:hidden_all = 0
function! ToggleHiddenAll()
  if s:hidden_all  == 0
    let s:hidden_all = 1
    set noshowmode
    set noruler
    set laststatus=0
    set noshowcmd
    set nocul
    set cc=
  else
    let s:hidden_all = 0
    set showmode
    if &ft != 'netrw'
      set ruler
      set cul
      set cc=80
    endif
    set laststatus=2
    set showcmd
  endif
endfunction

" GUI Mode
if has('gui_running')
  set guioptions=cs
endif

" Split panes more obvious, terminal prettier
augroup BgHighlight
  autocmd!
  autocmd BufWinEnter,WinEnter,BufEnter *
        \ if &ft != 'netrw' && &buftype !='terminal' |
        \ setlocal cul cc=80 |
        \ let s:hidden_all = 1 | call ToggleHiddenAll() |
        \ endif " Set color column
  if exists(':terminal')
    if has('nvim')
      autocmd TermOpen * setlocal nonumber norelativenumber cc= wrap
    elseif exists('##TerminalOpen')
      autocmd TerminalOpen * setlocal nonumber norelativenumber cc= wrap
    endif
  endif
  autocmd BufWinEnter,WinEnter * if &ft == 'netrw' | setlocal cc= | endif
  autocmd BufWinLeave,WinLeave *
        \ if &ft != 'netrw' && &buftype != 'terminal' |
        \ setlocal nocul |
        \ setlocal cc= |
        \ endif
augroup END

command! SynStack call SynStack()
function! SynStack()
  if !exists("*synstack")
    return
  endif
  echo map(synstack(line('.'), col('.')), 'synIDattr(v:val,"name")')
endfunction

command! ToggleBgFlag call ToggleFlag('light-mode') | call ReadBgFlag()
command! ToggleBg call ToggleFlag('light-mode') | call ReadBgFlag()

command! ReadBgFlag call ReadBgFlag()
function! ReadBgFlag()
  if ReadFlag('light-mode')
    set background=light
  else
    set background=dark
  endif
endfunction
ReadBgFlag

" Color Scheme
if g:plugins_enabled && g:plugins_installed 
  colorscheme solarized8_high
else
  colorscheme default
endif

" Font on GUI Programs
if g:os ==? 'Windows'
  if &guifont !=? 'Consolas:h12'
    set guifont=Consolas:h12
  endif
elseif g:os ==? 'Darwin'
  if &guifont !=? 'Menlo:h12'
    set guifont=Menlo:h12
  endif
else
  if &guifont !=? 'Courier:h12'
    set guifont=Courier:h12
  endif
endif

