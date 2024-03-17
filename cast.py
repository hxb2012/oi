#!/usr/bin/env python3

"""
>>> parse('void f(int m, int n) { int a[m][n+1]; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: m, [], [], [], []
            TypeDecl: m, [], None
              IdentifierType: ['int']
          Decl: n, [], [], [], []
            TypeDecl: n, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Decl: a, [], [], [], []
        ArrayDecl: []
          ArrayDecl: []
            TypeDecl: a, [], None
              IdentifierType: ['int']
            BinaryOp: +
              ID: n
              Constant: int, 1
          ID: m

>>> parse('int f(int n, int a[n]) { return a[n-1]; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: n, [], [], [], []
            TypeDecl: n, [], None
              IdentifierType: ['int']
          Decl: a, [], [], [], []
            ArrayDecl: []
              TypeDecl: a, [], None
                IdentifierType: ['int']
              ID: n
        TypeDecl: f, [], None
          IdentifierType: ['int']
    Compound: 
      Return: 
        ArrayRef: 
          ID: a
          BinaryOp: -
            ID: n
            Constant: int, 1
>>> parse('void f(int a) { a += a * 2; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Assignment: +=
        ID: a
        BinaryOp: *
          ID: a
          Constant: int, 2
>>> parse('void f() { _Alignas(2*2*2) char c[128]; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Decl: c, [], [Alignas(alignment=BinaryOp(op='*',
                           left=BinaryOp(op='*',
                                         left=Constant(type='int',
                                                       value='2'
                                                       ),
                                         right=Constant(type='int',
                                                        value='2'
                                                        )
                                         ),
                           right=Constant(type='int',
                                          value='2'
                                          )
                           )
        )], [], []
        ArrayDecl: []
          TypeDecl: c, [], None
            IdentifierType: ['char']
          Constant: int, 128
>>> parse('void f() { for(;;) break; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      For: 
        Break: 
>>> parse('void f(int a) { switch(a) {case 1: case a+2: break; default: ; } }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Switch: 
        ID: a
        Compound: 
          Case: 
            Constant: int, 1
          Case: 
            BinaryOp: +
              ID: a
              Constant: int, 2
            Break: 
          Default: 
            EmptyStatement: 
>>> parse('void f(int a) { (char)a; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Cast: 
        Typename: None, [], None
          TypeDecl: None, [], None
            IdentifierType: ['char']
        ID: a
>>> parse('void f() { (struct {int a;}){.a = 1}; }');
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      CompoundLiteral: 
        Typename: None, [], None
          TypeDecl: None, [], None
            Struct: None
              Decl: a, [], [], [], []
                TypeDecl: a, [], None
                  IdentifierType: ['int']
        InitList: 
          NamedInitializer: 
            Constant: int, 1
            ID: a
>>> parse('void f() { for(;;) continue; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      For: 
        Continue: 
>>> parse('void f() { for(int i=0, b=2;i<1;i++) ; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      For: 
        DeclList: 
          Decl: i, [], [], [], []
            TypeDecl: i, [], None
              IdentifierType: ['int']
            Constant: int, 0
          Decl: b, [], [], [], []
            TypeDecl: b, [], None
              IdentifierType: ['int']
            Constant: int, 2
        BinaryOp: <
          ID: i
          Constant: int, 1
        UnaryOp: p++
          ID: i
        EmptyStatement: 
>>> parse('void f() { do { } while(1); }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      DoWhile: 
        Constant: int, 1
        Compound: 
>>> parse('int f(char *fmt, ...) { }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: fmt, [], [], [], []
            PtrDecl: []
              TypeDecl: fmt, [], None
                IdentifierType: ['char']
          EllipsisParam: 
        TypeDecl: f, [], None
          IdentifierType: ['int']
    Compound: 
>>> parse('enum E { A = 0, B, };')
FileAST: 
  Decl: None, [], [], [], []
    Enum: E
      EnumeratorList: 
        Enumerator: A
          Constant: int, 0
        Enumerator: B
>>> parse('void f() { 1, 2, 3; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      ExprList: 
        Constant: int, 1
        Constant: int, 2
        Constant: int, 3
>>> parse('void f(int a, int); void g(int a) { f(a, a+1); }')
FileAST: 
  Decl: f, [], [], [], []
    FuncDecl: 
      ParamList: 
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
        Typename: None, [], None
          TypeDecl: None, [], None
            IdentifierType: ['int']
      TypeDecl: f, [], None
        IdentifierType: ['void']
  FuncDef: 
    Decl: g, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: g, [], None
          IdentifierType: ['void']
    Compound: 
      FuncCall: 
        ID: f
        ExprList: 
          ID: a
          BinaryOp: +
            ID: a
            Constant: int, 1
>>> parse('void f() { a: goto a; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Label: a
        Goto: a
>>> parse('void f() { signed int a; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Decl: a, [], [], [], []
        TypeDecl: a, [], None
          IdentifierType: ['signed', 'int']
>>> parse('void f() { if (1) { } }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      If: 
        Constant: int, 1
        Compound: 
>>> parse('int a[] = {1,2,3}; struct {int a; int b; } x = { .a = 1, 2 };')
FileAST: 
  Decl: a, [], [], [], []
    ArrayDecl: []
      TypeDecl: a, [], None
        IdentifierType: ['int']
    InitList: 
      Constant: int, 1
      Constant: int, 2
      Constant: int, 3
  Decl: x, [], [], [], []
    TypeDecl: x, [], None
      Struct: None
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
        Decl: b, [], [], [], []
          TypeDecl: b, [], None
            IdentifierType: ['int']
    InitList: 
      NamedInitializer: 
        Constant: int, 1
        ID: a
      Constant: int, 2
>>> parse("char * const * p; char ** const q;")
FileAST: 
  Decl: p, [], [], [], []
    PtrDecl: []
      PtrDecl: ['const']
        TypeDecl: p, [], None
          IdentifierType: ['char']
  Decl: q, [], [], [], []
    PtrDecl: ['const']
      PtrDecl: []
        TypeDecl: q, [], None
          IdentifierType: ['char']
>>> parse('void f(int a) { return a; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Return: 
        ID: a
>>> parse('_Static_assert(sizeof(int) == 8, "Error")');
FileAST: 
  StaticAssert: 
    BinaryOp: ==
      UnaryOp: sizeof
        Typename: None, [], None
          TypeDecl: None, [], None
            IdentifierType: ['int']
      Constant: int, 8
    Constant: string, "Error"
>>> parse('void f(struct X{ int a; } x) { x.a; };');
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: x, [], [], [], []
            TypeDecl: x, [], None
              Struct: X
                Decl: a, [], [], [], []
                  TypeDecl: a, [], None
                    IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      StructRef: .
        ID: x
        ID: a
>>> parse('void f(int a) {a?a:a+1;}')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      TernaryOp: 
        ID: a
        ID: a
        BinaryOp: +
          ID: a
          Constant: int, 1
>>> parse('typedef unsigned int a; typedef struct {int a;} b; typedef b c;')
FileAST: 
  Typedef: a, [], ['typedef']
    TypeDecl: a, [], None
      IdentifierType: ['unsigned', 'int']
  Typedef: b, [], ['typedef']
    TypeDecl: b, [], None
      Struct: None
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
  Typedef: c, [], ['typedef']
    TypeDecl: c, [], None
      IdentifierType: ['b']
>>> parse('void f(int a) { !a; }')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        ParamList: 
          Decl: a, [], [], [], []
            TypeDecl: a, [], None
              IdentifierType: ['int']
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      UnaryOp: !
        ID: a
>>> parse('union {int a; long b;} c; union X {int a; long b;}; union Y {int a; long b;} e, f;')
FileAST: 
  Decl: c, [], [], [], []
    TypeDecl: c, [], None
      Union: None
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
        Decl: b, [], [], [], []
          TypeDecl: b, [], None
            IdentifierType: ['long']
  Decl: None, [], [], [], []
    Union: X
      Decl: a, [], [], [], []
        TypeDecl: a, [], None
          IdentifierType: ['int']
      Decl: b, [], [], [], []
        TypeDecl: b, [], None
          IdentifierType: ['long']
  Decl: e, [], [], [], []
    TypeDecl: e, [], None
      Union: Y
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
        Decl: b, [], [], [], []
          TypeDecl: b, [], None
            IdentifierType: ['long']
  Decl: f, [], [], [], []
    TypeDecl: f, [], None
      Union: Y
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
        Decl: b, [], [], [], []
          TypeDecl: b, [], None
            IdentifierType: ['long']
>>> parse('void f() {while(1) {}}')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      While: 
        Constant: int, 1
        Compound: 
>>> parse('#pragma once')
FileAST: 
  Pragma: once
>>> parse('void f() {int a; { int a; }}')
FileAST: 
  FuncDef: 
    Decl: f, [], [], [], []
      FuncDecl: 
        TypeDecl: f, [], None
          IdentifierType: ['void']
    Compound: 
      Decl: a, [], [], [], []
        TypeDecl: a, [], None
          IdentifierType: ['int']
      Compound: 
        Decl: a, [], [], [], []
          TypeDecl: a, [], None
            IdentifierType: ['int']
"""

from pycparser import CParser
from io import StringIO

def parse(s):
    parser = CParser()
    ast = parser.parse(s)
    buf = StringIO()
    ast.show(buf)
    print(buf.getvalue(), end='')
