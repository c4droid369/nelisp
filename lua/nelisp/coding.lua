local vars=require'nelisp.vars'
local alloc=require'nelisp.alloc'
local b=require'nelisp.bytes'
local lisp=require'nelisp.lisp'
local lread=require'nelisp.lread'
local chars=require'nelisp.chars'
local signal=require'nelisp.signal'
local fns=require'nelisp.fns'
local charset=require'nelisp.charset'

---@class nelisp.coding_system
---@field id number
---@field common_flags number
---@field mode number
---@field src_multibyte boolean
---@field dst_multibyte boolean
---@field char_at_source boolean
---@field raw_destination boolean
---@field annotated boolean
---@field eol_seen number
---@field max_charset_id number
---@field safe_charsets string
---@field carryover_bytes number
---@field default_char number
---@field detector (fun(c:nelisp.coding_system,i:nelisp.coding_detection_info):boolean)|0
---@field decoder fun(c:nelisp.coding_system)
---@field encoder fun(c:nelisp.coding_system):boolean
---@field spec_undecided nelisp.coding_undecided_spec?
---@class nelisp.coding_undecided_spec
---@field inhibit_nbd number
---@field inhibit_ied number
---@field prefer_utf_8 boolean

---@enum nelisp.coding_arg
local coding_arg={
    name=1,
    mnemonic=2,
    coding_type=3,
    charset_list=4,
    ascii_compatible_p=5,
    decode_translation_table=6,
    encode_translation_table=7,
    post_read_conversion=8,
    pre_write_conversion=9,
    default_char=10,
    for_unibyte=11,
    plist=12,
    eol_type=13,
    max=13
}
---@enum nelisp.coding_arg_undecided
local coding_arg_undecided={
    inhibit_null_byte_detection=coding_arg.max+1,
    inhibit_iso_escape_detection=coding_arg.max+2,
    prefer_utf_8=coding_arg.max+3,
    max=coding_arg.max+3,
}
---@enum nelisp.coding_attr
local coding_attr={
    base_name=0,
    docstring=1,
    mnemonic=2,
    type=3,
    charset_list=4,
    ascii_compat=5,
    decode_tbl=6,
    encode_tbl=7,
    trans_tbl=8,
    post_read=9,
    pre_write=10,
    default_char=11,
    for_unibyte=12,
    plist=13,
    category=14,
    safe_charsets=15,
    charset_valids=16,
    ccl_decoder=17,
    ccl_encoder=18,
    ccl_valids=19,
    iso_initial=20,
    iso_usage=21,
    iso_request=22,
    iso_flags=23,
    utf_bom=24,
    utf_16_endian=25,
    emacs_mule_full=26,
    undecided_inhibit_null_byte_detection=27,
    undecided_inhibit_iso_escape_detection=28,
    undecided_prefer_utf_8=29,
    last_index=30
}
---@enum nelisp.coding_category
local coding_category={
    iso_7=0,
    iso_7_tight=1,
    iso_8_1=2,
    iso_8_2=3,
    iso_7_else=4,
    iso_8_else=5,
    utf_8_auto=6,
    utf_8_nosig=7,
    utf_8_sig=8,
    utf_16_auto=9,
    utf_16_be=10,
    utf_16_le=11,
    utf_16_be_nosig=12,
    utf_16_le_nosig=13,
    charset=14,
    sjis=15,
    big5=16,
    ccl=17,
    emacs_mule=18,
    raw_text=19,
    undecided=20,
    max=21,
}
local coding_mask={
    annotation=0x00ff,
    annotate_composition=0x0001,
    annotate_direction=0x0002,
    annotate_charset=0x0003,
    for_unibyte=0x0100,
    require_flushing=0x0200,
    require_decoding=0x0400,
    require_encoding=0x0800,
    require_detection=0x1000,
    reset_at_bol=0x2000,
}

---@type table<nelisp.coding_category,nelisp.coding_system>
---(0-indexed)
local coding_categories={}

local M={}
function M.encode_file_name(s)
    if not _G.nelisp_later then
        error('TODO')
    end
    return s
