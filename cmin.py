#!/usr/bin/env python3

import os
from io import StringIO
from typing import Mapping, NamedTuple, Any
from contextlib import contextmanager
from pcpp import Preprocessor
from pycparser import CParser, c_generator
from pycparser.c_ast import Node, Decl, TypeDecl, Struct, Union, Enum, IdentifierType, InitList, NamedInitializer, ArrayDecl, PtrDecl, FuncDecl, FuncDef, Compound, Switch, If, ID


class BaseVisitor:

    def visit(self, node):
        method = 'visit_' + node.__class__.__name__
        return getattr(self, method, self.visit_default)(node)

    def visit_default(self, node):
        assert False, f'Not implemeneted {node.__class__.__name__}'


class Symbol:

    def __init__(self, orig_name):
        self.orig_name = orig_name

    def __add__(self, other):
        return self.name + other

    def __radd__(self, other):
        return other + self.name

    def __str__(self):
        return self.name

class CGenerator(c_generator.CGenerator):

    def visit_IdentifierType(self, n):
        return ' '.join(str(name) for name in n.names)

    def visit_DeclList(self, n):
        s = self.visit(n.decls[0])
        if len(n.decls) > 1:
            s += ', ' + ', '.join(str(self.visit_Decl(decl, no_type=True))
                                  for decl in n.decls[1:])
        return s


class StructDeclarationRewriter(BaseVisitor):

    def __init__(self):
        self.counter = 0

    def rewrite_type(self, t):
        if isinstance(t, Enum):
            return t.__class__(name=t.name, values=None)
        else:
            return t.__class__(name=t.name, decls=None)

    def rewrite(self, l):
        last_decl = None

        for i, node in enumerate(l):
            if ( isinstance(node, Decl) and
                 isinstance(node.type, TypeDecl) and
                 type(node.type.type) in (Struct, Union, Enum)):
                t = node.type.type
                if last_decl is not t:
                    last_decl = t
                else:
                    if t.name is None:
                        sym = Symbol(self.counter)
                        sym.name = f'_anonymous_{sym.orig_name}'
                        t.name = sym
                        self.counter += 1
                    node.type.type = self.rewrite_type(t)
            else:
                last_decl = None

    def visit_default(self, node):
        pass

    def visit_FileAST(self, node):
        if node.ext is not None:
            self.rewrite(node.ext)
        for d in node.ext or ():
            self.visit(d)

    def visit_FuncDef(self, node):
        self.visit(node.body)

    def visit_Compound(self, node):
        if node.block_items is not None:
            self.rewrite(node.block_items)
        for d in node.block_items or ():
            self.visit(d)

    def visit_Switch(self, node):
        self.visit(node.stmt)

    def visit_If(self, node):
        self.visit(node.iftrue)
        if node.iffalse:
            self.visit(node.iffalse)

    def visit_DoWhile(self, node):
        self.visit(node.stmt)

    def visit_While(self, node):
        self.visit(node.stmt)

    def visit_For(self, node):
        self.visit(node.init)
        self.visit(node.stmt)

    def visit_DeclList(self, node):
        self.rewrite(node.decls)


def rewrite_struct_declaration(s):
    """
    >>> rewrite_struct_declaration('struct X {int a;} a,b;')
    struct X
    {
      int a;
    } a;
    struct X b;
    >>> rewrite_struct_declaration('struct {int a;} a,b;')
    struct _anonymous_0
    {
      int a;
    } a;
    struct _anonymous_0 b;
    >>> rewrite_struct_declaration('union X {int a;} a,b;')
    union X
    {
      int a;
    } a;
    union X b;
    >>> rewrite_struct_declaration('enum X {A = 0,} a,b;')
    enum X
    {
      A = 0
    } a;
    enum X b;
    >>> rewrite_struct_declaration('void f() { struct X {int a;} a,b; }')
    void f()
    {
      struct X
      {
        int a;
      } a;
      struct X b;
    }
    <BLANKLINE>
    >>> rewrite_struct_declaration('void f() { for (;;){ struct X {int a;} a,b; } }')
    void f()
    {
      for (;;)
      {
        struct X
        {
          int a;
        } a;
        struct X b;
      }
    <BLANKLINE>
    }
    <BLANKLINE>
    >>> rewrite_struct_declaration('void f() { for (struct X {int a;} a,b;;); }')
    void f()
    {
      for (struct X
      {
        int a;
      } a, b;;)
        ;
    <BLANKLINE>
    }
    <BLANKLINE>
    """
    parser = CParser()
    ast = parser.parse(s)
    StructDeclarationRewriter().visit(ast)
    generator = CGenerator()
    print(generator.visit(ast), end='')

