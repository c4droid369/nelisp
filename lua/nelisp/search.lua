local vars=require'nelisp.vars'
local lisp=require'nelisp.lisp'
local str=require'nelisp.obj.str'
local fixnum=require'nelisp.obj.fixnum'
local lread=require'nelisp.lread'
local b=require'nelisp.bytes'
local print_=require'nelisp.print'
local signal=require'nelisp.signal'
local M={}
local function at_endline_loc_p(...)
    if not _G.nelisp_later then
        error('TODO')
    end
    return false
end
local search_regs={start={},end_={}}
local last_search_thing=vars.Qnil
---@param s nelisp.str
---@return string
local function eregex_to_vimregex(s)
    if not _G.nelisp_later then
        error('TODO: signal error on bad pattern')
    end
    local buf=lread.make_readcharfun(s,0)
    local ret_buf=print_.make_printcharfun()
    ret_buf.write('\\V')
    while true do
        local c=buf.read()
        if c==-1 then
            break
        end
        if c==b'\\' then
            c=buf.read()
            if c==-1 then
                signal.xsignal(vars.Qinvalid_regexp,str.make('Trailing backslash','auto'))
            end
            error('TODO')
        elseif c==b'^' then
            if not (buf.idx==1 or at_endline_loc_p(buf,buf.idx)) then
                goto normal_char
            end
            ret_buf.write('\\^')
        elseif c==b' ' then
            error('TODO')
        elseif c==b'$' then
            error('TODO')
        elseif c==b'+' or c==b'*' or c==b'?' then
            error('TODO')
        elseif c==b'.' then
            error('TODO')
        elseif c==b'[' then
            ret_buf.write('\\[')
            local p=print_.make_printcharfun()
            c=buf.read()
            if c==b'^' then
                ret_buf.write('^')
                c=buf.read()
            end
            if c==b']' then
                ret_buf.write(']')
                c=buf.read()
            end
            while c~=b']' do
                p.write(c)
                if c==-1 then
                    signal.xsignal(vars.Qinvalid_regexp,'Unmatched [ or [^')
                end
                c=buf.read()
            end
            p.write(c)
            local pat=p.out()
            if pat:find('[:word:]',1,true) then
                error('TODO')
            elseif pat:find('[:ascii:]',1,true) then
                error('TODO')
            elseif pat:find('[:nonascii:]',1,true) then
                error('TODO')
            elseif pat:find('[:ff:]',1,true) then
                error('TODO')
            elseif pat:find('[:return:]',1,true) then
                pat=pat:gsub('%[:return:%]',':return:[]')
            elseif pat:find('[:tab:]',1,true) then
                pat=pat:gsub('%[:tab:%]',':tab:[]')
            elseif pat:find('[:escape:]',1,true) then
                pat=pat:gsub('%[:escape:%]',':escape:[]')
            elseif pat:find('[:backspace:]',1,true) then
                pat=pat:gsub('%[:backspace:%]',':backspace:[]')
            elseif pat:find('[:ident:]',1,true) then
                pat=pat:gsub('%[:ident:%]',':ident:[]')
            elseif pat:find('[:keyword:]',1,true) then
                pat=pat:gsub('%[:keyword:%]',':keyword:[]')
            elseif pat:find('[:fname:]',1,true) then
                pat=pat:gsub('%[:fname:%]',':fname:[]')
            end
            ret_buf.write(pat)
        else
            goto normal_char
        end
        goto continue
        ::normal_char::
        ret_buf.write(c)
        ::continue::
    end
    return ret_buf.out()
end

local F={}
local function string_match_1(regexp,s,start,posix,modify_data)
    lisp.check_string(regexp)
    lisp.check_string(s)
    if not _G.nelisp_later then
        error('TODO')
    end
    if not lisp.nilp(start) then
        error('TODO')
    end
    local vregex=eregex_to_vimregex(regexp)
    local re=vim.regex(vregex)
    local f,t=re:match_str(lisp.sdata(s))
    if not f or not t then
        return vars.Qnil
    end
    search_regs={
        start={f},
        end_={t},
    }
    last_search_thing=vars.Qt
    return fixnum.make(f)
