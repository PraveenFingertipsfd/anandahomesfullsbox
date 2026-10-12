/**
 * Lead duplicate-check / lookup REST API (GET).
 *
 * Endpoint:  GET /services/apexrest/LeadCheck?mobile=<number>
 *
 * Given a mobile number it checks whether a Lead__c already exists (matching on
 * Primary Phone or Secondary Phone). If none exists, a new Lead__c is created for
 * the number with Allocated_Project__c = 'No Project'. The owner is intentionally
 * NOT set here - it is populated by other processes during insert, and the response
 * reports whoever the lead ended up with.
 *
 * No authentication is performed in this class.
 *
 *   - Lead found     -> 200, returns Lead Id + Owner Name + a mobile to call.
 *                       ownerMobile is the owner's own mobile while the owner is
 *                       working (User.is_working__c). When the owner is not working
 *                       it is the mobile of the owner's Today's Backup Caller
 *                       (User.Todays_Backup_Caller__c) and backupCallerName says who
 *                       that is. With no backup assigned it falls back to the owner's
 *                       mobile.
 *   - Lead not found -> lead created, 201, returns the new Lead Id plus the owner
 *                       it was assigned to (same ownerName / ownerMobile /
 *                       backupCallerName rules as above).
 *   - Number shorter than 10 digits and not found -> 404, no lead created.
 *   - Missing mobile -> 400.
 *
 * Audit logging (Apex_Log__c), written on every call:
 *   Request__c          -> method, URL
 *   Input_parameters__c -> all query parameters (access_token masked)
 *   Response__c         -> "HTTP <code> | LOOKUP: <how matched>" + response JSON
 *   Status__c           -> SUCCESS / FAIL
 *   Error_Message__c    -> validation message, or exception type + message +
 *                          line + stack trace + per-row DML errors
 */