class RecordingTable:

    def __init__(self, table):
        self.table = table
        self.reference = set()
        self.declare = set()

    def __getitem__(self, name):
        self.reference.add(name)
        return self.table[name]

    def __contains__(self, name):
        return name in self.table

    def __setitem__(self, name, value):
        self.declare.add(name)
        self.table[name] = value

class SymbolTable:

    def __init__(self, parent=None):
        self.table = {}
        self.parent = parent

    def __getitem__(self, name):
        if name in self.table:
            return self.table[name]
        if self.parent is not None:
            return self.parent[name]
        raise KeyError(name)

    def __contains__(self, name):
        return (name in self.table) or (name in self.parent)

    def __setitem__(self, name, value):
        if name in self.table:
            raise KeyError(name)
        self.table[name] = value


def encode_symbol(n):
    if n < 1404:
        # [A-Z]?[A-Za-z]
        low = n % 52
        high = n//52
        if high == 0:
            h = ''
        else:
            h = chr(0x40+high)
        if low < 26:
            l = chr(0x41 + n)
        else:
            l = chr(0x61 + n - 26)
        return h + l
    assert False, "Too many symbols"


class Counter:

    def __init__(self):
        self.next_value = 0

    def get(self):
        name = encode_symbol(self.next_value)
        self.next_value += 1
        return name

class LocalCounter:

    def __init__(self, parent):
        self.next_value = parent.next_value
        if isinstance(parent, LocalCounter):
            self.base = parent.base
        else:
            self.base = parent

    def get(self):
        name = encode_symbol(self.next_value)
        self.next_value += 1
        self.base.next_value = max(self.next_value, self.base.next_value)
        return name


BUILTIN_TYPES = {k: k for k in ('void', 'char','short', 'int', 'long', 'float', 'double')}

class Tables(NamedTuple):
    typedefs: Mapping[str, Any] = BUILTIN_TYPES
    struct_names: Mapping[str, Symbol] = {}
    struct_decls: Mapping[str, Struct] = {}
    union_names: Mapping[str, Symbol] = {}
    union_decls: Mapping[str, Union] = {}
    enum_names: Mapping[str, Symbol] = {}
    enum_decls: Mapping[str, Enum] = {}
    decl_types: Mapping[str, Any] = {}
    decl_inits: Mapping[str, Any] = {}

class Counters(NamedTuple):
    decl: Any
    struct: Any
    union: Any
    enum: Any

