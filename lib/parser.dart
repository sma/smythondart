import 'package:smython/smython.dart';

import 'ast_eval.dart';
import 'scanner.dart';

/// Parses **Smython**, a programming language similar to a subset of Python 3.
///
/// Here is a simple example:
///
/// ```py
/// def fac(n):
///     if n == 0: return 1
///     return n * fac(n - 1)
/// print(fac(10))
/// ```
///
/// Syntax differences to Python 3:
///
/// Smython has no decorators, `async` functions, typed function parameters,
/// function keyword arguments, argument spatting with `*` or `**`, no
/// `del`, `import`, `global`, `nonlocal`, `assert` or `yield` statements,
/// no `@=`, `&=`, `|=`, `^=`, `<<=`, `>>=`, `//=` or `**=`, no `continue`
/// in loops, no `from` clause in `raise`, no `with` statement, no combined
/// `try`/`except`/`finally`, no multiple inheritance in classes, no lambdas,
/// no `<>`, `@`, `//`, `&`, `|`, `^`, `<<`, `>>` or `~` operators, no `await`,
/// no list or dict comprehension, no `...`, no list in `[ ` but only a single
/// value or slice, no tripple-quoted, byte or raw string, only unicode one.
///
/// Currently, Smython uses only `int` for numeric values.
///
/// EBNF Grammar:
/// ```
/// file_input: {NEWLINE | stmt} ENDMARKER
///
/// stmt: simple_stmt | compound_stmt
/// simple_stmt: small_stmt {';' small_stmt} [';'] NEWLINE
/// small_stmt: expr_stmt | pass_stmt | flow_stmt
/// expr_stmt: testlist [('+=' | '-=' | '*=' | '/=' | '%=' | '=') testlist]
/// pass_stmt: 'pass'
/// flow_stmt: break_stmt | return_stmt | raise_stmt
/// break_stmt: 'break'
/// return_stmt: 'return' [testlist]
/// raise_stmt: 'raise' [test]
/// compound_stmt: if_stmt | while_stmt | for_stmt | try_stmt | funcdef | classdef
/// if_stmt: 'if' test ':' suite {'elif' test ':' suite} ['else' ':' suite]
/// while_stmt: 'while' test ':' suite ['else' ':' suite]
/// for_stmt: 'for' exprlist 'in' testlist ':' suite ['else' ':' suite]
/// exprlist: expr {',' expr} [',']
/// try_stmt: 'try' ':' suite (except_cont | finally_cont)
/// except_cont: except_clause {except_clause} ['else' ':' suite]
/// except_clause: 'except' [test ['as' NAME]] ':' suite
/// finally_cont: 'finally' ':' suite
/// funcdef: 'def' NAME parameters ':' suite
/// parameters: '(' [parameter {',' parameter} [',']] ')'
/// parameter: NAME ['=' test]
/// classdef: 'class' NAME ['(' [test] ')'] ':' suite
///
/// suite: simple_stmt | NEWLINE INDENT stmt+ DEDENT
///
/// test: or_test ['if' or_test 'else' test]
/// or_test: and_test {'or' and_test}
/// and_test: not_test {'and' not_test}
/// not_test: 'not' not_test | comparison
/// comparison: expr [('<'|'>'|'=='|'>='|'<='|'!='|'in'|'not' 'in'|'is' ['not']) expr]
/// expr: term {('+'|'-') term}
/// term: factor {('*'|'/'|'%') factor}
/// factor: ('+'|'-') factor | power
/// power: atom {trailer}
/// trailer: '(' [testlist] ')' | '[' subscript ']' | '.' NAME
/// subscript: test | [test] ':' [test] [':' [test]]
/// atom: '(' [testlist] ')' | '[' [testlist] ']' | '{' [dictorsetmaker] '}' | NAME | NUMBER | STRING+
/// dictorsetmaker: test ':' test {',' test ':' test} [','] | testlist
///
/// testlist: test {',' test} [',']
/// ```
///
/// Parsing may throw a syntax error.
Suite parse(String source) {
  return Parser(tokenize(source).iterator).parseFileInput();
}