end

local F={}
local function coding_system_spec(coding_system_symbol)
    return vars.F.gethash(coding_system_symbol,vars.coding_system_hash_table,vars.Qnil)
end
local function coding_system_id(coding_system_symbol)
    return fns.hash_lookup((vars.coding_system_hash_table --[[@as nelisp._hash_table]]),coding_system_symbol)
end
local function check_coding_system_get_spec(x)
    local spec=coding_system_spec(x)
    if lisp.nilp(spec) then
        error('TODO')
    end
    return spec
end
local function check_coding_system_get_id(x)
    local id=coding_system_id(x)
    if id<0 then
        error('TODO')
    end
    return id
end
local function coding_id_name(id)
    return lisp.aref((vars.coding_system_hash_table --[[@as nelisp._hash_table]]).key_and_value,id*2)
end
local function coding_id_attrs(id)
    return lisp.aref(lisp.aref(
        (vars.coding_system_hash_table --[[@as nelisp._hash_table]]).key_and_value,id*2+1),0)
end
local function coding_id_eol_type(id)
    return lisp.aref(lisp.aref(
        (vars.coding_system_hash_table --[[@as nelisp._hash_table]]).key_and_value,id*2+1),2)
end
---@return number
local function encode_inhibit_flag(flag)
    return (lisp.nilp(flag) and -1) or (lisp.eq(flag,vars.Qt) and 1) or 0
end
---@param coding_system nelisp.obj
---@param coding nelisp.coding_system
local function setup_coding_system(coding_system,coding)
    if lisp.nilp(coding_system) then
        coding_system=vars.Qundecided
    end

    coding.id=check_coding_system_get_id(coding_system)
    local attrs=coding_id_attrs(coding.id)
    local eol_type=not lisp.nilp(vars.V.inhibit_eol_conversion) and vars.Qunix or coding_id_eol_type(coding.id)

    coding.mode=0
    if lisp.vectorp(eol_type) then
        coding.common_flags=bit.bor(coding_mask.require_decoding,coding_mask.require_detection)
    elseif not lisp.eq(eol_type,vars.Qunix) then
        error('TODO')
    else
        coding.common_flags=0
    end
    if not lisp.nilp(lisp.aref(attrs,coding_attr.post_read)) then
        error('TODO')
    end
    if not lisp.nilp(lisp.aref(attrs,coding_attr.pre_write)) then
        error('TODO')
    end
    if not lisp.nilp(lisp.aref(attrs,coding_attr.for_unibyte)) then
        coding.common_flags=bit.bor(coding.common_flags,coding_mask.for_unibyte)
    end

    local val=lisp.aref(attrs,coding_attr.safe_charsets)
    coding.max_charset_id=lisp.schars(val)-1
    coding.safe_charsets=lisp.sdata(val)
    coding.default_char=lisp.fixnum(lisp.aref(attrs,coding_attr.default_char))
    coding.carryover_bytes=0
    coding.raw_destination=false

    local coding_type=lisp.aref(attrs,coding_attr.type)
    if lisp.eq(coding_type,vars.Qundecided) then
        coding.detector=0
        coding.decoder=decode_coding_raw_text
        coding.encoder=encode_coding_raw_text
        coding.common_flags=bit.bor(coding.common_flags,coding_mask.require_detection)
        coding.spec_undecided={} --[[@as unknown]]
        coding.spec_undecided.inhibit_nbd=encode_inhibit_flag(
            lisp.aref(attrs,coding_attr.undecided_inhibit_null_byte_detection))
        coding.spec_undecided.inhibit_ied=encode_inhibit_flag(
            lisp.aref(attrs,coding_attr.undecided_inhibit_iso_escape_detection))
        coding.spec_undecided.prefer_utf_8=not lisp.nilp(
            lisp.aref(attrs,coding_attr.undecided_prefer_utf_8))
    elseif lisp.eq(coding_type,vars.Qiso_2022) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qcharset) then
        coding.detector=detect_coding_charset
        coding.decoder=decode_coding_charset
            coding.encoder=encode_coding_charset
        coding.common_flags=bit.bor(coding.common_flags,coding_mask.require_decoding,coding_mask.require_encoding)
    elseif lisp.eq(coding_type,vars.Qutf_8) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qutf_16) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qccl) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qemacs_mule) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qshift_jis) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qbig5) then
        error('TODO')
    else
        assert(lisp.eq(coding_type,vars.Qraw_text))
        coding.detector=0
        coding.decoder=decode_coding_raw_text
        coding.encoder=encode_coding_raw_text
        if not lisp.eq(eol_type,vars.Qunix) then
            error('TODO')
        end
    end
