/**
 * @description Invocable Apex service called from Record-Triggered Flow on Booking__c (After Insert).
 *              Reads Payment Schedule configuration from Post_Sales_Configuration__c to determine
 *              which source object to copy from and how to match to the booking.
 *              Falls back to hardcoded defaults if no config exists.
 * @author System
 * @date 2026-03-15
 */
public with sharing class PaymentScheduleGeneratorService {

    // Default values (used when no config exists)
    private static final String DEFAULT_SOURCE_OBJECT = 'Master_Payment_Schedule__c';
    private static final String DEFAULT_SOURCE_PARENT = 'Project__c';
    private static final String DEFAULT_BOOKING_PARENT = 'Project__c';

    // Funding types that carry a per-milestone Bank/Customer prorata split (BRD §8.1).
    private static final Set<String> FUNDING_PRORATA = new Set<String>{ 'Prorata', 'Partial' };
    // Rounding tolerance (paise) when reconciling the split totals.
    private static final Decimal SPLIT_TOLERANCE = 1;
    // TDS is 1% of the Flat (base) amount.
    public static final Decimal TDS_RATE = 0.01;

    /**
     * @description Flow input wrapper
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    @InvocableMethod(label='Generate Payment Schedules for Booking' description='Creates Payment Schedule records from configured source for a new Booking' category='Financial')
    public static void generateSchedules(List<FlowInput> inputs) {
        Set<Id> bookingIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input.bookingId != null) {
                bookingIds.add(input.bookingId);
            }
        }

        if (bookingIds.isEmpty()) return;

        generateForBookings(bookingIds);
    }

    /**
     * @description Core generation logic. Reads config from Post_Sales_Configuration__c
     *              (type = 'Payment Schedule') to determine source object and parent matching.
     */
    public static void generateForBookings(Set<Id> bookingIds) {
        // Load Payment Schedule configuration
        Map<String, Object> creationConfig = loadCreationConfig();
        String sourceParentField = (String) creationConfig.get('sourceParentField');
        String bookingParentField = (String) creationConfig.get('bookingParentField');
        List<Object> fieldMappings = (List<Object>) creationConfig.get('fieldMappings');

        // Step 1: Query Bookings with the configured parent lookup field
        String bookingQuery = 'SELECT Id, Name, ' + bookingParentField + ', Plot__c, Plot__r.Unit_Type__c, '
            + 'Grand_Total__c, Total_Flat_Cost__c, GST_Amount__c, '
            + 'Total_Payable_Amount__c '
            + 'FROM Booking__c WHERE Id IN :bookingIds';

        List<Booking__c> bookings = Database.query(bookingQuery);
        if (bookings.isEmpty()) return;

        // Collect parent IDs from the configured field
        Set<Id> parentIds = new Set<Id>();
        Map<Id, Booking__c> bookingMap = new Map<Id, Booking__c>();
        for (Booking__c b : bookings) {
            Id parentId = (Id) b.get(bookingParentField);
            if (parentId != null) {
                parentIds.add(parentId);
            }
            bookingMap.put(b.Id, b);
        }

        if (parentIds.isEmpty()) return;

        // Build the set of source fields to query (defaults + mapped fields)
        Set<String> sourceFields = new Set<String>{
            'Id', 'Name', sourceParentField, 'Sequence__c', 'Percentage__c',
            'Payment_Type__c', 'Status__c', 'Is_Active__c',
            'Days_After_Booking__c', 'Days_After_Previous__c',
            'Applicable_For__c', 'Description__c', 'Milestone_Description__c', 'Is_Agreement__c'
        };
        // Add any additional source fields from field mappings
        for (Object mObj : fieldMappings) {
            Map<String, Object> m = (Map<String, Object>) mObj;
            String sf = (String) m.get('sourceField');
            if (String.isNotBlank(sf)) sourceFields.add(sf);
        }

        // Step 2: Query Master Payment Schedules using configured parent field
        String masterQuery = 'SELECT ' + String.join(new List<String>(sourceFields), ', ')
            + ' FROM Master_Payment_Schedule__c '
            + 'WHERE ' + sourceParentField + ' IN :parentIds '
            + 'AND Is_Active__c = true '
            + 'ORDER BY Sequence__c ASC';

        List<Master_Payment_Schedule__c> masterSchedules = Database.query(masterQuery);
        if (masterSchedules.isEmpty()) return;

        // Group Master Schedules by parent
        Map<Id, List<Master_Payment_Schedule__c>> masterByParent = new Map<Id, List<Master_Payment_Schedule__c>>();
        for (Master_Payment_Schedule__c ms : masterSchedules) {
            Id parentId = (Id) ms.get(sourceParentField);
            if (!masterByParent.containsKey(parentId)) {
                masterByParent.put(parentId, new List<Master_Payment_Schedule__c>());
            }
            masterByParent.get(parentId).add(ms);
        }

        // Step 3: Create Payment Schedules for each Booking
        List<Payment_Schedule__c> schedulesToInsert = new List<Payment_Schedule__c>();
        List<Booking__c> bookingsToUpdate = new List<Booking__c>();

        for (Booking__c booking : bookings) {
            Id parentId = (Id) booking.get(bookingParentField);
            if (parentId == null) continue;

            List<Master_Payment_Schedule__c> masters = masterByParent.get(parentId);
            if (masters == null || masters.isEmpty()) continue;

            Decimal totalPayable = booking.Grand_Total__c != null ? booking.Grand_Total__c : 0;
            if (totalPayable == 0 && booking.Total_Flat_Cost__c != null) {
                totalPayable = booking.Total_Flat_Cost__c + (booking.GST_Amount__c != null ? booking.GST_Amount__c : 0);
            }

            Decimal baseAmount = booking.Total_Flat_Cost__c != null ? booking.Total_Flat_Cost__c : totalPayable;
            Decimal gstTotal = booking.GST_Amount__c != null ? booking.GST_Amount__c : 0;

            String unitType = booking.Plot__r != null ? booking.Plot__r.Unit_Type__c : null;

            List<Master_Payment_Schedule__c> applicableMasters = new List<Master_Payment_Schedule__c>();
            for (Master_Payment_Schedule__c ms : masters) {
                if (String.isBlank(ms.Applicable_For__c) || String.isBlank(unitType) ||
                    ms.Applicable_For__c.contains(unitType)) {
                    applicableMasters.add(ms);
                }
            }

            if (applicableMasters.isEmpty()) continue;

            Date bookingDate = Date.today();

            for (Master_Payment_Schedule__c ms : applicableMasters) {
                Payment_Schedule__c ps = new Payment_Schedule__c();
                ps.Booking__c = booking.Id;
                ps.Master_Payment_Schedule__c = ms.Id;
                ps.Milestone_Name__c = ms.Name;
                ps.Is_Milestone_Based__c = true;
                ps.Status__c = ms.Status__c;
                ps.Demand_Raised__c = false;
                // Flow the Agreement flag from the master milestone (BRD pointer 5).
                ps.Is_Agreement__c = ms.Is_Agreement__c == true;

                // Apply field mappings from config
                if (!fieldMappings.isEmpty()) {
                    for (Object mObj : fieldMappings) {
                        Map<String, Object> m = (Map<String, Object>) mObj;
                        String sf = (String) m.get('sourceField');
                        String tf = (String) m.get('targetField');
                        if (String.isNotBlank(sf) && String.isNotBlank(tf)) {
                            try {
                                ps.put(tf, ms.get(sf));
                            } catch (Exception e) {
                                System.debug('Field mapping error: ' + sf + ' -> ' + tf + ': ' + e.getMessage());
                            }
                        }
                    }
                } else {
                    // Default mappings when no config
                    ps.Sequence__c = ms.Sequence__c;
                    ps.S_No__c = ms.Sequence__c;
                    ps.Percentage__c = ms.Percentage__c;
                   // ps.Milestone_Name__c = ms.Payment_Type__c;
                    ps.Description__c = ms.Description__c;
                }

                Decimal percentage = ms.Percentage__c != null ? ms.Percentage__c : 0;
                // The milestone's share of the Booking's Total Flat Cost ALREADY includes the 1%
                // TDS. Split that share into TDS (1%) and the Flat amount (the remaining 99%, which
                // is what gets split Bank/Customer). GST comes from the Booking's GST Amount.
                // Total Payable for the schedule = Flat + GST + TDS (i.e. share + GST).
                Decimal share = (baseAmount * percentage / 100).setScale(0, System.RoundingMode.HALF_UP);
                Decimal scheduleTds = (share * TDS_RATE).setScale(0, System.RoundingMode.HALF_UP);
                Decimal scheduleBase = share - scheduleTds;
                Decimal scheduleGst = (gstTotal * percentage / 100).setScale(0, System.RoundingMode.HALF_UP);
                Decimal scheduleTotal = scheduleBase + scheduleGst + scheduleTds;

                ps.Amount__c = scheduleTotal;
                ps.Payment_Schedule_Amount__c = scheduleBase;
                ps.GST_Amount__c = scheduleGst;
                ps.TDS_Amount__c = scheduleTds;
                ps.Pending_Amount__c = scheduleTotal;
                ps.Payment_Schedule_Amount_Pending__c = scheduleBase;
                ps.GST_Amount_Pending__c = scheduleGst;
                ps.TDS_Amount_Pending__c = scheduleTds;
                ps.Amount_Paid__c = 0;
                ps.Payment_Schedule_Amount_Paid__c = 0;
                ps.GST_Amount_Paid__c = 0;
                ps.TDS_Amount_Paid__c = 0;

                if (ms.Days_After_Booking__c != null && ms.Days_After_Booking__c > 0) {
                    ps.Due_Date__c = bookingDate.addDays(Integer.valueOf(ms.Days_After_Booking__c));
                } else if (ms.Days_After_Previous__c != null && ms.Days_After_Previous__c > 0) {
                    ps.Due_Date__c = bookingDate.addDays(Integer.valueOf(ms.Days_After_Previous__c));
                }

                schedulesToInsert.add(ps);
            }

            Booking__c bookingUpdate = new Booking__c();
            bookingUpdate.Id = booking.Id;
            if (totalPayable > 0) {
                bookingUpdate.Total_Payable_Amount__c = totalPayable;
            }
            bookingsToUpdate.add(bookingUpdate);
        }

        if (!schedulesToInsert.isEmpty()) {
            insert schedulesToInsert;
        }

        if (!bookingsToUpdate.isEmpty()) {
            update bookingsToUpdate;
        }

        // Auto-populate the Bank/Customer prorata split for Prorata/Partial bookings whose loan
        // is already sanctioned. Safe no-op for everyone else (loan not yet known, self-funded, …).
        applyProrataSplit(bookingMap.keySet());
    }

    /**
     * @description Populates the per-milestone Bank/Customer prorata split
     *              (Bank_Flat_Amount__c / Customer_Flat_Prorata__c and the GST equivalents) on a
     *              booking's payment schedules, derived from the booking's Loan Sanctioned Amount
     *              and Deficit. Enforces the BRD §8.3.1 invariants exactly:
     *                • per milestone  : Bank_Flat + Customer_Flat = base (and same for GST)
     *                • across totals  : Σ Bank_Flat = Loan Sanctioned, Σ Customer_Flat = Deficit
     *              SAFETY: only runs for Prorata/Partial bookings with a positive Loan Sanctioned
     *              Amount, only when the schedule base totals reconcile with Loan + Deficit, and it
     *              never lets a split failure block the caller (schedules simply stay unsplit).
     */
    public static void applyProrataSplit(Set<Id> bookingIds) {
        if (bookingIds == null || bookingIds.isEmpty()) return;

        Map<Id, Booking__c> books = new Map<Id, Booking__c>([
            SELECT Id, Funding_Type__c, Loan_Sanctioned_Amount__c, Deficit__c
            FROM Booking__c WHERE Id IN :bookingIds
        ]);
        Set<Id> eligible = new Set<Id>();
        for (Booking__c b : books.values()) {
            if (b.Funding_Type__c != null && FUNDING_PRORATA.contains(b.Funding_Type__c)
                && b.Loan_Sanctioned_Amount__c != null && b.Loan_Sanctioned_Amount__c > 0) {
                eligible.add(b.Id);
            }
        }
        if (eligible.isEmpty()) return;

        Map<Id, List<Payment_Schedule__c>> byBooking = new Map<Id, List<Payment_Schedule__c>>();
        for (Payment_Schedule__c ps : [
            SELECT Id, Booking__c, Sequence__c, Payment_Schedule_Amount__c, GST_Amount__c,
                   Bank_Flat_Amount__c, Customer_Flat_Prorata__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :eligible
            ORDER BY Booking__c, Sequence__c ASC NULLS LAST
        ]) {
            if (!byBooking.containsKey(ps.Booking__c)) {
                byBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
            }
            byBooking.get(ps.Booking__c).add(ps);
        }

        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
        for (Id bId : byBooking.keySet()) {
            Booking__c b = books.get(bId);
            Decimal loan = b.Loan_Sanctioned_Amount__c;
            Decimal deficit = b.Deficit__c != null ? b.Deficit__c : 0;
            List<Payment_Schedule__c> scheds = byBooking.get(bId);

            // Never overwrite an existing (manual or prior) split — only fill in when unsplit.
            Boolean alreadySplit = false;
            Decimal totalBase = 0;
            for (Payment_Schedule__c ps : scheds) {
                totalBase += (ps.Payment_Schedule_Amount__c != null ? ps.Payment_Schedule_Amount__c : 0);
                if ((ps.Bank_Flat_Amount__c != null && ps.Bank_Flat_Amount__c != 0)
                    || (ps.Customer_Flat_Prorata__c != null && ps.Customer_Flat_Prorata__c != 0)) {
                    alreadySplit = true;
                }
            }
            if (alreadySplit) continue;
            if (totalBase <= 0) continue;
            // Consistency guard: the split only reconciles when the schedule base totals equal
            // Loan Sanctioned + Deficit (i.e. no separate customer margin baked into the base).
            if ((totalBase - (loan + deficit)).abs() > SPLIT_TOLERANCE) continue;

            Decimal bankFraction = loan / totalBase; // == loan / (loan + deficit)
            Decimal runningBank = 0;
            for (Integer i = 0; i < scheds.size(); i++) {
                Payment_Schedule__c ps = scheds[i];
                Decimal base = ps.Payment_Schedule_Amount__c != null ? ps.Payment_Schedule_Amount__c : 0;
                Decimal gst  = ps.GST_Amount__c != null ? ps.GST_Amount__c : 0;

                Decimal bankFlat;
                if (i == scheds.size() - 1) {
                    // Last milestone absorbs rounding so Σ Bank_Flat == Loan Sanctioned exactly.
                    bankFlat = loan - runningBank;
                } else {
                    bankFlat = (base * bankFraction).setScale(0, System.RoundingMode.HALF_UP);
                    runningBank += bankFlat;
                }
                if (bankFlat < 0) bankFlat = 0;
                if (bankFlat > base) bankFlat = base;

                Decimal bankGst = (gst * bankFraction).setScale(0, System.RoundingMode.HALF_UP);
                if (bankGst < 0) bankGst = 0;
                if (bankGst > gst) bankGst = gst;

                Payment_Schedule__c upd = new Payment_Schedule__c(Id = ps.Id);
                upd.Bank_Flat_Amount__c = bankFlat;
                upd.Customer_Flat_Prorata__c = base - bankFlat;
                upd.Bank_GST_Amount__c = bankGst;
                upd.Customer_GST_Prorata__c = gst - bankGst;
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            // Never let a split write break the caller (e.g. booking creation): if the invariant
            // trigger rejects an edge case, leave the schedules unsplit and log it.
            try {
                update toUpdate;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'applyProrataSplit: split skipped - ' + e.getMessage());
            }
        }
    }

    /**
     * Load creation config from Post_Sales_Configuration__c (type = 'Payment Schedule').
     * Returns sourceParentField, bookingParentField, and fieldMappings.
     */
    private static Map<String, Object> loadCreationConfig() {
        Map<String, Object> config = new Map<String, Object>{
            'sourceParentField' => DEFAULT_SOURCE_PARENT,
            'bookingParentField' => DEFAULT_BOOKING_PARENT,
            'fieldMappings' => new List<Object>()
        };

        try {
            List<Post_Sales_Configuration__c> configs = [
                SELECT Reminder_Config__c
                FROM Post_Sales_Configuration__c
                WHERE Configuration_Type__c = 'Payment Schedule'
                AND Is_Active__c = true
                LIMIT 1
            ];

            if (!configs.isEmpty() && String.isNotBlank(configs[0].Reminder_Config__c)) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(configs[0].Reminder_Config__c);
                String sp = (String) parsed.get('sourceParentField');
                String bp = (String) parsed.get('bookingParentField');
                if (String.isNotBlank(sp)) config.put('sourceParentField', sp);
                if (String.isNotBlank(bp)) config.put('bookingParentField', bp);

                List<Object> mappings = (List<Object>) parsed.get('fieldMappings');
                if (mappings != null && !mappings.isEmpty()) {
                    config.put('fieldMappings', mappings);
                }
            }
        } catch (Exception e) {
            System.debug('Error loading Payment Schedule config, using defaults: ' + e.getMessage());
        }

        return config;
    }
}