class Parser {
  final Iterator<Token> _iter;

  Parser(this._iter) {
    advance();
  }

  // -------- Helper --------

  /// Returns the current token (not consuming it).
  Token get token => _iter.current;

  /// Consumes the curent token and advances to the next token.
  void advance() => _iter.moveNext();

  /// Consumes the current token if and only if its value is [value].
  bool at(String value) {
    if (token.value == value) {
      advance();
      return true;
    }
    return false;
  }

  /// Consumes the current token if and only if its value is [value] and throws
  /// a syntax error otherwise.
  void expect(String value) {
    if (!at(value)) throw syntaxError('expected $value');
  }

  /// Constructs a syntax error with [message] and the current token.
  /// It should also denote the line.
  String syntaxError(String message) {
    return 'SyntaxError: $message but found $token at line ${token.line}';
  }

  // -------- Suite parsing --------

  // file_input: {NEWLINE | stmt} ENDMARKER
  Suite parseFileInput() {
    final stmts = <Stmt>[];
    while (!at(Token.eof.value)) {
      if (!at("\n")) stmts.addAll(parseStmt());
    }
    return Suite(stmts);
  }

  // suite: simple_stmt | NEWLINE INDENT stmt+ DEDENT
  Suite parseSuite() {
    if (at("\n")) {
      expect(Token.indent.value);
      final stmts = <Stmt>[];
      while (!at(Token.dedent.value)) {
        stmts.addAll(parseStmt());
      }
      return Suite(stmts);
    }
    return Suite(parseSimpleStmt());
  }

  // -------- Statement parsing --------

  // stmt: simple_stmt | compound_stmt
  List<Stmt> parseStmt() {
    final stmt = parseCompoundStmtOpt();
    if (stmt != null) return [stmt];
    return parseSimpleStmt();
  }

  // -------- Compount statement parsing --------

  // compound_stmt: if_stmt | while_stmt | for_stmt | try_stmt | funcdef | classdef
  Stmt parseCompoundStmtOpt() {
    if (at("if")) return parseIfStmt();
    if (at("while")) return parseWhileStmt();
    if (at("for")) return parseForStmt();
    if (at("try")) return parseTryStmt();
    if (at("def")) return parseFuncDef();
    if (at("class")) return parseClassDef();
    return null;
  }

  // if_stmt: 'if' test ':' suite {'elif' test ':' suite} ['else' ':' suite]
  Stmt parseIfStmt() {
    final test = parseTest();
    expect(":");
    return IfStmt(test, parseSuite(), _parseIfStmtCont());
  }

  // private: ['elif' test ':' suite | 'else' ':' suite]
  Suite _parseIfStmtCont() {
    if (at("elif")) {
      final test = parseTest();
      expect(":");
      return Suite([IfStmt(test, parseSuite(), _parseIfStmtCont())]);
    }
    return _parseElse();
  }

  // private: ['else' ':' suite]
  Suite _parseElse() {
    if (at("else")) {
      expect(":");
      return parseSuite();
    }
    return Suite([const PassStmt()]);
  }

  // while_stmt: 'while' test ':' suite ['else' ':' suite]
  Stmt parseWhileStmt() {
    final test = parseTest();
    expect(":");
    return WhileStmt(test, parseSuite(), _parseElse());
  }

  // for_stmt: 'for' exprlist 'in' testlist ':' suite ['else' ':' suite]
  Stmt parseForStmt() {
    final target = parseExprListAsTuple();
    expect("in");
    final iter = parseTestListAsTuple();
    expect(":");
    return ForStmt(target, iter, parseSuite(), _parseElse());
  }

