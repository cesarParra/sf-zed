public with sharing class Foo {
// this is a test. This is another test
  public static Integer add(Integer a, Integer b) {
    if (a == null || b == null) {
      return 0;
    }

    List<SObject> myrecords = [SELECT Id FROM Account];

    // SOSL (inline) — should be parsed as a query_expression -> sosl_query_body
    // and highlighted using the SOSL injected language.
    List<List<SObject>> searchResults = [
      FIND 'Acme*' IN NAME FIELDS
      RETURNING Account(Id, Name), Contact(Id, Name)
    ];

    return a + b;
  }
}
T