end
---@param base nelisp.obj
---@return nelisp.obj
local function make_subsidiaries(base)
    local suffixes={'-unix','-dos','-mac'}
    local subsidiaries=alloc.make_vector(3,'nil')
    for k,v in ipairs(suffixes) do
        lisp.aset(subsidiaries,k-1,lread.intern(lisp.sdata(lisp.symbol_name(base))..v))
    end
    return subsidiaries
end
F.define_coding_system_internal={'define-coding-system-internal',coding_arg.max,-2,0,[[For internal use only.
usage: (define-coding-system-internal ...)]]}
function F.define_coding_system_internal.f(args)
    if #args<coding_arg.max then
        vars.F.signal(vars.Qwrong_number_of_arguments,vars.F.cons(
            lread.intern('define-coding-system-internal'),
            lisp.make_fixnum(#args)))
    end
    local attrs=alloc.make_vector(coding_attr.last_index,'nil')
    local max_charset_id=0

    local name=args[coding_arg.name]
    lisp.check_symbol(name)
    lisp.aset(attrs,coding_attr.base_name,name)

    local val=args[coding_arg.mnemonic]
    if lisp.stringp(val) then
        val=lisp.make_fixnum(chars.stringchar(lisp.sdata(val)))
    else
        chars.check_character(val)
    end
    lisp.aset(attrs,coding_attr.mnemonic,val)

    local coding_type=args[coding_arg.coding_type]
    lisp.check_symbol(coding_type)
    lisp.aset(attrs,coding_attr.type,coding_type)

    local charset_list=args[coding_arg.charset_list]
    if lisp.symbolp(charset_list) then
        if lisp.eq(charset_list,vars.Qiso_2022) then
            error('TODO')
        elseif lisp.eq(charset_list,vars.Qemacs_mule) then
            error('TODO')
        end
        local tail=charset_list
        while lisp.consp(tail) do
            rawget(_G,'error')('TODO')
            break
        end
    else
        charset_list=vars.F.copy_sequence(charset_list)
        local tail=charset_list
        while lisp.consp(tail) do
            val=lisp.xcar(tail)
            local cs=charset.check_charset_get_charset(val)
            if lisp.eq(coding_type,vars.Qiso_2022) and cs.iso_final<0
                or lisp.eq(coding_type,vars.Qemacs_mule) and cs.emacs_mule_id<0 then
                signal.error("Can't handle charset `%s'",
                    lisp.sdata(lisp.symbol_name(charset.charset_name(cs))))
            end
            lisp.xsetcar(tail,lisp.make_fixnum(cs.id))
            if max_charset_id<cs.id then
                max_charset_id=cs.id
            end
            tail=lisp.xcdr(tail)
        end
    end
    lisp.aset(attrs,coding_attr.charset_list,charset_list)

    local safe_charsets={}
    for i=1,max_charset_id+1 do
        safe_charsets[i]='\xff'
    end
    local tail=charset_list
    while lisp.consp(tail) do
        safe_charsets[lisp.fixnum(lisp.xcar(tail))+1]='\0'
        tail=lisp.xcdr(tail)
    end
    lisp.aset(attrs,coding_attr.safe_charsets,alloc.make_unibyte_string(table.concat(safe_charsets)))

    lisp.aset(attrs,coding_attr.ascii_compat,args[coding_arg.ascii_compatible_p])

    val=args[coding_arg.decode_translation_table]
    if not lisp.chartablep(val) and not lisp.consp(val) then
        lisp.check_symbol(val)
    end
    lisp.aset(attrs,coding_attr.decode_tbl,val)

    val=args[coding_arg.encode_translation_table]
    if not lisp.chartablep(val) and not lisp.consp(val) then
        lisp.check_symbol(val)
    end
    lisp.aset(attrs,coding_attr.encode_tbl,val)

    val=args[coding_arg.post_read_conversion]
    lisp.check_symbol(val)
    lisp.aset(attrs,coding_attr.post_read,val)

    val=args[coding_arg.pre_write_conversion]
    lisp.check_symbol(val)
    lisp.aset(attrs,coding_attr.pre_write,val)

    val=args[coding_arg.default_char]
    if lisp.nilp(val) then
        lisp.aset(attrs,coding_attr.default_char,lisp.make_fixnum(b' '))
    else
        chars.check_character(val)
        lisp.aset(attrs,coding_attr.default_char,val)
    end

    val=args[coding_arg.for_unibyte]
    lisp.aset(attrs,coding_attr.for_unibyte,lisp.nilp(val) and vars.Qnil or vars.Qt)

    val=args[coding_arg.plist]
    lisp.check_list(val)
    lisp.aset(attrs,coding_attr.plist,val)

    local category
    if lisp.eq(coding_type,vars.Qcharset) then
        val=alloc.make_vector(256,'nil')
        tail=charset_list
        while lisp.consp(tail) do
            local cs=vars.charset_table[lisp.fixnum(lisp.xcar(tail))]
            local dim=cs.dimension
            local idx=(dim-1)*4
            if cs.ascii_compatible_p then
                lisp.aset(attrs,coding_attr.ascii_compat,vars.Qt)
            end
            for i=cs.code_space[idx],cs.code_space[idx+1] do
                local tmp=lisp.aref(val,i)
                local dim2
                if lisp.nilp(tmp) then
                    tmp=lisp.xcar(tail)
                elseif lisp.fixnatp(tmp) then
                    dim2=vars.charset_table[lisp.fixnum(tmp)].dimension
                    if dim<dim2 then
                        tmp=lisp.list(lisp.xcar(tail),tmp)
                    else
                        tmp=lisp.list(tmp,lisp.xcar(tail))
                    end
                else
                    error('TODO')
                end
                lisp.aset(val,i,tmp)
            end
            tail=lisp.xcdr(tail)
        end
        lisp.aset(attrs,coding_attr.charset_valids,val)
        category=coding_category.charset
    elseif lisp.eq(coding_type,vars.Qccl) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qutf_16) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qiso_2022) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qemacs_mule) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qshift_jis) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qbig5) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qraw_text) then
        category=coding_category.raw_text
        lisp.aset(attrs,coding_attr.ascii_compat,vars.Qt)
    elseif lisp.eq(coding_type,vars.Qutf_8) then
        error('TODO')
    elseif lisp.eq(coding_type,vars.Qundecided) then
        if #args<coding_arg_undecided.max then
            vars.F.signal(vars.Qwrong_number_of_arguments,vars.F.cons(
                lread.intern('define-coding-system-internal'),
                lisp.make_fixnum(#args)))
        end
        lisp.aset(attrs,coding_attr.undecided_inhibit_null_byte_detection,
            args[coding_arg_undecided.inhibit_null_byte_detection])
        lisp.aset(attrs,coding_attr.undecided_inhibit_iso_escape_detection,
            args[coding_arg_undecided.inhibit_iso_escape_detection])
        lisp.aset(attrs,coding_attr.undecided_prefer_utf_8,
            args[coding_arg_undecided.prefer_utf_8])
        category=coding_category.undecided
    else
        signal.error('Invalid coding system type: %s',lisp.sdata(lisp.symbol_name(coding_type)))
    end
    lisp.aset(attrs,coding_attr.category,lisp.make_fixnum(category))

    lisp.aset(attrs,coding_attr.plist,
        vars.F.cons(vars.QCcategory,
            vars.F.cons(lisp.aref(vars.coding_category_table,category),
                lisp.aref(attrs,coding_attr.plist))))
    lisp.aset(attrs,coding_attr.plist,
        vars.F.cons(vars.QCascii_compatible_p,
            vars.F.cons(lisp.aref(attrs,coding_attr.ascii_compat),
                lisp.aref(attrs,coding_attr.plist))))

    local eol_type=args[coding_arg.eol_type]
    if not lisp.nilp(eol_type)
        and not lisp.eq(eol_type,vars.Qunix)
        and not lisp.eq(eol_type,vars.Qdos)
        and not lisp.eq(eol_type,vars.Qmac) then
        signal.error('Invalid eol-type')
    end

    if lisp.nilp(eol_type) then
        eol_type=make_subsidiaries(name)
        for i=0,2 do
            local this_name=lisp.aref(eol_type,i)
            local this_aliases=lisp.list(this_name)
            local this_eol_type=i==0 and vars.Qunix or i==1 and vars.Qdos or vars.Qmac
            local this_spec=alloc.make_vector(3,'nil')
            lisp.aset(this_spec,0,attrs)
            lisp.aset(this_spec,1,this_aliases)
            lisp.aset(this_spec,2,this_eol_type)
            vars.F.puthash(this_name,this_spec,vars.coding_system_hash_table)
            vars.V.coding_system_list=vars.F.cons(this_name,vars.V.coding_system_list)
            val=vars.F.assoc(vars.F.symbol_name(this_name),vars.V.coding_system_alist,vars.Qnil)
            if lisp.nilp(val) then
                vars.V.coding_system_alist=vars.F.cons(vars.F.cons(
                    vars.F.symbol_name(this_name),vars.Qnil),vars.V.coding_system_alist)
            end
        end
    end

    local aliases=lisp.list(name)
    local spec_vec=alloc.make_vector(3,'nil')
    lisp.aset(spec_vec,0,attrs)
    lisp.aset(spec_vec,1,aliases)
    lisp.aset(spec_vec,2,eol_type)

    vars.F.puthash(name,spec_vec,vars.coding_system_hash_table)
    vars.V.coding_system_list=vars.F.cons(name,vars.V.coding_system_list)
    val=vars.F.assoc(vars.F.symbol_name(name),vars.V.coding_system_alist,vars.Qnil)
    if lisp.nilp(val) then
        vars.V.coding_system_alist=vars.F.cons(vars.F.cons(
            vars.F.symbol_name(name),vars.Qnil),vars.V.coding_system_alist)
    end

    local id=coding_categories[category].id
    if id<0 or lisp.eq(name,coding_id_name(id)) then
        setup_coding_system(name,coding_categories[category])
    end

    return vars.Qnil
end
F.define_coding_system_alias={'define-coding-system-alias',2,2,0,[[Define ALIAS as an alias for CODING-SYSTEM.]]}
function F.define_coding_system_alias.f(alias,coding_system)
    lisp.check_symbol(alias)
    local spec=check_coding_system_get_spec(coding_system)
    local aliases=lisp.aref(spec,1)
    while not lisp.nilp(lisp.xcdr(aliases)) do
        aliases=lisp.xcdr(aliases)
    end
    lisp.xsetcdr(aliases,lisp.list(alias))

    local eol_type=lisp.aref(spec,2)
    if lisp.vectorp(eol_type) then
        local subsidiaries=make_subsidiaries(alias)
        for i=0,2 do
            vars.F.define_coding_system_alias(lisp.aref(subsidiaries,i),lisp.aref(eol_type,i))
        end
    end

    vars.F.puthash(alias,spec,vars.coding_system_hash_table)
    vars.V.coding_system_list=vars.F.cons(alias,vars.V.coding_system_list)
    local val=vars.F.assoc(vars.F.symbol_name(alias),vars.V.coding_system_alist,vars.Qnil)
    if lisp.nilp(val) then
        vars.V.coding_system_alist=vars.F.cons(vars.F.cons(
            vars.F.symbol_name(alias),vars.Qnil),vars.V.coding_system_alist)
    end
    return vars.Qnil
end

function M.init()
    for i=0,coding_category.max-1 do
        coding_categories[i]={id=-1} --[[@as unknown]]
    end

    vars.coding_system_hash_table=vars.F.make_hash_table(vars.QCtest,vars.Qeq)
    vars.coding_category_table=alloc.make_vector(coding_category.max,'nil')
    lisp.aset(vars.coding_category_table,coding_category.iso_7,
        lread.intern_c_string('coding-category-iso-7'))
    lisp.aset(vars.coding_category_table,coding_category.iso_7_tight,
        lread.intern_c_string('coding-category-iso-7-tight'))
    lisp.aset(vars.coding_category_table,coding_category.iso_8_1,
        lread.intern_c_string('coding-category-iso-8-1'))
    lisp.aset(vars.coding_category_table,coding_category.iso_8_2,
        lread.intern_c_string('coding-category-iso-8-2'))
    lisp.aset(vars.coding_category_table,coding_category.iso_7_else,
        lread.intern_c_string('coding-category-iso-7-else'))
    lisp.aset(vars.coding_category_table,coding_category.iso_8_else,
        lread.intern_c_string('coding-category-iso-8-else'))
    lisp.aset(vars.coding_category_table,coding_category.utf_8_auto,
        lread.intern_c_string('coding-category-utf-8-auto'))
    lisp.aset(vars.coding_category_table,coding_category.utf_8_nosig,
        lread.intern_c_string('coding-category-utf-8'))
    lisp.aset(vars.coding_category_table,coding_category.utf_8_sig,
        lread.intern_c_string('coding-category-utf-8-sig'))
    lisp.aset(vars.coding_category_table,coding_category.utf_16_be,
        lread.intern_c_string('coding-category-utf-16-be'))
    lisp.aset(vars.coding_category_table,coding_category.utf_16_auto,
        lread.intern_c_string('coding-category-utf-16-auto'))
    lisp.aset(vars.coding_category_table,coding_category.utf_16_le,
        lread.intern_c_string('coding-category-utf-16-le'))
    lisp.aset(vars.coding_category_table,coding_category.utf_16_be_nosig,
        lread.intern_c_string('coding-category-utf-16-be-nosig'))
    lisp.aset(vars.coding_category_table,coding_category.utf_16_le_nosig,
        lread.intern_c_string('coding-category-utf-16-le-nosig'))
    lisp.aset(vars.coding_category_table,coding_category.charset,
        lread.intern_c_string('coding-category-charset'))
    lisp.aset(vars.coding_category_table,coding_category.sjis,
        lread.intern_c_string('coding-category-sjis'))
    lisp.aset(vars.coding_category_table,coding_category.big5,
        lread.intern_c_string('coding-category-big5'))
    lisp.aset(vars.coding_category_table,coding_category.ccl,
        lread.intern_c_string('coding-category-ccl'))
    lisp.aset(vars.coding_category_table,coding_category.emacs_mule,
        lread.intern_c_string('coding-category-emacs-mule'))
    lisp.aset(vars.coding_category_table,coding_category.raw_text,
        lread.intern_c_string('coding-category-raw-text'))
    lisp.aset(vars.coding_category_table,coding_category.undecided,
        lread.intern_c_string('coding-category-undecided'))

    local args={}
    for i=1,coding_arg_undecided.max do
        args[i]=vars.Qnil
    end
    args[coding_arg.name]=vars.Qno_conversion
    args[coding_arg.mnemonic]=lisp.make_fixnum(b'=')
    args[coding_arg.coding_type]=vars.Qraw_text
    args[coding_arg.ascii_compatible_p]=vars.Qt
    args[coding_arg.default_char]=lisp.make_fixnum(0)
    args[coding_arg.for_unibyte]=vars.Qt
    args[coding_arg.eol_type]=vars.Qunix

    local plist={
        vars.QCname,
        args[coding_arg.name],
        vars.QCmnemonic,
        args[coding_arg.mnemonic],
        lread.intern_c_string(':coding-type'),
        args[coding_arg.coding_type],
        vars.QCascii_compatible_p,
        args[coding_arg.ascii_compatible_p],
        vars.QCdefault_char,
        args[coding_arg.default_char],
        lread.intern_c_string(':for-unibyte'),
        args[coding_arg.for_unibyte],
        lread.intern_c_string(':docstring'),
        alloc.make_pure_c_string('Do no conversion.\n'..'\n'..
            'When you visit a file with this coding, the file is read into a\n'..
            'unibyte buffer as is, thus each byte of a file is treated as a\n'..
            'character.'),
        lread.intern_c_string(':eol-type'),
        args[coding_arg.eol_type],
    }
    args[coding_arg.plist]=vars.F.list(plist)
    vars.F.define_coding_system_internal(args)

    args[coding_arg.name]=vars.Qundecided
    plist[2]=args[coding_arg.name]
    args[coding_arg.mnemonic]=lisp.make_fixnum(b'-')
    plist[4]=args[coding_arg.mnemonic]
    args[coding_arg.coding_type]=vars.Qundecided
    plist[6]=args[coding_arg.coding_type]
    plist[9]=lread.intern_c_string(':charset-list')
    args[coding_arg.charset_list]=lisp.list(vars.Qascii)
    plist[10]=args[coding_arg.charset_list]
    args[coding_arg.for_unibyte]=vars.Qnil
    plist[12]=args[coding_arg.for_unibyte]
    plist[14]=alloc.make_pure_c_string("No conversion on encoding, "..
        "automatic conversion on decoding.")
    args[coding_arg.eol_type]=vars.Qnil
    plist[16]=args[coding_arg.eol_type]
    args[coding_arg.plist]=vars.F.list(plist)
    args[coding_arg_undecided.inhibit_null_byte_detection]=lisp.make_fixnum(0)
    args[coding_arg_undecided.inhibit_iso_escape_detection]=lisp.make_fixnum(0)
    vars.F.define_coding_system_internal(args)

    for i=0,coding_category.max-1 do
        vars.F.set(lisp.aref(vars.coding_category_table,i),vars.Qno_conversion)
    end
end
function M.init_syms()
    vars.defsym('QCcategory',':category')
    vars.defsym('QCmnemonic',':mnemonic')
    vars.defsym('QCdefault_char',':default-char')

    vars.defsym('Qunix','unix')
    vars.defsym('Qdos','dos')
    vars.defsym('Qmac','mac')

    vars.defsym('Qno_conversion','no-conversion')
    vars.defsym('Qundecided','undecided')

    vars.defsym('Qraw_text','raw-text')
    vars.defsym('Qiso_2022','iso-2022')
    vars.defsym('Qemacs_mule','emacs-mule')
    vars.defsym('Qcharset','charset')
    vars.defsym('Qccl','ccl')
    vars.defsym('Qutf_8','utf-8')
    vars.defsym('Qutf_16','utf-16')
    vars.defsym('Qshift_jis','shift-jis')
    vars.defsym('Qbig5','big5')

    vars.defvar_lisp('coding_system_list','coding-system-list',[[List of coding systems.

Do not alter the value of this variable manually.  This variable should be
updated by the functions `define-coding-system' and
`define-coding-system-alias'.]])
    vars.V.coding_system_list=vars.Qnil
    vars.defvar_lisp('coding_system_alist','coding-system-alist',[[Alist of coding system names.
Each element is one element list of coding system name.
This variable is given to `completing-read' as COLLECTION argument.

Do not alter the value of this variable manually.  This variable should be
updated by `define-coding-system-alias'.]])
    vars.V.coding_system_alist=vars.Qnil

    vars.defvar_bool('inhibit_eol_conversion','inhibit-eol-conversion',[[
Non-nil means always inhibit code conversion of end-of-line format.
See info node `Coding Systems' and info node `Text and Binary' concerning
such conversion.]])
    vars.V.inhibit_eol_conversion=vars.Qnil

    vars.defsubr(F,'define_coding_system_internal')
    vars.defsubr(F,'define_coding_system_alias')
end
return M
