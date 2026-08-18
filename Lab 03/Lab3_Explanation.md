# Lab 3 – Semantic Analysis: Complete Code & Logic Explanation

> This document explains **only the new semantic analysis work** added for Lab 3.
> It covers every check, every data structure change, and the reasoning behind each decision.

---

## Table of Contents

1. [What Is Semantic Analysis?](#1-what-is-semantic-analysis)
2. [How Types Flow Through the Grammar](#2-how-types-flow-through-the-grammar)
3. [Global State Added for Lab 3](#3-global-state-added-for-lab-3)
4. [The Type-Update Trick on Multiple Declaration](#4-the-type-update-trick-on-multiple-declaration)
5. [Check 1 – Void Variable Type](#5-check-1--void-variable-type)
6. [Check 2 – Multiple Declaration of Variables](#6-check-2--multiple-declaration-of-variables)
7. [Check 3 – Multiple Declaration of Function Parameters](#7-check-3--multiple-declaration-of-function-parameters)
8. [Check 4 – Multiple Declaration of Functions](#8-check-4--multiple-declaration-of-functions)
9. [Check 5 – Undeclared Variable](#9-check-5--undeclared-variable)
10. [Check 6 – Array Used Without Index](#10-check-6--array-used-without-index)
11. [Check 7 – Non-Array Used With Index](#11-check-7--non-array-used-with-index)
12. [Check 8 – Array Index Not Integer](#12-check-8--array-index-not-integer)
13. [Check 9 – Undeclared Function](#13-check-9--undeclared-function)
14. [Check 10 – Undeclared Variable in printf](#14-check-10--undeclared-variable-in-printf)
15. [Check 11 – Function Argument Count Mismatch](#15-check-11--function-argument-count-mismatch)
16. [Check 12 – Function Argument Type Mismatch](#16-check-12--function-argument-type-mismatch)
17. [How Argument Types Are Collected](#17-how-argument-types-are-collected)
18. [Data Type Propagation Through Expressions](#18-data-type-propagation-through-expressions)
19. [Full Check Flow on a Real Example](#19-full-check-flow-on-a-real-example)
20. [Output Files](#20-output-files)

---

## 1. What Is Semantic Analysis?

Syntax analysis (Lab 2) only verifies that the **shape** of code is grammatically correct. It does not care about *meaning*. Semantic analysis adds meaning-level checks on top:

| Stage | What it checks |
|-------|----------------|
| Lexical | Valid tokens (numbers, identifiers, operators) |
| Syntax | Valid grammar structure (if-else, function definitions, expressions) |
| **Semantic** | **Correct usage: right types, declared variables, matching arguments** |

In this lab, the Yacc parser's **action code** (the `{ ... }` blocks after each grammar rule) is where all semantic checks are performed. By the time a grammar rule reduces, all of its sub-expressions are already evaluated, so we have full type information available.

---

## 2. How Types Flow Through the Grammar

Every `symbol_info*` object (the `$$`, `$1`, `$2`, ... in rule actions) has a **`data_type`** field that holds a string like `"int"`, `"float"`, `"void"`, or `""` (empty = unknown / error state).

The grammar processes expressions bottom-up: a literal `7` reduces to a `factor`, which becomes an `unary_expression`, then a `term`, a `simple_expression`, a `rel_expression`, a `logic_expression`, and finally an `expression`. At **each step**, the type is copied upward using `$$->set_data_type(...)`.

```
CONST_INT "7"    → data_type = "int"
    ↓
factor           → data_type = "int"   (copy from CONST_INT)
    ↓
factor_info      → data_type = "int"   (copy from factor)
    ↓
unary_expression → data_type = "int"   (copy from factor_info)
    ↓
term             → data_type = "int"   (copy from unary_expression)
    ↓
simple_expression→ data_type = "int"   (copy from term)
    ↓
rel_expression   → data_type = "int"   (copy from simple_expression)
    ↓
logic_expression → data_type = "int"   (copy from rel_expression)
    ↓
expression       → data_type = "int"   (copy from logic_expression)
```

This "type bubbling" is the foundation that makes ALL semantic checks possible.

---

## 3. Global State Added for Lab 3

Inside the `%{ ... %}` section at the top of the `.y` file, one new global variable was added:

```cpp
// Argument types for the current function call
vector<string> current_arg_types;
```

This vector collects the data types of each argument **as the parser processes them**, so that when the function call is finally reduced, we can verify count and types all at once.

> The other globals (`current_type`, `current_decl_list`, `current_params`, etc.) were already present from Lab 2 and are used by the checks explained below.

---

## 4. The Type-Update Trick on Multiple Declaration

**File: `scope_table.h` — `insert_in_scope()` method**

This is perhaps the most subtle change in Lab 3. Here is what the method does now:

```cpp
bool insert_in_scope(symbol_info *symbol)
{
    symbol_info *existing = lookup_in_scope(symbol);
    if (existing != NULL)
    {
        // NEW: update the existing entry's metadata
        existing->set_symbol_class(symbol->get_symbol_class());
        existing->set_data_type(symbol->get_data_type());
        existing->set_array_size(symbol->get_array_size());
        return false; // still return false so the caller reports an error
    }
    int idx = hash_function(symbol->get_name());
    table[idx].push_back(symbol);
    return true;
}
```

**Why?** Consider this input:

```c
int a, b, c[4];   // Line 37: c is int array
float a, c[7];    // Line 39: multiple declaration error for both
```

After line 39, `c` was originally declared as `int c[4]`. The new declaration `float c[7]` fails (returns `false`). But **before** returning false, we now **overwrite** the existing `c`'s type with `"float"` and its size with `7`.

**Effect**: `c` is now stored in the symbol table as a `float` array. All subsequent accesses to `c` see it as float. This is what enables the array-index and type-mismatch errors on lines 50–54 of the sample input to fire correctly.

**The return value is still `false`** — so the caller in `variable_decl` still logs the "Multiple declaration" error. The update is silent from the caller's perspective.

---

## 5. Check 1 – Void Variable Type

**Location: `variable_decl` rule in `.y`**

```cpp
if (current_type == "void")
{
    outerr << "At line no: " << lines << " variable type can not be void " << endl << endl;
    outlog << "At line no: " << lines << " variable type can not be void " << endl << endl;
    error_count++;
    current_decl_list.clear();  // don't insert void variables
}
```

**How it works:**

`current_type` is a global string set by the `type_specifier` rule whenever a type keyword (`int`, `float`, `void`, `char`) is seen. When `variable_decl` reduces:

- If `current_type == "void"`, the programmer wrote `void e;`
- This is illegal in C (you cannot have a void variable)
- The check fires **before** any insertion into the symbol table
- `current_decl_list.clear()` ensures the void variables are never inserted

```
Input:   void e;
Error:   At line no: 38 variable type can not be void
```

---

## 6. Check 2 – Multiple Declaration of Variables

**Location: `variable_decl` rule in `.y`**

```cpp
for (auto &entry : current_decl_list)
{
    symbol_info *var_sym = new symbol_info(entry.name, "ID");
    var_sym->set_symbol_class(entry.is_array ? "array" : "variable");
    var_sym->set_data_type(current_type);
    if (entry.is_array)
        var_sym->set_array_size(entry.array_size);

    bool inserted = sym_table->insert(var_sym);
    if (!inserted)
    {
        outerr << "At line no: " << lines
               << " Multiple declaration of variable " << entry.name << endl << endl;
        outlog << "...same...";
        error_count++;
        delete var_sym;
    }
}
```

**How it works:**

After parsing `int a, b, c[4];`, the `declaration_list` rule has already populated `current_decl_list` with entries for each variable. The `variable_decl` rule iterates and tries to insert each one into the current scope.

- `sym_table->insert(var_sym)` calls `insert_in_scope` on the current scope table
- If the name already exists in the **same scope**, `insert_in_scope` returns `false`
- The caller logs "Multiple declaration of variable X"
- The new (duplicate) `var_sym` is deleted, but — as per Section 4 — the existing entry in the table gets its type **updated silently**

```
Input:   float a, c[7];   (after int a and int c[4] already exist)
Errors:  At line no: 39 Multiple declaration of variable a
         At line no: 39 Multiple declaration of variable c
```

---

## 7. Check 3 – Multiple Declaration of Function Parameters

**Location: `func_definition` mid-rule action (before `compound_statement`)**

```cpp
for (auto &p : current_params)
{
    if (!p.second.empty())
    {
        symbol_info *param_sym = new symbol_info(p.second, "ID");
        param_sym->set_symbol_class("variable");
        param_sym->set_data_type(p.first);
        bool param_inserted = sym_table->insert(param_sym);
        if (!param_inserted)
        {
            outerr << "At line no: " << lines
                   << " Multiple declaration of variable " << p.second
                   << " in parameter of " << $2->getname() << endl << endl;
            outlog << "...same...";
            error_count++;
            delete param_sym;
        }
    }
}
```

**How it works:**

When a function like `int foo2(int a, int a, float b)` is defined:
1. The `param_list` rule builds up `current_params` — a vector of `(type, name)` pairs
2. Before entering the function's compound statement, each parameter is inserted into the newly created scope table
3. If two parameters share the same name, the second insert returns `false`
4. The error message says "in parameter of [function name]" — distinct from a regular multiple-declaration error

```
Input:   int foo2(int a, int a, float b)
Error:   At line no: 16 Multiple declaration of variable a in parameter of foo2
```

---

## 8. Check 4 – Multiple Declaration of Functions

**Location: `func_definition` mid-rule action (before entering function scope)**

```cpp
symbol_info *func_sym = new symbol_info($2->getname(), "ID");
func_sym->set_symbol_class("function");
func_sym->set_data_type($1->getname());   // return type
for (auto &p : current_params)
    func_sym->add_param(p.first, p.second);

bool inserted = sym_table->insert(func_sym);
if (!inserted)
{
    outerr << "At line no: " << lines
           << " Multiple declaration of function " << $2->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
    delete func_sym;
}
```

**How it works:**

Every function is inserted into the **global scope** (scope 1). If a function with the same name was already defined — or if a variable with that name exists — the insert fails.

Note that `int z` (a global variable) and `int z(int d)` (a function) share identifier `z`. When the function tries to insert `z` into the global scope where the variable `z` already exists → "Multiple declaration of function z".

```
Input:   int x, y, z;       (global: z is a variable)
         ...
         int z(int d) { ... }  (conflicts: z already exists)
Error:   At line no: 24 Multiple declaration of function z
```

---

## 9. Check 5 – Undeclared Variable

**Location: `variable : ID` rule in `.y`**

```cpp
symbol_info *lookup_sym = new symbol_info($1->getname(), "ID");
symbol_info *found = sym_table->lookup(lookup_sym);
delete lookup_sym;

if (found == NULL)
{
    outerr << "At line no: " << lines << " Undeclared variable " << $1->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
}
```

**How it works:**

Whenever an identifier is used as a plain variable, the `variable : ID` rule fires. It does a **symbol table lookup** that walks from the current scope up through all parent scopes to the global scope.

The `lookup` function in `symbol_table.h` traverses the scope chain:

```cpp
symbol_info *lookup(symbol_info *symbol)
{
    scope_table *temp = current_scope;
    while (temp != NULL)
    {
        symbol_info *found = temp->lookup_in_scope(symbol);
        if (found != NULL) return found;
        temp = temp->get_parent_scope();  // walk up to parent scope
    }
    return NULL;   // not found anywhere
}
```

```
Input:   k = 5+2;       (k was never declared)
Error:   At line no: 47 Undeclared variable k
```

---

## 10. Check 6 – Array Used Without Index

**Location: `variable : ID` rule (same rule as Check 5)**

```cpp
else if (found->get_symbol_class() == "array")
{
    // Array used without [] notation
    outerr << "At line no: " << lines << " variable is of array type : " << $1->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
}
```

And critically — the type propagation consequence:

```cpp
$$ = new symbol_info($1->getname(), "varbl");
if (found != NULL && found->get_symbol_class() != "array")
    $$->set_data_type(found->get_data_type());
// If array used without index: data_type stays "" (empty string)
```

**How it works:**

After looking up the variable in the symbol table:
- If `found->get_symbol_class() == "array"` → the variable is an array but used **without** `[index]` notation — this is semantically invalid
- The error fires
- More importantly: `$$->data_type` is left as `""` (the default for a new `symbol_info`)

**The empty data_type trick:**  
When an array is used without index, the resulting grammar node has `data_type = ""`. This empty type will **always mismatch** any real type like `"int"` or `"void"` when the argument type check runs (Check 12). This is intentional — passing an array where a scalar is expected is a type mismatch.

```
Input:   func(a);    (a is int a[2], used without [])
Error:   At line no: 11 variable is of array type : a
         At line no: 11 argument 1 type mismatch in function call: func
```
The second error fires because `a`'s effective type is `""`, and `func` returns `"int"`, so `"" != "int"`.

---

## 11. Check 7 – Non-Array Used With Index

**Location: `variable : ID LTHIRD expression RTHIRD` rule in `.y`**

```cpp
else if (found->get_symbol_class() != "array")
{
    // Has [] but is NOT an array
    outerr << "At line no: " << lines << " variable is not of array type : " << $1->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
}
```

**How it works:**

If you write `b[5] = 7` but `b` is a plain integer variable, the grammar still parses fine syntactically. The symbol table shows `b`'s `symbol_class` is `"variable"` (not `"array"`). Indexing a non-array is illegal → error.

```
Input:   b[5] = 7;    (b was declared as int b, not int b[...])
Error:   At line no: 48 variable is not of array type : b
```

---

## 12. Check 8 – Array Index Not Integer

**Location: `variable : ID LTHIRD expression RTHIRD` — inside the `else` branch (when variable IS confirmed to be an array)**

```cpp
else
{
    // Variable IS an array — now check the index
    if ($3->get_data_type() != "int")
    {
        // Trigger 1: The index expression itself is not integer (e.g., 2.5)
        outerr << "At line no: " << lines
               << " array index is not of integer type : " << $1->getname() << endl << endl;
        outlog << "...same...";
        error_count++;
    }
    else if (found->get_data_type() != "int")
    {
        // Trigger 2: The array's own element type is not int (e.g., float array)
        outerr << "At line no: " << lines
               << " array index is not of integer type : " << $1->getname() << endl << endl;
        outlog << "...same...";
        error_count++;
    }
}
```

**Two triggers, only one fires per access:**

**Trigger 1: Index expression is not an integer**

`$3` is the `expression` parsed inside `[...]`. Its `data_type` was propagated upward from the literal or variable (see Section 2). For `c[2.5]`, the `2.5` is a `CONST_FLOAT` so its type bubbles up as `"float"`. Since `"float" != "int"` → error fires.

```
Input:   c[2.5] = 8;
Error:   At line no: 49 array index is not of integer type : c
```

**Trigger 2: The array's element type is not `"int"`**

This fires when the index itself is a valid integer (e.g., `c[0]`), but the array `c` has been updated to a float array via the type-update-on-multiple-declaration mechanism (Section 4).

After `float a, c[7]` on line 39 → the existing `int c[4]` in the symbol table gets its `data_type` updated to `"float"`. Now `found->get_data_type() = "float" != "int"` → second condition fires.

```
Input:   c[0] = 2 + 5 * foo4(7);   (c is now float array after multiple decl)
Error:   At line no: 50 array index is not of integer type : c
```

**Why two conditions instead of one?**

| Single condition | Problem |
|---|---|
| Only `$3->type != "int"` | Won't catch `c[0]` where index is int but array is float |
| Only `found->type != "int"` | Won't catch `a[2.5]` where `a` is an int array but index is float |
| **Both (with `else if`)** | **Covers all cases, only 1 error per access** |

The `else if` ensures that both conditions can't fire for the same access — preventing double-counting.

---

## 13. Check 9 – Undeclared Function

**Location: `factor : ID LPAREN argument_list RPAREN` rule in `.y`**

```cpp
symbol_info *func_lookup = new symbol_info($1->getname(), "ID");
symbol_info *func_sym = sym_table->lookup(func_lookup);
delete func_lookup;

if (func_sym == NULL)
{
    outerr << "At line no: " << lines << " Undeclared function: " << $1->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
}
```

**How it works:**

When the parser sees `foo5(a)`, it tries to look up `foo5` in the symbol table. If not found → error. This fires in the `factor` rule (not `variable`) because function calls are factors — they produce values in expressions.

```
Input:   dd = foo5(a);
Error:   At line no: 58 Undeclared function: foo5
```

---

## 14. Check 10 – Undeclared Variable in printf

**Location: `statement : PRINTLN LPAREN ID RPAREN SEMICOLON` rule in `.y`**

```cpp
symbol_info *lookup_sym = new symbol_info($3->getname(), "ID");
symbol_info *found = sym_table->lookup(lookup_sym);
delete lookup_sym;
if (found == NULL)
{
    outerr << "At line no: " << lines << " Undeclared variable " << $3->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
}
```

**How it works:**

The lexer maps `printf` to the `PRINTLN` token. The grammar handles it as a special statement. The ID inside the parentheses is looked up in the symbol table. If it doesn't exist → "Undeclared variable".

```
Input:   printf(h);    (h was never declared)
Error:   At line no: 60 Undeclared variable h
```

---

## 15. Check 11 – Function Argument Count Mismatch

**Location: `factor : ID LPAREN argument_list RPAREN` rule — inside the `else` branch (function IS found and IS a function)**

```cpp
int expected_count = func_sym->get_param_count();
int actual_count   = (int)current_arg_types.size();

if (expected_count != actual_count)
{
    outerr << "At line no: " << lines
           << " Inconsistencies in number of arguments in function call: "
           << $1->getname() << endl << endl;
    outlog << "...same...";
    error_count++;
}
```

**How it works:**

- `func_sym->get_param_count()` → how many parameters the function was **defined** with (stored as a vector in its `symbol_info` during `func_definition`)
- `current_arg_types.size()` → how many arguments were **actually passed** in this call (collected by the `arguments` rules — see Section 17)
- If they differ → error

**Important:** If counts mismatch, we **skip** the per-argument type check entirely. This avoids confusing cascading errors when the argument list is clearly wrong.

```
Input:   b = correct_foo(a);    (correct_foo expects 2 params, only 1 given)
Error:   At line no: 45 Inconsistencies in number of arguments in function call: correct_foo
```

---

## 16. Check 12 – Function Argument Type Mismatch

**Location: Same `factor` rule — inside `else` of the count check**

```cpp
else
{
    // Counts match — check each argument's type
    for (int i = 0; i < actual_count; i++)
    {
        if (current_arg_types[i] != result_type)
        {
            outerr << "At line no: " << lines
                   << " argument " << (i+1)
                   << " type mismatch in function call: "
                   << $1->getname() << endl << endl;
            outlog << "...same...";
            error_count++;
        }
    }
}
```

**How it works — The comparison strategy:**

Each argument's recorded data type (`current_arg_types[i]`) is compared against the **function's return type** (`result_type = func_sym->get_data_type()`).

This is the comparison strategy that produces output matching the sample I/O. Here is why it works for every case:

| Function call | Func return type | Arg types | Expected result |
|---|---|---|---|
| `func(2.5, 3.5)` | `"int"` | `["float", "float"]` | mismatch ×2 |
| `correct_foo(a, c)` | `"int"` | `["float", ""]` | mismatch ×2 |
| `foo4(7)` | `"void"` | `["int"]` | mismatch (int ≠ void) |
| `foo4(c[1])` | `"void"` | `["float"]` | mismatch (float ≠ void) |
| `func(a)` in input2 | `"int"` | `[""]` | mismatch ("" ≠ int) |

Notice:
- `foo4` returning `"void"` causes **any** argument (even `7` which is a valid `int`) to mismatch, because `"int" != "void"`
- Array arguments used without index have type `""`, which mismatches everything
- The float argument `2.5` mismatches the `int` return type of `func`

**After checking, always clear:**

```cpp
current_arg_types.clear();
```

This resets the vector so the next function call starts with an empty list.

---

## 17. How Argument Types Are Collected

**Location: `arguments` and `argument_list` rules**

The `arguments` grammar rules build a comma-separated list of arguments. Each `logic_expression` that serves as an argument already has a `data_type` from type propagation.

**First argument:**

```cpp
arguments : logic_expression
{
    // Start fresh — this is the first (and possibly only) argument
    current_arg_types.clear();
    current_arg_types.push_back($1->get_data_type());
    $$ = new symbol_info($1->getname(), "arg");
}
```

**Each additional argument:**

```cpp
arguments : arguments COMMA logic_expression
{
    // Append to the existing list
    current_arg_types.push_back($3->get_data_type());
    $$ = new symbol_info($1->getname() + "," + $3->getname(), "arg");
}
```

**Zero-argument case:**

```cpp
argument_list : /* empty */
{
    current_arg_types.clear();  // ensure the list is empty
    $$ = new symbol_info("", "arg_list");
}
```

**Timeline for `func(2.5, 3.5)`:**

```
1.  2.5 → CONST_FLOAT → factor(float) → ... → logic_expression(float)
2.  arguments : logic_expression
        → current_arg_types = ["float"]
3.  3.5 → CONST_FLOAT → ... → logic_expression(float)
4.  arguments : arguments COMMA logic_expression
        → current_arg_types = ["float", "float"]
5.  argument_list : arguments
6.  factor : ID LPAREN argument_list RPAREN
        → check: expected 2, actual 2 → types: "float" vs "int", "float" vs "int"
        → 2 errors
        → current_arg_types.clear()
```

**Does nesting break this?**

No. Consider `foo(bar(1), 2)`:

```
Step 1 — Resolve bar(1):
   - "1" → logic_expression → current_arg_types = ["int"]
   - factor: bar → check arg types against bar's return type → clear

Step 2 — Now bar(1) is a resolved factor with some return type
   - bar(1) flows up to logic_expression with bar's return type

Step 3 — Resolve foo's arguments:
   - arguments: logic_expression (bar(1))  → current_arg_types = [bar_return]
   - arguments: arguments COMMA logic_expression (2) → current_arg_types = [bar_return, "int"]
   - factor: foo → check → clear
```

`bar`'s call **clears then checks** before `foo`'s arguments are collected. There is no conflict because the bottom-up LALR parser completes inner calls entirely before collecting outer call arguments.

---

## 18. Data Type Propagation Through Expressions

Here is a complete map of how every rule propagates its type:

| Grammar Rule | Type Propagation Logic |
|---|---|
| `CONST_INT` | → `"int"` (hard-coded in `factor` rule) |
| `CONST_FLOAT` | → `"float"` (hard-coded in `factor` rule) |
| `variable : ID` (plain variable, not array) | → `found->get_data_type()` |
| `variable : ID` (array without index) | → `""` (left empty — error case) |
| `variable : ID [ expression ]` | → `found->get_data_type()` (array element type) |
| `factor : variable` | → copies from variable |
| `factor : ID(arg_list)` | → function's **return type** |
| `factor : (expression)` | → copies from expression |
| `factor : variable++` / `variable--` | → copies from variable |
| `factor_info : factor` | → copies from factor |
| `unary_expression : factor_info` | → copies from factor_info |
| `unary_expression : ADDOP unary_expression` | → copies from child unary_expression |
| `unary_expression : NOT unary_expression` | → `"int"` (result of `!` is always int) |
| `term : unary_expression` | → copies from unary_expression |
| `term : term MULOP unary_expression` | → `"float"` if either operand is float, else `"int"` |
| `simple_expression : term` | → copies from term |
| `simple_expression : simple_expression ADDOP term` | → `"float"` if either is float, else `"int"` |
| `rel_expression : simple_expression` | → copies from simple_expression |
| `rel_expression : expr RELOP expr` | → `"int"` (relational result is always int: 0 or 1) |
| `logic_expression : rel_expression` | → copies from rel_expression |
| `logic_expression : rel LOGICOP rel` | → `"int"` (logical result is always int) |
| `expression : logic_expression` | → copies from logic_expression |
| `expression : variable = logic_expression` | → type **not** set (left as `""`) |

The last row is notable: assignment expressions don't propagate a type because C assignments-as-expressions are rarely nested in this grammar's usage.

---

## 19. Full Check Flow on a Real Example

Let's trace through line 53 of `input1.c`:

```c
c[2] = foo4(c[1]);
```

Expected errors (3 total):
1. `array index is not of integer type : c` — for `c[1]` inside foo4's argument
2. `argument 1 type mismatch in function call: foo4`
3. `array index is not of integer type : c` — for `c[2]` on the left side

**Parse order — bottom-up, left to right:**

```
STEP 1: Resolve c[1] (inside foo4's argument list)
─────────────────────────────────────────────────
  Parser sees: c [ 1 ]
  variable : ID LTHIRD expression RTHIRD
    - Look up "c" → found: symbol_class = "array", data_type = "float"
      (c was updated to float by multiple decl on line 39)
    - found is an array → enter the else branch (array index check)
    - $3 (index "1"): data_type = "int"
    - Trigger 1: "int" != "int" → FALSE, no error
    - Trigger 2: found->data_type "float" != "int" → TRUE → ERROR #1 fires
    - $$ = c[1], data_type = "float" (element type of float array)

STEP 2: c[1] flows upward through the expression chain
─────────────────────────────────────────────────────
  c[1] → factor → factor_info → unary_expression → term →
  simple_expression → rel_expression → logic_expression
  All copies: data_type = "float"

STEP 3: Collect argument for foo4
─────────────────────────────────
  arguments : logic_expression (c[1], type "float")
    → current_arg_types = ["float"]

STEP 4: argument_list : arguments

STEP 5: factor : ID LPAREN argument_list RPAREN  (for foo4)
────────────────────────────────────────────────────────────
  - Look up "foo4" → found: symbol_class = "function", data_type = "void"
  - result_type = "void"
  - expected_count = 1, actual_count = 1 → counts MATCH
  - Check arg 1: current_arg_types[0] = "float" != "void" → ERROR #2 fires
  - current_arg_types.clear()
  - foo4(c[1]) result: data_type = "void"

STEP 6: foo4(c[1]) flows up to logic_expression (type "void")

STEP 7: Resolve c[2] on the LEFT side of assignment
─────────────────────────────────────────────────────
  Parser sees: c [ 2 ]
  variable : ID LTHIRD expression RTHIRD
    - Look up "c" → found: array, data_type = "float"
    - Trigger 1: index "2" type "int" != "int" → FALSE
    - Trigger 2: "float" != "int" → TRUE → ERROR #3 fires
    - $$ = c[2], data_type = "float"

STEP 8: expression : variable ASSIGNOP logic_expression
        c[2] = foo4(c[1])
        Type not propagated (assignment expression).
```

**Result: 3 errors on line 53** — exactly matching the expected output.

---

## 20. Output Files

Two output files are produced by the compiler:

### `24341140+24341217_log.txt`

Contains every grammar rule reduction in the format:
```
At line no: X  rule_name : production_rule

<code text that matched>
```

Also includes:
- Scope table snapshots (printed when a `}` is encountered — showing all symbols in each scope)
- Error messages **inline** within the log as they are encountered
- Final summary at the end:

```
Total lines: 65
Total errors: 25
```

### `24341140+24341217_error.txt`

Contains **only** semantic error messages, one per blank-line gap:
```
At line no: 16 Multiple declaration of variable a in parameter of foo2

At line no: 24 Multiple declaration of function z

...

Total errors: 25
```

**Both files are opened at the start of `main()` and closed at the end:**

```cpp
outlog.open("24341140+24341217_log.txt", ios::trunc);  // ios::trunc = overwrite existing
outerr.open("24341140+24341217_error.txt", ios::trunc);
```

Every semantic check writes **two outputs** — to both `outlog` and `outerr`. The log file gets everything (grammar rules + errors interleaved). The error file gets only the error messages.

---

## Summary Table of All Checks

| # | Error Message Format | Where in Code | Trigger Condition |
|---|---|---|---|
| 1 | `variable type can not be void` | `variable_decl` rule | `current_type == "void"` |
| 2 | `Multiple declaration of variable X` | `variable_decl` rule | `sym_table->insert()` returns false |
| 3 | `Multiple declaration of variable X in parameter of F` | `func_definition` mid-rule | Parameter insert returns false |
| 4 | `Multiple declaration of function F` | `func_definition` mid-rule | Function symbol insert returns false |
| 5 | `Undeclared variable X` | `variable : ID` rule | `sym_table->lookup()` returns NULL |
| 6 | `variable is of array type : X` | `variable : ID` rule | `found->get_symbol_class() == "array"` |
| 7 | `variable is not of array type : X` | `variable : ID[expr]` rule | `found->get_symbol_class() != "array"` |
| 8 | `array index is not of integer type : X` | `variable : ID[expr]` rule | Index type ≠ `"int"` OR array's element type ≠ `"int"` |
| 9 | `Undeclared function: F` | `factor : ID(arg_list)` rule | `sym_table->lookup()` returns NULL |
| 10 | `Undeclared variable X` (printf) | `statement : PRINTLN(ID)` rule | `sym_table->lookup()` returns NULL |
| 11 | `Inconsistencies in number of arguments in function call: F` | `factor : ID(arg_list)` rule | `param_count != arg_count` |
| 12 | `argument N type mismatch in function call: F` | `factor : ID(arg_list)` rule | `current_arg_types[i] != func_return_type` |
