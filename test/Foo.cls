public with sharing class Foo {
// this is a test. This is another test
  public static Integer add(Integer a, Integer b) {
    if (a == null || b == null) {
      return 0;
    }

    List<SObject> myrecords = [SELECT Id FROM Account];

    return a + b;
  }
}
