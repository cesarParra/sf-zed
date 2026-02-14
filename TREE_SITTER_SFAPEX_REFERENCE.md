# Tree-Sitter-SFApex Grammar Reference

Complete reference for the tree-sitter-sfapex parser grammar.
Source: https://github.com/aheber/tree-sitter-sfapex

**Last Updated:** 2026-02-08

---

## Table of Contents

1. [Overview](#overview)
2. [Grammar Architecture](#grammar-architecture)
3. [Apex Language Rules](#apex-language-rules)
   - [Declarations](#declarations)
   - [Expressions](#expressions)
   - [Statements](#statements)
   - [Types](#types)
   - [Literals](#literals)
   - [Modifiers](#modifiers)
   - [Annotations](#annotations)
4. [SOQL Grammar Rules](#soql-grammar-rules)
5. [SOSL Grammar Rules](#sosl-grammar-rules)
6. [Node Types and Fields](#node-types-and-fields)
7. [Common Patterns](#common-patterns)

---

## Overview

The tree-sitter-sfapex project provides Tree-sitter grammars for Salesforce languages:
- **Apex**: Main language grammar (adapted from Java)
- **SOQL**: Salesforce Object Query Language
- **SOSL**: Salesforce Object Search Language

The grammar uses **case-insensitive** keywords via the `ci()` helper function.

---

## Grammar Architecture

### Precedence Levels (PREC)

```javascript
PREC = {
  COMMENT: 0,           // //  /*  */
  ASSIGN: 1,            // =  += -=  *=  /=  %=  &=  ^=  |=  <<=  >>=  >>>=
  ELEMENT_VAL: 2,
  TERNARY: 3,           // ? :
  NULL_COALESCE: 4,     // ??
  OR: 5,                // ||
  AND: 6,               // &&
  BIT_OR: 7,            // |
  BIT_XOR: 8,           // ^
  BIT_AND: 9,           // &
  EQUALITY: 10,         // ==  != <>
  REL: 11,              // <  <=  >  >=  instanceof
  SHIFT: 12,            // <<  >>  >>>
  ADD: 13,              // +  -
  MULT: 14,             // *  /  %
  CAST: 15,             // (Type)
  OBJ_INST: 15,         // new
  UNARY: 16,            // ++a  --a  a++  a--  +  -  !  ~
  ARRAY: 17,            // [Index]
  OBJ_ACCESS: 17,       // .
  PARENS: 18,           // (Expression)
}
```

### Supertypes

- `expression`
- `declaration`
- `statement`
- `primary_expression`
- `_literal`
- `_type`
- `_simple_type`
- `_unannotated_type`
- `comment`

### Inline Rules

- `_name`
- `_simple_type`
- `_class_body_declaration`
- `_variable_initializer`

---

## Apex Language Rules

### Declarations

#### class_declaration

**Grammar Rule:**
```javascript
class_declaration: ($) =>
  seq(
    optional($.modifiers),
    ci("class"),
    field("name", $.identifier),
    optional(field("type_parameters", $.type_parameters)),
    optional(field("superclass", $.superclass)),
    optional(field("interfaces", $.interfaces)),
    field("body", $.class_body)
  )
```

**Fields:**
- `name` (required): `identifier` - The class name
- `body` (required): `class_body` - The class body containing members
- `type_parameters` (optional): `type_parameters` - Generic type parameters
- `superclass` (optional): `superclass` - The parent class (extends clause)
- `interfaces` (optional): `interfaces` - Implemented interfaces

**Children:**
- `modifiers` (optional): Access modifiers, annotations, etc.

**Example:**
```apex
public class MyClass extends BaseClass implements IInterface {
    // body
}
```

---

#### interface_declaration

**Grammar Rule:**
```javascript
interface_declaration: ($) =>
  seq(
    optional($.modifiers),
    ci("interface"),
    field("name", $.identifier),
    field("type_parameters", optional($.type_parameters)),
    optional($.extends_interfaces),
    field("body", $.interface_body)
  )
```

**Fields:**
- `name` (required): `identifier` - The interface name
- `body` (required): `interface_body` - The interface body
- `type_parameters` (optional): `type_parameters` - Generic type parameters

**Children:**
- `modifiers` (optional): Access modifiers and annotations
- `extends_interfaces` (optional): Extended interfaces

---

#### enum_declaration

**Grammar Rule:**
```javascript
enum_declaration: ($) =>
  seq(
    optional($.modifiers),
    ci("enum"),
    field("name", $.identifier),
    field("interfaces", optional($.interfaces)),
    field("body", $.enum_body)
  )
```

**Fields:**
- `name` (required): `identifier` - The enum name
- `body` (required): `enum_body` - Contains enum constants
- `interfaces` (optional): `interfaces` - Implemented interfaces

**Children:**
- `modifiers` (optional): Access modifiers and annotations

**Example:**
```apex
public enum Status { OPEN, CLOSED, PENDING }
```

**enum_body:**
```javascript
enum_body: ($) => seq("{", commaJoined($.enum_constant), "}")
```

**enum_constant:**
```javascript
enum_constant: ($) =>
  seq(optional($.modifiers), field("name", $.identifier))
```

---

#### method_declaration

**Grammar Rule:**
```javascript
method_declaration: ($) =>
  seq(
    optional($.modifiers),
    $._method_header,
    choice(field("body", $.block), ";")
  )

_method_header: ($) =>
  seq(
    optional(seq(field("type_parameters", $.type_parameters), repeat($.annotation))),
    field("type", $._unannotated_type),
    $._method_declarator
  )

_method_declarator: ($) =>
  seq(
    field("name", $.identifier),
    field("parameters", $.formal_parameters),
    field("dimensions", optional($.dimensions))
  )
```

**Fields:**
- `name` (required): `identifier` - The method name
- `type` (required): `_unannotated_type` - Return type (including void_type)
- `parameters` (required): `formal_parameters` - Parameter list
- `body` (optional): `block` - Method body (absent for abstract methods)
- `type_parameters` (optional): `type_parameters` - Generic type parameters
- `dimensions` (optional): `dimensions` - Array dimensions for return type

**Children:**
- `modifiers` (optional): Access modifiers, static, virtual, etc.
- `annotation` (multiple): Annotations like @testMethod, @AuraEnabled

**Example:**
```apex
public static String getName(Id recordId) {
    return 'test';
}
```

---

#### static_initializer

**Grammar Rule:**
```javascript
static_initializer: ($) => seq(ci("static"), $.block)
```

A static initializer block inside a class body. Executes when the class is loaded. Contains a `block` node with the initializer statements.

**Children:**
- `block` (required): The block of statements to execute

**Example:**
```apex
public class MyClass {
    static {
        // runs when class is loaded
    }
}
```

**Note:** This is listed under `_class_body_declaration`, making it a valid direct child of `class_body` alongside `field_declaration`, `method_declaration`, `constructor_declaration`, etc.

---

#### constructor_declaration

**Grammar Rule:**
```javascript
constructor_declaration: ($) =>
  seq(
    optional($.modifiers),
    $._constructor_declarator,
    field("body", $.constructor_body)
  )

_constructor_declarator: ($) =>
  seq(
    field("type_parameters", optional($.type_parameters)),
    field("name", $.identifier),
    field("parameters", $.formal_parameters)
  )
```

**Fields:**
- `name` (required): `identifier` - Constructor name (same as class name)
- `parameters` (required): `formal_parameters` - Parameter list
- `body` (required): `constructor_body` - Constructor body
- `type_parameters` (optional): `type_parameters` - Generic type parameters

**Children:**
- `modifiers` (optional): Access modifiers

**Example:**
```apex
public MyClass(String param) {
    this.field = param;
}
```

---

#### field_declaration

**Grammar Rule:**
```javascript
field_declaration: ($) =>
  seq(
    optional($.modifiers),
    field("type", $._unannotated_type),
    $._variable_declarator_list,
    choice($.accessor_list, ";")
  )
```

**Fields:**
- `type` (required): `_unannotated_type` - The field type
- `declarator` (required, multiple): `variable_declarator` - Variable declarators

**Children:**
- `modifiers` (optional): Access modifiers, static, transient, etc.
- `accessor_list` (optional): Property accessor list (get/set)

**Example:**
```apex
private static final String CONSTANT = 'value';
public String myProperty { get; set; }
```

---

#### local_variable_declaration

**Grammar Rule:**
```javascript
local_variable_declaration: ($) =>
  seq(
    optional($.modifiers),
    field("type", $._unannotated_type),
    $._variable_declarator_list,
    ";"
  )
```

**Fields:**
- `type` (required): `_unannotated_type` - The variable type
- `declarator` (required, multiple): `variable_declarator` - Variable declarators

**Children:**
- `modifiers` (optional): Final modifier

**Example:**
```apex
String name = 'test';
Integer count;
```

---

#### variable_declarator

**Grammar Rule:**
```javascript
variable_declarator: ($) =>
  seq(
    $._variable_declarator_id,
    optional(seq(
      alias("=", $.assignment_operator),
      field("value", $._variable_initializer)
    ))
  )

_variable_declarator_id: ($) =>
  seq(
    field("name", $.identifier),
    field("dimensions", optional($.dimensions))
  )
```

**Fields:**
- `name` (required): `identifier` - Variable name
- `value` (optional): `expression` or `array_initializer` - Initial value
- `dimensions` (optional): `dimensions` - Array dimensions

**Children:**
- `assignment_operator` (optional): The `=` operator

---

#### trigger_declaration

**Grammar Rule:**
```javascript
trigger_declaration: ($) =>
  seq(
    ci("trigger"),
    field("name", $.identifier),
    ci("on"),
    field("object", $.identifier),
    "(",
    field("events", commaJoined1($.trigger_event)),
    ")",
    field("body", $.trigger_body)
  )
```

**Fields:**
- `name` (required): `identifier` - Trigger name
- `object` (required): `identifier` - SObject type
- `events` (required, multiple): `trigger_event` - Trigger events
- `body` (required): `trigger_body` (which is a `block`)

**Trigger Events:**
- `before_insert`: "before insert"
- `before_update`: "before update"
- `before_delete`: "before delete"
- `after_insert`: "after insert"
- `after_update`: "after update"
- `after_delete`: "after delete"
- `after_undelete`: "after undelete"

**Example:**
```apex
trigger AccountTrigger on Account (before insert, after update) {
    // trigger logic
}
```

---

#### accessor_declaration

**Grammar Rule:**
```javascript
accessor_declaration: ($) =>
  seq(
    optional($.modifiers),
    field("accessor", choice(ci("get"), ci("set"))),
    choice(field("body", $.block), ";")
  )
```

**Fields:**
- `accessor` (required): `get` or `set` - The accessor type
- `body` (optional): `block` - Accessor body (absent for automatic properties)

**Children:**
- `modifiers` (optional): Access modifiers

**Example:**
```apex
public String Name {
    get { return this.name; }
    set { this.name = value; }
}

// Automatic property
public String Email { get; set; }
```

---

### Expressions

#### expression (root)

**Grammar Rule:**
```javascript
expression: ($) =>
  choice(
    $.assignment_expression,
    $.binary_expression,
    $.instanceof_expression,
    $.ternary_expression,
    $.update_expression,
    $.primary_expression,
    $.unary_expression,
    $.cast_expression,
    $.dml_expression
  )
```

---

#### assignment_expression

**Grammar Rule:**
```javascript
assignment_expression: ($) =>
  prec.right(PREC.ASSIGN,
    seq(
      field("left", choice($.identifier, $.field_access, $.array_access)),
      field("operator", alias(
        choice("=", "+=", "-=", "*=", "/=", "&=", "|=", "^=", "%=",
               "<<=", ">>=", ">>>="),
        $.assignment_operator
      )),
      field("right", $.expression)
    )
  )
```

**Fields:**
- `left` (required): `identifier`, `field_access`, or `array_access` - Target
- `operator` (required): `assignment_operator` - Assignment operator
- `right` (required): `expression` - Value to assign

**Example:**
```apex
x = 5;
obj.field += 10;
arr[0] *= 2;
```

---

#### binary_expression

**Grammar Rule:**
```javascript
binary_expression: ($) =>
  choice(
    // Various operators with different precedence
    prec.left(PREC.MULT, seq(field("left", $.expression),
                              field("operator", "*"),
                              field("right", $.expression))),
    // ... (similar for all binary operators)
  )
```

**Fields:**
- `left` (required): `expression` - Left operand
- `operator` (required): One of: `>`, `<`, `>=`, `<=`, `==`, `===`, `!=`, `<>`, `!==`, `&&`, `||`, `??`, `+`, `-`, `*`, `/`, `&`, `|`, `^`, `%`, `<<`, `>>`, `>>>`
- `right` (required): `expression` - Right operand

**Special Operators:**
- `??` - Null coalescing operator (PREC.NULL_COALESCE = 4)
- `===` / `!==` - Triple equals (PREC.EQUALITY = 10)
- `<>` - Not equals (alternate syntax)

**Example:**
```apex
x + y
a && b
name ?? 'default'
```

---

#### ternary_expression

**Grammar Rule:**
```javascript
ternary_expression: ($) =>
  prec.right(PREC.TERNARY,
    seq(
      field("condition", $.expression),
      "?",
      field("consequence", $.expression),
      ":",
      field("alternative", $.expression)
    )
  )
```

**Fields:**
- `condition` (required): `expression` - Condition to test
- `consequence` (required): `expression` - Value if true
- `alternative` (required): `expression` - Value if false

**Example:**
```apex
String result = x > 0 ? 'positive' : 'negative';
```

---

#### unary_expression

**Grammar Rule:**
```javascript
unary_expression: ($) =>
  prec.left(PREC.UNARY,
    seq(
      field("operator", choice("+", "-", "!", "~")),
      field("operand", $.expression)
    )
  )
```

**Fields:**
- `operator` (required): `+`, `-`, `!`, or `~` - Unary operator
- `operand` (required): `expression` - The operand

**Example:**
```apex
!condition
-value
~flags
```

---

#### update_expression

**Grammar Rule:**
```javascript
update_expression: ($) =>
  prec.left(PREC.UNARY,
    choice(
      seq(field("operand", $.expression), field("operator", $.update_operator)),
      seq(field("operator", $.update_operator), field("operand", $.expression))
    )
  )

update_operator: ($) => choice("++", "--")
```

**Fields:**
- `operator` (required): `update_operator` (`++` or `--`)
- `operand` (required): `expression` - The operand

**Example:**
```apex
i++;
++i;
count--;
```

---

#### cast_expression

**Grammar Rule:**
```javascript
cast_expression: ($) =>
  prec(PREC.CAST,
    seq("(", field("type", $._type), ")", field("value", $.expression))
  )
```

**Fields:**
- `type` (required): `_type` - Target type
- `value` (required): `expression` - Value to cast

**Example:**
```apex
(String)obj
(Integer)value
```

---

#### instanceof_expression

**Grammar Rule:**
```javascript
instanceof_expression: ($) =>
  prec(PREC.REL,
    seq(
      field("left", $.expression),
      ci("instanceof"),
      field("right", $._type)
    )
  )
```

**Fields:**
- `left` (required): `expression` - Expression to check
- `right` (required): `_type` - Type to check against

**Example:**
```apex
obj instanceof Account
value instanceof String
```

---

#### dml_expression

**Grammar Rule:**
```javascript
dml_expression: ($) =>
  prec.right(
    choice(
      // Standard DML
      seq(
        $.dml_type,
        optional(field("security_mode", seq(ci("as"), $.dml_security_mode))),
        field("target", $.expression)
      ),
      // Upsert with optional key
      seq(
        alias($.upsert_dml_type, $.dml_type),
        optional(field("security_mode", seq(ci("as"), $.dml_security_mode))),
        field("target", $.expression),
        optional(field("upsert_key", $._unannotated_type))
      ),
      // Merge with merge_with field
      seq(
        alias($.merge_dml_type, $.dml_type),
        optional(field("security_mode", seq(ci("as"), $.dml_security_mode))),
        field("target", $.expression),
        " ",
        field("merge_with", $.expression)
      )
    )
  )

dml_type: ($) => choice($.insert, $.update, $.delete, $.undelete)
merge_dml_type: ($) => $.merge
upsert_dml_type: ($) => $.upsert

insert: ($) => ci("insert")
update: ($) => ci("update")
delete: ($) => ci("delete")
merge: ($) => ci("merge")
undelete: ($) => ci("undelete")
upsert: ($) => ci("upsert")

dml_security_mode: ($) => choice($.user, $.system)
user: ($) => ci("user")
system: ($) => ci("system")
```

**Fields:**
- `target` (required): `expression` - Object(s) to operate on
- `security_mode` (optional, multiple): `as` keyword + `dml_security_mode` - Security mode
- `upsert_key` (optional): `_unannotated_type` - External ID field for upsert
- `merge_with` (optional): `expression` - Record to merge with (for merge)

**Children:**
- `dml_type` (required): One of `insert`, `update`, `delete`, `undelete`, `merge`, `upsert`

**DML Types:**
- `insert` - Insert records
- `update` - Update records
- `delete` - Delete records
- `undelete` - Restore records from recycle bin
- `upsert` - Insert or update based on external ID
- `merge` - Merge two records

**Security Modes:**
- `user` - Run as current user (with sharing)
- `system` - Run with system privileges

**Example:**
```apex
insert as user newAccount;
update accounts;
upsert contacts Email__c;
merge masterAccount duplicateAccount;
delete as system records;
```

---

#### query_expression

**Grammar Rule:**
```javascript
query_expression: ($) =>
  seq("[", choice($.soql_query_body, $.sosl_query_body), "]")
```

**Children:**
- `soql_query_body` or `sosl_query_body` (required): The query

**Example:**
```apex
List<Account> accounts = [SELECT Id, Name FROM Account];
List<List<SObject>> results = [FIND 'test' IN ALL FIELDS];
```

---

#### method_invocation

**Grammar Rule:**
```javascript
method_invocation: ($) =>
  seq(
    choice(
      field("name", $.identifier),
      seq(
        field("object", choice($.primary_expression, $.super)),
        $._property_navigation,
        field("type_arguments", optional($.type_arguments)),
        field("name", $.identifier)
      )
    ),
    field("arguments", $.argument_list)
  )

argument_list: ($) => seq("(", commaJoined($.expression), ")")
```

**Fields:**
- `name` (required): `identifier` - Method name
- `object` (optional): `primary_expression` or `super` - Object to call method on
- `type_arguments` (optional): `type_arguments` - Generic type arguments
- `arguments` (required): `argument_list` - Method arguments

**Children:**
- `safe_navigation_operator` (optional): `?.` instead of `.`

**Example:**
```apex
doSomething();
obj.method(arg1, arg2);
obj?.safeMethod();
super.method();
```

---

#### field_access

**Grammar Rule:**
```javascript
field_access: ($) =>
  seq(
    field("object", choice($.primary_expression, $.super)),
    $._property_navigation,
    field("field", choice($.identifier, $.this))
  )

_property_navigation: ($) => choice($.safe_navigation_operator, ".")
safe_navigation_operator: ($) => "?."
```

**Fields:**
- `object` (required): `primary_expression` or `super` - Object to access field from
- `field` (required): `identifier` or `this` - Field name

**Children:**
- `safe_navigation_operator` (optional): `?.` for null-safe access

**Example:**
```apex
obj.field
obj?.field  // Safe navigation
super.field
obj.this
```

---

#### java_field_access

**Grammar Rule:**
```javascript
java_field_access: ($) =>
  seq(token(seq(ci("java"), /[\s\n]*/, ":")), $.field_access)
```

**Used to access Java classes in Apex (rare).**

**Example:**
```apex
java:System.out.println();
```

---

#### array_access

**Grammar Rule:**
```javascript
array_access: ($) =>
  seq(
    field("array", $.primary_expression),
    "[",
    field("index", $.expression),
    "]"
  )
```

**Fields:**
- `array` (required): `primary_expression` - Array or list
- `index` (required): `expression` - Index expression

**Example:**
```apex
arr[0]
list[i + 1]
```

---

#### object_creation_expression

**Grammar Rule:**
```javascript
object_creation_expression: ($) =>
  prec.right(
    seq(
      ci("new"),
      field("type_arguments", optional($.type_arguments)),
      field("type", $._simple_type),
      field("arguments", $.argument_list),
      optional($.class_body)
    )
  )
```

**Fields:**
- `type` (required): `_simple_type` - Type to instantiate
- `arguments` (required): `argument_list` - Constructor arguments
- `type_arguments` (optional): `type_arguments` - Generic type arguments

**Children:**
- `class_body` (optional): Anonymous class body

**Example:**
```apex
new Account()
new Account(Name = 'Test')
new List<String>()
new MyClass() { /* anonymous class body */ }
```

---

#### array_creation_expression

**Grammar Rule:**
```javascript
array_creation_expression: ($) =>
  prec.right(
    seq(
      ci("new"),
      field("type", $._simple_type),
      choice(
        seq(
          field("dimensions", repeat1($.dimensions_expr)),
          field("dimensions", optional($.dimensions))
        ),
        seq(
          field("dimensions", $.dimensions),
          field("value", $.array_initializer)
        ),
        seq(field("value", $.array_initializer))
      )
    )
  )

dimensions_expr: ($) => seq("[", $.expression, "]")
dimensions: ($) => prec.right(repeat1(seq("[", "]")))
```

**Fields:**
- `type` (required): `_simple_type` - Element type
- `dimensions` (optional, multiple): `dimensions` or `dimensions_expr` - Array dimensions
- `value` (optional): `array_initializer` - Initial values

**Example:**
```apex
new String[10]
new Integer[5][3]
new String[] { 'a', 'b', 'c' }
```

---

#### map_creation_expression

**Grammar Rule:**
```javascript
map_creation_expression: ($) =>
  prec.right(
    seq(
      ci("new"),
      field("type", $._simple_type),
      seq(field("value", $.map_initializer))
    )
  )

map_initializer: ($) => seq("{", commaJoined($.map_key_initializer), "}")
map_key_initializer: ($) => seq($.expression, "=>", $.expression)
```

**Fields:**
- `type` (required): `_simple_type` - Map type
- `value` (required): `map_initializer` - Initial key-value pairs

**Example:**
```apex
new Map<String, Integer> { 'a' => 1, 'b' => 2 }
```

---

#### version_expression

**Grammar Rule:**
```javascript
version_expression: ($) =>
  seq(
    ci("Package"),
    ".",
    ci("Version"),
    ".",
    choice(ci("Request"), field("version_num", $.version_number))
  )

version_number: ($) => seq(/\d+/, ".", /\d+/)
```

**Fields:**
- `version_num` (optional): `version_number` - Version number

**Example:**
```apex
Package.Version.Request
Package.Version.1.0
```

---

#### switch_expression

**Grammar Rule:**
```javascript
switch_expression: ($) =>
  seq(
    ci("switch"),
    ci("on"),
    field("condition", $.expression),
    field("body", $.switch_block)
  )

switch_block: ($) => seq("{", repeat1($.switch_rule), "}")

switch_rule: ($) => seq($.switch_label, $.block)

switch_label: ($) =>
  seq(
    ci("when"),
    choice(
      $.when_sobject_type,
      commaJoined1($.expression),
      ci("else")
    )
  )

when_sobject_type: ($) => seq($._unannotated_type, $.identifier)
```

**Fields:**
- `condition` (required): `expression` - Value to switch on
- `body` (required): `switch_block` - Switch cases

**Example:**
```apex
switch on value {
    when 1, 2, 3 {
        System.debug('Small');
    }
    when Account a {
        System.debug('Account: ' + a.Name);
    }
    when else {
        System.debug('Default');
    }
}
```

---

#### primary_expression

**Grammar Rule:**
```javascript
primary_expression: ($) =>
  choice(
    $._literal,
    $.class_literal,
    $.this,
    $.identifier,
    $.parenthesized_expression,
    $.object_creation_expression,
    $.field_access,
    $.java_field_access,
    $.array_access,
    $.method_invocation,
    $.array_creation_expression,
    $.map_creation_expression,
    $.query_expression,
    $.version_expression
  )
```

---

### Statements

#### block

**Grammar Rule:**
```javascript
block: ($) => seq("{", repeat($.statement), "}")
```

**Children:**
- `statement` (multiple, optional): Statements in the block

---

#### if_statement

**Grammar Rule:**
```javascript
if_statement: ($) =>
  prec.right(
    seq(
      ci("if"),
      field("condition", $.parenthesized_expression),
      field("consequence", $.statement),
      optional(seq(ci("else"), field("alternative", $.statement)))
    )
  )
```

**Fields:**
- `condition` (required): `parenthesized_expression` - Condition to test
- `consequence` (required): `statement` - Statement if true
- `alternative` (optional): `statement` - Statement if false (else clause)

**Example:**
```apex
if (x > 0) {
    System.debug('Positive');
} else {
    System.debug('Non-positive');
}
```

---

#### for_statement

**Grammar Rule:**
```javascript
for_statement: ($) =>
  seq(
    ci("for"),
    "(",
    choice(
      field("init", $.local_variable_declaration),
      seq(commaJoined(field("init", $.expression)), ";")
    ),
    field("condition", optional($.expression)),
    ";",
    commaJoined(field("update", $.expression)),
    ")",
    field("body", $.statement)
  )
```

**Fields:**
- `init` (optional, multiple): `expression` or `local_variable_declaration` - Initialization
- `condition` (optional): `expression` - Loop condition
- `update` (optional, multiple): `expression` - Update expressions
- `body` (required): `statement` - Loop body

**Example:**
```apex
for (Integer i = 0; i < 10; i++) {
    System.debug(i);
}
```

---

#### enhanced_for_statement

**Grammar Rule:**
```javascript
enhanced_for_statement: ($) =>
  seq(
    ci("for"),
    "(",
    optional($.modifiers),
    field("type", $._unannotated_type),
    $._variable_declarator_id,
    ":",
    field("value", $.expression),
    ")",
    field("body", $.statement)
  )
```

**Fields:**
- `type` (required): `_unannotated_type` - Element type
- `name` (required): `identifier` - Loop variable name
- `dimensions` (optional): `dimensions` - Array dimensions
- `value` (required): `expression` - Iterable to loop over
- `body` (required): `statement` - Loop body

**Children:**
- `modifiers` (optional): Modifiers for loop variable

**Example:**
```apex
for (Account acc : accounts) {
    System.debug(acc.Name);
}
```

---

#### while_statement

**Grammar Rule:**
```javascript
while_statement: ($) =>
  seq(
    ci("while"),
    field("condition", $.parenthesized_expression),
    field("body", $.statement)
  )
```

**Fields:**
- `condition` (required): `parenthesized_expression` - Loop condition
- `body` (required): `statement` - Loop body

**Example:**
```apex
while (i < 10) {
    i++;
}
```

---

#### do_statement

**Grammar Rule:**
```javascript
do_statement: ($) =>
  seq(
    ci("do"),
    field("body", $.block),
    ci("while"),
    field("condition", $.parenthesized_expression),
    ";"
  )
```

**Fields:**
- `body` (required): `block` - Loop body (must be a block)
- `condition` (required): `parenthesized_expression` - Loop condition

**Example:**
```apex
do {
    i++;
} while (i < 10);
```

---

#### try_statement

**Grammar Rule:**
```javascript
try_statement: ($) =>
  seq(
    ci("try"),
    field("body", $.block),
    choice(
      repeat1($.catch_clause),
      seq(repeat($.catch_clause), $.finally_clause)
    )
  )

catch_clause: ($) =>
  seq(ci("catch"), "(", $.formal_parameter, ")", field("body", $.block))

finally_clause: ($) => seq(ci("finally"), $.block)
```

**Fields:**
- `body` (required): `block` - Try block

**Children:**
- `catch_clause` (multiple, optional/required): Catch blocks
- `finally_clause` (optional): Finally block

**catch_clause Fields:**
- `body` (required): `block` - Catch body

**catch_clause Children:**
- `formal_parameter` (required): Exception parameter

**Example:**
```apex
try {
    doSomething();
} catch (DmlException e) {
    System.debug(e);
} finally {
    cleanup();
}
```

---

#### return_statement

**Grammar Rule:**
```javascript
return_statement: ($) => seq(ci("return"), optional($.expression), ";")
```

**Children:**
- `expression` (optional): Return value

**Example:**
```apex
return;
return value;
return calculate();
```

---

#### throw_statement

**Grammar Rule:**
```javascript
throw_statement: ($) => seq(ci("throw"), $.expression, ";")
```

**Children:**
- `expression` (required): Exception to throw

**Example:**
```apex
throw new MyException('Error message');
```

---

#### break_statement

**Grammar Rule:**
```javascript
break_statement: ($) => seq(ci("break"), optional($.identifier), ";")
```

**Example:**
```apex
break;
```

---

#### continue_statement

**Grammar Rule:**
```javascript
continue_statement: ($) => seq(ci("continue"), optional($.identifier), ";")
```

**Example:**
```apex
continue;
```

---

#### expression_statement

**Grammar Rule:**
```javascript
expression_statement: ($) => seq($.expression, ";")
```

**Children:**
- `expression` (required): The expression

**Example:**
```apex
x = 5;
method();
i++;
```

---

#### run_as_statement

**Grammar Rule:**
```javascript
run_as_statement: ($) =>
  seq(
    ci("System.runAs"),
    field("user", $.parenthesized_expression),
    $.block
  )
```

**Fields:**
- `user` (required): `parenthesized_expression` - User to run as

**Example:**
```apex
System.runAs(testUser) {
    // code runs as testUser
}
```

---

### Types

#### _type (root type rule)

**Grammar Rule:**
```javascript
_type: ($) => choice($._unannotated_type, $.annotated_type)
```

---

#### _unannotated_type

**Grammar Rule:**
```javascript
_unannotated_type: ($) => choice($._simple_type, $.array_type)
```

---

#### _simple_type

**Grammar Rule:**
```javascript
_simple_type: ($) =>
  choice(
    $.void_type,
    $.boolean_type,
    alias($.identifier, $.type_identifier),
    $.scoped_type_identifier,
    $.java_type,
    $.generic_type
  )
```

---

#### void_type

**Grammar Rule:**
```javascript
void_type: ($) => ci("void")
```

**Example:**
```apex
void method() { }
```

---

#### boolean_type

**Grammar Rule:**
```javascript
boolean_type: ($) => "boolean"
```

**Example:**
```apex
boolean flag = true;
```

---

#### type_identifier

**A simple identifier used as a type.**

**Example:**
```apex
String name;
Account acc;
```

---

#### scoped_type_identifier

**Grammar Rule:**
```javascript
scoped_type_identifier: ($) =>
  seq(
    choice(
      alias($.identifier, $.type_identifier),
      $.scoped_type_identifier,
      $.generic_type
    ),
    ".",
    repeat($.annotation),
    alias($.identifier, $.type_identifier)
  )
```

**Used for namespaced types.**

**Example:**
```apex
System.Type
MyNamespace.MyClass
```

---

#### generic_type

**Grammar Rule:**
```javascript
generic_type: ($) =>
  seq(
    choice(
      alias($.identifier, $.type_identifier),
      $.scoped_type_identifier
    ),
    $.type_arguments
  )

type_arguments: ($) => seq("<", commaJoined($._type), ">")
```

**Children:**
- `type_identifier` or `scoped_type_identifier` (required): Base type
- `type_arguments` (required): Generic type arguments

**Example:**
```apex
List<String>
Map<String, Account>
Set<Id>
```

---

#### array_type

**Grammar Rule:**
```javascript
array_type: ($) =>
  seq(
    field("element", $._unannotated_type),
    field("dimensions", $.dimensions)
  )

dimensions: ($) => prec.right(repeat1(seq("[", "]")))
```

**Fields:**
- `element` (required): `_unannotated_type` - Element type
- `dimensions` (required): `dimensions` - Array dimensions

**Example:**
```apex
String[]
Integer[][]
Account[]
```

---

#### java_type

**Grammar Rule:**
```javascript
java_type: ($) =>
  seq(token(seq(ci("java"), /[\s\n]*/, ":")), $.scoped_type_identifier)
```

**Example:**
```apex
java:java.util.List
```

---

#### annotated_type

**Grammar Rule:**
```javascript
annotated_type: ($) => seq(repeat1($.annotation), $._unannotated_type)
```

**Example:**
```apex
@Nullable String name;
```

---

#### type_parameters

**Grammar Rule:**
```javascript
type_parameters: ($) => seq("<", commaJoined1($.type_parameter), ">")

type_parameter: ($) =>
  seq(
    repeat($.annotation),
    alias($.identifier, $.type_identifier),
    optional($.type_bound)
  )

type_bound: ($) => seq(ci("extends"), $._type, repeat(seq("&", $._type)))
```

**Example:**
```apex
public class MyClass<T extends SObject> { }
```

---

### Literals

#### _literal (root literal rule)

**Grammar Rule:**
```javascript
_literal: ($) =>
  choice(
    $.int,
    $.decimal_floating_point_literal,
    $.boolean,
    $.string_literal,
    $.null_literal
  )
```

---

#### int

**Grammar Rule:**
```javascript
int: ($) => token(seq(DIGITS, optional(choice("l", "L"))))

// where DIGITS = token(joined(/_+/, /[0-9]+/))
```

**Example:**
```apex
42
1000000
42L
1_000_000
```

---

#### decimal_floating_point_literal

**Grammar Rule:**
```javascript
decimal_floating_point_literal: ($) =>
  token(
    choice(
      seq(DIGITS, ".", optional(DIGITS), optional(seq(/[eE]/, optional(choice("-", "+")), DIGITS)), optional(/[fFdD]/)),
      seq(".", DIGITS, optional(seq(/[eE]/, optional(choice("-", "+")), DIGITS)), optional(/[fFdD]/)),
      seq(DIGITS, /[eEpP]/, optional(choice("-", "+")), DIGITS, optional(/[fFdD]/)),
      seq(DIGITS, optional(seq(/[eE]/, optional(choice("-", "+")), DIGITS)), /[fFdD]/)
    )
  )
```

**Example:**
```apex
3.14
2.5e10
.5
1.0f
```

---

#### boolean

**Grammar Rule:**
```javascript
boolean: ($) => choice(ci("TRUE"), ci("FALSE"))
```

**Example:**
```apex
true
false
```

---

#### string_literal

**Grammar Rule:**
```javascript
string_literal: ($) => /'(\\[nNrRtTbBfFuU"'_%\\]|[^\\'])*'/
```

**Supports escape sequences:**
- `\n` - Newline
- `\r` - Carriage return
- `\t` - Tab
- `\b` - Backspace
- `\f` - Form feed
- `\uXXXX` - Unicode character
- `\"`, `\'` - Quotes
- `\\` - Backslash
- `\%`, `\_` - SQL wildcards

**Example:**
```apex
'Hello, World!'
'Line 1\nLine 2'
'O\'Reilly'
```

---

#### null_literal

**Grammar Rule:**
```javascript
null_literal: ($) => ci("NULL")
```

**Example:**
```apex
null
```

---

#### class_literal

**Grammar Rule:**
```javascript
class_literal: ($) => seq($._unannotated_type, ".", ci("class"))
```

**Example:**
```apex
String.class
Account.class
```

---

### Modifiers

#### modifiers

**Grammar Rule:**
```javascript
modifiers: ($) => repeat1(choice($.annotation, $.modifier))
```

**Children:**
- `annotation` (multiple): Annotations
- `modifier` (multiple): Modifier keywords

---

#### modifier

**Grammar Rule:**
```javascript
modifier: ($) =>
  choice(
    $.global,
    $.public,
    $.testMethod,
    $.webservice,
    $.protected,
    $.override,
    $.private,
    $.virtual,
    $.abstract,
    $.static,
    $.final,
    $.transient,
    $.with_sharing,
    $.without_sharing,
    $.inherited_sharing
  )
```

**Modifier Keywords:**
- `global` - Globally accessible (across namespaces)
- `public` - Public access
- `private` - Private access
- `protected` - Protected access
- `static` - Static member
- `final` - Cannot be overridden/reassigned
- `abstract` - Abstract class/method
- `virtual` - Can be overridden
- `override` - Overrides parent method
- `transient` - Not serialized
- `testMethod` - Test method (deprecated, use @isTest)
- `webservice` - Web service method
- `with_sharing` - Enforce sharing rules
- `without_sharing` - Ignore sharing rules
- `inherited_sharing` - Inherit sharing from caller

**Example:**
```apex
public static final String CONSTANT = 'value';
global virtual class MyClass { }
private transient Integer tempValue;
public with sharing class SecureClass { }
```

---

### Annotations

#### annotation

**Grammar Rule:**
```javascript
annotation: ($) =>
  seq(
    "@",
    field("name", $._name),
    optional(field("arguments", $.annotation_argument_list))
  )

annotation_argument_list: ($) =>
  seq(
    "(",
    choice(
      field("value", $._element_value),
      repeat($.annotation_key_value)
    ),
    ")"
  )

annotation_key_value: ($) =>
  seq(
    field("key", $.identifier),
    alias("=", $.assignment_operator),
    field("value", $._element_value)
  )

_element_value: ($) =>
  prec(PREC.ELEMENT_VAL,
    choice($.expression, $.element_value_array_initializer, $.annotation)
  )

element_value_array_initializer: ($) =>
  seq("{", commaJoined($._element_value), optional(","), "}")
```

**Fields:**
- `name` (required): `identifier` or `scoped_identifier` - Annotation name
- `arguments` (optional): `annotation_argument_list` - Annotation arguments

**Common Annotations:**
- `@isTest` - Test class/method
- `@future` - Asynchronous method
- `@AuraEnabled` - Accessible from Lightning components
- `@InvocableMethod` - Callable from flows
- `@InvocableVariable` - Flow input/output variable
- `@TestSetup` - Test setup method
- `@TestVisible` - Visible to test methods
- `@Deprecated` - Deprecated element
- `@ReadOnly` - Read-only method
- `@RemoteAction` - Visualforce remote action
- `@SuppressWarnings` - Suppress warnings

**Example:**
```apex
@isTest
private class MyTest { }

@AuraEnabled(cacheable=true)
public static List<Account> getAccounts() { }

@future(callout=true)
public static void callWebService() { }

@InvocableMethod(label='My Action' description='Does something')
public static void myAction(List<Request> requests) { }
```

---

### Formal Parameters

#### formal_parameters

**Grammar Rule:**
```javascript
formal_parameters: ($) => seq("(", commaJoined($.formal_parameter), ")")
```

**Children:**
- `formal_parameter` (multiple, optional): Parameters

---

#### formal_parameter

**Grammar Rule:**
```javascript
formal_parameter: ($) =>
  seq(
    optional($.modifiers),
    field("type", $._unannotated_type),
    $._variable_declarator_id
  )
```

**Fields:**
- `type` (required): `_unannotated_type` - Parameter type
- `name` (required): `identifier` - Parameter name
- `dimensions` (optional): `dimensions` - Array dimensions

**Children:**
- `modifiers` (optional): Parameter modifiers (e.g., final)

**Example:**
```apex
public void method(String name, Integer count) { }
public void method(final String name, List<String> items) { }
```

---

### Comments

#### comment (supertype)

**Grammar Rule:**
```javascript
comment: ($) => choice($.line_comment, $.block_comment)
```

---

#### line_comment

**Grammar Rule:**
```javascript
line_comment: ($) => token(prec(PREC.COMMENT, seq("//", /[^\n]*/)))
```

**Example:**
```apex
// This is a comment
```

---

#### block_comment

**Grammar Rule:**
```javascript
block_comment: ($) =>
  token(prec(PREC.COMMENT, seq("/*", /[^*]*\*+([^/*][^*]*\*+)*/, "/")))
```

**Example:**
```apex
/* This is a
   block comment */
```

---

### Identifiers

#### identifier

**Grammar Rule:**
```javascript
identifier: ($) => /[\p{L}_$][\p{L}\p{Nd}_$]*/
```

**Matches:**
- Starts with letter, underscore, or dollar sign
- Followed by letters, digits, underscores, or dollar signs
- Supports Unicode letters

**Example:**
```apex
myVariable
_private
$global
userName
名前  // Unicode supported
```

---

#### scoped_identifier

**Grammar Rule:**
```javascript
scoped_identifier: ($) =>
  seq(field("scope", $._name), ".", field("name", $.identifier))

_name: ($) => choice($.identifier, $.scoped_identifier)
```

**Fields:**
- `scope` (required): `identifier` or `scoped_identifier` - Scope
- `name` (required): `identifier` - Name

**Example:**
```apex
System.debug
MyNamespace.MyClass.method
```

---

## SOQL Grammar Rules

SOQL (Salesforce Object Query Language) is embedded in Apex using `[query]` syntax.

### soql_query_body

**Grammar Rule:**
```javascript
soql_query_body: ($) => {
  const s = [
    field("select_clause", $.select_clause),
    field("from_clause", $.from_clause),
    optional(field("using_clause", $.using_clause)),
    optional(field("where_clause", $.where_clause)),
    optional(field("with_clause", alias($.soql_with_clause, $.with_clause))),
    optional(field("group_by_clause", $.group_by_clause)),
    optional(field("order_by_clause", $.order_by_clause)),
    optional(field("limit_clause", $.limit_clause)),
    optional(field("offset_clause", $.offset_clause)),
    optional(field("for_clause", $.for_clause)),
    optional(field("update_clause", $.update_clause)),
  ];
  if (dialect == dialects.APEX) {
    s.push(optional(field("all_rows_clause", $.all_rows_clause)));
  }
  return seq(...s);
}
```

**Fields:**
- `select_clause` (required): Fields to select
- `from_clause` (required): Objects to query
- `using_clause` (optional): Scope/lookup/listview
- `where_clause` (optional): Filter conditions
- `with_clause` (optional): Additional constraints
- `group_by_clause` (optional): Grouping
- `order_by_clause` (optional): Sorting
- `limit_clause` (optional): Result limit
- `offset_clause` (optional): Result offset
- `for_clause` (optional): FOR UPDATE/REFERENCE/VIEW
- `update_clause` (optional): UPDATE TRACKING/VIEWSTAT
- `all_rows_clause` (optional, Apex only): ALL ROWS

---

### select_clause

**Grammar Rule:**
```javascript
select_clause: ($) =>
  seq(ci("SELECT"), choice($.count_expression, commaJoined1($._selectable_expression)))

_selectable_expression: ($) =>
  choice(
    $._value_expression,
    $.alias_expression,
    $.type_of_clause,
    $.fields_expression,
    $.subquery
  )

count_expression: ($) => seq($._function_name, "(", ")")
```

**Children:**
- `count_expression`: `COUNT()`
- `field_identifier`: Field name
- `function_expression`: Aggregate or other function
- `alias_expression`: Field with alias
- `type_of_clause`: TYPEOF polymorphic query
- `fields_expression`: FIELDS(ALL/CUSTOM/STANDARD)
- `subquery`: Nested query

**Example:**
```soql
SELECT Id, Name, COUNT()
SELECT Id, Name FROM Account
SELECT Name, (SELECT LastName FROM Contacts) FROM Account
SELECT FIELDS(ALL) FROM Account
```

---

### from_clause

**Grammar Rule:**
```javascript
from_clause: ($) =>
  seq(ci("FROM"), commaJoined1(choice($.storage_identifier, $.storage_alias)))

storage_identifier: ($) => choice($.identifier, $.dotted_identifier)
storage_alias: ($) =>
  seq($.storage_identifier, optional(ci("AS")), $.identifier)
```

**Children:**
- `storage_identifier`: Object name (e.g., `Account`, `Account.Contacts`)
- `storage_alias`: Object with alias (e.g., `Account a`, `Account AS a`)

**Example:**
```soql
FROM Account
FROM Account a
FROM Account AS a
FROM Contact, Account
```

---

### where_clause

**Grammar Rule:**
```javascript
where_clause: ($) => seq(ci("WHERE"), $._boolean_expression)

_boolean_expression: ($) =>
  choice(
    $.and_expression,
    $.or_expression,
    $.not_expression,
    $._condition_expression
  )

and_expression: ($) =>
  seq($._condition_expression, repeat1(seq(ci("AND"), $._condition_expression)))

or_expression: ($) =>
  seq($._condition_expression, repeat1(seq(ci("OR"), $._condition_expression)))

not_expression: ($) => seq(ci("NOT"), $._condition_expression)

_condition_expression: ($) =>
  choice(
    seq("(", $._boolean_expression, ")"),
    $.comparison_expression
  )
```

**Children:**
- `and_expression`: Multiple conditions with AND
- `or_expression`: Multiple conditions with OR
- `not_expression`: Negated condition
- `comparison_expression`: Single comparison

**Example:**
```soql
WHERE Name = 'Test'
WHERE Name = 'Test' AND Type = 'Customer'
WHERE Name = 'Test' OR Name = 'Demo'
WHERE NOT (Status = 'Closed')
```

---

### comparison_expression

**Grammar Rule:**
```javascript
comparison_expression: ($) => seq($._value_expression, $._comparison)

_comparison: ($) => choice($._value_comparison, $._set_comparison)

_value_comparison: ($) =>
  seq(
    $.value_comparison_operator,
    choice($._soql_literal, $.bound_apex_expression)
  )

_set_comparison: ($) =>
  seq(
    $.set_comparison_operator,
    choice($.subquery, $.comparable_list, $.bound_apex_expression)
  )

value_comparison_operator: ($) =>
  choice("=", "!=", "<>", "<", "<=", ">", ">=", ci("LIKE"))

set_comparison_operator: ($) =>
  choice(ci("IN"), seq(ci("NOT IN")), ci("INCLUDES"), ci("EXCLUDES"))
```

**Value Comparison Operators:**
- `=` - Equals
- `!=`, `<>` - Not equals
- `<`, `<=`, `>`, `>=` - Comparisons
- `LIKE` - Pattern matching

**Set Comparison Operators:**
- `IN` - In set
- `NOT IN` - Not in set
- `INCLUDES` - Includes (for multi-select picklists)
- `EXCLUDES` - Excludes (for multi-select picklists)

**Example:**
```soql
WHERE Name = 'Test'
WHERE Amount > 1000
WHERE Name LIKE 'Test%'
WHERE Id IN ('001...', '002...')
WHERE Status NOT IN ('Closed', 'Cancelled')
WHERE Tags__c INCLUDES ('VIP', 'Priority')
```

---

### bound_apex_expression

**Grammar Rule:**
```javascript
bound_apex_expression: ($) => {
  if (dialect == dialects.APEX) {
    return seq(":", $.expression);
  } else {
    return "**DONOTMATCHEVER**";
  }
}
```

**Used to bind Apex variables in SOQL queries (Apex dialect only).**

**Example:**
```apex
String searchName = 'Test';
List<Account> accounts = [SELECT Id FROM Account WHERE Name = :searchName];
```

---

### group_by_clause

**Grammar Rule:**
```javascript
group_by_clause: ($) =>
  seq(
    ci("GROUP BY"),
    $._group_by_expression,
    optional($.having_clause)
  )

_group_by_expression: ($) =>
  commaJoined1(choice($.field_identifier, $.function_expression))

having_clause: ($) => seq(ci("HAVING"), $._boolean_expression)
```

**Example:**
```soql
GROUP BY Name
GROUP BY Name, Type
GROUP BY Name HAVING COUNT(Id) > 5
```

---

### order_by_clause

**Grammar Rule:**
```javascript
order_by_clause: ($) =>
  seq(ci("ORDER BY"), commaJoined1($.order_expression))

order_expression: ($) =>
  seq(
    $._value_expression,
    optional($.order_direction),
    optional($.order_null_direction)
  )

order_direction: ($) => choice(ci("ASC"), ci("DESC"))
order_null_direction: ($) => choice(ci("NULLS FIRST"), ci("NULLS LAST"))
```

**Example:**
```soql
ORDER BY Name
ORDER BY Name ASC
ORDER BY Name DESC NULLS LAST
ORDER BY Name, CreatedDate DESC
```

---

### limit_clause

**Grammar Rule:**
```javascript
limit_clause: ($) =>
  seq(ci("LIMIT"), choice($.int, $.bound_apex_expression))
```

**Example:**
```soql
LIMIT 10
LIMIT :maxResults
```

---

### offset_clause

**Grammar Rule:**
```javascript
offset_clause: ($) =>
  seq(ci("OFFSET"), choice($.int, $.bound_apex_expression))
```

**Example:**
```soql
OFFSET 20
OFFSET :startIndex
```

---

### for_clause

**Grammar Rule:**
```javascript
for_clause: ($) => seq(ci("FOR"), commaJoined1($.for_type))
for_type: ($) => choice(ci("UPDATE"), ci("REFERENCE"), ci("VIEW"))
```

**For Types:**
- `UPDATE` - Lock records for update
- `REFERENCE` - Reference counting for big objects
- `VIEW` - Update view statistics

**Example:**
```soql
FOR UPDATE
FOR VIEW
FOR UPDATE, REFERENCE
```

---

### update_clause

**Grammar Rule:**
```javascript
update_clause: ($) => seq(ci("UPDATE"), commaJoined1($.update_type))
update_type: ($) => choice(ci("TRACKING"), ci("VIEWSTAT"))
```

**Update Types:**
- `TRACKING` - Update field tracking
- `VIEWSTAT` - Update view statistics

**Example:**
```soql
UPDATE TRACKING
UPDATE VIEWSTAT
```

---

### using_clause

**Grammar Rule:**
```javascript
using_clause: ($) =>
  seq(
    ci("USING"),
    choice($.using_scope_clause, $.using_lookup_clause, $.using_listview_clause)
  )

using_scope_clause: ($) => seq(ci("SCOPE"), $.using_scope_type)
using_scope_type: ($) =>
  choice(
    ci("delegated"),
    ci("everything"),
    ci("mine"),
    ci("mine_and_my_groups"),
    ci("my_territory"),
    ci("my_team_territory"),
    ci("team")
  )

using_lookup_clause: ($) =>
  seq(
    ci("LOOKUP"),
    field("lookup_field", $.dotted_identifier),
    optional($.using_lookup_bind_clause)
  )

using_listview_clause: ($) => seq(ci("ListView"), "=", $.identifier)
```

**Scope Types:**
- `delegated` - Delegated records
- `everything` - All records
- `mine` - My records
- `mine_and_my_groups` - My records and groups
- `my_territory` - My territory
- `my_team_territory` - Team territory
- `team` - Team records

**Example:**
```soql
USING SCOPE mine
USING SCOPE everything
USING LOOKUP Account.Name
USING ListView = 'MyListView'
```

---

### soql_with_clause

**Grammar Rule:**
```javascript
soql_with_clause: ($) =>
  seq(ci("WITH"), alias($.soql_with_type, $.with_type))

soql_with_type: ($) =>
  choice(
    ci("Security_Enforced"),
    ci("User_Mode"),
    ci("System_Mode"),
    $.with_record_visibility_expression,
    $.with_data_cat_expression,
    $.with_user_id_type
  )

with_user_id_type: ($) => seq(ci("UserId"), "=", $.string_literal)

with_record_visibility_expression: ($) =>
  seq(
    ci("RecordVisibilityContext"),
    "(",
    commaJoined1($.with_record_visibility_param),
    ")"
  )

with_record_visibility_param: ($) =>
  choice(
    seq(ci("maxDescriptorPerRecord"), "=", $.int),
    seq(ci("supportsDomains"), "=", $.boolean),
    seq(ci("supportsDelegates"), "=", $.boolean)
  )

with_data_cat_expression: ($) =>
  seq(
    ci("DATA CATEGORY"),
    joined(ci("AND"), $.with_data_cat_filter)
  )

with_data_cat_filter: ($) =>
  seq(
    $.identifier,
    $.with_data_cat_filter_type,
    choice($.identifier, seq("(", commaJoined1($.identifier), ")"))
  )

with_data_cat_filter_type: ($) =>
  choice(ci("AT"), ci("ABOVE"), ci("BELOW"), ci("ABOVE_OR_BELOW"))
```

**With Types:**
- `Security_Enforced` - Enforce field-level security
- `User_Mode` - Run in user mode
- `System_Mode` - Run in system mode
- `UserId = 'xxx'` - Run as specific user
- `RecordVisibilityContext(...)` - Record visibility settings
- `DATA CATEGORY ...` - Filter by data categories

**Example:**
```soql
WITH Security_Enforced
WITH User_Mode
WITH System_Mode
WITH UserId = '005...'
WITH RecordVisibilityContext(maxDescriptorPerRecord=5, supportsDomains=true)
WITH DATA CATEGORY Geography AT USA
```

---

### type_of_clause

**Grammar Rule:**
```javascript
type_of_clause: ($) =>
  seq(
    ci("TYPEOF"),
    choice($.identifier, $.dotted_identifier),
    repeat($.when_expression),
    optional($.else_expression),
    ci("END")
  )

when_expression: ($) =>
  seq(ci("WHEN"), $.identifier, ci("THEN"), $.field_list)

else_expression: ($) => seq(ci("ELSE"), $.field_list)

field_list: ($) =>
  seq(commaJoined1(choice($.identifier, $.dotted_identifier)))
```

**Used for polymorphic queries (e.g., querying What or Who fields).**

**Example:**
```soql
SELECT TYPEOF What
    WHEN Account THEN Name, Phone
    WHEN Opportunity THEN Name, Amount
    ELSE Name
END
FROM Task
```

---

### fields_expression

**Grammar Rule:**
```javascript
fields_expression: ($) => seq(ci("FIELDS"), "(", $.fields_type, ")")
fields_type: ($) => choice(ci("ALL"), ci("CUSTOM"), ci("STANDARD"))
```

**Fields Types:**
- `ALL` - All fields
- `CUSTOM` - Custom fields only
- `STANDARD` - Standard fields only

**Example:**
```soql
SELECT FIELDS(ALL) FROM Account
SELECT FIELDS(CUSTOM) FROM Account
SELECT FIELDS(STANDARD) FROM Account
```

---

### function_expression

**Grammar Rule:**
```javascript
function_expression: ($) =>
  choice(
    seq(
      field("function_name", alias(ci("DISTANCE"), $.identifier)),
      "(",
      choice($.field_identifier, $.bound_apex_expression),
      ",",
      $.geo_location_type,
      ",",
      $.string_literal,
      ")"
    ),
    seq($._function_name, "(", commaJoined1($._value_expression), ")")
  )

_function_name: ($) => field("function_name", $.identifier)
```

**Common SOQL Functions:**
- Aggregate: `COUNT()`, `SUM()`, `AVG()`, `MIN()`, `MAX()`
- Date: `CALENDAR_MONTH()`, `CALENDAR_QUARTER()`, `CALENDAR_YEAR()`, `DAY_IN_MONTH()`, `DAY_IN_WEEK()`, `DAY_IN_YEAR()`, `WEEK_IN_MONTH()`, `WEEK_IN_YEAR()`, `HOUR_IN_DAY()`
- Other: `convertCurrency()`, `FORMAT()`, `toLabel()`, `GROUPING()`
- Location: `DISTANCE()`, `GEOLOCATION()`

**Example:**
```soql
SELECT COUNT(Id) FROM Account
SELECT Name, COUNT(Id) FROM Account GROUP BY Name
SELECT Name, AVG(Amount) FROM Opportunity GROUP BY Name
SELECT Name, DISTANCE(Location__c, GEOLOCATION(37.7749, -122.4194), 'mi') FROM Account
```

---

### subquery

**Grammar Rule:**
```javascript
subquery: ($) => seq("(", $.soql_query_body, ")")
```

**Example:**
```soql
SELECT Name, (SELECT LastName FROM Contacts) FROM Account
SELECT Name, (SELECT Amount FROM Opportunities WHERE IsClosed = false) FROM Account
```

---

### SOQL Literals

#### date_literal

**Grammar Rule:**
```javascript
date_literal: ($) =>
  choice(
    ci("YESTERDAY"),
    ci("TODAY"),
    ci("TOMORROW"),
    ci("LAST_WEEK"),
    ci("THIS_WEEK"),
    ci("NEXT_WEEK"),
    ci("LAST_MONTH"),
    ci("THIS_MONTH"),
    ci("NEXT_MONTH"),
    ci("LAST_90_DAYS"),
    ci("NEXT_90_DAYS"),
    ci("THIS_QUARTER"),
    ci("LAST_QUARTER"),
    ci("NEXT_QUARTER"),
    ci("THIS_YEAR"),
    ci("LAST_YEAR"),
    ci("NEXT_YEAR"),
    ci("THIS_FISCAL_QUARTER"),
    ci("LAST_FISCAL_QUARTER"),
    ci("NEXT_FISCAL_QUARTER"),
    ci("THIS_FISCAL_YEAR"),
    ci("LAST_FISCAL_YEAR"),
    ci("NEXT_FISCAL_YEAR")
  )
```

---

#### date_literal_with_param

**Grammar Rule:**
```javascript
date_literal_with_param: ($) =>
  seq(
    alias(
      token(choice(
        ci("LAST_N_DAYS"),
        ci("NEXT_N_DAYS"),
        ci("N_DAYS_AGO"),
        ci("NEXT_N_WEEKS"),
        ci("LAST_N_WEEKS"),
        ci("N_WEEKS_AGO"),
        ci("NEXT_N_MONTHS"),
        ci("LAST_N_MONTHS"),
        ci("N_MONTHS_AGO"),
        ci("NEXT_N_QUARTERS"),
        ci("LAST_N_QUARTERS"),
        ci("N_QUARTERS_AGO"),
        ci("NEXT_N_YEARS"),
        ci("LAST_N_YEARS"),
        ci("N_YEARS_AGO"),
        ci("NEXT_N_FISCAL_QUARTERS"),
        ci("LAST_N_FISCAL_QUARTERS"),
        ci("N_FISCAL_QUARTERS_AGO"),
        ci("NEXT_N_FISCAL_YEARS"),
        ci("LAST_N_FISCAL_YEARS"),
        ci("N_FISCAL_YEARS_AGO")
      )),
      $.date_literal
    ),
    ":",
    $.int
  )
```

**Example:**
```soql
LAST_N_DAYS:7
NEXT_N_WEEKS:4
N_MONTHS_AGO:3
```

---

#### date

**Grammar Rule:**
```javascript
date: ($) =>
  /[1-4][0-9]{3}-(?:0[1-9]|1[0-2])-(?:[0-2][1-9]|[1-2]0|3[0-1])/
```

**Format:** `YYYY-MM-DD`

**Example:**
```soql
WHERE CreatedDate = 2024-01-15
```

---

#### date_time

**Grammar Rule:**
```javascript
date_time: ($) =>
  /[1-4][0-9]{3}-(?:0[1-9]|1[0-2])-(?:[0-2][1-9]|[1-2]0|3[0-1])T([0-1]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d\d?\d?)?(?:Z|[+-][0-1]\d:[0-5]\d)/
```

**Format:** `YYYY-MM-DDTHH:MM:SS.sss±HH:MM` or `YYYY-MM-DDTHH:MM:SS.sssZ`

**Example:**
```soql
WHERE CreatedDate = 2024-01-15T10:30:00Z
WHERE CreatedDate > 2024-01-15T10:30:00.123-08:00
```

---

#### currency_literal

**Grammar Rule:**
```javascript
currency_literal: ($) => /\w{3}\d+(\.\d+)?/
```

**Format:** Three-letter currency code + amount

**Example:**
```soql
WHERE Amount > USD1000
WHERE Amount = EUR500.50
```

---

### all_rows_clause

**Grammar Rule:**
```javascript
all_rows_clause: ($) => ci("ALL ROWS")
```

**Includes deleted and archived records (Apex dialect only).**

**Example:**
```apex
[SELECT Id FROM Account ALL ROWS]
```

---

## SOSL Grammar Rules

SOSL (Salesforce Object Search Language) is used for full-text search across multiple objects.

### sosl_query_body

**Grammar Rule:**
```javascript
sosl_query_body: ($) =>
  seq(
    $.find_clause,
    optional($.in_clause),
    optional(repeat($.returning_clause)),
    optional(repeat(alias($.sosl_with_clause, $.with_clause))),
    optional($.sosl_using_clause),
    optional($.limit_clause),
    optional($.offset_clause),
    optional($.update_clause)
  )
```

**Children:**
- `find_clause` (required): Search term
- `in_clause` (optional): Search scope
- `returning_clause` (multiple, optional): Objects to return
- `with_clause` (multiple, optional): Additional constraints
- `sosl_using_clause` (optional): Search mode
- `limit_clause` (optional): Result limit
- `offset_clause` (optional): Result offset
- `update_clause` (optional): Update tracking/viewstat

---

### find_clause

**Grammar Rule:**
```javascript
find_clause: ($) =>
  seq(
    ci("FIND"),
    choice(
      $.bound_apex_expression,
      seq($.term_separator_start, $.term, $.term_separator_end)
    )
  )

term_separator_start: ($) => (dialect == dialects.SOSL ? "{" : "'")
term_separator_end: ($) => (dialect == dialects.SOSL ? "}" : "'")
term: ($) => (dialect == dialects.SOSL ? /(\\\}|[^}])+/ : /(\\\'|[^'])+/)
```

**In Apex, search terms are enclosed in `{ }` (converted to string literals internally).**

**Example:**
```apex
[FIND {test*} IN ALL FIELDS]
[FIND {Joe Smith} IN NAME FIELDS]
[FIND :searchTerm IN ALL FIELDS]
```

---

### in_clause

**Grammar Rule:**
```javascript
in_clause: ($) => seq(ci("IN"), $.in_type, ci("FIELDS"))
in_type: ($) =>
  choice(ci("ALL"), ci("EMAIL"), ci("NAME"), ci("PHONE"), ci("SIDEBAR"))
```

**In Types:**
- `ALL` - Search all fields
- `EMAIL` - Search email fields
- `NAME` - Search name fields
- `PHONE` - Search phone fields
- `SIDEBAR` - Search sidebar fields

**Example:**
```sosl
IN ALL FIELDS
IN NAME FIELDS
IN EMAIL FIELDS
```

---

### returning_clause

**Grammar Rule:**
```javascript
returning_clause: ($) =>
  seq(ci("RETURNING"), commaJoined1($.sobject_return))

sobject_return: ($) =>
  seq(
    $.identifier,
    optional(
      seq(
        "(",
        $.selected_fields,
        optional($.using_clause),
        optional($.where_clause),
        optional($.order_by_clause),
        optional($.limit_clause),
        optional($.offset_clause),
        ")"
      )
    )
  )

selected_fields: ($) => commaJoined1($._selectable_expression)
```

**Children:**
- `sobject_return` (multiple): Object specifications

**Example:**
```sosl
RETURNING Account(Name, Phone)
RETURNING Account(Name), Contact(FirstName, LastName)
RETURNING Account(Name WHERE Type = 'Customer' ORDER BY Name LIMIT 10)
```

---

### sosl_using_clause

**Grammar Rule:**
```javascript
sosl_using_clause: ($) =>
  seq(
    ci("USING"),
    choice($.using_phrase_search, $.using_advanced_search)
  )

using_phrase_search: ($) => ci("PHRASE SEARCH")
using_advanced_search: ($) => ci("ADVANCED SEARCH")
```

**Using Types:**
- `PHRASE SEARCH` - Exact phrase search
- `ADVANCED SEARCH` - Advanced search with operators

**Example:**
```sosl
USING PHRASE SEARCH
USING ADVANCED SEARCH
```

---

### sosl_with_clause

**Grammar Rule:**
```javascript
sosl_with_clause: ($) =>
  seq(ci("WITH"), alias($.sosl_with_type, $.with_type))

sosl_with_type: ($) =>
  choice(
    $.with_data_cat_expression,
    $.with_division_expression,
    $.with_highlight,
    $.with_metadata_expression,
    $.with_network_expression,
    $.with_pricebook_expression,
    $.with_snippet_expression,
    $.with_spell_correction_expression
  )

with_division_expression: ($) =>
  seq(ci("DIVISION"), "=", choice($.bound_apex_expression, $.string_literal))

with_highlight: ($) => ci("HIGHLIGHT")

with_metadata_expression: ($) =>
  seq(ci("METADATA"), "=", $.string_literal)

with_network_expression: ($) => seq(ci("NETWORK"), $._comparison)

with_pricebook_expression: ($) =>
  seq(ci("PricebookId"), "=", $.string_literal)

with_snippet_expression: ($) =>
  seq(
    ci("SNIPPET"),
    optional(seq("(", ci("target_length"), "=", $.int, ")"))
  )

with_spell_correction_expression: ($) =>
  seq(ci("SPELL_CORRECTION"), "=", $.boolean)
```

**With Types:**
- `DIVISION = 'xxx'` - Filter by division
- `HIGHLIGHT` - Highlight search terms in results
- `METADATA = 'xxx'` - Filter by metadata
- `NETWORK IN ('xxx')` - Filter by network
- `PricebookId = 'xxx'` - Filter by pricebook
- `SNIPPET(target_length=120)` - Include search snippets
- `SPELL_CORRECTION = true` - Enable spell correction
- `DATA CATEGORY ...` - Filter by data categories

**Example:**
```sosl
WITH HIGHLIGHT
WITH SNIPPET(target_length=120)
WITH SPELL_CORRECTION = true
WITH DIVISION = 'Americas'
WITH NETWORK IN ('0DB...')
```

---

## Node Types and Fields

### Complete Node Type Summary

**Total Node Types:** 713

**Categories:**
- **Declarations:** 12 types
- **Expressions:** 39 types
- **Statements:** 15 types
- **Types:** 27 types
- **Literals:** 7 types
- **SOQL Nodes:** 1 type (+ many clause types)
- **SOSL Nodes:** 4 types (+ many clause types)
- **Keywords & Operators:** 333 types
- **Other:** Various helper nodes

### Key Node Type Patterns

#### Field Access Pattern

When using Tree-sitter C API to access fields:

```c
TSNode node = ...; // some node
TSNode name_node = ts_node_child_by_field_name(node, "name", 4);
TSNode body_node = ts_node_child_by_field_name(node, "body", 4);
```

**Important:** Field names are **exact** and **case-sensitive**.

#### Multiple Field Values

Some fields can have multiple values (marked with `multiple: true`). Use:

```c
uint32_t count = ts_node_child_count(node);
for (uint32_t i = 0; i < count; i++) {
    TSNode child = ts_node_child(node, i);
    const char* field_name = ts_node_field_name_for_child(node, i);
    if (field_name && strcmp(field_name, "declarator") == 0) {
        // Process declarator
    }
}
```

#### Named vs Anonymous Nodes

- **Named nodes** have semantic meaning (e.g., `identifier`, `method_declaration`)
- **Anonymous nodes** are punctuation/keywords (e.g., `{`, `}`, `class`, `public`)

Use `ts_node_is_named()` to distinguish:

```c
bool is_named = ts_node_is_named(node);
```

---

## Common Patterns

### Pattern: Get Class Name

```c
TSNode class_node = ...; // class_declaration node
TSNode name_node = ts_node_child_by_field_name(class_node, "name", 4);
// name_node is an identifier
```

### Pattern: Get Method Return Type

```c
TSNode method_node = ...; // method_declaration node
TSNode type_node = ts_node_child_by_field_name(method_node, "type", 4);
// type_node is a _unannotated_type (could be void_type, type_identifier, generic_type, etc.)
```

### Pattern: Get Method Parameters

```c
TSNode method_node = ...; // method_declaration node
TSNode params_node = ts_node_child_by_field_name(method_node, "parameters", 10);
// params_node is formal_parameters, which contains formal_parameter children
uint32_t param_count = ts_node_named_child_count(params_node);
for (uint32_t i = 0; i < param_count; i++) {
    TSNode param = ts_node_named_child(params_node, i);
    // param is a formal_parameter
    TSNode param_type = ts_node_child_by_field_name(param, "type", 4);
    TSNode param_name = ts_node_child_by_field_name(param, "name", 4);
}
```

### Pattern: Iterate Class Members

```c
TSNode class_node = ...; // class_declaration node
TSNode body_node = ts_node_child_by_field_name(class_node, "body", 4);
// body_node is class_body
uint32_t child_count = ts_node_named_child_count(body_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode member = ts_node_named_child(body_node, i);
    const char* type = ts_node_type(member);
    // type could be "method_declaration", "field_declaration", etc.
}
```

### Pattern: Check for Modifiers

```c
TSNode decl_node = ...; // any declaration node
uint32_t child_count = ts_node_child_count(decl_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(decl_node, i);
    const char* type = ts_node_type(child);
    if (strcmp(type, "modifiers") == 0) {
        // Found modifiers node
        uint32_t modifier_count = ts_node_named_child_count(child);
        for (uint32_t j = 0; j < modifier_count; j++) {
            TSNode modifier = ts_node_named_child(child, j);
            const char* mod_type = ts_node_type(modifier);
            // mod_type could be "modifier" (containing "public", "static", etc.)
            // or "annotation"
        }
    }
}
```

### Pattern: Get Variable Declarators

```c
TSNode var_decl_node = ...; // local_variable_declaration or field_declaration
TSNode type_node = ts_node_child_by_field_name(var_decl_node, "type", 4);

// Iterate declarators (multiple=true)
uint32_t child_count = ts_node_child_count(var_decl_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(var_decl_node, i);
    const char* field_name = ts_node_field_name_for_child(var_decl_node, i);
    if (field_name && strcmp(field_name, "declarator") == 0) {
        // child is a variable_declarator
        TSNode name = ts_node_child_by_field_name(child, "name", 4);
        TSNode value = ts_node_child_by_field_name(child, "value", 5);
    }
}
```

### Pattern: Navigate Field Access Chain

```c
TSNode field_access_node = ...; // field_access node
TSNode object_node = ts_node_child_by_field_name(field_access_node, "object", 6);
TSNode field_node = ts_node_child_by_field_name(field_access_node, "field", 5);

// object_node could be another field_access (chained), an identifier, etc.
// Recursively process if object_node is also a field_access
```

### Pattern: Handle Binary Expressions

```c
TSNode binary_node = ...; // binary_expression node
TSNode left_node = ts_node_child_by_field_name(binary_node, "left", 4);
TSNode right_node = ts_node_child_by_field_name(binary_node, "right", 5);

// Find operator (anonymous node)
uint32_t child_count = ts_node_child_count(binary_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(binary_node, i);
    const char* field_name = ts_node_field_name_for_child(binary_node, i);
    if (field_name && strcmp(field_name, "operator") == 0) {
        const char* operator_type = ts_node_type(child);
        // operator_type is "+", "-", "*", "&&", etc.
    }
}
```

### Pattern: Get Enum Constants

```c
TSNode enum_node = ...; // enum_declaration node
TSNode body_node = ts_node_child_by_field_name(enum_node, "body", 4);
// body_node is enum_body
uint32_t const_count = ts_node_named_child_count(body_node);
for (uint32_t i = 0; i < const_count; i++) {
    TSNode const_node = ts_node_named_child(body_node, i);
    // const_node is enum_constant
    TSNode name_node = ts_node_child_by_field_name(const_node, "name", 4);
}
```

### Pattern: Extract SOQL Query

```c
TSNode query_expr_node = ...; // query_expression node
// First child should be "["
// Last child should be "]"
TSNode query_body = ts_node_child(query_expr_node, 1);
const char* body_type = ts_node_type(query_body);
// body_type is "soql_query_body" or "sosl_query_body"

if (strcmp(body_type, "soql_query_body") == 0) {
    TSNode select_clause = ts_node_child_by_field_name(query_body, "select_clause", 13);
    TSNode from_clause = ts_node_child_by_field_name(query_body, "from_clause", 11);
    TSNode where_clause = ts_node_child_by_field_name(query_body, "where_clause", 12);
    // etc.
}
```

### Pattern: Get Trigger Events

```c
TSNode trigger_node = ...; // trigger_declaration node
uint32_t child_count = ts_node_child_count(trigger_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(trigger_node, i);
    const char* field_name = ts_node_field_name_for_child(trigger_node, i);
    if (field_name && strcmp(field_name, "events") == 0) {
        // child is a trigger_event
        const char* event_type = ts_node_type(child);
        // event_type is "before_insert", "after_update", etc.
    }
}
```

### Pattern: Distinguish Safe Navigation

```c
TSNode field_access_node = ...; // field_access node
bool is_safe_navigation = false;
uint32_t child_count = ts_node_child_count(field_access_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(field_access_node, i);
    const char* type = ts_node_type(child);
    if (strcmp(type, "safe_navigation_operator") == 0) {
        is_safe_navigation = true;
        break;
    }
}
```

---

## Important Notes

### Case Insensitivity

All Apex keywords are **case-insensitive** in the grammar. The `ci()` helper function is used throughout. This means:

```apex
PUBLIC CLASS MyClass { }
public class MyClass { }
Public Class MyClass { }
```

All parse identically.

### Anonymous vs Named Children

When iterating children:
- Use `ts_node_child()` to get all children (including anonymous nodes like `{`, `}`, keywords)
- Use `ts_node_named_child()` to get only named children (semantic nodes)

### Field Names Are String Literals

When calling `ts_node_child_by_field_name()`, the field name must be a **null-terminated C string**. The length parameter is the length of the string.

```c
// Correct
TSNode name = ts_node_child_by_field_name(node, "name", 4);

// Incorrect - wrong length
TSNode name = ts_node_child_by_field_name(node, "name", 5);
```

### Nullable Fields

Many fields are **optional** (marked with `required: false`). Always check if the returned node is null:

```c
TSNode where_clause = ts_node_child_by_field_name(query_body, "where_clause", 12);
if (ts_node_is_null(where_clause)) {
    // No WHERE clause
} else {
    // Process WHERE clause
}
```

### Multiple Field Values

Fields marked with `multiple: true` can have multiple children with the same field name. Iterate all children and check field names:

```c
// For field_declaration with multiple declarators
uint32_t child_count = ts_node_child_count(field_decl_node);
for (uint32_t i = 0; i < child_count; i++) {
    TSNode child = ts_node_child(field_decl_node, i);
    const char* field_name = ts_node_field_name_for_child(field_decl_node, i);
    if (field_name && strcmp(field_name, "declarator") == 0) {
        // Process declarator
    }
}
```

### Whitespace and Comments

Whitespace and comments are **not** part of the syntax tree. They are handled by the `extras` rule:

```javascript
extras: ($) => [$.line_comment, $.block_comment, /\s/]
```

### Conflicts

The grammar has several conflict resolutions defined. These are ambiguities that Tree-sitter resolves using GLR parsing:

```javascript
conflicts: ($) => [
  [$._unannotated_type, $.primary_expression],
  [$._unannotated_type, $.primary_expression, $.scoped_type_identifier],
  // ... etc.
]
```

These conflicts mean that in some contexts, the parser cannot determine if a sequence of tokens is a type or an expression until more context is available.

---

## Known Quirks

### Generic types in anonymous Apex context

When parsing top-level statements (anonymous Apex), generic type declarations like
`List<String> items;` are **not** parsed as `local_variable_declaration`. Instead, the
parser interprets `<` and `>` as comparison operators, producing a `binary_expression`
inside an `expression_statement`:

```
parser_output
  expression_statement
    binary_expression
      binary_expression
        identifier        // "List"
        identifier        // "String"
      identifier          // "items"
```

This happens because the grammar has conflicts between `_unannotated_type` and
`primary_expression` — without a surrounding class/method context, the parser cannot
disambiguate a generic type from a comparison. Non-generic types like `String myVar;`
parse correctly as `local_variable_declaration`.

**Workaround:** When indexing anonymous Apex files, generic-typed local variables will
be missed by `local_variable_declaration` visitors. A future enhancement could look
for specific `expression_statement > binary_expression` patterns that resemble
generic variable declarations.

### The `type` field on `local_variable_declaration` captures the full type node

For `String myVar = 'hello';`, the `type` field points to a `type_identifier` node
whose text is `"String"`. For array types like `String[] items;`, the `type` field
points to an `array_type` node. Use `_nodeText` over the full byte range to capture
the complete type text.

### `variable_declarator` children under `local_variable_declaration`

The `declarator` field can appear multiple times (e.g., `Integer a, b;` has two
`variable_declarator` children). These are **not** accessed via
`ts_node_child_by_field_name` (which returns only the first match). Instead, iterate
all named children and filter by node type `variable_declarator`.

### The `_variable_declarator_list` is inlined

The `_variable_declarator_list` rule uses `field("declarator", ...)` on each item,
but the rule itself is prefixed with `_` so it is inlined — meaning the
`variable_declarator` nodes appear directly as children of `local_variable_declaration`
(or `field_declaration`) rather than inside a wrapper node.

---

## Grammar Source Files

### Main Files

1. **apex/grammar.js** - Main Apex grammar
2. **common/soql-grammar.js** - SOQL grammar module (exported function)
3. **common/sosl-grammar.js** - SOSL grammar module (exported function)
4. **common/common.js** - Shared utilities (`ci`, `commaJoined`, etc.)

### Helper Functions

#### ci(keyword)

Case-insensitive keyword matcher:

```javascript
function ci(keyword) {
  return alias(
    new RegExp(
      keyword.split('').map(c => `[${c.toUpperCase()}${c.toLowerCase()}]`).join('')
    ),
    keyword
  );
}
```

#### commaJoined(rule)

Comma-separated list (zero or more):

```javascript
function commaJoined(rule) {
  return optional(seq(rule, repeat(seq(",", rule))));
}
```

#### commaJoined1(rule)

Comma-separated list (one or more):

```javascript
function commaJoined1(rule) {
  return seq(rule, repeat(seq(",", rule)));
}
```

#### joined(separator, rule)

Custom separator-joined list:

```javascript
function joined(separator, rule) {
  return seq(rule, repeat(seq(separator, rule)));
}
```

---

## References

- **Repository:** https://github.com/aheber/tree-sitter-sfapex
- **Tree-sitter Documentation:** https://tree-sitter.github.io/tree-sitter/
- **Apex Language Reference:** https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/
- **SOQL/SOSL Reference:** https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/

---

**End of Reference Document**
