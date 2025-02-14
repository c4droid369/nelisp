#include "alloc.c"
#include "lread.c"

int pub ret(/*nelisp.obj*/) number_to_fixnum(lua_State *L){
    check_nargs(L,1);
    check_isnumber(L,1);

    Lisp_Object obj = make_fixnum(lua_tointeger(L,-1));
    push_obj(L,obj);
    return 1;
}

int pub ret(/*nelisp.obj*/) number_to_float(lua_State *L){
    check_nargs(L,1);
    check_isnumber(L,1);

    Lisp_Object obj = make_float(lua_tonumber(L,-1));
    push_obj(L,obj);
    return 1;
}

int pub ret(/*number*/) fixnum_to_number(lua_State *L){
    check_nargs(L,1);
    check_isobject(L,1);

    Lisp_Object obj = userdata_to_obj(L,1);
    if (!FIXNUMP(obj))
        luaL_error(L,"Expected fixnum");
    EMACS_INT i = XFIXNUM(obj);
    lua_pushinteger(L, i);
    return 1;
}

int pub ret(/*number*/) float_to_number(lua_State *L){
    check_nargs(L,1);
    check_isobject(L,1);

    Lisp_Object obj = userdata_to_obj(L,1);
    if (!FLOATP(obj))
        luaL_error(L,"Expected float");
    double i = XFLOAT_DATA(obj);
    lua_pushnumber(L, i);
    return 1;
}

int pub ret(/*nelisp.obj*/) string_to_unibyte_lstring(lua_State *L){
    check_nargs(L,1);
    check_isstring(L,1);

    size_t len;
    const char* str = lua_tolstring(L,-1,&len);
    Lisp_Object obj = make_unibyte_string(str,len);
    push_obj(L,obj);
    return 1;
}

int pub ret(/*string*/) unibyte_lstring_to_string(lua_State *L){
    check_nargs(L,1);
    check_isobject(L,1);

    Lisp_Object obj = userdata_to_obj(L,1);
    if (!STRINGP(obj) || STRING_MULTIBYTE(obj))
        luaL_error(L,"Expected unibyte string");
    const char* str = (const char*)SDATA(obj);
    lua_pushlstring(L,str,SBYTES(obj));
    return 1;
}

int pub ret(/*[nelisp.obj,nelisp.obj]*/) cons_to_table(lua_State *L){
    check_nargs(L,1);
    check_isobject(L,1);

    Lisp_Object obj = userdata_to_obj(L,1);
    if (!CONSP(obj))
        luaL_error(L,"Expected cons");
    Lisp_Object car=XCAR(obj);
    Lisp_Object cdr=XCDR(obj);
    lua_newtable(L);
    // (-1)tbl
    push_obj(L,car);
    // (-2)tbl,(-1)car
    lua_rawseti(L,-2,1);
    // (-1)tbl
    push_obj(L,cdr);
    // (-2)tbl,(-1)cdr
    lua_rawseti(L,-2,2);
    // (-1)tbl
    return 1;
}

int pub ret(/*nelisp.obj[]*/) vector_to_table(lua_State *L){
    check_nargs(L,1);
    check_isobject(L,1);

    Lisp_Object obj = userdata_to_obj(L,1);
    if (!VECTORP(obj))
        luaL_error(L,"Expected vector");

    lua_newtable(L);
    // (-1)tbl
    ptrdiff_t len = ASIZE(obj);
    for (ptrdiff_t i=0; i<len; i++){
        // (-1)tbl
        push_obj(L,XVECTOR(obj)->contents[i]);
        // (-2)tbl,(-1)obj
        lua_rawseti(L,-2,i+1);
        // (-1)tbl
    };
    // (-1)tbl
    return 1;
}

int pub ret() collectgarbage(lua_State *L){
    check_nargs(L,0);

    garbage_collect_();
    return 0;
}
int pub ret() init(lua_State *L){
    global_lua_state = L;
    check_nargs(L,0);

    init_obarray_once();

    return 0;
}