end
F.string_match={'string-match',2,4,0,[[Return index of start of first match for REGEXP in STRING, or nil.
Matching ignores case if `case-fold-search' is non-nil.
If third arg START is non-nil, start search at that index in STRING.

If INHIBIT-MODIFY is non-nil, match data is not changed.

If INHIBIT-MODIFY is nil or missing, match data is changed, and
`match-end' and `match-beginning' give indices of substrings matched
by parenthesis constructs in the pattern.  You can use the function
`match-string' to extract the substrings matched by the parenthesis
constructions in REGEXP.  For index of first char beyond the match, do
(match-end 0).]]}
function F.string_match.f(regexp,s,start,inhibit_modify)
    return string_match_1(regexp,s,start,false,lisp.nilp(inhibit_modify))
end
F.match_data={'match-data',0,3,0,[[Return a list of positions that record text matched by the last search.
Element 2N of the returned list is the position of the beginning of the
match of the Nth subexpression; it corresponds to `(match-beginning N)';
element 2N + 1 is the position of the end of the match of the Nth
subexpression; it corresponds to `(match-end N)'.  See `match-beginning'
and `match-end'.
If the last search was on a buffer, all the elements are by default
markers or nil (nil when the Nth pair didn't match); they are integers
or nil if the search was on a string.  But if the optional argument
INTEGERS is non-nil, the elements that represent buffer positions are
always integers, not markers, and (if the search was on a buffer) the
buffer itself is appended to the list as one additional element.

Use `set-match-data' to reinstate the match data from the elements of
this list.

Note that non-matching optional groups at the end of the regexp are
elided instead of being represented with two `nil's each.  For instance:

  (progn
    (string-match "^\\(a\\)?\\(b\\)\\(c\\)?$" "b")
    (match-data))
  => (0 1 nil nil 0 1)

If REUSE is a list, store the value in REUSE by destructively modifying it.
If REUSE is long enough to hold all the values, its length remains the
same, and any unused elements are set to nil.  If REUSE is not long
enough, it is extended.  Note that if REUSE is long enough and INTEGERS
is non-nil, no consing is done to make the return value; this minimizes GC.

If optional third argument RESEAT is non-nil, any previous markers on the
REUSE list will be modified to point to nowhere.

Return value is undefined if the last search failed.]]}
function F.match_data.f(integers,reuse,reseat)
    if not lisp.nilp(reseat) then
        error('TODO')
    end
    if lisp.nilp(last_search_thing) then
        return vars.Qnil
    end
    local data={}
    if #search_regs.start~=1 then
        error('TODO')
    else
        if lisp.eq(last_search_thing,vars.Qt) then
            if search_regs.start[1]==-1 then
                data[1]=vars.Qnil
                data[2]=vars.Qnil
            else
                data[1]=fixnum.make(search_regs.start[1])
                data[2]=fixnum.make(search_regs.end_[1])
            end
        else
            error('TODO')
        end
    end
    if not lisp.consp(reuse) then
        reuse=vars.F.list(data)
    else
        error('TODO')
    end
    return reuse
end
F.set_match_data={'set-match-data',1,2,0,[[Set internal data on last search match from elements of LIST.
LIST should have been created by calling `match-data' previously.

If optional arg RESEAT is non-nil, make markers on LIST point nowhere.]]}
function F.set_match_data.f(list,reseat)
    lisp.check_list(list)
    local length=lisp.list_length(list)/2
    last_search_thing=vars.Qt
    local num_regs=search_regs and #search_regs.start or 0
    local i=0
    while lisp.consp(list) do
        local marker=lisp.xcar(list)
        if lisp.bufferp(marker) then
            error('TODO')
        end
        if i>=length then
            break
        end
        if lisp.nilp(marker) then
            search_regs.start[i+1]=-1
            list=lisp.xcdr(list)
        else
            if lisp.markerp(marker) then
                error('TODO')
            end
            local form=marker
            if not lisp.nilp(reseat) and lisp.markerp(marker) then
                error('TODO')
            end
            list=lisp.xcdr(list)
            if not lisp.consp(list) then
                break
            end
            marker=lisp.xcar(list --[[@as nelisp.cons]])
            if lisp.markerp(marker) then
                error('TODO')
            end
            search_regs.start[i+1]=fixnum.tonumber(form --[[@as nelisp.fixnum]])
            search_regs.end_[i+1]=fixnum.tonumber(marker --[[@as nelisp.fixnum]])
        end
        list=lisp.xcdr(list --[[@as nelisp.cons]])
        i=i+1
    end
    while i<num_regs do
        search_regs.start[i+1]=nil
        search_regs.end_[i+1]=nil
        i=i+1
    end
    return vars.Qnil
end

function M.init_syms()
    vars.setsubr(F,'string_match')
    vars.setsubr(F,'match_data')
    vars.setsubr(F,'set_match_data')
end
return M