  // exprlist: expr {',' expr} [',']
  TupleExpr parseExprListAsTuple() {
    final expr = parseExpr();
    if (!at(",")) return expr;
    final exprs = <Expr>[expr];
    while (hasTest) {
      exprs.add(parseExpr());
      if (!at(",")) break;
    }
    return TupleExpr(exprs);
  }

  // try_stmt: 'try' ':' suite (except_clause {except_clause} ['else' ':' suite] | 'finally' ':' suite)
  Stmt parseTryStmt() {
    expect(":");
    final trySuite = parseSuite();
    if (at("finally")) {
      expect(":");
      return TryFinallyStmt(trySuite, parseSuite());
    }
    expect("except");
    final excepts = <ExceptClause>[_parseExceptClause()];
    while (at("except")) {
      excepts.add(_parseExceptClause());
    }
    return TryExceptStmt(trySuite, excepts, _parseElse());
  }

  // except_clause: 'except' [test ['as' NAME]] ':' suite
  ExceptClause _parseExceptClause() {
    Expr test;
    String name;
    if (!at(":")) {
      test = parseTest();
      if (at("as")) {
        name = parseName();
      }
      expect(":");
    }
    return ExceptClause(test, name, parseSuite());
  }

  // funcdef: 'def' NAME parameters ':' suite
  Stmt parseFuncDef() {
    final name = parseName();
    final defExprs = <Expr>[];
    final params = parseParameters(defExprs);
    expect(":");
    return DefStmt(name, params, defExprs, parseSuite());
  }

  // parameters: '(' [parameter {',' parameter} [',']] ')'
  List<String> parseParameters(List<Expr> defExprs) {
    final params = <String>[];
    expect("(");
    if (at(")")) return params;
    params.add(parseParameter(defExprs));
    while (at(",")) {
      if (at(")")) return params;
      params.add(parseParameter(defExprs));
    }
    expect(")");
    return params;
  }

  // parameter: NAME ['=' test]
  String parseParameter(List<Expr> defExprs) {
    final name = parseName();
    if (at("=")) defExprs.add(parseTest());
    return name;
  }

  // classdef: 'class' NAME ['(' [test] ')'] ':' suite
  Stmt parseClassDef() {
    final name = parseName();
    Expr superExpr = const LitExpr(SmyValue.none);
    if (at("(")) {
      if (!at(")")) {
        superExpr = parseTest();
        expect(")");
      }
    }
    expect(":");
    return ClassStmt(name, superExpr, parseSuite());
  }

  // -------- Simple statement parsing --------

  // simple_stmt: small_stmt {';' small_stmt} [';'] NEWLINE
  List<Stmt> parseSimpleStmt() {
    final stmts = <Stmt>[parseSmallStmt()];
    while (at(";")) {
      if (at("\n")) return stmts;
      stmts.add(parseSmallStmt());
    }
    expect("\n");
    return stmts;
  }

  // small_stmt: expr_stmt | pass_stmt | flow_stmt
  // flow_stmt: break_stmt | return_stmt | raise_stmt
  Stmt parseSmallStmt() {
    if (at("pass")) return const PassStmt();
    if (at("break")) return const BreakStmt();
    if (at("return")) {
      // return_stmt: 'return' [testlist]
      return ReturnStmt(hasTest ? parseTestListAsTuple() : const LitExpr(SmyValue.none));
    }
    if (at("raise")) {
      // raise_stmt: 'raise' [test]
      return RaiseStmt(hasTest ? parseTest() : const LitExpr(SmyValue.none));
    }
    return parseExprStmt();
  }

