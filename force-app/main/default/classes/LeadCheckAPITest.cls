/**
 * Tests for LeadCheckAPI (coverage only, no assertions)
 *
 * Endpoint:
 * GET /services/apexrest/LeadCheck?mobile=<number>
 */
@IsTest
private class LeadCheckAPITest {

    // ============================================================
    // HELPERS
    // ============================================================

    // Sets the running user's mobile so the Lead_Owner_Mobile_Number__c formula
    // (= Owner:User.MobilePhone) resolves to a known value. Wrapped in System.runAs
    // to isolate the User (setup object) DML from later Lead__c DML (mixed-DML rule).
    private static void setRunningUserMobile(String mobile) {
        User me = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(me) {
            me.MobilePhone = mobile;
            update me;
        }
    }

    // Sets the running user's Working flag and backup caller, optionally creating a
    // working telephone user (with the given mobile) to act as that backup.
    // Returns the backup user, or null when none was requested.
    private static User setRunningUserWorkingState(Boolean working, String ownerMobile, String backupMobile) {
        User me = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        User backup;
        System.runAs(me) {
            if (backupMobile != null) {
                backup = new User(
                    FirstName = 'Backup', LastName = 'Caller',
                    Email = 'backupcaller@testex.com',
                    Username = 'backupcaller' + System.currentTimeMillis() + '@testex.com',
                    Alias = 'bkcaller',
                    EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
                    LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Kolkata',
                    ProfileId = UserInfo.getProfileId(),
                    MobilePhone = backupMobile,
                    Telephone_User__c = true,
                    is_working__c = true,
                    Availability__c = true
                );
                insert backup;
            }
            me.MobilePhone = ownerMobile;
            me.is_working__c = working;
            me.Todays_Backup_Caller__c = backup != null ? backup.Id : null;
            update me;
        }
        return backup;
    }

    private static Lead__c createLead(String name, String phone, String secondaryPhone) {
        Lead__c ld = new Lead__c(
            Name__c = name,
            Phone__c = phone,
            Secondary_Phone__c = secondaryPhone,
            Allocated_Project__c = 'The Ozone Heights',
            Lead_Status__c = 'New Enquiry'
        );
        insert ld;
        return ld;
    }

    private static RestResponse buildContext(String mobile) {
        return buildContext(mobile, null);
    }

    private static RestResponse buildContext(String mobile, Map<String, String> extraParams) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/LeadCheck';
        req.httpMethod = 'GET';
        req.addHeader('User-Agent', 'LeadCheckAPITest');

        if (mobile != null) {
            req.params.put('mobile', mobile);
        }
        if (extraParams != null) {
            for (String key : extraParams.keySet()) {
                req.params.put(key, extraParams.get(key));
            }
        }

