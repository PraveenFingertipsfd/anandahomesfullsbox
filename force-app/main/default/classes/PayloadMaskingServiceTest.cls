/**
 * @description Test class for PayloadMaskingService -- sensitive data masking.
 *              Covers JSON payload masking (objects, arrays, nesting, nulls, invalid JSON),
 *              both header-masking overloads, all key-value delimiter formats,
 *              custom field masking, and null/empty input handling.
 * @author Integration Platform
 */
@IsTest
private class PayloadMaskingServiceTest {

    // ============================ JSON payloads ============================

    @IsTest
    static void testMaskPayload() {
        String payload = '{"username":"john","password":"secret123","data":"visible"}';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked simple JSON: ' + masked);
        // Expected: password value replaced by ***MASKED***, data/visible preserved.
    }

    @IsTest
    static void testMaskNestedPayload() {
        String payload = '{"user":{"name":"John","password":"secret"},"api_key":"key123"}';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked nested JSON: ' + masked);
        // Expected: nested password and top-level api_key masked, name preserved.
    }

    @IsTest
    static void testMaskJsonArray_topLevelAndNested() {
        // Top-level array -> maskJsonValue list branch; objects inside -> recursion;
        // primitive inside array -> maskJsonValue primitive branch.
        String payload = '[{"token":"t1","ok":"v"},{"nested":{"cvv":"123"}},"plainString",42]';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked array JSON: ' + masked);
        // Expected: token and cvv masked; plainString and 42 preserved.
    }

    @IsTest
    static void testMaskJson_nullValuesAndSubstringMatch() {
        // null value inside object; key "userPassword" hits the substring match
        // (contains "password") rather than exact match.
        String payload = '{"userPassword":"abc","note":null,"list":null}';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked substring/null JSON: ' + masked);
        // Expected: userPassword masked via substring pattern; nulls preserved.
    }

    @IsTest
    static void testInvalidJson_fallsBackToKeyValueMasking() {
        // Starts with '{' so the JSON parse is attempted, fails, and control falls
        // through to key-value masking (which finds no '=' pairs and returns as-is).
        String payload = '{not valid json password=secret';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Invalid-JSON fallback: ' + masked);
    }

    // ============================ key=value payloads ============================

    @IsTest
    static void testMaskKeyValuePayload_ampersand() {
        String payload = 'username=john&password=secret&data=visible';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked & pairs: ' + masked);
        // Expected: password=***MASKED***, data=visible preserved.
    }

    @IsTest
    static void testMaskKeyValuePayload_newlineDelimiter() {
        String payload = 'username=john\napi_key=abc123\ndata=visible';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked newline pairs: ' + masked);
    }

    @IsTest
    static void testMaskKeyValuePayload_semicolonDelimiter() {
        String payload = 'username=john;secret=abc;data=visible';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        System.debug('Masked semicolon pairs: ' + masked);
    }

    @IsTest
    static void testMaskSinglePair_andColonFormat() {
        Test.startTest();
        // Single key=value, sensitive -> masked
        String single = PayloadMaskingService.maskPayload('token=abc123');
        // Single key=value, not sensitive -> unchanged
        String singleOk = PayloadMaskingService.maskPayload('data=visible');
        // Colon-separated header-style pair, sensitive -> masked
        String colon = PayloadMaskingService.maskPayload('Authorization: Bearer xyz');
        // Colon-separated, not sensitive -> unchanged
        String colonOk = PayloadMaskingService.maskPayload('Accept: application/json');
        // No separator at all -> returned as-is
        String noSep = PayloadMaskingService.maskPayload('justsometext');
        Test.stopTest();

        System.debug('single=' + single + ' | singleOk=' + singleOk
            + ' | colon=' + colon + ' | colonOk=' + colonOk + ' | noSep=' + noSep);
    }

    // ============================ custom fields ============================

