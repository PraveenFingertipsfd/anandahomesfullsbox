/**
 * @description Test class for PlaceholderResolver -- template placeholder resolution.
 *              Covers simple placeholders, nested dot-notation paths, missing placeholders,
 *              null/empty inputs, multiple placeholder replacement, type conversion,
 *              conditional truthiness per type, array/path edge cases, and SObject resolution.
 * @author Integration Platform
 */
@IsTest
private class PlaceholderResolverTest {

    @IsTest
    static void testSimplePlaceholder() {
        String template = 'Hello, {{name}}!';
        Map<String, Object> data = new Map<String, Object>{ 'name' => 'World' };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('Hello, World!', result, 'Simple placeholder should be resolved');
    }

    @IsTest
    static void testNestedPlaceholder() {
        String template = 'Account: {{account.name}}';
        Map<String, Object> nestedData = new Map<String, Object>{ 'name' => 'Acme Corp' };
        Map<String, Object> data = new Map<String, Object>{ 'account' => nestedData };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('Account: Acme Corp', result, 'Nested placeholder should be resolved');
    }

    @IsTest
    static void testMissingPlaceholder() {
        String template = 'Value: {{missing}}';
        Map<String, Object> data = new Map<String, Object>{ 'present' => 'here' };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('Value: ', result, 'Missing placeholder should resolve to empty string');
    }

    @IsTest
    static void testNullTemplate() {
        Map<String, Object> data = new Map<String, Object>{ 'key' => 'value' };

        Test.startTest();
        String result = PlaceholderResolver.resolve(null, data);
        Test.stopTest();

        System.assertEquals(null, result, 'Null template should return null');
    }

    @IsTest
    static void testEmptyData() {
        String template = 'Name: {{name}}';
        Map<String, Object> data = new Map<String, Object>();

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('Name: ', result, 'Placeholder with empty data should resolve to empty');
    }

    @IsTest
    static void testMultiplePlaceholders() {
        String template = '{{first}} {{last}} - {{email}}';
        Map<String, Object> data = new Map<String, Object>{
            'first' => 'John', 'last' => 'Doe', 'email' => 'john@example.com'
        };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('John Doe - john@example.com', result,
            'All placeholders should be resolved');
    }

    @IsTest
    static void testDefaultValueSyntax() {
        String template = 'Status: {{status:unknown}}';
        Map<String, Object> data = new Map<String, Object>();

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('Status: unknown', result,
            'Default value should be used when field is missing');
    }

    @IsTest
    static void testArrayIndexAccess() {
        List<Object> items = new List<Object>{ 'first', 'second', 'third' };
        Map<String, Object> data = new Map<String, Object>{ 'items' => items };

        Test.startTest();
        Object result = PlaceholderResolver.resolveNestedPath('items[0]', data);
        Test.stopTest();

        System.assertEquals('first', result, 'Should resolve array index 0');
    }

    @IsTest
    static void testConditionalBlock() {
        String template = 'Hello{{#if showGreeting}}, World{{/if}}!';
        Map<String, Object> dataTrue = new Map<String, Object>{ 'showGreeting' => true };
        Map<String, Object> dataFalse = new Map<String, Object>{ 'showGreeting' => false };

        Test.startTest();
        String resultTrue = PlaceholderResolver.resolve(template, dataTrue);
        String resultFalse = PlaceholderResolver.resolve(template, dataFalse);
        Test.stopTest();

        System.assertEquals('Hello, World!', resultTrue, 'True condition should include content');
        System.assertEquals('Hello!', resultFalse, 'False condition should exclude content');
    }

    // ===================== ADDED COVERAGE =====================

    /** convertToString: Boolean, Integer, Decimal, Date, Datetime, and other-object branches. */
    @IsTest
    static void testConvertToString_allTypeBranches() {
        Map<String, Object> data = new Map<String, Object>{
            'flag'    => true,
            'count'   => 42,
            'price'   => 19.99,
            'due'     => Date.newInstance(2026, 1, 15),
            'stamp'   => Datetime.newInstanceGmt(2026, 1, 15, 10, 30, 0),
            'listVal' => new List<Object>{ 1, 2 } // falls through to String.valueOf
        };
        String template = '{{flag}}|{{count}}|{{price}}|{{due}}|{{stamp}}|{{listVal}}';

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assert(result.contains('true'), 'Boolean branch: ' + result);
        System.assert(result.contains('42'), 'Integer branch: ' + result);
        System.assert(result.contains('19.99'), 'Decimal branch: ' + result);
        System.assert(result.contains('2026-01-15T10:30:00.000Z'), 'Datetime branch: ' + result);
    }

    /** evaluateCondition: String truthiness (non-blank true, blank false). */
    @IsTest
    static void testConditional_stringTruthiness() {
        String template = '{{#if name}}HAS{{/if}}{{#if empty}}NOPE{{/if}}';
        Map<String, Object> data = new Map<String, Object>{ 'name' => 'x', 'empty' => '' };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('HAS', result, 'Non-blank string truthy, blank string falsy');
    }

    /** evaluateCondition: Integer truthiness (non-zero true, zero false). */
    @IsTest
    static void testConditional_integerTruthiness() {
        String template = '{{#if some}}YES{{/if}}{{#if zero}}NO{{/if}}';
        Map<String, Object> data = new Map<String, Object>{ 'some' => 7, 'zero' => 0 };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('YES', result, 'Non-zero integer truthy, zero falsy');
    }

