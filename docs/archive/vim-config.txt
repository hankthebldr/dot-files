:syntax on 
:colorscheme desert 
set rtp+=/opt/homebrew/opt/fzf
set expandtab
set tabstop=2
set shiftwidth=2
filetype plugin indent on

call plug#begin('~/.vim/plugged')

" Add plugins here
Plug 'preservim/nerdtree'      " File Explorer
Plug 'vim-airline/vim-airline' " Status Line
Plug 'tpope/vim-fugitive'      " Git Integration
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }  " Fuzzy Finder

call plug#end()

