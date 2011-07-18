"=============================================================================
"    Copyright: Copyright (C) 2009 Niels Aan de Brugh
"               Permission is hereby granted to use and distribute this code,
"               with or without modifications, provided that this copyright
"               notice is copied with it. Like anything else that's free,
"               filtering.vim is provided *as is* and comes with no
"               warranty of any kind, either expressed or implied. In no
"               event will the copyright holder be liable for any damages
"               resulting from the use of this software.
" Name Of File: filtering.vim
"  Description: Quick Filter Plugin Vim Plugin
"   Maintainer: Niels Aan de Brugh (nielsadb+vim at gmail dot com)
" Last Changed: 2 July 2011
"      Version: See g:filtering2_version for version number.
"        Usage: This file should reside in the plugin directory and be
"               automatically sourced.
"=============================================================================

if exists("g:filtering2_version") || &cp
    " finish
endif
let g:filtering_version = '2.0alpha'

function! FilteringEmptyCallback(obj)"{{{
  " This function should be empty and at the top of this file.
endfunction"}}}

" Public Methods
function! FilteringRun() dict"{{{
  if empty(self.alt)
    return <SID>FancyError("@1No search pattern set.@0 Add at least one search pattern alternative, e.g. addToParameter('alt', 'stuff').")
  endif
  if !bufexists(self.source)
    return <SID>FancyError(printf('Buffer %d @1no longer exists@0.', self.source))
  endif

  call <SID>FlipToWindowOrLoadBufferHere(self.source)

  let self.matches = {}
  let self.context_top = {}
  let self.context_bottom = {}
  let self.context_extra = {}

  let start_position = getpos('.')
  let search_register = @/
  for attr in s:UnpackedAttributes
    let {'s:'.attr} = self[attr]
  endfor
  if exists('b:filtering_target')
    silent exe printf('g/%s/call <SID>AddMatchFromResultWindow()', join(self.alt, '\|'))
  else
    silent exe printf('g/%s/call <SID>AddMatch()', join(self.alt, '\|'))
  endif
  let @/ = search_register
  call setpos('.', start_position)
  for attr in s:UnpackedAttributes
    unlet {'s:'.attr}
  endfor

  if self.target == -1 || !bufexists(self.target)
    let self.target = self.createNewResultWindow()
  else
    call <SID>FlipToWindowOrLoadBufferHere(self.target)
  endif

  return self.pasteResults()
endfunction
let s:UnpackedAttributes = ['include', 'exclude', 'matches', 'match_context_in_results',
      \ 'extra', 'context_lines', 'extra_stop_lines', 'extra_stop_pattern',
      \ 'context_extra', 'context_top', 'context_bottom']