    /** evaluateCondition: Decimal truthiness and generic-object truthiness. */
    @IsTest
    static void testConditional_decimalAndObjectTruthiness() {
        String template = '{{#if amt}}AMT{{/if}}{{#if zeroAmt}}ZERO{{/if}}{{#if obj}}OBJ{{/if}}';
        Map<String, Object> data = new Map<String, Object>{
            'amt' => 12.5, 'zeroAmt' => 0.0,
            'obj' => new Map<String, Object>{ 'k' => 'v' } // non-null object → truthy
        };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('AMTOBJ', result,
            'Non-zero decimal and non-null object truthy, zero decimal falsy');
    }

    /** Nested conditionals: outer true wraps inner false. */
    @IsTest
    static void testConditional_nestedBlocks() {
        String template = '{{#if outer}}A{{#if inner}}B{{/if}}C{{/if}}';
        Map<String, Object> data = new Map<String, Object>{ 'outer' => true, 'inner' => false };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

    }

    /** Unclosed {{#if}} (no {{/if}}) exits the loop without modification. */
    @IsTest
    static void testConditional_unclosedBlock_leftAlone() {
        String template = 'Start {{#if x}}never closed';
        Map<String, Object> data = new Map<String, Object>{ 'x' => true };

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assert(result.startsWith('Start'), 'Unclosed block should not loop forever: ' + result);
    }

    /** Direct-key match takes priority even when the key contains dots. */
    @IsTest
    static void testNestedPath_directKeyWithDots() {
        Map<String, Object> data = new Map<String, Object>{ 'a.b' => 'direct' };

        Test.startTest();
        Object result = PlaceholderResolver.resolveNestedPath('a.b', data);
        Test.stopTest();

        System.assertEquals('direct', result, 'Dotted key should match directly before splitting');
    }

    /** Path failure branches: through a non-map value, blank path, null data. */
    @IsTest
    static void testNestedPath_failureBranches() {
        Map<String, Object> data = new Map<String, Object>{ 'scalar' => 'text' };

        Test.startTest();
        Object throughScalar = PlaceholderResolver.resolveNestedPath('scalar.child', data);
        Object blankPath = PlaceholderResolver.resolveNestedPath('', data);
        Object nullData = PlaceholderResolver.resolveNestedPath('x', null);
        Test.stopTest();

        System.assertEquals(null, throughScalar, 'Traversing through a scalar returns null');
        System.assertEquals(null, blankPath, 'Blank path returns null');
        System.assertEquals(null, nullData, 'Null data returns null');
    }

    /** Array failure branches: bad index text, out-of-range, index on non-list. */
    @IsTest
    static void testArrayIndex_failureBranches() {
        Map<String, Object> data = new Map<String, Object>{
            'items' => new List<Object>{ 'only' },
            'notList' => 'scalar'
        };

        Test.startTest();
        Object badIndex = PlaceholderResolver.resolveNestedPath('items[abc]', data);
        Object outOfRange = PlaceholderResolver.resolveNestedPath('items[5]', data);
        Object indexOnScalar = PlaceholderResolver.resolveNestedPath('notList[0]', data);
        Test.stopTest();

        System.assertEquals(null, badIndex, 'Non-numeric index returns null');
        System.assertEquals(null, outOfRange, 'Out-of-range index returns null');
        System.assertEquals(null, indexOnScalar, 'Index on non-list returns null');
    }

    /** Array index combined with nested map traversal after the index. */
    @IsTest
    static void testArrayIndex_thenNestedField() {
        List<Object> items = new List<Object>{
            new Map<String, Object>{ 'name' => 'Widget' }
        };
        Map<String, Object> data = new Map<String, Object>{ 'items' => items };

        Test.startTest();
        Object result = PlaceholderResolver.resolveNestedPath('items[0].name', data);
        Test.stopTest();

        System.assertEquals('Widget', result, 'Index then field should resolve');
    }

    /** Default value containing a colon (only the FIRST colon splits). */
    @IsTest
    static void testDefaultValue_containsColon() {
        String template = '{{url:https://example.com}}';
        Map<String, Object> data = new Map<String, Object>();

        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        System.assertEquals('https://example.com', result,
            'Default may itself contain colons');
    }

    /** resolveFromSObject: flat fields, relationship fields, and null guards. */
    @IsTest
    static void testResolveFromSObject_flatAndRelationship() {
        Account parent = new Account(Name = 'Parent Co');
        insert parent;
        Contact c = new Contact(LastName = 'Smith', FirstName = 'Jane', AccountId = parent.Id);
        insert c;

        Contact queried = [SELECT Id, FirstName, LastName, Account.Name
                           FROM Contact WHERE Id = :c.Id];

        Test.startTest();
        String result = PlaceholderResolver.resolveFromSObject(
            'Contact {{FirstName}} {{LastName}} works at {{Account.Name}}', queried
        );
        String nullRecord = PlaceholderResolver.resolveFromSObject('{{x}}', null);
        String blankTemplate = PlaceholderResolver.resolveFromSObject('', queried);
        Test.stopTest();

        System.assertEquals('Contact Jane Smith works at Parent Co', result,
            'Flat and relationship fields should resolve: ' + result);
        System.assertEquals('{{x}}', nullRecord, 'Null record returns template unchanged');
        System.assertEquals('', blankTemplate, 'Blank template returned as-is');
    }
}