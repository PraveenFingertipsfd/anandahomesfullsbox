/**
 * @description Handles booking swap (unit change) - clones the old booking to a new unit,
 * transfers all child records and files, and updates unit statuses.
 * Called from Flow when Booking Status changes to 'Swapped'.
 */
public with sharing class BookingSwapHandler {

    /** Raised when a swap cannot be completed. Surfaces the reason to the caller/Flow so the
     *  transaction rolls back cleanly instead of leaving the booking half-swapped. */
    public class BookingSwapException extends Exception {}

    // ==================== CHILD CLONE CONFIGURATION ====================

    /**
     * @description Inner class defining which child objects to clone during a booking swap.
     * Each entry specifies the child object API name, the lookup field to Booking,
     * and optionally a child line-item object that should also be cloned with
     * its parent re-mapped.
     */
    public class ChildCloneConfig {
        public String objectApiName;
        public String bookingLookupField;
        public String lineItemObjectApiName;
        public String lineItemParentLookupField;
        public String lineItemBookingLookupField;

        public ChildCloneConfig(String objectApiName, String bookingLookupField) {
            this.objectApiName = objectApiName;
            this.bookingLookupField = bookingLookupField;
            this.lineItemObjectApiName = null;
            this.lineItemParentLookupField = null;
            this.lineItemBookingLookupField = null;
        }

        public ChildCloneConfig(String objectApiName, String bookingLookupField,
                                String lineItemObjectApiName, String lineItemParentLookupField,
                                String lineItemBookingLookupField) {
            this.objectApiName = objectApiName;
            this.bookingLookupField = bookingLookupField;
            this.lineItemObjectApiName = lineItemObjectApiName;
            this.lineItemParentLookupField = lineItemParentLookupField;
            this.lineItemBookingLookupField = lineItemBookingLookupField;
        }
    }

    /**
     * @description Configuration list defining all child objects that should be cloned
     * when a booking is swapped. Add or remove entries here to control cloning behaviour
     * without modifying the core swap logic.
     */
    private static List<ChildCloneConfig> getChildCloneConfigs() {
        return new List<ChildCloneConfig>{
            new ChildCloneConfig('Co_Applicants__c',       'Booking__c'),
            new ChildCloneConfig('KYC_Documents__c',       'Booking__c'),
            new ChildCloneConfig('Payment_Schedule__c',    'Booking__c'),
            new ChildCloneConfig('Advance_Payment__c',     'Booking__c'),
            new ChildCloneConfig('Demands__c',             'Booking__c'),
            new ChildCloneConfig('Receipt__c',             'Booking__c',
                                 'Receipt_Line_Item__c',   'Receipt__c', 'Booking__c'),
            new ChildCloneConfig('Interest_Line_Item__c',  'Booking__c'),
            new ChildCloneConfig('Refund__c',              'Booking__c',
                                 'Refund_Line_Item__c',    'Refund__c', 'Booking__c')
        };
    }

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

        Savepoint sp = Database.setSavepoint();
        Boolean priorReceiptGateBypass = ReceiptApprovalGateService.bypass;

        try {
            // Step 1: Query old booking with all fields
            Booking__c oldBooking = queryBookingWithAllFields(request.oldBookingId);
            Id oldUnitId = oldBooking.Plot__c;

            // Step 1a: Swap eligibility (BRD §12) — only before Registration and only within
            // the same project. Validated before any DML so an invalid swap is a clean no-op.
            String eligibilityError = swapEligibilityError(oldBooking, request.newUnitId);
            if (String.isNotBlank(eligibilityError)) {
                throw new BookingSwapException(eligibilityError);
            }

            // Cloning transfers existing receipts (which may be pending/rejected) to the new
            // booking; suspend the receipt approval gate for this trusted server-side move.
            ReceiptApprovalGateService.bypass = true;

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
            newBooking.Booking_Verification_Approval_Status__c = null;
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

            // Step 5: Clone Master-Detail child records (non-reparentable) using data-driven config
            for (ChildCloneConfig config : getChildCloneConfigs()) {
                cloneChildRecords(request.oldBookingId, newBooking.Id, config);
            }

            // Step 6: Reparent Lookup child records
            //reparentLookupChildren(request.oldBookingId, newBooking.Id);

            // Step 7: Transfer files (ContentDocumentLinks)
            transferFiles(request.oldBookingId, newBooking.Id);

            // Step 8: Record swap history on both bookings (BRD §12).
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
            try {
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
            } catch (Exception configEx) {
                System.debug('Post Sales Config lookup for swap: ' + configEx.getMessage());
            }

        } catch (BookingSwapException swapEx) {
            // A validation failure (e.g. ineligible swap) — roll back and re-surface so the
            // whole transaction (including the Status = Swapped change) is undone and the user
            // sees why, instead of the booking being left half-swapped.
            Database.rollback(sp);
            throw swapEx;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new BookingSwapException('The swap could not be completed: ' + e.getMessage(), e);
        } finally {
            ReceiptApprovalGateService.bypass = priorReceiptGateBypass;
        }

        return result;
    }

    // ==================== SWAP ELIGIBILITY (BRD §12) ====================

    /** Stages at/after Registration — a booking can no longer be swapped from these. */
    private static final Set<String> SWAP_BLOCKED_STATUSES = new Set<String>{
        'Registration', 'Handover', 'Registered', 'Completed', 'Cancellation', 'Cancelled'
    };

    /**
     * @description Returns an error message if the swap is not eligible, or null if it is.
     *              Swaps are allowed only before Registration and only within the same project.
     */
    private static String swapEligibilityError(Booking__c oldBooking, Id newUnitId) {
        if (oldBooking == null) return 'Old booking could not be loaded.';

        if (oldBooking.Status__c != null && SWAP_BLOCKED_STATUSES.contains(oldBooking.Status__c)) {
            return 'Swap is allowed only before Registration. This booking is in "'
                + oldBooking.Status__c + '" stage and cannot be swapped.';
        }
        if (oldBooking.Status__c == 'Swapping') {
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
     * @description Generic method to clone child records based on a ChildCloneConfig entry.
     * Handles simple children as well as parent-with-line-item patterns (e.g. Receipt -> Receipt Line Items).
     */
    private static void cloneChildRecords(Id oldBookingId, Id newBookingId, ChildCloneConfig config) {
        List<String> fields = getFieldNames(config.objectApiName);
        String bookingField = String.escapeSingleQuotes(config.bookingLookupField);
        String query = 'SELECT ' + String.join(fields, ', ') +
                       ' FROM ' + String.escapeSingleQuotes(config.objectApiName) +
                       ' WHERE ' + bookingField + ' = :oldBookingId';
        List<SObject> fullRecords = Database.query(query);
        if (fullRecords.isEmpty()) return;

        List<SObject> clones = new List<SObject>();
        for (SObject rec : fullRecords) {
            SObject clone = rec.clone(false, true, false, false);
            clone.put(config.bookingLookupField, newBookingId);
            clones.add(clone);
        }
        insert clones;

        // If this config has a line-item child, clone those too with parent remapping
        if (config.lineItemObjectApiName != null) {
            // Build map of old parent IDs to new parent IDs
            Map<Id, Id> oldToNewParentMap = new Map<Id, Id>();
            for (Integer i = 0; i < fullRecords.size(); i++) {
                oldToNewParentMap.put(fullRecords[i].Id, clones[i].Id);
            }
            cloneLineItems(oldBookingId, newBookingId, config, oldToNewParentMap);
        }
    }

    /**
     * @description Clone line-item child records, remapping both the Booking lookup and
     * the parent lookup (e.g. Receipt__c) to the newly cloned parent record.
     */
    private static void cloneLineItems(Id oldBookingId, Id newBookingId,
                                        ChildCloneConfig config, Map<Id, Id> parentMap) {
        List<String> fields = getFieldNames(config.lineItemObjectApiName);
        String bookingField = String.escapeSingleQuotes(config.lineItemBookingLookupField);
        String query = 'SELECT ' + String.join(fields, ', ') +
                       ' FROM ' + String.escapeSingleQuotes(config.lineItemObjectApiName) +
                       ' WHERE ' + bookingField + ' = :oldBookingId';
        List<SObject> fullRecords = Database.query(query);
        if (fullRecords.isEmpty()) return;

        List<SObject> clones = new List<SObject>();
        for (SObject rec : fullRecords) {
            SObject clone = rec.clone(false, true, false, false);
            clone.put(config.lineItemBookingLookupField, newBookingId);
            // Reparent to the cloned parent record
            Id oldParentId = (Id) rec.get(config.lineItemParentLookupField);
            if (oldParentId != null && parentMap.containsKey(oldParentId)) {
                clone.put(config.lineItemParentLookupField, parentMap.get(oldParentId));
            }
            clones.add(clone);
        }
        insert clones;
    }

    // ==================== REPARENT LOOKUP CHILDREN ====================

    

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

    // ==================== UTILITY ====================

    private static List<String> getFieldNames(String objectApiName) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        return new List<String>(fieldMap.keySet());
    }
}