"}}}
function! FilteringReturn() dict"{{{
  if !bufexists(self.target)
    return <SID>FancyError('The search window was @1already closed@0.)
  endif
  call <SID>FlipToWindowOrLoadBufferHere(self.target)
  return self
endfunction"}}}
function! FilteringAddToParameter(name, value) dict"{{{
  let rv = self.validateParameter(s:ValidAddToParams, a:name, a:value, 'addToParameter')
  if !rv.dummy
    if type(self[a:name]) == type([])
      call add(self[a:name], a:value)
    elseif type(self[a:name]) == type(42)
      let self[a:name] += a:value
    endif
  endif
  return rv
endfunction
let s:ValidAddToParams = {
      \'alt'                 : type(''),
      \'include'             : type(''),
      \'exclude'             : type(''),
      \'context_lines'       : type(42),
      \'context_lines_mode'  : type(42),
      \'show_match_to_extra' : type(42),
      \'show_results_raw'    : type(42),
      \}"}}}
function! FilteringAddInputToParameter(name, prompt) dict"{{{
  let value = self.on_input_requested(a:prompt)
  return empty(value) ? <SID>FilteringStub('') : self.addToParameter(a:name, value)
endfunction"}}}
function! FilteringSetParameterToInput(name, prompt) dict"{{{
  let value = self.on_input_requested(a:prompt)
  return empty(value) ? <SID>FilteringStub('') : self.setParameter(a:name, value)
endfunction"}}}
function! FilteringSetParameter(name, value) dict"{{{
  let rv = self.validateParameter(s:ValidSetParams, a:name, a:value, 'setParameter')
  if !rv.dummy
    let self[a:name] = a:value
  endif
  return rv
endfunction
let s:ValidSetParams = {
      \'on_result_buffer_created' : type(function('FilteringEmptyCallback')),
      \'context_lines'            : type(42),
      \'auto_follow'              : type(42),
      \'context_lines_mode'       : type(42),
      \'show_match_to_extra'      : type(42),
      \'show_results_raw'         : type(42),
      \}"}}}

function! FilteringReEvaluate() dict"{{{
  if !empty(self.last_settings) && self.context_lines <= self.last_settings.context_lines
    for setting in ['alt', 'include', 'exclude', 'extra', 'extra_stop_pattern', 'extra_stop_lines']
      if self.last_settings[setting] != self[setting]
        return self.run()
      endif
    endfor
    return self.redraw()
  endif
  return self.run()
endfunction"}}}
function! FilteringParseQuery(query, separator) dict"{{{
  let pattern_parts = split(a:query, a:separator)
  let self.alt = pattern_parts[0]
  if len(pattern_parts) > 1
    let self.extra = pattern_parts[1]
  endif
  if len(pattern_parts) > 2
    if pattern_parts[2] + 0
      let self.extra_stop_lines = pattern_parts[2] + 0
      let self.extra_stop_pattern = ''
    elseif type(pattern_parts[2]) == type('')
      let self.extra_stop_lines = -1
      let self.extra_stop_pattern = pattern_parts[2]
    else
      let self.extra_stop_lines = <SID>Def('g:filteringExtraPatternDefaultLinesAhead', -1)
      let self.extra_stop_pattern = <SID>Def('g:filteringExtraPatternDefaultStopPattern', '^$')
    endif
  endif
  return self
endfunction"}}}
function! FilteringGotoLineInBuffer(buffer_nr, source_line_nr, close) dict"{{{
  if a:line_nr < 1
    return
  endif
  if buffer_nr == self.target
    return <SID>FancyError('Cannot follow result in target window. Programming error?')
  endif
  if a:window
    bdelete
  endif
  call <SID>FlipToWindowOrLoadBufferHere(buffer_nr)
  exe 'normal! ' . a:source_line_nr . 'G'
  normal! zz
  return self
endfunction"}}}
function! FilteringFollowInBuffer(buffer_nr, line_nr, blink_times) dict"{{{
  if a:line_nr < 1
    return
  endif
  let source_window = bufwinnr(a:buffer_nr)
  if source_window != -1
    let start_window = winnr()
    exe source_window . 'wincmd w'
    exe 'normal! ' . a:line_nr . 'G'
    exe 'normal! zz'
    call self.blink(a:blink_times)
    exe start_window . 'wincmd w'
  endif
  return self
endfunction"}}}
function! FilteringGetCurrentLineSelection() dict"{{{
  if <SID>ValidateCalledFromResults('getCurrentLineSelection')
    let l:linenr = matchstr(getline('.'), "^[_ ] *[0-9]*:")
    if !empty(l:linenr)
      let l:firstdigit = match(l:linenr, "[0-9]")
      let l:linenr = strpart(l:linenr, l:firstdigit, strlen(l:linenr) - l:firstdigit - 1)
      return l:linenr
    endif
  endif
  return -1
endfunction"}}}
function! FilteringDestruct() dict"{{{
  let start_buffer = bufnr('')
  if bufexists(self.target)
    call <SID>FlipToWindowOrLoadBufferHere(self.target)
    bdelete
  endif
  if bufexists(self.source)
    call <SID>FlipToWindowOrLoadBufferHere(self.source)
    if exists('b:filtering_source')
      silent! unlet b:filtering_source[self.id]
    endif
  endif
  if start_buffer != self.target
    call <SID>FlipToWindowOrLoadBufferHere(start_buffer)
  endif
  return self
endfunction"}}}
function! FilteringBlink(times) dict"{{{
  for i in range(1, 2*a:times)
    set invcursorline
    redraw
    sleep 100m
  endfor
  return self
endfunction"}}}
function! FilteringToggleAutoFollow(kind) dict"{{{
  " This function keeps auto follow for source and original synchronized if
  " that is the same buffer. This is more convenient.
  if kind == 'source'
    let self.auto_follow_source = !self.auto_follow_source
    if self.source == self.original
      let self.auto_follow_original = s!elf.auto_follow_source
    endif
  elseif kind == 'original'
    let self.auto_follow_original = !self.auto_follow_original
    if self.source == self.original
      let self.auto_follow_source = s!elf.auto_follow_original
    endif
  else
    return <SID>FancyError('Incorrect kind @1'.a:kind.'@0.')
  endif
  call <SID>FancyEcho(printf('Auto follow: Original @1%s@0 Source @1%s@0',
        \ self.auto_follow_original ? 'ON' : 'OFF',
        \ self.auto_follow_source ? 'ON' : 'OFF')
  return self
endfunction"}}}

" Public methods (convenience).
function! FilteringGotoSelectionInOriginal(close) dict"{{{
  return self.gotoLineInBuffer(self.orginal, self.getCurrentLineSelection(), a:close)
endfunction"}}}
function! FilteringGotoSelectionInSource(close) dict"{{{
  return self.gotoLineInBuffer(self.source, self.getCurrentLineSelection(), a:close)
endfunction"}}}
function! FilteringFollowSelectionInOriginal(blink_times) dict"{{{
  return self.followInBuffer(self.original, self.getCurrentLineSelection(), a:blink_times)
endfunction"}}}
function! FilteringFollowSelectionInSource(blink_times) dict"{{{
  return self.followInBuffer(self.source, self.getCurrentLineSelection(), a:blink_times)
endfunction"}}}

" Public Functions
function! FilteringNew()"{{{
  " 1st section: public methods.
  " 1st section: public methods (convenience)
  " 2nd section: public attributes.
  " 2nd section: public read-only attributes.
  " 4th section: public callbacks.
  " 5th section: private methods.
  " 6th section: private attributes.
  let ctx = exists('b:filtering_target') ? 0 : <SID>Def('g:filteringDefaultContextLines', 0)
  if !exists('b:filtering_source')
    let b:filtering_source = {}
  endif
  let s:object_id += 1
  let obj = {
        \'run'                      : function('FilteringRun'),
        \'return'                   : function('FilteringReturn'),
        \'addToParameter'           : function('FilteringAddToParameter'),
        \'addInputToParameter'      : function('FilteringAddInputToParameter'),
        \'setParameter'             : function('FilteringSetParameter'),
        \'setParameterToInput'      : function('FilteringSetParameterToInput'),
        \'reevaluate'               : function('FilteringReEvaluate'),
        \'parseQuery'               : function('FilteringParseQuery'),
        \'gotoLineInBuffer'         : function('FilteringGotoLineInBuffer'),
        \'followInBuffer'           : function('FilteringFollowInBuffer'),
        \'getCurrentLineSelection'  : function('FilteringGetCurrentLineSelection'),
        \'destruct'                 : function('FilteringDestruct'),
        \'blink'                    : function('FilteringBlink'),
        \'toggleAutoFollow'         : function('FilteringToggleAutoFollow'),
        \
        \'gotoSelectionInOriginal'  : function('FilteringGotoSelectionInOriginal'),
        \'gotoSelectionInSource'    : function('FilteringGotoSelectionInSource'),
        \'followSelectionInOriginal': function('FilteringFollowSelectionInOriginal'),
        \'followSelectionInSource'  : function('FilteringFollowSelectionInSource'),
        \
        \'alt'                      : [],
        \'include'                  : [],
        \'exclude'                  : [],
        \'extra'                    : '',
        \'context_lines'            : ctx,
        \'extra_stop_lines'         : <SID>Def('g:filteringExtraPatternDefaultLinesAhead', -1),
        \'extra_stop_pattern'       : <SID>Def('g:filteringExtraPatternDefaultStopPattern', '^$'),
        \'match_context_in_results' : <SID>Def('g:filteringMatchContextInResults', 1),
        \'show_match_to_extra'      : <SID>Def('g:filteringShowMatchToExtra', 1),
        \'show_results_raw'         : <SID>Def('g:filteringShowResultsRaw', 0),
        \
        \'id'                       : s:object_id,
        \'dummy'                    : 0,
        \
        \'on_result_buffer_created' : function('FilteringEmptyCallback'),
        \'on_input_requested'       : function('input'),
        \
        \'createNewResultWindow'    : function('FilteringCreateNewWindow'),
        \'setKeyMappings'           : function('FilteringSetKeyMappings'),
        \'pasteResults'             : function('FilteringPasteResults'),
        \'validateParameter'        : function('FilteringValidateParameter'),
        \'redraw'                   : function('FilteringRedraw'),
        \
        \'original'                 : exists('b:filtering_target') ? b:filtering_target.original : bufnr(''),
        \'source'                   : bufnr(''),
        \'target'                   : -1,
        \'context_lines_mode'       : 0,
        \'last_settings'            : {},
        \'auto_follow_source'       : <SID>Def('g:filteringDefaultAutoFollow', 0),
        \'auto_follow_original'     : <SID>Def('g:filteringDefaultAutoFollow', 0),
        \}
  let b:filtering_source[obj.id] = obj
  return obj
endfunction
let s:object_id = 1
"}}}
function! FilteringGetForTarget()"{{{
  return exists('b:filtering_target')
        \ ? b:filtering_target
        \ : <SID>FilteringStub('Not a filtering results window.')
endfunction"}}}
function! FilteringGetForSource(...)"{{{
  if !exists('b:filtering_source')
    return <SID>FilteringStub('@1No search@0 was ever started from this window.')
  endif
  let actual_searches = filter(b:filtering_source, 'v:val.target != -1')
  if empty(actual_searches)
    return <SID>FilteringStub('All filtering window have been @1closed@0.')
  elseif len(actual_searches) == 1
    return value(actual_searches)[0]
  else
    if exists('a:001')
      return a:001(values(actual_searches))
    else
      return <SID>SelectFromMultipleSearches(values(actual_searches))
    endif
  endif
endfunction"}}}

" Private Methods
function! FilteringCreateNewWindow() dict"{{{
  " Just create a new window, and resize if it's too big. Trying to derive
  " the correct size from the start is futile, see the code of the previous
  " version (and that still was not robust).
  let max_height = len(self.matches)
        \ + len(self.context_top) * len(self.context_top)
        \ + len(self.context_bottom) * len(self.context_bottom)
  wincmd n
  if winheight(winnr()) > max_height
    exe 'resize -' . (winheight(winnr()) - max_height)
  endif

  setlocal buftype=nofile bufhidden=hide noswapfile winfixheight nowrap
  setlocal cursorline nonumber
  let b:filtering_target = self

  " Auto command for auto-follow.
  au CursorMoved <buffer> call <SID>AutoCmdCursorMoved()

  " Syntax highlighting mimicks original buffer, gray out context lines.
  exe "setlocal filetype=" . getbufvar(self.original, '&filetype')
  syntax match FilterContext "^_ *\d\+: .*$"

  call self.setKeyMappings()
  call self.on_result_buffer_created(self)
  return bufnr('')
endfunction"}}}
function! FilteringSetKeyMappings() dict"{{{
  let s:mappingFilter = <SID>Def('g:filteringDefaultKeyMappings', [])
  call <SID>Map('<CR>', 'call FilteringGetForTarget().gotoSelectionInOriginal(0).blink(1)')
  call <SID>Map('<S-CR>', 'call FilteringGetForTarget().gotoSelectionInOriginal(1).destruct().blink(1)')
  call <SID>Map('<Esc>', 'call FilteringGetForTarget().destruct()')
  call <SID>Map('a', 'call FilteringGetForTarget().toggleAutoFollow("source")')
  call <SID>Map('A', 'call FilteringGetForTarget().toggleAutoFollow("original")')
  call <SID>Map('o', 'call FilteringGetForTarget().followSelectionInSource(1)')
  call <SID>Map('O', 'call FilteringGetForTarget().followSelectionInOriginal(1)')
  call <SID>Map('c', 'call FilteringGetForTarget().addToParameter("context_lines", 1).reevaluate()')
  call <SID>Map('C', 'call FilteringGetForTarget().addToParameter("context_lines", -1).reevaluate()')
  call <SID>Map('d', 'call FilteringGetForTarget().addToParameter("context_lines_mode", 1).reevaluate()')
  call <SID>Map('r', 'call FilteringGetForTarget().reevaluate()')
  call <SID>Map('t', 'call FilteringGetForTarget().addToParameter("show_match_to_extra", 1).reevaluate()')
  call <SID>Map('D', 'call FilteringGetForTarget().addToParameter("show_match_to_extra", 1).reevaluate()')
  call <SID>Map('u', 'call FilteringGetForTarget().addToParameter("show_results_raw", 1).reevaluate()')
  call <SID>Map('j', 'call <SID>NextResult()<CR>:echo')
  call <SID>Map('k', 'call <SID>PrevResult()<CR>:echo')
 call <SID>MapI('&', 'call FilteringGetForTarget().addInputToParameter("include", "AND: ").reevaluate()')
 call <SID>MapI('!', 'call FilteringGetForTarget().addInputToParameter("exclude", "NOT: ").reevaluate()')
 call <SID>MapI('<Bar>', 'call FilteringGetForTarget().addInputToParameter("alt", "OR: ").reevaluate()')
 call <SID>MapI('e', 'call FilteringGetForTarget().setParameterToInput("extra", "EXTRA: ").reevaluate()')
  unlet s:mappingFilter
endfunction"}}}
function! FilteringPasteResults() dict"{{{
  let self.context_lines_mode = self.context_lines_mode % 3
  let self.show_match_to_extra = self.show_match_to_extra % 2
  let self.show_results_raw = self.show_results_raw % 2
  let top_elements_max = index([0, 2], self.context_lines_mode) != -1 ? self.context_lines : 0
  let bottom_elements_max = index([0, 1], self.context_lines_mode) != -1 ? self.context_lines : 0

  let self.last_settings = {}
  let self.last_settings = deepcopy(self)

  let res = {}
  if self.show_match_to_extra
    for i in keys(self.context_extra)
      call <SID>SpliceList(res, self.context_extra[i], i)
    endfor
  else
    for i in keys(self.context_extra)
      let res[i + len(self.context_extra[i])] = self.context_extra[i][-1]
    endfor
  endif
  if top_elements_max > 0
    for i in keys(self.context_top)
      let top_elements = min([top_elements_max, len(self.context_top[i])])
      call <SID>SpliceList(res, self.context_top[i][-top_elements :], i-top_elements)
    endfor
  endif
  if bottom_elements_max > 0
    for i in keys(self.context_bottom)
      let bottom_elements = min([bottom_elements_max, len(self.context_bottom[i])])
      call <SID>SpliceList(res, self.context_bottom[i][: bottom_elements-1], i+1)
    endfor
  endif
  for i in keys(self.matches)
    let res[i] = self.matches[i]
  endfor

  setlocal modifiable
  normal! gg"_dG
  let i = max(map(keys(res), 'str2nr(v:val)'))
  if self.show_results_raw
    while i > 0
      if has_key(res, i)
        call append(0, strpart(res[i], 9))
      endif
      let i -= 1
    endwhile
  else
    while i > 0
      if has_key(res, i)
        call append(0, res[i])
      endif
      let i -= 1
    endwhile
  endif
  normal! ddgg
  setlocal nomodifiable

  return self
endfunction"}}}
function! FilteringValidateParameter(table, name, value, caller) dict"{{{
  if !has_key(a:table, a:name)
    return <SID>FancyError(printf('Parameter %s @1not a valid parameter@0 to set using %s.', a:name, a:caller))
  endif
  if type(a:value) != a:table[a:name]
    return <SID>FancyError(printf('Value %s for parameter %s has @1incorrect type@0. Got %d expecting %d.', a:value, a:name, a:table[a:name], type(a:value)))
  endif
  return self
endfunction"}}}
function! FilteringRedraw() dict"{{{
  call <SID>FlipToWindowOrLoadBufferHere(self.target)
  let on_result = self.getCurrentLineSelection()
  let on_pos = getpos('.')
  call self.pasteResults()
  if on_result > 0 && !self.last_settings.show_results_raw
    call search(printf('^ %06d: ', 'c'))
  else
    call setpos('.', on_pos)
  end
  return self
endfunction"}}}

" Private Functions
function! <SID>FilteringStub(txt)"{{{
  " TODO: when final, make up to date with interface
  let obj = {
        \'run'                      : function('FilteringDummyFunction'),
        \'return'                   : function('FilteringDummyFunction'),
        \'addToParameter'           : function('FilteringDummyFunction'),
        \'addInputToParameter'      : function('FilteringDummyFunction'),
        \'setParameter'             : function('FilteringDummyFunction'),
        \'setParameterToInput'      : function('FilteringDummyFunction'),
        \'reevaluate'               : function('FilteringDummyFunction'),
        \'parseQuery'               : function('FilteringDummyFunction'),
        \'gotoLineInBuffer'         : function('FilteringDummyFunction'),
        \'followInBuffer'           : function('FilteringDummyFunction'),
        \'getCurrentLineSelection'  : function('FilteringDummyFunction'),
        \'destruct'                 : function('FilteringDummyFunction'),
        \'blink'                    : function('FilteringDummyFunction'),
        \'toggleAutoFollow'         : function('FilteringDummyFunction'),
        \
        \'gotoSelectionInOriginal'  : function('FilteringDummyFunction'),
        \'gotoSelectionInSource'    : function('FilteringDummyFunction'),
        \'followSelectionInOriginal': function('FilteringDummyFunction'),
        \'followSelectionInSource'  : function('FilteringDummyFunction'),
        \
        \'dummy'          : 1,
        \'error_msg'      : a:txt,
        \}
  return obj
endfunction"}}}
function! FilteringDummyFunction(...) dict"{{{
  if !empty(self.error_msg)
    call <SID>FancyEcho(self.error_msg)
    return <SID>FilteringStub('')
  endif
  return self
endfunction"}}}
function! <SID>AddMatch()"{{{
  let ln = getline('.')
  let nr = line('.')

  if !<SID>FilterIncludeAndExclude(ln)
    return
  endif

  " If an extra pattern was set, filter based on that that.
  let extra_stop_line = nr
  if !empty(s:extra)
    " First determine the stop condition
    let extra_stop_line = s:extra_stop_lines <= 0 ?
          \ line('$') : nr + s:extra_stop_lines
    if !empty(s:extra_stop_pattern)
      let extra_stop_line = search(s:extra_stop_pattern, 'nW', extra_stop_line)
      if extra_stop_line == -1
        return
      endif
    endif
    " Copy context lines up to extra match
    if extra_stop_line > nr
      let context_lines = []
      call <SID>CopyContextRange(context_line, nr + 1, extra_stop_line)
      let s:context_extra[nr] = context_lines
    endif
  endif

  " Always copy the match itself
  let s:matches[nr] = printf(" %6d: %s", nr, ln)

  " When filtering from a result window, don't copy any context.
  if s:context_lines > 0
    " Top context
    let top = []
    call <SID>CopyContextRange(top, max([1, nr - s:context_lines]), nr - 1)
    let s:context_top[nr] = top

    " Bottom context
    let bottom = []
    call <SID>CopyContextRange(bottom, nr + 1, min([line('$'), nr + s:context_lines]))
    let s:context_bottom[nr] = bottom
  endif
endfunction"}}}
function! <SID>AddMatchFromResultWindow()"{{{
  let ln = getline('.')
  let nr = line('.')

  " If this is a context line, perhaps we need to stop now.
  if !s:match_context_in_results && match(ln, "^ ") == -1
    return
  endif

  if !<SID>FilterIncludeAndExclude(ln)
    return
  endif

  " Always copy the match itself
  let s:matches[nr] = printf(" %6d: %s", nr, ln)
endfunction"}}}
function! <SID>FilterIncludeAndExclude(ln)"{{{
  " Fliter out lines not containing included patterns.
  for incl in s:include
    if match(a:ln, incl) == -1
      return 0
    endif
  endfor
  " Fliter out lines containing excluded patterns.
  for excl in s:exclude
    if match(a:ln, excl) != -1
      return 0
    endif
  endfor
  return 1
endfunction"}}}
function! <SID>SpliceList(mp, lst, offset)"{{{
  for i in range(0, len(a:lst)-1)
    let a:mp[i + a:offset] = a:lst[i]
  endfor
endfunction"}}}

" Utility Functions (also private)
function! <SID>ValidateCalledFromResults(caller)"{{{
  if !exists('b:filtering_target')
    return <SID>FancyError(printf('Function %s should be called @1from a results window@0.', a:caller))
  endif
  return 1
endfunction"}}}
function! <SID>FancyEcho(text)"{{{
  let l:i = 0
  while l:i < len(a:text)
    if a:text[l:i] == "@"
      let l:i = l:i + 1
      if a:text[l:i] == "0"
        echohl None
      elseif a:text[l:i] == "1"
        echohl Directory
      elseif a:text[l:i] == "2"
        echohl WarningMsg
      elseif a:text[l:i] == "@"
        echon "@"
      endif
    else
      echon a:text[l:i]
    endif
    let l:i = l:i + 1
  endwhile
  echohl None
  return 0
endfunction"}}}
function! <SID>FancyError(text)"{{{
  call <SID>FancyEcho(a:text)
  return <SID>FilteringStub('')
endfunction"}}}
function! <SID>FlipToWindowOrLoadBufferHere(buffer_nr)"{{{
  if bufnr('') == a:buffer_nr
    return
  endif
  let l:win = bufwinnr(a:buffer_nr)
  if l:win == -1
    exe "buffer " . a:buffer_nr
  else
    exe l:win . "wincmd w"
  endif
endfunction"}}}
function! <SID>Def(name, value_if_not_set)"{{{
  return exists(a:name) ? {a:name} : a:value_if_not_set
endfunction"}}}
function! <SID>Map(key, cmd)"{{{
  if index(s:mappingFilter, a:key) == -1
    exe printf('nnoremap <buffer> %s :%s<CR>', a:key, a:cmd)
  endif
endfunction"}}}
function! <SID>MapI(key, cmd)"{{{
  if index(s:mappingFilter, a:key) == -1
    exe printf('nnoremap <buffer> %s :%s<CR>', a:key, a:cmd)
  endif
endfunction"}}}
function! <SID>CopyContextRange(lst, from, to)"{{{
  let i = a:from
  while i <= a:to
    call add(a:lst, printf("_%6d: %s", i, getline(i)))
    let i += 1
  endwhile
endfunction"}}}
function! <SID>AutoCmdCursorMoved()"{{{
  if !exists('b:filtering_last_selected_line')
        \ || line('.') != b:filtering_last_selected_line
    let b:filtering_last_selected_line = line('.')
    let obj = FilteringGetForTarget()
    if obj.auto_follow_original
      obj.followSelectionInOriginal(0)
    endif
    if obj.auto_follow_source
          \ && (!obj.auto_follow_original || obj.original != obj.source)
      obj.followSelectionInSource(0)
    endif
  endif
endfunction"}}}
function! <SID>SelectFromMultipleSearches(searches)"{{{
  let options = []
  let nr = 1
  for s in a:searches
    call add(options, printf('%3d: %s %s%s',
          \ nr, join(s.alt, ' | '), (empty(s.extra) ? '' : 'extra: '), s.extra))
    let nr += 1
  endfor
  let selected = inputlist(options)
  return selected > 0 && selected <= len(options)
        \ ? a:searches[selected-1]
        \ : <SID>FancyError('No valid search was selected')
endfunction"}}}
function! <SID>NextResult()"{{{
  if FilteringGetForTarget().last_settings.show_results_raw
    normal! j
  else
    call search('^ ', '')
  end
endfunction"}}}
function! <SID>PrevResult()"{{{
  if FilteringGetForTarget().last_settings.show_results_raw
    normal! k
  else
    normal! 0
    call search('^ ', 'b')
  end
endfunction"}}}

function! TestOld()
  let start = reltime()
  call Gather('PRINTSERVER ', 0)
  echo 'old script: '.reltimestr(reltime(start))
endfunction

function! TestNew()
  let start = reltime()
  " call FilteringNew().addToParameter('alt', 'PBE ').setParameter('extra', 'PRINTSERVER').run()
  call FilteringNew().addToParameter('alt', 'PBE').run()
  echo 'new script: '.reltimestr(reltime(start))
endfunction

" vim:sw=2:fdm=marker