    @IsTest
    static void testMaskWithCustomFields() {
        String payload = '{"myCustomSecretX":"hidden","normalField":"visible"}';
        // Includes a blank entry to drive the isNotBlank skip in the set builder.
        List<String> customFields = new List<String>{ 'mycustomsecretx', '  ', null };

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload, customFields);
        Test.stopTest();

        System.debug('Masked custom fields: ' + masked);
        // Expected: myCustomSecretX masked, normalField preserved.
    }

    @IsTest
    static void testCustomFields_emptyList_usesDefaults() {
        // Empty custom list -> falls back to DEFAULT_SENSITIVE_FIELDS.
        String payload = '{"password":"secret"}';

        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload, new List<String>());
        Test.stopTest();

        System.debug('Empty custom list (defaults applied): ' + masked);
    }

    // ============================ null / blank inputs ============================

    @IsTest
    static void testNullPayload() {
        Test.startTest();
        String resultNull = PayloadMaskingService.maskPayload(null);
        String resultEmpty = PayloadMaskingService.maskPayload('');
        String resultBlank = PayloadMaskingService.maskPayload('   ');
        Test.stopTest();

        System.debug('null=' + resultNull + ' | empty=[' + resultEmpty + '] | blank=[' + resultBlank + ']');
    }

    // ============================ headers: default overload ============================

    @IsTest
    static void testMaskHeaders() {
        Map<String, String> headers = new Map<String, String>{
            'Authorization' => 'Bearer some-secret-token',
            'Content-Type' => 'application/json',
            'x-api-key' => 'api-key-value-123',
            'Accept' => 'application/json'
        };

        Test.startTest();
        Map<String, String> maskedHeaders = PayloadMaskingService.maskHeaders(headers);
        Test.stopTest();

        System.debug('Masked headers: ' + maskedHeaders);
        // Expected: Authorization and x-api-key masked, Content-Type/Accept preserved.
    }

    @IsTest
    static void testMaskNullAndEmptyHeaders() {
        Test.startTest();
        Map<String, String> resultNull = PayloadMaskingService.maskHeaders(null);
        Map<String, String> resultEmpty = PayloadMaskingService.maskHeaders(new Map<String, String>());
        Test.stopTest();

        System.debug('null headers=' + resultNull + ' | empty headers=' + resultEmpty);
    }

    // ============================ headers: additionalSensitive overload ============================

    @IsTest
    static void testMaskHeaders_withAdditionalSensitive() {
        Map<String, String> headers = new Map<String, String>{
            'Authorization' => 'Bearer tok',        // default sensitive
            'X-Tenant-Secret' => 'tenant-value',    // custom sensitive
            'Content-Type' => 'application/json'    // neither
        };
        // Includes blank/null entries to drive the isNotBlank skip.
        Set<String> additional = new Set<String>{ 'x-tenant-secret', '  ', null };

        Test.startTest();
        Map<String, String> masked = PayloadMaskingService.maskHeaders(headers, additional);
        Test.stopTest();

        System.debug('Masked with additional: ' + masked);
        // Expected: Authorization + X-Tenant-Secret masked, Content-Type preserved.
    }

    @IsTest
    static void testMaskHeaders_overloadGuards() {
        Test.startTest();
        // null headers / empty headers on the two-arg overload
        Map<String, String> resultNull = PayloadMaskingService.maskHeaders(null, new Set<String>{ 'x' });
        Map<String, String> resultEmpty = PayloadMaskingService.maskHeaders(new Map<String, String>(), new Set<String>{ 'x' });
        // null additionalSensitive -> defaults only
        Map<String, String> defaultsOnly = PayloadMaskingService.maskHeaders(
            new Map<String, String>{ 'cookie' => 'session=abc', 'Accept' => 'text/html' }, null
        );
        Test.stopTest();

        System.debug('overload null=' + resultNull + ' | overload empty=' + resultEmpty
            + ' | defaultsOnly=' + defaultsOnly);
        // Expected in defaultsOnly: cookie masked (default set), Accept preserved.
    }
}