if !has('nvim')
  finish
end

map  p  <Plug>(miniyank-autoput)
map  P  <Plug>(miniyank-autoPut)
nmap gp <Plug>(miniyank-cycle)