  // expr_stmt: testlist [('+=' | '-=' | '*=' | '/=' | '%=' | '=') testlist]
  Stmt parseExprStmt() {
    if (hasTest) {
      final expr = parseTestListAsTuple();
      if (at("=")) return AssignStmt(expr, parseTestListAsTuple());
      // if (at("+=")) return AddAssignStmt(expr, parseTestListAsTuple());
      // if (at("-=")) return SubAssignStmt(expr, parseTestListAsTuple());
      // if (at("*=")) return MulAssignStmt(expr, parseTestListAsTuple());
      // if (at("/=")) return DivAssignStmt(expr, parseTestListAsTuple());
      // if (at("%=")) return ModAssignStmt(expr, parseTestListAsTuple());
      return ExprStmt(expr);
    }
    return throw syntaxError('expected statement');
  }

  // -------- Expression parsing --------

  // test: or_test ['if' or_test 'else' test]
  Expr parseTest() {
    final expr = parseOrTest();
    if (at("if")) {
      final test = parseOrTest();
      expect("else");
      return CondExpr(test, expr, parseTest());
    }
    return expr;
  }

  // or_test: and_test {'or' and_test}
  Expr parseOrTest() {
    var expr = parseAndTest();
    while (at("or")) {
      expr = OrExpr(expr, parseAndTest());
    }
    return expr;
  }

  // and_test: not_test {'and' not_test}
  Expr parseAndTest() {
    var expr = parseNotTest();
    while (at("and")) {
      expr = AndExpr(expr, parseNotTest());
    }
    return expr;
  }

  // not_test: 'not' not_test | comparison
  Expr parseNotTest() {
    if (at("not")) return NotExpr(parseNotTest());
    return parseComparison();
  }

  // comparison: expr [('<'|'>'|'=='|'>='|'<='|'!='|'in'|'not' 'in'|'is' ['not']) expr]
  Expr parseComparison() {
    final expr = parseExpr();
    if (at("<")) return LtExpr(expr, parseExpr());
    if (at(">")) return GtExpr(expr, parseExpr());
    if (at("==")) return EqExpr(expr, parseExpr());
    if (at(">=")) return GeExpr(expr, parseExpr());
    if (at("<=")) return LeExpr(expr, parseExpr());
    if (at("!=")) return NeExpr(expr, parseExpr());
    if (at("in")) return InExpr(expr, parseExpr());
    if (at("not")) {
      expect("in");
      return NotExpr(InExpr(expr, parseExpr()));
    }
    if (at("is")) {
      if (at("not")) return NotExpr(IsExpr(expr, parseExpr()));
      return IsExpr(expr, parseExpr());
    }
    return expr;
  }

  // expr: term {('+'|'-') term}
  Expr parseExpr() {
    var expr = parseTerm();
    while (true) {
      if (at("+"))
        expr = AddExpr(expr, parseTerm());
      else if (at("-"))
        expr = SubExpr(expr, parseTerm());
      else
        break;
    }
    return expr;
  }

  // term: factor {('*'|'/'|'%') factor}
  Expr parseTerm() {
    var expr = parseFactor();
    while (true) {
      if (at("*"))
        expr = MulExpr(expr, parseFactor());
      else if (at("/"))
        expr = DivExpr(expr, parseFactor());
      else if (at("%"))
        expr = ModExpr(expr, parseFactor());
      else
        break;
    }
    return expr;
  }

  // factor: ('+'|'-') factor | power
  Expr parseFactor() {
    if (at("+")) return PosExpr(parseFactor());
    if (at("-")) return NegExpr(parseFactor());
    return parsePower();
  }

  // power: atom {trailer}
  Expr parsePower() {
    var expr = parseAtom();
    // trailer: '(' [testlist] ')' | '[' subscript ']' | '.' NAME
    while (true) {
      if (at("(")) {
        expr = CallExpr(expr, parseTestListOpt());
        expect(")");
      } else if (at("[")) {
        expr = IndexExpr(expr, parseSubscript());
        expect("]");
      } else if (at(".")) {
        expr = AttrExpr(expr, parseName());
      } else {
        break;
      }
    }
    return expr;
  }

