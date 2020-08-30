let s:base_column_query = 'select table_name,column_name from information_schema.columns'
let s:query = s:base_column_query.' order by column_name asc'
let s:count_query = 'select count(*) as total from information_schema.columns'
let s:table_column_query = s:base_column_query.' where table_name={db_tbl_name}'
let s:hana_base_query = 'select top 100 column_name from sys.columns'
let s:hana_query = s:hana_base_query . ' order by column_name asc'
let s:hana_count_query = 'select count(*) as total from sys.columns where schema_name = current_schema'
let s:hana_table_column_query = s:hana_base_query . ' where table_name={db_tbl_name} and schema_name = current_schema'

function! s:map_and_filter(delimiter, list) abort
  return filter(
        \ map(a:list, { _, table -> map(split(table, a:delimiter), 'trim(v:val)') }),
        \ 'len(v:val) ==? 2'
        \ )
endfunction

function! s:hana_map(delimiter, list) abort
  return map(a:list[2:-4], {_,table -> table[1:-2]})
endfunction

function! s:hana_count_parsert(index, result) abort
  return str2nr(get(a:result[2:-4], a:index, 0))
endfunction

function! s:count_parser(index, result) abort
  return str2nr(get(a:result, a:index, 0))
endfunction

let s:hdbsql = {
      \ 'column_query': printf('-j "%s"', s:hana_query),
      \ 'count_column_query': printf('-j "%s"', s:hana_count_query),
      \ 'table_column_query': {table -> printf('-j "%s"', substitute(s:hana_table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \ 'quote': 1,
      \ 'column_parser': function('s:hana_map', ['|']),
      \ 'count_parser': function('s:hana_count_parser', [1])
      \ }


let s:postgres = {
      \ 'column_query': printf('-A -c "%s"', s:query),
      \ 'count_column_query': printf('-A -c "%s"', s:count_query),
      \ 'table_column_query': {table -> printf('-A -c "%s"', substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \ 'quote': 1,
      \ 'column_parser': function('s:map_and_filter', ['|']),
      \ 'count_parser': function('s:count_parser', [1])
      \ }

let s:schemas = {
      \ 'postgres': s:postgres,
			\ 'hdbsql': s:hdbsql,
      \ 'postgresql': s:postgres,
      \ 'mysql': {
      \   'column_query': printf('-e "%s"', s:query),
      \   'count_column_query': printf('-e "%s"', s:count_query),
      \   'table_column_query': {table -> printf('-e "%s"', substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \   'quote': 0,
      \   'column_parser': function('s:map_and_filter', ['\t']),
      \   'count_parser': function('s:count_parser', [1])
      \ },
      \ 'sqlserver': {
      \   'column_query': printf('-h-1 -W -s "|" -Q "%s"', s:query),
      \   'count_column_query': printf('-h-1 -W -Q "%s"', s:count_query),
      \   'table_column_query': {table -> printf('-h-1 -W -Q "%s"', substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \   'quote': 0,
      \   'column_parser': function('s:map_and_filter', ['|']),
      \   'count_parser': function('s:count_parser', [0])
      \ },
    \ }

function! vim_dadbod_completion#schemas#get(scheme)
  return get(s:schemas, a:scheme, {})
endfunction