class SymbolRenamer(BaseVisitor):

    def __init__(self):
        super().__init__()
        self.tables = Tables()
        self.counters = None

    @contextmanager
    def enter_child_scope(self):
        tables = self.tables
        self.tables = Tables._make(map(SymbolTable, tables))
        counters = self.counters
        if counters is not None:
            self.counters = Counters._make(map(LocalCounter, counters))
        try:
            yield
        finally:
            self.counters = counters
            self.tables = tables

    @contextmanager
    def record(self):
        for table in self.tables:
            table.table = RecordingTable(table.table)
        try:
            yield
        finally:
            for table in self.tables:
                table.table = table.table.table

    @contextmanager
    def enter_counters(self):
        counters = self.counters
        self.counters = self.global_counters
        try:
            yield
        finally:
            self.counters = counters

    def create_symbol(self, name, counter='decl'):
        sym = Symbol(name)
        sym.name = name
        if self.counters:
            sym.name = getattr(self.counters, counter).get()
        return sym

    def get_typedecl(self, node):
        while not isinstance(node, TypeDecl):
            node = node.type
        return node

    def resolve_type(self, type):
        if isinstance(type, TypeDecl):
            type = type.type

        if isinstance(type, Struct):
            if type.decls is not None:
                return type
            name = type.name.orig_name
            if name in self.tables.struct_names.table:
                return self.tables.struct_decls.table[name]
            else:
                return self.tables.struct_decls[name]
        elif isinstance(type, Union):
            if type.decls is not None:
                return type
            name = type.name.orig_name
            if name in self.tables.union_names.table:
                return self.tables.union_decls.table[name]
            else:
                return self.tables.union_decls[name]
        elif isinstance(type, IdentifierType):
            if len(type.names) == 1 and not isinstance(type.names[0], str):
                t = self.tables.typedefs[type.names[0].orig_name]
                return self.resolve_type(t)

        return type


    def visit_FileAST(self, node):
        self.global_counters = Counters(Counter(), Counter(), Counter(), Counter())

        declare = []
        reference = []

        with self.enter_child_scope():
            for d in node.ext:
                with self.record():
                    self.visit(d)

                    declare.append(tuple(table.table.declare for table in self.tables))
                    reference.append(tuple(table.table.reference for table in self.tables))

            declare_map = [{c:i
                            for i, s in enumerate(t)
                            for c in s}
                           for t in zip(*declare)]

            field_decl_types = Tables._fields.index("decl_types")
            field_decl_inits = Tables._fields.index("decl_inits")

            init_map = {v:declare_map[field_decl_inits][k]
                        for k, v in declare_map[field_decl_types].items()
                        if k in declare_map[field_decl_inits] }

            reference_set = [
                { declare_map[i][c]
                  for i, s in enumerate(t)
                  for c in s }
                for t in reference]

            main = declare_map[field_decl_types]['main']
            visited = {main}
            queue = [main]

            while queue:
                n = queue.pop(0)
                init = init_map.get(n, n)
                if init != n and init not in visited:
                    queue.append(init)
                    visited.add(init)

                for x in reference_set[n]:
                    if x not in visited:
                        queue.append(x)
                        visited.add(x)

            visited = list(visited)
            visited.sort()
            node.ext = [node.ext[i] for i in visited]

            declare = [declare[i] for i in visited]
            field_typedefs = Tables._fields.index("typedefs")

            names = ["struct_names", "union_names", "enum_names"]
            name_fields = [Tables._fields.index(f) for f in names]
            name_counters =  [getattr(self.global_counters, f)
                              for f in ["struct", "union", "enum"]]

            for d in declare:
                for c in d[field_decl_types]:
                    if c == 'main':
                        continue
                    t = self.tables.decl_types[c]
                    if isinstance(t, Enum):
                        self.tables.decl_inits[c].name.name = self.global_counters.decl.get()
                    else:
                        decl = self.get_typedecl(t)
                        if isinstance(decl.declname, Symbol):
                            decl.declname.name = self.global_counters.decl.get()

                for c in d[field_typedefs]:
                    t = self.tables.typedefs[c]
                    decl = self.get_typedecl(t)
                    decl.declname.name = self.global_counters.decl.get()

                for n, f, counter in zip(names, name_fields, name_counters):
                    for c in d[f]:
                        s = getattr(self.tables, n)[c]
                        s.name = counter.get()


    def visit_Decl(self, node):
        name = node.name
        if name is not None:
            typedecl = self.get_typedecl(node.type)
            if name not in self.tables.decl_types.table:
                self.tables.decl_types[name] = node.type
                if 'extern' not in node.storage:
                    sym = self.create_symbol(name)
                    typedecl.declname = sym
            else:
                t = self.tables.decl_types[name]
                assert not isinstance(t, Enum), f"redefinition of {name!r}"
                previous = self.get_typedecl(t)
                typedecl.declname = previous.declname
                # assert typedecl == previous, f"conflict types for {name!r}"

            if node.init is not None:
                self.tables.decl_inits[name] = node.init

        self.visit(node.type)
        if node.init is None:
            return

        if isinstance(node.init, InitList):
            self.visit_InitList(node.init, node.type)
        else:
            self.visit(node.init)

    def visit_InitList(self, node, type):
        type = self.resolve_type(type)
        if isinstance(type, ArrayDecl):
            for e in node.exprs:
                if isinstance(e, NamedInitializer):
                    self.visit_NamedInitializer(e, type.type)
                elif isinstance(e, InitList):
                    self.visit_InitList(e, type.type)
                else:
                    self.visit(e)
        else:
            index = 0
            for e in node.exprs:
                if isinstance(e, NamedInitializer):
                    name = e.name[0].name
                    for i, decl in enumerate(type.decls):
                        if decl.name == name:
                            index = i
                            break
                    else:
                        assert False, f"have no member named {name!r}"
                    self.visit_NamedInitializer(e, type.decls[index].type)
                elif isinstance(e, InitList):
                    self.visit_InitList(e, type.decls[index].type)
                else:
                    self.visit(e)

                index += 1

    def visit_NamedInitializer(self, node, type):
        if isinstance(node.name[0], ID):
            node.name[0].name = type.declname

        if isinstance(node.expr, InitList):
            self.visit_InitList(node.expr, type)
        else:
            self.visit(node.expr)

    def visit_Typedef(self, node):
        self.tables.typedefs[node.name] = node.type
        self.visit(node.type)
        decl = self.get_typedecl(node.type)
        decl.declname = self.create_symbol(node.name)

    def visit_FuncDecl(self, node):
        self.visit(node.type)

        with self.enter_counters():
            with self.enter_child_scope():
                if node.args:
                    self.visit(node.args)

    def visit_ArrayDecl(self, node):
        self.visit(node.type)
        if node.dim is not None:
            self.visit(node.dim)

    def visit_FuncDef(self, node):
        name = node.decl.name
        typedecl = self.get_typedecl(node.decl.type)
        if name not in self.tables.decl_types.table:
            self.tables.decl_types[name] = node.decl.type
            sym = self.create_symbol(typedecl.declname)
            typedecl.declname = sym
        else:
            declare = self.tables.decl_types[name]
            typedecl.declname = self.get_typedecl(declare).declname

        self.tables.decl_inits[name] = node
        self.visit(node.decl.type.type)

        with self.enter_counters():
            with self.enter_child_scope():
                if node.decl.type.args:
                    self.visit(node.decl.type.args)
                self.labels = {}
                self.visit(node.body)

    def visit_Enum(self, node):
        name = node.name
        names = self.tables.enum_names
        if name is not None:
            if name in (names if node.values is None else names.table):
                node.name = self.tables.enum_names[name]
            else:
                sym = self.create_symbol(name, 'enum')
                self.tables.enum_names[name] = sym
                node.name = sym

        if node.values is None:
            return

        if name is not None:
            assert name not in self.tables.enum_decls.table, f"redefinition of enum {name}"
            self.tables.enum_decls[name] = node

        for enum in node.values.enumerators:
            assert enum.name not in self.tables.decl_types.table, f"redefinition of {enum.name!r}"
            self.tables.decl_types[enum.name] = node
            self.tables.decl_inits[enum.name] = enum

            sym = self.create_symbol(enum.name)
            enum.name = sym

            if enum.value is not None:
                self.visit(enum.value)

    def visit_Struct(self, node):
        for i, decl in enumerate(node.decls or ()):
            self.visit(decl.type)
            typedecl = self.get_typedecl(decl.type)
            sym = Symbol(typedecl.declname)
            sym.name = encode_symbol(i)
            typedecl.declname = sym

        name = node.name
        names = self.tables.struct_names
        if name is not None:
            if name in (names if node.decls is None else names.table):
                node.name = self.tables.struct_names[name]
            else:
                sym = self.create_symbol(name, 'struct')
                self.tables.struct_names[name] = sym
                node.name = sym

        if node.decls is None:
            return

        if name is not None:
            assert name not in self.tables.struct_decls.table, f"redefinition of struct {name}"
            self.tables.struct_decls[name] = node

    def visit_Union(self, node):
        for i, decl in enumerate(node.decls or ()):
            self.visit(decl.type)
            typedecl = self.get_typedecl(decl.type)
            sym = Symbol(typedecl.declname)
            sym.name = encode_symbol(i)
            typedecl.declname = sym

        name = node.name
        names = self.tables.union_names

        if name is not None:
            if name in (names if node.decls is None else names.table):
                node.name = self.tables.union_names[name]
            else:
                sym = self.create_symbol(name, 'union')
                self.tables.union_names[name] = sym
                node.name = sym

        if node.decls is None:
            return

        if name is not None:
            assert name not in self.tables.union_decls.table, f"redefinition of union {name}"
            self.tables.union_decls[name] = node

    def visit_StructRef(self, node):
        t = self.resolve_type(self.visit(node.name))
        name = node.field.name
        if node.type == '->':
            assert isinstance(t, PtrDecl), "Not a pointer"
            t = self.resolve_type(t.type)

        for decl in t.decls:
            if decl.name == name:
                node.field.name = self.get_typedecl(decl.type).declname
                return decl.type
        else:
            assert False, f"have no member named {name!r}"


    def visit_TypeDecl(self, node):
        self.visit(node.type)

    def visit_PtrDecl(self, node):
        self.visit(node.type)

    def visit_IdentifierType(self, node):
        if len(node.names) > 1:
            return
        t = self.tables.typedefs[node.names[0]]
        if isinstance(t, Node):
            node.names = [self.get_typedecl(t).declname]

    def visit_Compound(self, node):
        with self.enter_child_scope():
            for item in node.block_items or ():
                self.visit(item)

    def visit_ExprList(self, node):
        for item in node.exprs or ():
            self.visit(item)

    def visit_ParamList(self, node):
        for item in node.params or ():
            self.visit(item)

    def visit_Typename(self, node):
        self.visit(node.type)

    def visit_If(self, node):
        with self.enter_child_scope():
            if node.cond is not None:
                self.visit(node.cond)
            if node.iftrue is not None:
                self.visit(node.iftrue)
            if node.iffalse is not None:
                self.visit(node.iffalse)

    def visit_For(self, node):
        with self.enter_child_scope():
            if node.init is not None:
                self.visit(node.init)
            if node.cond is not None:
                self.visit(node.cond)
            if node.next is not None:
                self.visit(node.next)
            if node.stmt is not None:
                self.visit(node.stmt)

    def visit_DeclList(self, node):
        for item in node.decls or ():
            self.visit(item)

        if node.decls and len(node.decls) > 1:
            for item in node.decls[1:]:
                item.name = self.get_typedecl(item.type).declname


    def visit_While(self, node):
        with self.enter_child_scope():
            if node.cond is not None:
                self.visit(node.cond)
            if node.stmt is not None:
                self.visit(node.stmt)

    def visit_DoWhile(self, node):
        with self.enter_child_scope():
            if node.stmt is not None:
                self.visit(node.stmt)
            if node.cond is not None:
                self.visit(node.cond)

    def visit_Switch(self, node):
        with self.enter_child_scope():
            if node.cond is not None:
                self.visit(node.cond)
            if node.stmt is not None:
                self.visit(node.stmt)

    def visit_Case(self, node):
        self.visit(node.expr)
        for item in node.stmts or ():
            self.visit(item)

    def visit_Default(self, node):
        for item in node.stmts or ():
            self.visit(item)

    def visit_Return(self, node):
        if node.expr is not None:
            self.visit(node.expr)

    def visit_Alignas(self, node):
        self.visit(node.alignment)

    def visit_StaticAssert(self, node):
        self.visit(node.condition)

    def visit_UnaryOp(self, node):
        t = self.visit(node.expr)
        if node.op == '*':
            t = self.resolve_type(t)
            assert isinstance(t, PtrDecl), "Not a pointer"
            return t.type
        elif node.op == '&':
            return PtrDecl(quals=[], type=t)

    def visit_BinaryOp(self, node):
        self.visit(node.left)
        self.visit(node.right)

    def visit_TernaryOp(self, node):
        if node.cond is not None:
            self.visit(node.cond)
        if node.iftrue is not None:
            self.visit(node.iftrue)
        if node.iffalse is not None:
            self.visit(node.iffalse)

    def visit_ArrayRef(self, node):
        t = self.visit(node.name)
        t = self.resolve_type(t)
        assert isinstance(t, ArrayDecl)
        self.visit(node.subscript)
        return t.type

    def visit_Assignment(self, node):
        self.visit(node.rvalue)
        self.visit(node.lvalue)

    def visit_ID(self, node):
        name = node.name
        t = self.tables.decl_types[name]
        if isinstance(t, Enum):
            node.name = self.tables.decl_inits[name].name
        else:
            node.name = self.get_typedecl(self.tables.decl_types[name]).declname
        return t

    def visit_CompoundLiteral(self, node):
        self.visit(node.type.type)
        t = node.type.type
        self.visit_InitList(node.init, t)
        return t

    def visit_Cast(self, node):
        self.visit(node.to_type.type)
        self.visit(node.expr)
        return node.to_type.type

    def visit_FuncCall(self, node):
        t = self.visit(node.name)
        if node.args is not None:
            self.visit(node.args)
        t = self.resolve_type(t)
        if isinstance(t, PtrDecl):
            t = self.resolve_type(t.type)
        assert isinstance(t, FuncDecl)
        return t.type

    def visit_Constant(self, node):
        pass

    def visit_Break(self, node):
        pass

    def visit_Continue(self, node):
        pass

    def visit_EmptyStatement(self, node):
        pass

    def visit_Pragma(self, node):
        pass

    def visit_EllipsisParam(self, node):
        pass

    def visit_Label(self, node):
        name = node.name
        if name in self.labels:
            node.name = self.labels[name]
        else:
            sym = Symbol(name)
            sym.name = encode_symbol(len(self.labels))
            self.labels[name] = sym
            node.name = sym

        self.visit(node.stmt)

    def visit_Goto(self, node):
        name = node.name
        if name in self.labels:
            node.name = self.labels[name]
        else:
            sym = Symbol(name)
            sym.name = encode_symbol(len(self.labels))
            self.labels[name] = sym
            node.name = sym