  // subscript: test | [test] ':' [test] [':' [test]]
  Expr parseSubscript() {
    Expr start;
    final none = const LitExpr(SmyValue.none);
    if (hasTest) {
      start = parseTest();
      if (!at(":")) return start;
    } else {
      start = none;
      expect(":");
    }
    final stop = hasTest ? parseTest() : none;
    final step = at(":") && hasTest ? parseTest() : none;
    return CallExpr(const VarExpr(SmyString("slice")), [start, stop, step]);
  }

  // atom: '(' [testlist] ')' | '[' [testlist] ']' | '{' [dictorsetmaker] '}' | NAME | NUMBER | STRING+
  Expr parseAtom() {
    if (at("(")) return _parseTupleMaker();
    if (at("[")) return _parseListMaker();
    if (at("{")) return _parseDictOrSetMaker();
    final t = token;
    if (t.isName) {
      advance();
      final name = t.value;
      if (name == "True") return const LitExpr(SmyValue.trueValue);
      if (name == "False") return const LitExpr(SmyValue.falseValue);
      if (name == "None") return const LitExpr(SmyValue.none);
      return VarExpr(SmyString(name));
    }
    if (t.isNumber) {
      advance();
      return LitExpr(SmyInt(t.number));
    }
    if (t.isString) {
      final buffer = StringBuffer();
      while (token.isString) {
        buffer.write(token.string);
        advance();
      }
      return LitExpr(SmyString(buffer.toString()));
    }
    throw syntaxError('expected (, [, {, NAME, NUMBER, or STRING');
  }

  Expr _parseTupleMaker() {
    if (at(")")) return const TupleExpr([]);
    final expr = parseTest();
    if (at(")")) return expr;
    expect(",");
    final exprs = [expr] + parseTestListOpt();
    expect(")");
    return TupleExpr(exprs);
  }

  Expr _parseListMaker() {
    final exprs = parseTestListOpt();
    expect("]");
    return ListExpr(exprs);
  }

  // dictorsetmaker: test ':' test {',' test ':' test} [','] | testlist
  Expr _parseDictOrSetMaker() {
    if (at("}")) return const DictExpr([]);
    final expr = parseTest();
    if (at(":")) {
      // dictionary
      final exprs = <Expr>[expr, parseTest()];
      while (at(",")) {
        if (at("}")) return DictExpr(exprs);
        exprs.add(parseTest());
        expect(":");
        exprs.add(parseTest());
      }
      expect("}");
      return DictExpr(exprs);
    } else {
      // set
      final exprs = [expr];
      if (at(",")) exprs.addAll(parseTestListOpt());
      expect("}");
      return SetExpr(exprs);
    }
  }

  // NAME
  String parseName() {
    final t = token;
    if (t.isName) {
      advance();
      return t.value;
    }
    throw syntaxError('expected NAME');
  }

  // -------- Expression list parsing --------

  // testlist: test {',' test} [',']
  TupleExpr parseTestListAsTuple() {
    final test = parseTest();
    if (!at(",")) return test;
    final tests = <Expr>[test];
    if (hasTest) tests.addAll(parseTestListOpt());
    return TupleExpr(tests);
  }

  // testlist: test {',' test} [',']
  List<Expr> parseTestListOpt() {
    final exprs = <Expr>[];
    if (hasTest) {
      exprs.add(parseTest());
      while (at(",")) {
        if (!hasTest) break;
        exprs.add(parseTest());
      }
    }
    return exprs;
  }

  /// Returns whether the current token is a valid start of a `test`.
  /// It must be either a name, a number, a string, a prefix `+` or `-`,
  /// the `not` statement, or `(`, `[`, and `{`.
  bool get hasTest {
    // final t = token;
    // return t.isName || t.isNumber || "+-([{\"'".contains(t.value[0]) || t.value == "not";
    return token.value.startsWith(RegExp('[-+\'"\\d([{]')) || token.isName || token.value == "not";
  }
}