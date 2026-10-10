/**
 * @description Handles booking swap (unit change) - clones the old booking to a new unit,
 * transfers all child records and files, and updates unit statuses.
 * Called from Flow when Booking Status changes to 'Swapped'.
 *
 * Cloning uses a global old->new Id registry so that every lookup between cloned
 * records (Receipt Line Item -> Payment Schedule / Demand / Advance / Receipt,
 * Demand -> Payment Schedule, etc.) is remapped to the NEW booking's records.
 * BookingFinancialRecalcService is bypassed during cloning and run once at the end
 * for both bookings, so financial totals are rebuilt on fully-linked data.
 */
public with sharing class BookingSwapHandler {

    /** Raised when a swap cannot be completed. Surfaces the reason to the caller/Flow so the
     *  transaction rolls back cleanly instead of leaving the booking half-swapped. */
    public class BookingSwapException extends Exception {}

    // ==================== CHILD CLONE CONFIGURATION ====================

    /**
     * @description Inner class defining which child objects to clone during a booking swap.
     * Each entry specifies the child object API name, the lookup field to Booking,
     * and optionally a child line-item object that should also be cloned.
     * Lookups between cloned records are remapped automatically via the Id registry,
     * so no per-field remap configuration is needed.
     */
    public class ChildCloneConfig {
        public String objectApiName;
        public String bookingLookupField;
        public String lineItemObjectApiName;
        public String lineItemBookingLookupField;
        /** Optional extra SOQL filter for the parent object (e.g. only Approved receipts). */
        public String extraWhere;
        /** Optional extra SOQL filter for the line-item object — MUST mirror the parent
         *  filter (via the parent relationship) so line items of skipped parents are
         *  skipped too, otherwise they would clone still pointing at the OLD parent. */
        public String lineItemExtraWhere;

        public ChildCloneConfig(String objectApiName, String bookingLookupField) {
            this.objectApiName = objectApiName;
            this.bookingLookupField = bookingLookupField;
            this.lineItemObjectApiName = null;
            this.lineItemBookingLookupField = null;
        }

        public ChildCloneConfig(String objectApiName, String bookingLookupField,
                                String lineItemObjectApiName, String lineItemBookingLookupField) {
            this.objectApiName = objectApiName;
            this.bookingLookupField = bookingLookupField;
            this.lineItemObjectApiName = lineItemObjectApiName;
            this.lineItemBookingLookupField = lineItemBookingLookupField;
        }
    }

    /**
     * @description Configuration list defining all child objects that should be cloned
     * when a booking is swapped. ORDER MATTERS: it is the dependency order for lookup
     * remapping. An object must appear AFTER every object it looks up to, so the
     * registry already contains the new Ids when its records are cloned.
     * (Payment Schedules before Demands, both before Receipts, Receipt Line Items last.)
     */
    private static List<ChildCloneConfig> getChildCloneConfigs() {
        // Only APPROVED receipts are transferred to the new booking. Pending and Rejected
        // receipts (and their line items) stay on the old booking.
        ChildCloneConfig receiptConfig = new ChildCloneConfig(
            'Receipt__c', 'Booking__c', 'Receipt_Line_Item__c', 'Booking__c');
        receiptConfig.extraWhere =
            'Approval_Status__c = \'' + APPROVAL_STATUS_APPROVED + '\'';
        receiptConfig.lineItemExtraWhere =
            'Receipt__r.Approval_Status__c = \'' + APPROVAL_STATUS_APPROVED + '\'';

        return new List<ChildCloneConfig>{
            new ChildCloneConfig('Co_Applicant__c',       'Booking__c'),
            new ChildCloneConfig('KYC_Documents__c',      'Booking__c'),
            new ChildCloneConfig('Payment_Schedule__c',   'Booking__c'),
            new ChildCloneConfig('Advance_Payment__c',    'Booking__c'),
            new ChildCloneConfig('Demands__c',            'Booking__c'),
            receiptConfig,
            new ChildCloneConfig('Interest_Line_Item__c', 'Booking__c'),
            new ChildCloneConfig('Refund__c',             'Booking__c')
        };
    }

    /** Receipt approval status considered transferable during a swap.
     *  Replace with PostSalesConstants.APPROVAL_STATUS_APPROVED if that constant exists. */
    private static final String APPROVAL_STATUS_APPROVED = 'Approved';

    // ==================== INPUT / OUTPUT WRAPPERS ====================

    public class SwapRequest {
        @InvocableVariable(label='Old Booking ID' required=true)
        public Id oldBookingId;

        @InvocableVariable(label='New Unit ID' required=true)
        public Id newUnitId;

        @InvocableVariable(label='New Booking Status' required=true description='Status for the new booking (e.g. Draft, Approved, Active)')
        public String newBookingStatus;
    }

    public class SwapResult {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='New Booking ID')
        public Id newBookingId;
    }

    // ==================== INVOCABLE METHOD ====================

    @InvocableMethod(label='Swap Booking to New Unit' description='Clones a booking to a new unit, transfers child records and files, updates unit statuses')
    public static List<SwapResult> swapBookings(List<SwapRequest> requests) {
        List<SwapResult> results = new List<SwapResult>();

        for (SwapRequest request : requests) {
            results.add(processSwap(request));
        }

        return results;
    }

    // ==================== CORE LOGIC ====================

    private static SwapResult processSwap(SwapRequest request) {
        SwapResult result = new SwapResult();
        result.success = false;

        if (request.oldBookingId == null) {
            throw new BookingSwapException('Old Booking ID is required to perform a swap.');
        }
        if (request.newUnitId == null) {
            throw new BookingSwapException('Cannot swap this booking: the "Swap To Unit" field is '
                + 'empty. Select the target unit on the booking before it is swapped.');
        }
        if (String.isBlank(request.newBookingStatus)) {
            throw new BookingSwapException('New Booking Status is required to perform a swap.');
        }

        Boolean priorReceiptGateBypass = ReceiptApprovalGateService.bypass;
        Boolean priorRecalcBypass = BookingFinancialRecalcService.bypass;

        // Step 1: Query old booking with all fields
        Booking__c oldBooking = queryBookingWithAllFields(request.oldBookingId);
        Id oldUnitId = oldBooking.Plot__c;

        // Step 1a: Swap eligibility (BRD §12) — only before Registration and only within
        // the same project. Validated before any DML so an invalid swap is a clean no-op.
        String eligibilityError = swapEligibilityError(oldBooking, request.newUnitId);
        if (String.isNotBlank(eligibilityError)) {
            throw new BookingSwapException(eligibilityError);
        }

        try {
            // Cloning transfers existing receipts (which may be pending/rejected) to the new
            // booking; suspend the receipt approval gate for this trusted server-side move.
            ReceiptApprovalGateService.bypass = true;

            // Suppress per-record financial recalculation while cloning; one full
            // recalculation runs at the end on completely linked data.
            BookingFinancialRecalcService.bypass = true;

            // Step 2: Clone the booking for the new unit
            Booking__c newBooking = oldBooking.clone(false, true, false, false);
            newBooking.Plot__c = request.newUnitId;
            newBooking.Status__c = request.newBookingStatus;
            newBooking.Booking_Date__c = Date.today();
            // Clear cancellation/swap fields on new booking
            newBooking.Cancellation_Date__c = null;
            newBooking.Cancellation_Reason__c = null;
            newBooking.Swap_Date__c = null;
            newBooking.Swapped_To_Booking__c = null;
            // Clear approval statuses for fresh start
            newBooking.Booking_Verification_Approval_Status__c = 'Approved';
            newBooking.Assignment_Approval_Status__c = null;
            newBooking.Sale_Agreement_Approval_Status__c = null;
            newBooking.Cancellation_Approval_Before_Agreement__c = null;
            newBooking.Swapping_Approval_Before_Agreement__c = null;
            insert newBooking;

            // Step 3: Update old booking - mark as Swapped
            oldBooking.Swap_Date__c = Date.today();
            oldBooking.Swapped_To_Booking__c = newBooking.Id;
            update oldBooking;

            // Step 4: Update Unit statuses
            List<Plot__c> unitsToUpdate = new List<Plot__c>();

            // Old unit → Available
            if (oldUnitId != null) {
                unitsToUpdate.add(new Plot__c(
                    Id = oldUnitId,
                    Status__c = PostSalesConstants.UNIT_STATUS_AVAILABLE,
                    Current_Booking__c = null
                ));
            }

            // New unit → Booked
            unitsToUpdate.add(new Plot__c(
                Id = request.newUnitId,
                Status__c = PostSalesConstants.UNIT_STATUS_BOOKED,
                Current_Booking__c = newBooking.Id
            ));

            update unitsToUpdate;

            // Step 5: Clone child records using a global old->new Id registry so every
            // lookup between cloned records is remapped to the new booking's records.
            Map<Id, Id> idRegistry = new Map<Id, Id>();
            idRegistry.put(request.oldBookingId, newBooking.Id);

            for (ChildCloneConfig config : getChildCloneConfigs()) {
                cloneChildRecords(request.oldBookingId, newBooking.Id, config, idRegistry);
            }

            // Step 5a: Fix backward/circular references (e.g. Advance_Payment__c.Source_Receipt__c
            // points at a Receipt cloned AFTER the advance; Payment_Schedule__c.Last_Receipt__c
            // likewise). Now that the registry is complete, patch any cloned record still
            // holding an old Id in a lookup.
            fixupStaleReferences(newBooking.Id, idRegistry);

            // Step 6: Transfer files (ContentDocumentLinks)
            transferFiles(request.oldBookingId, newBooking.Id);

            // Step 7: Record swap history on both bookings (BRD §12).
            insert new Swap_History__c(
                Old_Booking__c = oldBooking.Id,
                New_Booking__c = newBooking.Id,
                Old_Plot__c    = oldUnitId,
                New_Plot__c    = request.newUnitId,
                Swap_Date__c   = Date.today(),
                Approved_By__c = UserInfo.getUserId(),
                Approved_Date__c = Date.today()
            );

            result.success = true;
            result.newBookingId = newBooking.Id;
            result.message = 'Booking swapped successfully. New Booking ID: ' + newBooking.Id;

            // Apply Post Sales Configuration for Transfer/Swap (auto-send email if configured)
            PostSalesAdminController.ConfigWrapper config = PostSalesAdminController.resolveConfigurationForRecord(
                'Transfer', newBooking.Id, 'Booking__c'
            );
            if (config != null && config.autoSendEmail == true && config.emailTemplateId != null) {
                String templateId = ConfigMatchingService.resolveEmailTemplateForAction(
                    'Transfer', newBooking.Id, 'Booking__c'
                );
                if (templateId != null) {
                    result.message += '. Email template resolved for auto-send.';
                }
            }

            // Step 8: Single financial recalculation for BOTH bookings on fully-linked data.
            // Must run after the bypass is lifted, so restore it first.
            BookingFinancialRecalcService.bypass = priorRecalcBypass;
            BookingFinancialRecalcService.recalculateForBookings(
                new Set<Id>{ request.oldBookingId, newBooking.Id }
            );

            return result;

        } finally {
            // Exception-safe restore: a failure mid-swap must not leave the gates
            // disabled for the remainder of the transaction.
            ReceiptApprovalGateService.bypass = priorReceiptGateBypass;
            BookingFinancialRecalcService.bypass = priorRecalcBypass;
        }
    }

    // ==================== SWAP ELIGIBILITY (BRD §12) ====================

    /** Stages at/after Registration — a booking can no longer be swapped from these. */
    private static final Set<String> SWAP_BLOCKED_STATUSES = new Set<String>{
        'Registration', 'Handover', 'Registered', 'Completed', 'Cancellation', 'Cancelled'
    };

    private static String swapEligibilityError(Booking__c oldBooking, Id newUnitId) {
        if (oldBooking == null) return 'Old booking could not be loaded.';

        if (oldBooking.Status__c != null && SWAP_BLOCKED_STATUSES.contains(oldBooking.Status__c)) {
            return 'Swap is allowed only before Registration. This booking is in "'
                + oldBooking.Status__c + '" stage and cannot be swapped.';
        }

        // Block only if a swap actually COMPLETED for this booking. Status__c = 'Swapping'
        // is the expected in-flight state when the approval flow invokes this handler,
        // so it must NOT be treated as already swapped.
        if (oldBooking.Is_Swapped__c == true || oldBooking.Swapped_To_Booking__c != null) {
            return 'This booking has already been swapped.';
        }

        List<Plot__c> newUnits = [SELECT Id, Project__c FROM Plot__c WHERE Id = :newUnitId LIMIT 1];
        if (newUnits.isEmpty()) {
            return 'The selected new unit could not be found.';
        }
        if (oldBooking.Project__c != null && newUnits[0].Project__c != oldBooking.Project__c) {
            return 'Swap is allowed only within the same project. Please select a unit from the '
                + 'same project as the current booking.';
        }
        return null;
    }

    // ==================== QUERY BOOKING WITH ALL FIELDS ====================

    private static Booking__c queryBookingWithAllFields(Id bookingId) {
        // Get all fields from the Booking__c object dynamically
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Booking__c.fields.getMap();
        List<String> fieldNames = new List<String>(fieldMap.keySet());

        String query = 'SELECT ' + String.join(fieldNames, ', ') +
                       ' FROM Booking__c WHERE Id = :bookingId LIMIT 1';

        return Database.query(query);
    }

    // ==================== GENERIC CHILD RECORD CLONING ====================

    /**
     * @description Clone a config entry's child object (and its line-item object, if any),
     * remapping every lookup that points at an already-cloned record via the Id registry.
     */
    private static void cloneChildRecords(Id oldBookingId, Id newBookingId,
                                          ChildCloneConfig config, Map<Id, Id> idRegistry) {
        cloneWithRemap(config.objectApiName, config.bookingLookupField,
                       oldBookingId, newBookingId, idRegistry, config.extraWhere);

        if (config.lineItemObjectApiName != null) {
            cloneWithRemap(config.lineItemObjectApiName, config.lineItemBookingLookupField,
                           oldBookingId, newBookingId, idRegistry, config.lineItemExtraWhere);
        }
    }

    /**
     * @description Generic clone of all records of one object belonging to the old booking.
     * For every writable lookup field on the clone, if its value is a key in the registry
     * (i.e. points at a record cloned earlier in this swap), it is replaced with the new Id.
     * All cloned old->new pairs are added to the registry for objects cloned later.
     */
    private static void cloneWithRemap(String objectApiName, String bookingField,
                                       Id oldBookingId, Id newBookingId, Map<Id, Id> idRegistry,
                                       String extraWhere) {
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) {
            throw new BookingSwapException(
                'BookingSwapHandler: unknown or null object API name: [' + objectApiName + ']');
        }
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        // Writable lookup fields — the only ones that may need remapping
        List<String> refFields = new List<String>();
        for (String f : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(f).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.isCreateable()) {
                refFields.add(f);
            }
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldMap.keySet()), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE ' + String.escapeSingleQuotes(bookingField) + ' = :oldBookingId';
        if (String.isNotBlank(extraWhere)) {
            query += ' AND (' + extraWhere + ')';
        }
        List<SObject> fullRecords = Database.query(query);
        if (fullRecords.isEmpty()) return;

        List<SObject> clones = new List<SObject>();
        for (SObject rec : fullRecords) {
            SObject clone = rec.clone(false, true, false, false);
            clone.put(bookingField, newBookingId);
            for (String rf : refFields) {
                Id refVal = (Id) rec.get(rf);
                if (refVal != null && idRegistry.containsKey(refVal)) {
                    clone.put(rf, idRegistry.get(refVal));
                }
            }
            clones.add(clone);
        }
        insert clones;

        // Register old -> new Ids for objects cloned after this one
        for (Integer i = 0; i < fullRecords.size(); i++) {
            idRegistry.put(fullRecords[i].Id, clones[i].Id);
        }
    }

    /**
     * @description Second pass after all cloning: patch lookups on cloned records that still
     * hold OLD Ids because their target object was cloned later (circular/backward references,
     * e.g. Advance_Payment__c.Source_Receipt__c -> Receipt__c, or
     * Payment_Schedule__c.Last_Receipt__c -> Receipt__c).
     */
    private static void fixupStaleReferences(Id newBookingId, Map<Id, Id> idRegistry) {
        List<SObject> toUpdate = new List<SObject>();

        for (ChildCloneConfig config : getChildCloneConfigs()) {
            collectStaleReferenceFixes(config.objectApiName, config.bookingLookupField,
                                       newBookingId, idRegistry, toUpdate);
            if (config.lineItemObjectApiName != null) {
                collectStaleReferenceFixes(config.lineItemObjectApiName,
                                           config.lineItemBookingLookupField,
                                           newBookingId, idRegistry, toUpdate);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void collectStaleReferenceFixes(String objectApiName, String bookingField,
                                                   Id newBookingId, Map<Id, Id> idRegistry,
                                                   List<SObject> toUpdate) {
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return;
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        List<String> refFields = new List<String>();
        for (String f : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(f).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.isUpdateable()) {
                refFields.add(f);
            }
        }
        if (refFields.isEmpty()) return;

        String query = 'SELECT Id, ' + String.join(refFields, ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE ' + String.escapeSingleQuotes(bookingField) + ' = :newBookingId';

        for (SObject rec : Database.query(query)) {
            Boolean changed = false;
            for (String rf : refFields) {
                Id refVal = (Id) rec.get(rf);
                if (refVal != null && idRegistry.containsKey(refVal)) {
                    rec.put(rf, idRegistry.get(refVal));
                    changed = true;
                }
            }
            if (changed) {
                toUpdate.add(rec);
            }
        }
    }

    // ==================== TRANSFER FILES ====================

    private static void transferFiles(Id oldBookingId, Id newBookingId) {
        // Get all ContentDocumentLinks for the old booking
        List<ContentDocumentLink> existingLinks = [
            SELECT ContentDocumentId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :oldBookingId
        ];

        if (existingLinks.isEmpty()) return;

        // Create new links for the new booking
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink link : existingLinks) {
            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = link.ContentDocumentId,
                LinkedEntityId = newBookingId,
                ShareType = link.ShareType,
                Visibility = link.Visibility
            ));
        }
        insert newLinks;
    }
}