def rename_ids(s):
    """
    >>> rename_ids('int main() {}')
    int main()
    {
    }
    <BLANKLINE>
    >>> rename_ids('int main() { a: goto a; }')
    int main()
    {
      A:
      goto A;
    <BLANKLINE>
    }
    <BLANKLINE>
    >>> rename_ids('int main() { goto a; a: ; }')
    int main()
    {
      goto A;
      A:
      ;
    <BLANKLINE>
    }
    <BLANKLINE>
    >>> rename_ids('void f(){} int main(){}')
    int main()
    {
    }
    <BLANKLINE>
    >>> rename_ids('int a; int main(){ return a; }')
    int A;
    int main()
    {
      return A;
    }
    <BLANKLINE>
    >>> rename_ids('int a[3]; int main(){ return a[0]; }')
    int A[3];
    int main()
    {
      return A[0];
    }
    <BLANKLINE>
    >>> rename_ids('int a = 1; int main(){ return a; }')
    int A = 1;
    int main()
    {
      return A;
    }
    <BLANKLINE>
    >>> rename_ids('int a; int main(){ return a; } int a = 1;')
    int A;
    int main()
    {
      return A;
    }
    <BLANKLINE>
    int A = 1;
    >>> rename_ids('int a; int main(){ int a; return a; }')
    int main()
    {
      int A;
      return A;
    }
    <BLANKLINE>
    >>> rename_ids('void f(); int main(){ f; } void f() {}')
    void A();
    int main()
    {
      A;
    }
    <BLANKLINE>
    void A()
    {
    }
    <BLANKLINE>
    >>> rename_ids('typedef int t; int main(){ t a; }')
    typedef int B;
    int main()
    {
      B A;
    }
    <BLANKLINE>
    >>> rename_ids('typedef int t; int main(){ typedef int t; t a; }')
    int main()
    {
      typedef int A;
      A B;
    }
    <BLANKLINE>
    >>> rename_ids('struct S; int main(){ struct S *s; }')
    struct A;
    int main()
    {
      struct A *A;
    }
    <BLANKLINE>
    >>> rename_ids('struct S; int main(){ struct S {}; struct S *s; }')
    int main()
    {
      struct A
      {
      };
      struct A *A;
    }
    <BLANKLINE>
    >>> rename_ids('union U; int main(){ union U *u; }')
    union A;
    int main()
    {
      union A *A;
    }
    <BLANKLINE>
    >>> rename_ids('union U; int main(){ union U {}; union U *u; }')
    int main()
    {
      union A
      {
      };
      union A *A;
    }
    <BLANKLINE>
    >>> rename_ids('enum E; int main(){ enum E *e; }')
    enum A;
    int main()
    {
      enum A *A;
    }
    <BLANKLINE>
    >>> rename_ids('enum E; int main(){ enum E { A }; enum E *e; }')
    int main()
    {
      enum A
      {
        A
      };
      enum A *B;
    }
    <BLANKLINE>
    >>> rename_ids('enum E { X }; int main(){ X; }')
    enum A
    {
      A
    };
    int main()
    {
      A;
    }
    <BLANKLINE>
    >>> rename_ids('enum E { X }; int main(){ int X; X; }')
    int main()
    {
      int A;
      A;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() { struct S s = {.x = 1}; }')
    struct A
    {
      int A;
    };
    int main()
    {
      struct A A = {.A = 1};
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() { struct S s[] = {{.x = 1}}; }')
    struct A
    {
      int A;
    };
    int main()
    {
      struct A A[] = {{.A = 1}};
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; struct T {struct S a; int b; struct S c;}; int main() { struct T t = {.a = {.x = 1}, 2, {.x = 3} }; }')
    struct A
    {
      int A;
    };
    struct B
    {
      struct A A;
      int B;
      struct A C;
    };
    int main()
    {
      struct B A = {.A = {.A = 1}, 2, {.A = 3}};
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() {struct S s; s.x = 1; }')
    struct A
    {
      int A;
    };
    int main()
    {
      struct A A;
      A.A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() {struct S *s; s->x = 1; }')
    struct A
    {
      int A;
    };
    int main()
    {
      struct A *A;
      A->A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('int main() {struct {int x;} *s; (*s).x = 1; }')
    int main()
    {
      struct 
      {
        int A;
      } *A;
      (*A).A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() {struct S s; (&s)->x = 1; }')
    struct A
    {
      int A;
    };
    int main()
    {
      struct A A;
      (&A)->A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() {struct S s[3]; s[0].x = 1; }')
    struct A
    {
      int A;
    };
    int main()
    {
      struct A A[3];
      A[0].A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('typedef struct {int x;} S; int main() { S s; s.x = 1; }')
    typedef struct 
    {
      int A;
    } B;
    int main()
    {
      B A;
      A.A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; struct T {struct S x;}; int main() {struct T t; t.x.x = 1; }')
    struct A
    {
      int A;
    };
    struct B
    {
      struct A A;
    };
    int main()
    {
      struct B A;
      A.A.A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('int main() {struct {int x;} s; s.x = 1; }')
    int main()
    {
      struct 
      {
        int A;
      } A;
      A.A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() { return (struct S){ .x = 1 }.x; }')
    struct A
    {
      int A;
    };
    int main()
    {
      return ((struct A){.A = 1}).A;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; int main() { int x; ((struct S)x).x = 1; }')
    struct A
    {
      int A;
    };
    int main()
    {
      int A;
      ((struct A) A).A = 1;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; struct S f(); int main() { return f().x; }')
    struct A
    {
      int A;
    };
    struct A A();
    int main()
    {
      return A().A;
    }
    <BLANKLINE>
    >>> rename_ids('struct S {int x;}; struct S (*f)(); int main() { return f().x; }')
    struct A
    {
      int A;
    };
    struct A (*A)();
    int main()
    {
      return A().A;
    }
    <BLANKLINE>
    >>> rename_ids('int main() { for(struct {int x;} a,b;;); }')
    int main()
    {
      for (struct A
      {
        int A;
      } A, B;;)
        ;
    <BLANKLINE>
    }
    <BLANKLINE>
    """
    parser = CParser()
    ast = parser.parse(s)
    StructDeclarationRewriter().visit(ast)
    SymbolRenamer().visit(ast)
    generator = CGenerator()
    print(generator.visit(ast), end='')