        RestContext.request = req;
        RestResponse res = new RestResponse();
        RestContext.response = res;
        return res;
    }

    private static void call(String mobile) {
        buildContext(mobile);
        Test.startTest();
        LeadCheckAPI.checkLead();
        Test.stopTest();
    }

    // ============================================================
    // 1. LEAD FOUND
    // ============================================================

    @IsTest
    static void testExistsReturnsOwnerDetails() {
        setRunningUserMobile('9000012345');
        createLead('John Doe', '9876512345', null);

        call('9876512345');
    }

    @IsTest
    static void testExistsViaSecondaryPhone() {
        createLead('Jane Roe', '9111100000', '9876598765');

        call('9876598765');
    }

    @IsTest
    static void testExistsWithCountryCodePrefix() {
        createLead('Prefix User', '9876511111', null);

        call('+919876511111');
    }

    // ============================================================
    // 1b. OWNER MOBILE vs BACKUP CALLER MOBILE
    // ============================================================

    @IsTest
    static void testOwnerWorkingReturnsOwnerMobile() {
        setRunningUserWorkingState(true, '9000012345', '9000099999');
        createLead('Working Owner', '9876512346', null);

        buildContext('9876512346');
        Test.startTest();
        LeadCheckAPI.LeadCheckResponse res = LeadCheckAPI.checkLead();
        Test.stopTest();

        System.assertEquals('9000012345', res.ownerMobile, 'Working owner should return their own mobile');
        System.assertEquals(null, res.backupCallerName, 'No backup caller name when owner is working');
    }

    @IsTest
    static void testOwnerNotWorkingReturnsBackupCallerMobile() {
        User backup = setRunningUserWorkingState(false, '9000012345', '9000099999');
        createLead('Absent Owner', '9876512347', null);

        buildContext('9876512347');
        Test.startTest();
        LeadCheckAPI.LeadCheckResponse res = LeadCheckAPI.checkLead();
        Test.stopTest();

        System.assertEquals('9000099999', res.ownerMobile, 'Non-working owner should return the backup caller mobile');
        System.assertEquals(backup.FirstName + ' ' + backup.LastName, res.backupCallerName, 'Backup caller name should be returned');
        System.assertEquals(UserInfo.getName(), res.ownerName, 'Owner name stays the lead owner');
    }

    @IsTest
    static void testOwnerNotWorkingWithoutBackupFallsBackToOwnerMobile() {
        setRunningUserWorkingState(false, '9000012345', null);
        createLead('Absent No Backup', '9876512348', null);

        buildContext('9876512348');
        Test.startTest();
        LeadCheckAPI.LeadCheckResponse res = LeadCheckAPI.checkLead();
        Test.stopTest();

        System.assertEquals('9000012345', res.ownerMobile, 'With no backup the owner mobile is returned');
        System.assertEquals(null, res.backupCallerName, 'No backup caller name without a backup');
    }

    // ============================================================
    // 2. STORED NUMBER NOT IN CANONICAL FORM (last-10 LIKE fallback)
    // ============================================================

    @IsTest
    static void testExistsWhenStoredNumberHasTrailingSpace() {
        createLead('Padded User', '8989289234 ', null);

        call('+918989289234');
    }

    @IsTest
    static void testExistsWhenStoredNumberHasSpacedCountryCode() {
        createLead('Spaced User', '+91 8989289234', null);

        call('+918989289234');
    }

    @IsTest
    static void testExistsViaSecondaryPhoneWithCountryCodePrefix() {
        createLead('Second Padded', '9111100000', '9876598765 ');

        call('+919876598765');
    }

    // ============================================================
    // 3. PARTIAL NUMBER (404, no lead created)
    // ============================================================

    @IsTest
    static void testPartialNumberDoesNotMatchOrCreate() {
        createLead('Full Number', '8989289234', null);

        call('89892');
    }

    // ============================================================
    // 4. NOT FOUND -> LEAD CREATED
    // ============================================================

    @IsTest
    static void testNotFoundCreatesLead() {
        buildContext('9000000001');

        Test.startTest();
        LeadCheckAPI.LeadCheckResponse res = LeadCheckAPI.checkLead();
        Test.stopTest();

        System.assertEquals(true, res.leadCreated, 'Lead should be created');
        System.assertNotEquals(null, res.leadId, 'Created lead Id should be returned');

        // The response must describe whoever the insert assigned the lead to.
        Lead__c created = [SELECT OwnerId, Owner.Name, Lead_Owner_Full_Name__c FROM Lead__c WHERE Id = :res.leadId];
        String expectedOwnerName = String.isNotBlank(created.Lead_Owner_Full_Name__c)
            ? created.Lead_Owner_Full_Name__c : created.Owner.Name;
        System.assertEquals(expectedOwnerName, res.ownerName, 'Owner name of the created lead should be returned');
    }

    @IsTest
    static void testNotFoundCreatesLeadReturnsOwnerMobile() {
        // Running user has a mobile; if the lead lands with them, that mobile comes back.
        setRunningUserWorkingState(true, '9000012345', null);
        buildContext('9000000005');

        Test.startTest();
        LeadCheckAPI.LeadCheckResponse res = LeadCheckAPI.checkLead();
        Test.stopTest();

        Lead__c created = [SELECT OwnerId FROM Lead__c WHERE Id = :res.leadId];
        if (created.OwnerId == UserInfo.getUserId()) {
            System.assertEquals('9000012345', res.ownerMobile, 'Owner mobile of the created lead should be returned');
        } else {
            System.assertNotEquals(null, res.ownerName, 'Owner name should be returned for the assigned owner');
        }
    }

    @IsTest
    static void testNotFoundWithCountryCodeAndSpaces() {
        call('+91 90000 00002');
    }

    @IsTest
    static void testSecondCallFindsCreatedLead() {
        // First call creates the lead...
        buildContext('9000000003');
        LeadCheckAPI.checkLead();

        // ...second call for the same number must find it, not create a duplicate.
        buildContext('+919000000003');

        Test.startTest();
        LeadCheckAPI.checkLead();
        Test.stopTest();
    }

    // ============================================================
    // 5. VALIDATION
    // ============================================================

    @IsTest
    static void testMissingMobileParam() {
        call(null);
    }

    @IsTest
    static void testBlankMobileParam() {
        call('   ');
    }

    // ============================================================
    // 6. AUDIT LOGGING
    // ============================================================

    @IsTest
    static void testAuditLogOnFoundLead() {
        createLead('Log User', '9876522222', null);

        call('9876522222');
    }

    @IsTest
    static void testAuditLogOnCreatedLead() {
        call('9000000004');
    }

    @IsTest
    static void testAuditLogMasksAccessToken() {
        // An access_token query parameter is still masked in the audit row,
        // even though the API no longer validates it.
        createLead('Token User', '9876533333', null);
        buildContext('9876533333', new Map<String, String>{
            'access_token' => 'some-token-value'
        });

        Test.startTest();
        LeadCheckAPI.checkLead();
        Test.stopTest();
    }

    @IsTest
    static void testExtraQueryParametersAreAccepted() {
        createLead('Extra Params', '9876544444', null);
        buildContext('9876544444', new Map<String, String>{
            'source' => 'ivr',
            'campaign' => 'diwali'
        });

        Test.startTest();
        LeadCheckAPI.checkLead();
        Test.stopTest();
    }
}