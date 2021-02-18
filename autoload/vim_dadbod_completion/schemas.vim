let s:base_column_query = 'select table_name,column_name from information_schema.columns'
let s:query = s:base_column_query.' order by column_name asc'
let s:schema_query = 'select table_schema,table_name from information_schema.columns group by table_schema,table_name'
let s:count_query = 'select count(*) as total from information_schema.columns'
let s:table_column_query = s:base_column_query.' where table_name={db_tbl_name}'
let s:hana_base_query = 'select table_name,column_name from sys.columns'
let s:hana_query = "select distinct table_name, column_name from table_columns"
let s:hana_schema_query = 'select distinct schema_name, table_name from m_tables group by schema_name, table_name'
let s:hana_count_query = 'select count(*) as total from table_columns'
let s:hana_table_column_query = s:hana_base_query . ' where table_name={db_tbl_name}'
let s:reserved_words = vim_dadbod_completion#reserved_keywords#get_as_dict()
let s:quote_rules = {
      \ 'camelcase': {val -> val =~# '[A-Z]' && val =~# '[a-z]'},
      \ 'space': {val -> val =~# '\s'},
      \ 'reserved_word': {val -> has_key(s:reserved_words, toupper(val))}
      \ }

function! s:map_and_filter(delimiter, list) abort
  return filter(
        \ map(a:list, { _, table -> map(split(table, a:delimiter), 'trim(v:val)') }),
        \ 'len(v:val) ==? 2'
        \ )
endfunction

function! s:hana_map(delimiter, list) abort
  return filter(
      \ map(a:list, { _, table -> map(split(table, a:delimiter), 'trim(substitute(v:val, "\"", "", "g"))') }),
      \ 'len(v:val) ==? 2'
      \ )
endfunction

function! s:hana_count_parser(index, result) abort
  let countList = a:result[2:-4]
  return str2nr(get(countList, a:index, 0))
endfunction

function! s:should_quote(rules, val) abort
  if empty(trim(a:val))
    return 0
  endif

  let do_quote = 0

  for rule in a:rules
    let do_quote = s:quote_rules[rule](a:val)
    if do_quote
      break
    endif
  endfor

  return do_quote
endfunction

function! s:count_parser(index, result) abort
return str2nr(get(a:result, a:index, 0))
endfunction

let s:hdbsql = {
      \ 'column_query': printf('-j "%s"', s:hana_query),
      \ 'count_column_query': printf('-j "%s"', s:hana_count_query),
      \ 'table_column_query': {table -> printf('-j "%s"', substitute(s:hana_table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \ 'schemas_query': printf('-j "%s"', s:hana_schema_query),
      \ 'schemas_parser': function('s:hana_map', [',']),
      \ 'quote': ['"', '"'],
      \ 'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
      \ 'column_parser': function('s:hana_map', [',']),
      \ 'count_parser': function('s:hana_count_parser', [0])
      \ }


let s:postgres = {
      \ 'column_query': printf('-A -c "%s"', s:query),
      \ 'count_column_query': printf('-A -c "%s"', s:count_query),
      \ 'table_column_query': {table -> printf('-A -c "%s"', substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \ 'functions_query': printf('-A -c "%s"', "SELECT routine_name FROM information_schema.routines WHERE routine_type='FUNCTION'"),
      \ 'functions_parser': {list->list[1:-4]},
      \ 'schemas_query': printf('-A -c "%s"', s:schema_query),
      \ 'schemas_parser': function('s:map_and_filter', ['|']),
      \ 'quote': ['"', '"'],
      \ 'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
      \ 'column_parser': function('s:map_and_filter', ['|']),
      \ 'count_parser': function('s:count_parser', [1])
      \ }

let s:oracle_args = "echo \"SET linesize 4000;\nSET pagesize 4000;\n%s\" | "
let s:oracle_base_column_query = printf(s:oracle_args, "COLUMN column_name FORMAT a50;\nCOLUMN table_name FORMAT a50;\nSELECT C.table_name, C.column_name FROM all_tab_columns C JOIN all_users U ON C.owner = U.username WHERE U.common = 'NO' %s;")
let s:oracle = {
\   'column_parser': function('s:map_and_filter', ['\s\s\+']),
\   'column_query': printf(s:oracle_base_column_query, 'ORDER BY C.column_name ASC'),
\   'count_column_query': printf(s:oracle_args, "COLUMN total FORMAT 9999999;\nSELECT COUNT(*) AS total FROM all_tab_columns C JOIN all_users U ON C.owner = U.username WHERE U.common = 'NO';"),
\   'count_parser': function('s:count_parser', [1]),
\   'quote': ['"', '"'],
\   'schemas_query': printf(s:oracle_args, "COLUMN owner FORMAT a20;\nCOLUMN table_name FORMAT a25;\nSELECT T.owner, T.table_name FROM all_tables T JOIN all_users U ON T.owner = U.username WHERE U.common = 'NO' ORDER BY T.table_name;"),
\   'schemas_parser': function('s:map_and_filter', ['\s\s\+']),
\   'should_quote': function('s:should_quote', [['camelcase', 'reserved_word', 'space']]),
\   'table_column_query': {table -> printf(s:oracle_base_column_query, "AND C.table_name='".table."'")},
\ }

let s:schemas = {
      \ 'postgres': s:postgres,
      \ 'hdbsql': s:hdbsql,
      \ 'postgresql': s:postgres,
      \ 'mysql': {
      \   'column_query': printf('-e "%s"', s:query),
      \   'count_column_query': printf('-e "%s"', s:count_query),
      \   'table_column_query': {table -> printf('-e "%s"', substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \   'schemas_query': printf('-e "%s"', s:schema_query),
      \   'schemas_parser': function('s:map_and_filter', ['\t']),
      \   'quote': ['`', '`'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['\t']),
      \   'count_parser': function('s:count_parser', [1])
      \ },
      \ 'oracle': s:oracle,
      \ 'sqlserver': {
      \   'column_query': printf('-h-1 -W -s "|" -Q "%s"', s:query),
      \   'count_column_query': printf('-h-1 -W -Q "%s"', s:count_query),
      \   'table_column_query': {table -> printf('-h-1 -W -Q "%s"', substitute(s:table_column_query, '{db_tbl_name}', "'".table."'", ''))},
      \   'schemas_query': printf('-h-1 -W -s "|" -Q "%s"', s:schema_query),
      \   'schemas_parser': function('s:map_and_filter', ['|']),
      \   'quote': ['[', ']'],
      \   'should_quote': function('s:should_quote', [['reserved_word', 'space']]),
      \   'column_parser': function('s:map_and_filter', ['|']),
      \   'count_parser': function('s:count_parser', [0])
      \ },
    \ }

function! vim_dadbod_completion#schemas#get(scheme)
  return get(s:schemas, a:scheme, {})
endfunction

function! vim_dadbod_completion#schemas#get_quotes_rgx() abort
  let open = []
  let close = []
  for db in values(s:schemas)
    if index(open, db.quote[0]) <= -1
      call add(open, db.quote[0])
    endif

    if index(close, db.quote[1]) <= -1
      call add(close, db.quote[1])
    endif
  endfor

  return {
        \ 'open': escape(join(open, '\|'), '[]'),
        \ 'close': escape(join(close, '\|'), '[]')
        \ }
endfunction
