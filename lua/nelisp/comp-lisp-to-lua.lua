local lisp=require'nelisp.lisp'
local vars=require'nelisp.vars'
local alloc=require'nelisp.alloc'
local lread=require'nelisp.lread'
local bytecode=require'nelisp.bytecode'
local signal=require'nelisp.signal'
local specpdl=require'nelisp.specpdl'
local eval=require'nelisp.eval'
local ins=bytecode.ins
local compiled_globals;compiled_globals={
    table=table,
    unpack=unpack,
    error=error,
    vars=vars,
    lisp=lisp,
    specpdl=specpdl,
    data=require'nelisp.data',
    fns=require'nelisp.fns',
    handler=require'nelisp.handler',
    discard=function (n,stack)
        if n==0 then return end
        for _=1,n do stack[#stack]=nil end
    end,
    discard_get=function (n,stack)
        assert(#stack>=n)
        if n==0 then return {} end
        local ret={}
        table.move(stack,#stack-n+1,#stack,1,ret)
        compiled_globals.discard(n,stack)
        assert(#ret==n)
        return ret
    end,
    call=function (call_args,call_fun)
        vars.lisp_eval_depth=vars.lisp_eval_depth+1
        if vars.lisp_eval_depth>lisp.fixnum(vars.V.max_lisp_eval_depth) then
            if lisp.fixnum(vars.V.max_lisp_eval_depth)<100 then
                vars.V.max_lisp_eval_depth=lisp.make_fixnum(100)
            end
            if vars.lisp_eval_depth>lisp.fixnum(vars.V.max_lisp_eval_depth) then
                signal.error("Lisp nesting exceeds `max-lisp-eval-depth'")
            end
        end

        local count1=specpdl.record_in_backtrace(call_fun,call_args,#call_args)
        if not lisp.nilp(vars.V.debug_on_next_call) then
            error('TODO')
        end
        local original_fun=call_fun
        if lisp.symbolp(call_fun) then
            call_fun=call_fun.fn
        end
        local val
        if lisp.subrp(call_fun) and not lisp.subr_native_compiled_dynp(call_fun) then
            val=eval.funcall_subr(call_fun,call_args)
        else
            val=eval.funcall_general(original_fun,call_args)
        end
        vars.lisp_eval_depth=vars.lisp_eval_depth-1
        if specpdl.backtrace_debug_on_exit(specpdl.index()-1) then
            error('TODO')
        end
        specpdl.unbind_to(specpdl.index()-1,nil)
        return val
    end,
}
local M={}
---@param fun nelisp.obj
---@param no_bin boolean?
---@return string
local function compile_compiled(fun,no_bin)
    if _G.nelisp_later then
        error('TODO: parse and compile the whole .elc file instead, allows for more optimizations')
        error('TODO: speed inprovement')
    end
    assert(lisp.compiledp(fun))

    local bytestr=(fun --[[@as nelisp._compiled]]).contents[lisp.compiled_idx.bytecode]
    assert(not lisp.string_multibyte(bytestr))
    local bytestr_data=lisp.sdata(bytestr)

    local code={}
    local pc=0
    local function fetch()
        pc=pc+1
        return assert(string.byte(bytestr_data,pc))
    end
    local function fetch2()
        local o=fetch()
        return o+bit.lshift(fetch(),8)
    end
    local last_pc
    while true do
        local current_pc=pc
        local noerr,op=pcall(fetch)
        if not noerr then
            break
        elseif op>=ins.stack_ref1 and op<=ins.stack_ref7 then
            if op==ins.stack_ref6 then
                op=fetch()
            elseif op==ins.stack_ref7 then
                op=fetch2()
            else
                op=op-ins.stack_ref
            end
            code[current_pc]={'stackref',op}
        elseif op>=ins.varref and op<=ins.varref7 then
            if op==ins.varref6 then
                op=fetch()
            elseif op==ins.varref7 then
                op=fetch2()
            else
                op=op-ins.varref
            end
            code[current_pc]={'varref',op}
        elseif op>=ins.varset and op<=ins.varset7 then
            if op==ins.varset6 then
                op=fetch()
            elseif op==ins.varset7 then
                op=fetch2()
            else
                op=op-ins.varset
            end
            code[current_pc]={'varset',op}
        elseif op>=ins.varbind and op<=ins.varbind7 then
            if op==ins.varbind6 then
                op=fetch()
            elseif op==ins.varbind7 then
                op=fetch2()
            else
                op=op-ins.varbind
            end
            code[current_pc]={'varbind',op}
        elseif op>=ins.call and op<=ins.call7 then
            if op==ins.call6 then
                op=fetch()
            elseif op==ins.call7 then
                op=fetch2()
            else
                op=op-ins.call
            end
            code[current_pc]={'callfn',op}
        elseif op>=ins.unbind and op<=ins.unbind7 then
            if op==ins.unbind6 then
                op=fetch()
            elseif op==ins.unbind7 then
                op=fetch2()
            else
                op=op-ins.unbind
            end
            code[current_pc]={'unbind',op}
        elseif op==ins.pophandler then
            code[current_pc]={'pophandler'}
        elseif op==ins.pushconditioncase or op==ins.pushcatch then
            local typ=op==ins.pushcatch and 'CATCHER' or 'CONDITION_CASE'
            code[current_pc]={'handler',typ,fetch2()}
        elseif op==ins.nth then
            code[current_pc]={'call','vars.F.nth',2}
        elseif op==ins.symbolp then
            code[current_pc]={'callb','lisp.symbolp',1}
        elseif op==ins.consp then
            code[current_pc]={'callb','lisp.consp',1}
        elseif op==ins.stringp then
            code[current_pc]={'callb','lisp.stringp',1}
        elseif op==ins.listp then
            code[current_pc]={'callb','lisp._listp',1}
        elseif op==ins.eq then
            code[current_pc]={'callb','lisp.eq',2}
        elseif op==ins.memq then
            code[current_pc]={'call','vars.F.memq',2}
        elseif op==ins['not'] then
            code[current_pc]={'callb','lisp.nilp',1}
        elseif op==ins.car then
            code[current_pc]={'call','vars.F.car',1}
        elseif op==ins.cdr then
            code[current_pc]={'call','vars.F.cdr',1}
        elseif op==ins.cons then
            code[current_pc]={'call','vars.F.cons',2}
        elseif op>=ins.list1 and op<=ins.list4 then
            code[current_pc]={'call','lisp.list',op-ins.list1+1}
        elseif op==ins.length then
            code[current_pc]={'call','vars.F.length',1}
        elseif op==ins.aref then
            code[current_pc]={'call','vars.F.aref',2}
        elseif op==ins.aset then
            code[current_pc]={'call','vars.F.aset',3}
        elseif op==ins.symbol_value then
            code[current_pc]={'call','vars.F.symbol_value',1}
        elseif op==ins.symbol_function then
            code[current_pc]={'call','vars.F.symbol_function',1}
        elseif op==ins.set then
            code[current_pc]={'call','vars.F.set',2}
        elseif op==ins.fset then
            code[current_pc]={'call','vars.F.fset',2}
        elseif op==ins.get then
            code[current_pc]={'call','vars.F.get',2}
        elseif op==ins.substring then
            code[current_pc]={'call','vars.F.substring',3}
        elseif op>=ins.concat2 and op<=ins.concat4 then
            code[current_pc]={'callt','vars.F.concat',op-ins.concat2+2}
        elseif op==ins.sub1 then
            code[current_pc]={'call','vars.F.sub1',1}
        elseif op==ins.add1 then
            code[current_pc]={'call','vars.F.add1',1}
        elseif op==ins.eqlsign then
            code[current_pc]={'callc','='}
        elseif op==ins.gtr then
            code[current_pc]={'callc','>'}
        elseif op==ins.lss then
            code[current_pc]={'callc','<'}
        elseif op==ins.leq then
            code[current_pc]={'callc','<='}
        elseif op==ins.geq then
            code[current_pc]={'callc','>='}
        elseif op==ins.diff then
            code[current_pc]={'callt','vars.F.minus',2}
        elseif op==ins.negate then
            code[current_pc]={'callt','vars.F.minus',1}
        elseif op==ins.plus then
            code[current_pc]={'callt','vars.F.plus',2}
        elseif op==ins.max then
            code[current_pc]={'callt','vars.F.max',2}
        elseif op==ins.min then
            code[current_pc]={'callt','vars.F.min',2}
        elseif op==ins.mult then
            code[current_pc]={'callt','vars.F.times',2}
        elseif op==ins.point then
            code[current_pc]={'todo','point'}
        elseif op==ins.goto_char then
            code[current_pc]={'call','vars.F.goto_char',1}
        elseif op==ins.insert then
            code[current_pc]={'todo','insert'}
        elseif op==ins.point_max then
            code[current_pc]={'todo','point_max'}
        elseif op==ins.point_min then
            code[current_pc]={'todo','point_min'}
        elseif op==ins.char_after then
            code[current_pc]={'call','vars.F.char_after',1}
        elseif op==ins.following_char then
            code[current_pc]={'call','vars.F.following_char',0}
        elseif op==ins.preceding_char then
            code[current_pc]={'call','vars.F.preceding_char',0}
        elseif op==ins.current_column then
            code[current_pc]={'todo','current_column'}
        elseif op==ins.eolp then
            code[current_pc]={'call','vars.F.eolp',0}
        elseif op==ins.eobp then
            code[current_pc]={'call','vars.F.eobp',0}
        elseif op==ins.bolp then
            code[current_pc]={'call','vars.F.bolp',0}
        elseif op==ins.bobp then
            code[current_pc]={'call','vars.F.bobp',0}
        elseif op==ins.current_buffer then
            code[current_pc]={'call','vars.F.current_buffer',0}
        elseif op==ins.set_buffer then
            code[current_pc]={'call','vars.F.set_buffer',1}
        elseif op==ins.save_current_buffer then
            code[current_pc]={'todo','save_current_buffer'}
        elseif op==ins.forward_char then
            code[current_pc]={'call','vars.F.forward_char',1}
        elseif op==ins.forward_word then
            code[current_pc]={'call','vars.F.forward_word',1}
        elseif op==ins.skip_chars_forward then
            code[current_pc]={'call','vars.F.skip_chars_forward',2}
        elseif op==ins.skip_chars_backward then
            code[current_pc]={'call','vars.F.skip_chars_backward',2}
        elseif op==ins.forward_line then
            code[current_pc]={'call','vars.F.forward_line',1}
        elseif op==ins.char_syntax then
            code[current_pc]={'call','vars.F.char_syntax',1}
        elseif op==ins.buffer_substring then
            code[current_pc]={'call','vars.F.buffer_substring',2}
        elseif op==ins.delete_region then
            code[current_pc]={'call','vars.F.delete_region',2}
        elseif op==ins.narrow_to_region then
            code[current_pc]={'call','vars.F.narrow_to_region',2}
        elseif op==ins.widen then
            code[current_pc]={'call','vars.F.widen',0}
        elseif op==ins.end_of_line then
            code[current_pc]={'call','vars.F.end_of_line',1}
        elseif op==ins.constant2 then
            code[current_pc]={'constant',fetch2()}
        elseif op==ins['goto'] then
            code[current_pc]={'goto',fetch2()}
        elseif op==ins.gotoifnil then
            code[current_pc]={'goto',when='lisp.nilp',fetch2()}
        elseif op==ins.gotoifnonnil then
            code[current_pc]={'goto',when='not lisp.nilp',fetch2()}
        elseif op==ins.gotoifnilelsepop then
            code[current_pc]={'goto',when='lisp.nilp',fetch2(),popafter=true}
        elseif op==ins.gotoifnonnilelsepop then
            code[current_pc]={'goto',when='not lisp.nilp',fetch2(),popafter=true}
        elseif op==ins['return'] then
            code[current_pc]={'return'}
        elseif op==ins.discard then
            code[current_pc]={'discardN',1}
        elseif op==ins.save_excursion then
            code[current_pc]={'todo','save_excursion'}
        elseif op==ins.dup then
            code[current_pc]={'stackref',0}
        elseif op==ins.save_restriction then
            code[current_pc]={'todo','save_restriction'}
        elseif op==ins.unwind_protect then
            code[current_pc]={'unwind_protect'}
        elseif op==ins.set_marker then
            code[current_pc]={'call','vars.F.set_marker',2}
        elseif op==ins.match_beginning then
            code[current_pc]={'call','vars.F.match_beginning',1}
        elseif op==ins.match_end then
            code[current_pc]={'call','vars.F.match_end',1}
        elseif op==ins.upcase then
            code[current_pc]={'call','vars.F.upcase',1}
        elseif op==ins.downcase then
            code[current_pc]={'call','vars.F.downcase',1}
        elseif op==ins.stringeqlsign then
            code[current_pc]={'call','vars.F.string_equal',2}
        elseif op==ins.stringlss then
            code[current_pc]={'call','vars.F.string_lessp',2}
        elseif op==ins.equal then
            code[current_pc]={'call','vars.F.equal',2}
        elseif op==ins.nthcdr then
            code[current_pc]={'call','vars.F.nthcdr',2}
        elseif op==ins.elt then
            code[current_pc]={'call','vars.F.elt',2}
        elseif op==ins.member then
            code[current_pc]={'call','vars.F.member',2}
        elseif op==ins.assq then
            code[current_pc]={'call','vars.F.assq',2}
        elseif op==ins.nreverse then
            code[current_pc]={'call','vars.F.nreverse',1}
        elseif op==ins.setcar then
            code[current_pc]={'setcons','car'}
        elseif op==ins.setcdr then
            code[current_pc]={'setcons','cdr'}
        elseif op==ins.car_safe then
            code[current_pc]={'call','vars.F.car_safe',1}
        elseif op==ins.cdr_safe then
            code[current_pc]={'call','vars.F.cdr_safe',1}
        elseif op==ins.nconc then
            code[current_pc]={'callt','vars.F.nconc',2}
        elseif op==ins.quo then
            code[current_pc]={'callt','vars.F.quo',2}
        elseif op==ins.rem then
            code[current_pc]={'call','vars.F.rem',2}
        elseif op==ins.numberp then
            code[current_pc]={'callb','lisp.numberp',1}
        elseif op==ins.integerp then
            code[current_pc]={'callb','lisp.integerp',1}
        elseif op==ins.listN then
            code[current_pc]={'call','lisp.list',fetch()}
        elseif op==ins.concatN then
            code[current_pc]={'callt','vars.F.concat',fetch()}
        elseif op==ins.insertN then
            code[current_pc]={'todo','insertN'}
        elseif op==ins.stack_set then
            code[current_pc]={'stackset',fetch()}
        elseif op==ins.discardN then
            code[current_pc]={'discardN',fetch()}
        elseif op==ins.switch then
            if code[last_pc][1]~='constant' then
                error('TODO')
            end
            local ht_idx=code[last_pc][2]
            local vector=(fun --[[@as nelisp._compiled]]).contents[lisp.compiled_idx.constants]
            assert(lisp.hashtablep(lisp.aref(vector,ht_idx)),'TODO')
            local ht=lisp.aref(vector,ht_idx) --[[@as nelisp._hash_table]]
            local switch={}
            local idx=0
            for _=0,ht.count-1 do
                while lisp.aref(ht.key_and_value,idx*2)==vars.Qunique do
                    idx=idx+1
                end
                assert(lisp.fixnump(lisp.aref(ht.key_and_value,idx*2+1)))
                table.insert(switch,lisp.fixnum(lisp.aref(ht.key_and_value,idx*2+1)))
                idx=idx+1
            end
            code[current_pc]={'switch',switch}
        elseif op>=ins.constant then
            code[current_pc]={'constant',op-ins.constant}
        else
            error('TODO: byte-code '..op)
        end
        last_pc=current_pc
    end
    for _,v in vim.spairs(code) do
        if v[1]=='goto' then
            assert(code[v[2]])
            code[v[2]-0.5]={'goto_label',v[2]}
        elseif v[1]=='switch' then
            for _,l in ipairs(v[2]) do
                code[l-0.5]={'goto_label',l}
            end
        elseif v[1]=='handler' then
            if _G.nelisp_later then
                error('TODO: error if goto out of handler function')
            end
            code[v[3]-0.5]={'goto_label',v[3]}
        end
    end
    local handlers={}
    local out={'local vectorp,stack=...'}
    for _,v in vim.spairs(code) do
        local op=v[1]
        if op=='goto_label' then
            table.insert(out,'::_'..v[2]..'_::')
        elseif op=='goto' then
            if v.popafter then
                assert(v.when)
                table.insert(out,('if %s(stack[#stack]) then'):format(v.when))
            elseif v.when then
                table.insert(out,('if %s(table.remove(stack)) then'):format(v.when))
            end
            table.insert(out,'goto _'..v[2]..'_')
            if v.when then
                table.insert(out,'end')
            end
            if v.popafter then
                table.insert(out,'stack[#stack]=nil')
            end
        elseif op=='handler' then
            table.insert(out,'do')
            table.insert(out,('local typ=%q'):format(v[2]))
            table.insert(out,'local tag_ch_val=table.remove(stack)')
            table.insert(out,'local bytecode_top=#stack')
            table.insert(out,'local noerr,msg=handler.with_handler(tag_ch_val,typ,function ()')
            table.insert(handlers,v[3])
        elseif op=='pophandler' then
            table.insert(out,'end)')
            table.insert(out,'if noerr then else')
            table.insert(out,'discard(bytecode_top-bytecode_top)')
            table.insert(out,'table.insert(stack,msg.val)')
            table.insert(out,'goto _'..assert(table.remove(handlers))..'_')
            table.insert(out,'end')
            table.insert(out,'end')
        elseif op=='unwind_protect' then
            table.insert(out,'do')
            table.insert(out,'local handler=table.remove(stack)')
            table.insert(out,'specpdl.record_unwind_protect(function ()')
            table.insert(out,'if lisp.functionp(handler) then')
            table.insert(out,'vars.F.funcall({handler})')
            table.insert(out,'else')
            table.insert(out,'vars.F.progn(handler)')
            table.insert(out,'end')
            table.insert(out,'end)')
            table.insert(out,'end')
        elseif op=='switch' then
            table.insert(out,'do')
            table.insert(out,'local jmp_table=table.remove(stack)')
            table.insert(out,'local i=fns.hash_lookup(jmp_table,table.remove(stack))')
            table.insert(out,'if i>=0 then')
            table.insert(out,'local op=lisp.fixnum(lisp.aref(jmp_table.key_and_value,2*i+1))')
            for k,l in ipairs(v[2]) do
                table.insert(out,('%sif op==%d then'):format(k==1 and '' or 'else',l))
                table.insert(out,'goto _'..l..'_')
            end
            table.insert(out,'else error("unreachable") end')
            table.insert(out,'end')
            table.insert(out,'end')
        elseif op=='stackref' then
            table.insert(out,('stack[#stack+1]=stack[#stack-%d]'):format(v[2]))
        elseif op=='constant' then
            table.insert(out,('stack[#stack+1]=vectorp[%d] or vars.Qnil'):format(v[2]+1))
        elseif op=='varref' then
            table.insert(out,('stack[#stack+1]=vars.F.symbol_value(vectorp[%d] or vars.Qnil)'):format(v[2]+1))
        elseif op=='varset' then
            table.insert(out,('data.set_internal(vectorp[%d] or vars.Qnil,table.remove(stack),"SET")'):format(v[2]+1))
        elseif op=='varbind' then
            table.insert(out,('specpdl.bind(vectorp[%d] or vars.Qnil,table.remove(stack))'):format(v[2]+1))
        elseif op=='unbind' then
            table.insert(out,('specpdl.unbind_to(specpdl.index()-%d,nil)'):format(v[2]))
        elseif op=='callfn' then
            table.insert(out,('table.insert(stack,call(discard_get(%d,stack),table.remove(stack)))'):format(v[2]))
        elseif op=='discardN' then
            local l=v[2]
            if bit.band(l,0x80)~=0 then
                l=bit.band(l,0x7f)
                table.insert(out,('stack[#stack-%d]=stack[#stack]'):format(l))
            end
            table.insert(out,('discard(%d,stack)'):format(l))
        elseif op=='call' then
            table.insert(out,('table.insert(stack,%s(unpack(discard_get(%d,stack))))'):format(v[2],v[3]))
        elseif op=='callt' then
            table.insert(out,('table.insert(stack,%s(discard_get(%d,stack)))'):format(v[2],v[3]))
        elseif op=='setcons' then
            table.insert(out,'lisp.check_cons(stack[#stack-1])')
            table.insert(out,('lisp.xset%s(stack[#stack-1],stack[#stack])'):format(v[2]))
            table.insert(out,'stack[#stack-1]=table.remove(stack)')
        elseif op=='callb' then
            table.insert(out,('table.insert(stack,%s(unpack(discard_get(%d,stack))) and vars.Qt or vars.Qnil)'):format(v[2],v[3]))
        elseif op=='stackset' then
            table.insert(out,('stack[#stack-%d]=table.remove(stack)'):format(v[2]))
        elseif op=='callc' then
            table.insert(out,'if lisp.fixnump(stack[#stack]) and lisp.fixnump(stack[#stack-1]) then')
            table.insert(out,('stack[#stack-1]=lisp.fixnum(stack[#stack-1])%slisp.fixnum(table.remove(stack)) and vars.Qt or vars.Qnil'):format(v[2]=='=' and '==' or v[2]))
            table.insert(out,'else error("TODO") end')
        elseif op=='return' then
            table.insert(out,'do return stack[#stack] end')
        elseif op=='pass' then
        elseif op=='todo' then
            table.insert(out,'error("TODO(nelisp-compiler): '..v[2]..'")')
        else
            error('TODO: '..op)
        end
    end
    table.insert(out,'error("unreachable")')
    if next(handlers) then
        if _G.nelisp_later then
            error('TODO: The emacs source code is unclear about what happens here, so I am just guessing')
        end
        assert(code[table.maxn(code)][1]=='return')
        local ret=out[#out]
        out[#out]=nil
        while table.remove(handlers) do
            table.insert(out,'end)')
            table.insert(out,'if noerr then else')
            table.insert(out,'discard(bytecode_top-bytecode_top)')
            table.insert(out,'table.insert(stack,msg.val)')
            table.insert(out,'error("TODO")')
            table.insert(out,'end')
            table.insert(out,'end')
        end
        out[#out+1]=ret
    end
    if no_bin then
        return table.concat(out,'\n')
    end
    return string.dump(assert(loadstring(table.concat(out,'\n'))),true)
end
---@param obj nelisp.obj
---@return string
local function escapestr(obj)
    local s=lisp.sdata(obj)
    return ('%q'):format(s)
end
---@param obj nelisp.obj
---@param printcharfun nelisp.print.printcharfun
---@return "DONT RETURN"
local function compile(obj,printcharfun)
    printcharfun.print_depth=printcharfun.print_depth+1
    if _G.nelisp_later then
        error('TODO: recursive/circular check')
        error('TODO: reuse reused objects')
    end
    local typ=lisp.xtype(obj)
    if typ==lisp.type.symbol then
        if obj==vars.Qnil then
            printcharfun.write('NIL')
        elseif obj==vars.Qt then
            printcharfun.write('T')
        else
            if lisp.symbolinternedininitialobarrayp(obj) then
                printcharfun.write('S('..escapestr(lisp.symbol_name(obj))..')')
            else
                error('TODO')
            end
        end
    elseif typ==lisp.type.int0 then
        printcharfun.write('INT('..('%d'):format(lisp.fixnum(obj))..')')
    elseif typ==lisp.type.float then
        printcharfun.write('FLOAT('..('%f'):format(lisp.xfloat_data(obj))..')')
    elseif typ==lisp.type.string then
        assert(lisp.string_intervals(obj)==nil)
        printcharfun.write('STR('..escapestr(obj))
        if lisp.string_multibyte(obj) then
            printcharfun.write(','..lisp.schars(obj))
        end
        printcharfun.write(')')
    elseif typ==lisp.type.cons then
        local elems={}
        local tail=obj
        while lisp.consp(tail) do
            table.insert(elems,lisp.xcar(tail))
            tail=lisp.xcdr(tail)
        end
        printcharfun.write('C(')
        for _,elem in ipairs(elems) do
            compile(elem,printcharfun)
            printcharfun.write(',')
        end
        compile(tail,printcharfun)
        printcharfun.write(')')
    elseif typ==lisp.type.vectorlike then
        if lisp.compiledp(obj) then
            printcharfun.write('COMP(')
            if true then
                printcharfun.write(('%q'):format(compile_compiled(obj)))
            end
            for i=0,lisp.asize(obj)-1 do
                printcharfun.write(',')
                compile(lisp.aref(obj,i),printcharfun)
            end
            printcharfun.write(')')
        elseif lisp.vectorp(obj) then
            printcharfun.write('V(')
            for i=0,lisp.asize(obj)-1 do
                if i~=0 then
                    printcharfun.write(',')
                end
                compile(lisp.aref(obj,i),printcharfun)
            end
            printcharfun.write(')')
        elseif lisp.hashtablep(obj) then
            local ht=(obj --[[@as nelisp._hash_table]])
            printcharfun.write('HASHTABEL{')
            printcharfun.write('SIZE=')
            printcharfun.write(('%d'):format(lisp.asize(ht.next)))
            printcharfun.write(',')
            if not lisp.nilp(ht.test.name) then
                printcharfun.write('TEST=')
                compile(ht.test.name,printcharfun)
                printcharfun.write(',')
            end
            if not lisp.nilp(ht.weak) then
                printcharfun.write('WEAK=')
                compile(ht.weak,printcharfun)
                printcharfun.write(',')
            end
            printcharfun.write('REHASH_SIZE=')
            compile(vars.F.hash_table_rehash_size(obj),printcharfun)
            printcharfun.write(',')
            printcharfun.write('REHASH_THRESHOLD=')
            compile(vars.F.hash_table_rehash_threshold(obj),printcharfun)
            printcharfun.write(',')
            printcharfun.write('DATA={')
            local idx=0
            for _=0,ht.count-1 do
                while lisp.aref(ht.key_and_value,idx*2)==vars.Qunique do
                    idx=idx+1
                end
                compile(lisp.aref(ht.key_and_value,idx*2),printcharfun)
                printcharfun.write(',')
                compile(lisp.aref(ht.key_and_value,idx*2+1),printcharfun)
                printcharfun.write(',')
                idx=idx+1
            end
            assert(idx==ht.count)
            printcharfun.write('}}')
        else
            error('TODO')
        end
    end
    printcharfun.print_depth=printcharfun.print_depth-1
    return 'DONT RETURN'
end
---@param obj nelisp.obj
---@return string
local function compile_obj(obj)
    local printcharfun=require'nelisp.print'.make_printcharfun()
    compile(obj,printcharfun)
    return printcharfun.out()
end
---@param objs nelisp.obj[]
---@return string[]
function M.compiles(objs)
    local out={}
    table.insert(out,'return {')
    for _,v in ipairs(objs) do
        table.insert(out,compile_obj(v)..',')
    end
    table.insert(out,'}')
    return out
end
---@param str string
local function str_to_fun(str)
    local fn=loadstring(str)
    debug.setfenv(fn,compiled_globals)
    return fn
end
---@param fun nelisp.obj
---@return fun(vectorp:nelisp.obj[],stack:nelisp.obj[]):nelisp.obj
function M.compiled_to_fun(fun)
    local str=compile_compiled(fun)
    return str_to_fun(str)
end
local globals={
    C=function (...)
        local args={...}
        local val=args[#args]
        for i=#args-1,1,-1 do
            val=alloc.cons(args[i],val)
        end
        return val
    end,
    S=function (s)
        return lread.intern(s)
    end,
    STR=function (s,nchars)
        if nchars then
            return alloc.make_multibyte_string(s,nchars)
        end
        return alloc.make_unibyte_string(s)
    end,
    INT=function (n)
        return lisp.make_fixnum(n)
    end,
    V=function (...)
        local args={...}
        local vec=alloc.make_vector(#args,'nil')
        for i=0,#args-1 do
            lisp.aset(vec,i,args[i+1])
        end
        return vec
    end,
    COMP=function (str_fn,...)
        local fun=lread.bytecode_from_list({...},{})
        if str_fn~='' then
            bytecode._cache[fun]=str_to_fun(str_fn)
        end
        return fun
    end,
    T=vars.Qt,
    NIL=vars.Qnil,
    HASHTABEL=function (opts)
        local args={}
        assert(opts.SIZE)
        table.insert(args,vars.Qsize)
        table.insert(args,lisp.make_fixnum(opts.SIZE))
        if opts.TEST then
            table.insert(args,vars.Qtest)
            table.insert(args,opts.TEST)
        end
        if opts.WEAK then
            table.insert(args,vars.Qweakness)
            table.insert(args,opts.WEAK)
        end
        assert(opts.REHASH_SIZE)
        table.insert(args,vars.Qrehash_size)
        table.insert(args,opts.REHASH_SIZE)
        assert(opts.REHASH_THRESHOLD)
        table.insert(args,vars.Qrehash_threshold)
        table.insert(args,opts.REHASH_THRESHOLD)
        assert(opts.DATA)
        table.insert(args,vars.Qdata)
        table.insert(args,lisp.list(unpack(opts.DATA)))
        return lread.hash_table_from_plist(lisp.list(unpack(args)))
    end,
    FLOAT=function (a)
        return alloc.make_float(a)
    end,
}
---@param code string
function M.read(code)
    local f=assert(loadstring(code))
    debug.setfenv(f,globals)
    return f()
end
return M