@RestResource(urlMapping='/LeadCheck')
global without sharing class LeadCheckAPI {

    // Cap on any single LongTextArea log field (mirrors LogPushAPI).
    private static final Integer LOG_FIELD_LIMIT = 32768;

    // Project stamped on leads created by this API.
    private static final String DEFAULT_LEAD_PROJECT = 'No Project';

    // How the last lookup resolved: 'exact', 'last-10 LIKE' or 'none'.
    private static String lookupMode = 'not run';

    global class LeadCheckResponse {
        public String message;
        public String ownerName;        // Lead owner's full name
        public String ownerMobile;      // Mobile to call: owner's own, or the backup caller's when the owner is not working
        public String backupCallerName; // Set only when ownerMobile belongs to the backup caller
        public String leadId;           // Found or newly created Lead__c Id
        public Boolean leadCreated;     // true when this call created the lead

        public LeadCheckResponse(String message, String ownerName, String ownerMobile) {
            this.message = message;
            this.ownerName = ownerName;
            this.ownerMobile = ownerMobile;
            this.leadCreated = false;
        }
    }

    /** Which number the caller should dial for a lead, and who it belongs to. */
    private class OwnerContact {
        String mobile;
        String backupCallerName;
    }

    @HttpGet
    global static LeadCheckResponse checkLead() {
        RestRequest req = RestContext.request;

        String mobile = req != null && req.params != null ? req.params.get('mobile') : null;

        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'LeadCheckAPI.checkLead';

        // REQUEST: method and URL.
        // Set before the try so it lands on every insert path.
        log.Request__c = (
            'METHOD: ' + (req != null ? req.httpMethod : '')
            + '\nURL: ' + (req != null ? req.requestURI : '')
        ).left(LOG_FIELD_LIMIT);

        // INPUT: all query parameters, masking credentials. Always set, so an
        // empty call is visibly empty ({}) rather than blank.
        Map<String, String> inputParams = (req != null && req.params != null)
            ? new Map<String, String>(req.params)
            : new Map<String, String>();
        if (inputParams.containsKey('access_token')) {
            inputParams.put('access_token', '***');
        }
        log.Input_parameters__c = JSON.serializePretty(inputParams).left(LOG_FIELD_LIMIT);

        try {
            // Validate required query parameter
            if (String.isBlank(mobile)) {
                return finish(
                    log,
                    new LeadCheckResponse(
                        'Mobile number is required. Pass it as ?mobile=<number>.', null, null),
                    400, 'FAIL', 'Mobile number is required.');
            }

            // Matches on several forms of the number so the caller can pass +91xxxxxxxxxx,
            // 91xxxxxxxxxx or the bare number, and so a lead whose stored number carries
            // stray spaces or punctuation is still found. See findLeadByPhone.
            Lead__c ld = findLeadByPhone(mobile);

            if (ld != null) {
                LeadCheckResponse found = buildOwnerResponse('Lead already exists.', ld);
                return finish(log, found, 200, 'SUCCESS', null);
            }

            // -----------------------------------------------------------------
            // No matching lead -> create one (owner left blank on purpose).
            // Only for a real 10-digit mobile, so junk input never creates leads.
            // -----------------------------------------------------------------
            String last10 = lastTenDigits(mobile);
            if (last10.length() < 10) {
                return finish(
                    log,
                    new LeadCheckResponse(
                        'This lead is not in the system, and the mobile number is not valid enough to create one.',
                        null, null),
                    404, 'SUCCESS', 'Lead not created: mobile has fewer than 10 digits.');
            }

            Lead__c newLead = createLead(last10);

            // The owner is assigned during insert (LeadTrigger round-robin), so re-read
            // the lead to report who it went to, with the same working/backup logic.
            LeadCheckResponse created = buildOwnerResponse(
                'Lead was not in the system and has been created.', reloadLead(newLead.Id));
            created.leadCreated = true;
            return finish(log, created, 201, 'SUCCESS', null);

        } catch (Exception e) {
            return finish(
                log,
                new LeadCheckResponse(
                    'An unexpected error occurred: ' + e.getMessage(), null, null),
                500, 'FAIL', describeException(e));
        }
    }

    // ---------------------------------------------------------------------------
    // Logging
    // ---------------------------------------------------------------------------

    /**
     * Single exit point: stamps status, error and response on the audit row, inserts
     * it, sets the HTTP status code and returns the response. A failure to write the
     * log is swallowed so it can never turn a good call into a 500 or hide the real
     * outcome (e.g. a lead already created).
     */
    private static LeadCheckResponse finish(
        Apex_Log__c log,
        LeadCheckResponse response,
        Integer statusCode,
        String status,
        String errorMessage
    ) {
        log.Status__c = status;
        if (String.isNotBlank(errorMessage)) {
            log.Error_Message__c = errorMessage.left(LOG_FIELD_LIMIT);
        }
        log.Response__c = (
            'HTTP ' + statusCode + ' | LOOKUP: ' + lookupMode
            + '\n' + JSON.serialize(response)
        ).left(LOG_FIELD_LIMIT);

        try {
            insert log;
        } catch (Exception ignore) {
            // Do not allow logging failure to hide the actual API outcome.
        }

        RestContext.response.statusCode = statusCode;
        return response;
    }

    /** Exception type, message, line number, stack trace and per-row DML errors. */
    private static String describeException(Exception e) {
        String detail = e.getTypeName() + ': ' + e.getMessage()
            + ' (line ' + e.getLineNumber() + ')'
            + '\n' + e.getStackTraceString();

        if (e instanceof DmlException) {
            DmlException de = (DmlException) e;
            for (Integer i = 0; i < de.getNumDml(); i++) {
                detail += '\nDML[' + i + ']: ' + de.getDmlStatusCode(i)
                    + ' - ' + de.getDmlMessage(i)
                    + ' | fields: ' + de.getDmlFieldNames(i);
            }
        }
        return detail;
    }

    // ---------------------------------------------------------------------------
    // Owner contact
    // ---------------------------------------------------------------------------

    /** Response carrying the lead Id, owner name and the mobile to call. */
    private static LeadCheckResponse buildOwnerResponse(String message, Lead__c ld) {
        String ownerName = String.isNotBlank(ld.Lead_Owner_Full_Name__c)
            ? ld.Lead_Owner_Full_Name__c
            : (ld.Owner != null ? ld.Owner.Name : null);

        OwnerContact contact = resolveOwnerContact(ld);

        LeadCheckResponse res = new LeadCheckResponse(message, ownerName, contact.mobile);
        res.backupCallerName = contact.backupCallerName;
        res.leadId = ld.Id;
        return res;
    }

    /** Re-reads a lead with the owner fields the response needs. */
    private static Lead__c reloadLead(Id leadId) {
        return [
            SELECT Id, OwnerId, Lead_Owner_Full_Name__c, Lead_Owner_Mobile_Number__c, Owner.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];
    }

    /**
     * Decides which mobile number to hand back for a found lead.
     *
     *   owner working (is_working__c = true)          -> owner's MobilePhone
     *   owner not working, backup caller assigned     -> backup caller's MobilePhone
     *   owner not working, no backup / backup has no  -> owner's MobilePhone
     *   mobile
     *
     * Owner is polymorphic (User or Group), so the User-only fields are read with a
     * second query on User rather than through Owner. A queue-owned lead, or one whose
     * owner cannot be read, falls back to the Lead_Owner_Mobile_Number__c formula.
     */
    private static OwnerContact resolveOwnerContact(Lead__c ld) {
        OwnerContact contact = new OwnerContact();
        contact.mobile = ld.Lead_Owner_Mobile_Number__c;

        if (ld.OwnerId == null || ld.OwnerId.getSObjectType() != User.SObjectType) {
            return contact;
        }

        List<User> owners = [
            SELECT MobilePhone, is_working__c,
                   Todays_Backup_Caller__c,
                   Todays_Backup_Caller__r.Name,
                   Todays_Backup_Caller__r.MobilePhone
            FROM User
            WHERE Id = :ld.OwnerId
            LIMIT 1
        ];
        if (owners.isEmpty()) {
            return contact;
        }
        User owner = owners[0];

        if (String.isNotBlank(owner.MobilePhone)) {
            contact.mobile = owner.MobilePhone;
        }

        Boolean ownerWorking = owner.is_working__c == true;
        Boolean hasBackupMobile = owner.Todays_Backup_Caller__c != null
            && owner.Todays_Backup_Caller__r != null
            && String.isNotBlank(owner.Todays_Backup_Caller__r.MobilePhone);

        if (!ownerWorking && hasBackupMobile) {
            contact.mobile = owner.Todays_Backup_Caller__r.MobilePhone;
            contact.backupCallerName = owner.Todays_Backup_Caller__r.Name;
        }
        return contact;
    }

    // ---------------------------------------------------------------------------
    // Lead creation
    //
    // Phone__c is stored as the last 10 digits (the normalized form). Owner is NOT
    // set - other processes populate it. Allocated_Project__c = 'No Project'.
    // ---------------------------------------------------------------------------
    private static Lead__c createLead(String phone10) {
        Lead__c ld = new Lead__c();
        ld.Name__c              = 'IVR';
        ld.Phone__c             = phone10;
        ld.Lead_Status__c       = 'New Enquiry';
        ld.Allocated_Project__c = DEFAULT_LEAD_PROJECT;

        // Pre-Sales record type, only if available to the running user.
        Schema.RecordTypeInfo preSalesRt = Schema.SObjectType.Lead__c
            .getRecordTypeInfosByName()
            .get('Pre Sales');
        if (preSalesRt != null && preSalesRt.isAvailable()) {
            ld.RecordTypeId = preSalesRt.getRecordTypeId();
        }

        insert ld;
        return ld;
    }

    // ---------------------------------------------------------------------------
    // Lead matching
    //
    // findLeadByPhone / lastTenDigits / buildPhoneVariants mirror LogPushAPI - keep the
    // three in sync. Deliberately duplicated rather than shared: a new utility class
    // would have to be granted Apex-class access on every guest profile that reaches
    // this endpoint.
    // ---------------------------------------------------------------------------

    /**
     * Finds the Lead whose primary or secondary phone is the given number, in two passes.
     *
     *   1. Exact match against the variant set. Fast - Phone__c is indexed - and correct
     *      for numbers stored in canonical form.
     *   2. On a miss, match the last 10 digits with LIKE. The stored value is outside
     *      this API's control, so a lead saved as '9876543210 ' (trailing space, invisible
     *      in the UI), '+91 9876543210' or '987-654-3210' would never satisfy pass 1 even
     *      though the digits are identical. WA_Formatted_Phone__c is an existing formula
     *      that strips ( ) - + and spaces from Phone__c, which covers punctuation sitting
     *      *inside* the primary number. There is no equivalent formula for
     *      Secondary_Phone__c, so an internally punctuated secondary number still misses.
     *
     * The LIKE pattern is built only from lastTenDigits(), so it can never carry a '%'
     * or '_' from the caller, and it is skipped entirely for anything shorter than 10
     * digits - '%12345%' would otherwise match arbitrary leads.
     *
     * Pass 2 filters on a formula field, which is not indexed and so scans Lead__c. It
     * only runs on the miss path and is capped at one row.
     *
     * Records how it resolved in lookupMode so the audit log shows which pass matched.
     */
    private static Lead__c findLeadByPhone(String phone) {
        lookupMode = 'none';

        Set<String> variants = buildPhoneVariants(phone);
        List<Lead__c> exact = [
            SELECT Id, OwnerId, Lead_Owner_Full_Name__c, Lead_Owner_Mobile_Number__c, Owner.Name
            FROM Lead__c
            WHERE Phone__c IN :variants OR Secondary_Phone__c IN :variants
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!exact.isEmpty()) {
            lookupMode = 'exact';
            return exact[0];
        }

        String last10 = lastTenDigits(phone);
        if (String.isBlank(last10) || last10.length() < 10) {
            return null;
        }

        String loose = '%' + last10 + '%';
        List<Lead__c> fuzzy = [
            SELECT Id, OwnerId, Lead_Owner_Full_Name__c, Lead_Owner_Mobile_Number__c, Owner.Name
            FROM Lead__c
            WHERE Phone__c LIKE :loose
               OR Secondary_Phone__c LIKE :loose
               OR WA_Formatted_Phone__c LIKE :loose
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (fuzzy.isEmpty()) {
            return null;
        }
        lookupMode = 'last-10 LIKE';
        return fuzzy[0];
    }

    /** Digits only, last 10 - the form Lead__c.Phone__c is normalized to. */
    private static String lastTenDigits(String raw) {
        String digits = raw.replaceAll('[^0-9]', '');
        return digits.length() > 10 ? digits.substring(digits.length() - 10) : digits;
    }

    /**
     * Produces the set of forms an inbound mobile number could match against a
     * stored (normalized) Phone__c / Secondary_Phone__c value:
     *   - the raw trimmed input
     *   - digits only (punctuation / spaces / '+' removed)
     *   - the last 10 digits (handles any leading country code, e.g. 91 / +1)
     *   - digits with a leading '91' stripped
     */
    private static Set<String> buildPhoneVariants(String mobile) {
        Set<String> variants = new Set<String>();

        String raw = mobile.trim();
        if (String.isNotBlank(raw)) {
            variants.add(raw);
        }

        String digits = raw.replaceAll('[^0-9]', '');
        if (String.isNotBlank(digits)) {
            variants.add(digits);

            if (digits.length() >= 10) {
                variants.add(digits.substring(digits.length() - 10));
            }
            if (digits.startsWith('91') && digits.length() > 10) {
                variants.add(digits.substring(2));
            }
        }

        return variants;
    }
}