def define_inttypes(bits):
    names = ['char', 'short', 'int', 'long', 'longlong']
    for b in [8,16,32,64]:
        name = names[bits.index(b)]
        yield f"#define uint{b}_t unsigned {name}\n"
        yield f"#define int{b}_t signed {name}\n"
        if name == 'long':
            yield f"#define UINT{b}_C(c) c##ul\n"
        elif name == 'longlong':
            yield f"#define UINT{b}_C(c) c##ull\n"
        else:
            yield f"#define UINT{b}_C(c) c##u\n"

    name = names[bits.index(bits[-1])]
    yield f"#define uintptr_t unsigned {name}\n"
    yield f"#define intptr_t signed {name}\n"


def mtime(filename):
    try:
        return os.stat(filename).st_mtime
    except FileNotFoundError:
        pass


def main(bits, input, output=None):
    if output is not None:
        time_i = mtime(input)
        assert time_i is not None, f"{input} not found"
        time_o = mtime(output)
        if time_o is not None and time_i < time_o:
            return

    cpp = Preprocessor()
    cpp.add_path(os.path.dirname(__file__))

    with open(input, 'r') as f:
        code = f.read()
    prolog = ''.join(define_inttypes(list(map(int, bits.split(",")))))
    cpp.parse(prolog + code, input)

    buf = StringIO()
    cpp.write(buf)
    assert cpp.return_code == 0, "preprocessor error"

    parser = CParser()
    ast = parser.parse(buf.getvalue(), input)
    StructDeclarationRewriter().visit(ast)
    SymbolRenamer().visit(ast)
    generator = CGenerator(reduce_parentheses=True)
    ccode = generator.visit(ast)

    if output is None:
        print(ccode)
    else:
        with open(output, "w") as f:
            f.write(ccode)

if __name__ == '__main__':
    import sys
    main(*sys.argv[1:])
