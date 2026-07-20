/**
 * @description Syncs a NOC's approval status onto its Booking (BRD §7.40). When a NOC__c
 *              Approval_Status__c changes, the booking's NOC_Approval_Status__c is updated so the
 *              booking carries a single NOC approval status. The NOC itself is approved through
 *              the config-driven Approval Configuration engine; this only reflects the result.
 * @author System
 */
public with sharing class NOCApprovalSyncService {

    /** Re-entrancy guard (updating the booking must not loop back). */
    private static Boolean syncing = false;

    /**
     * @description From the NOC after-insert/after-update trigger: copies the NOC approval status
     *              to the parent booking. On insert (oldMap null) every NOC with a status is
     *              synced; on update only those whose status changed. When a booking has multiple
     *              NOCs, the most recently changed NOC in this transaction wins.
     */
    public static void syncToBooking(List<NOC__c> newList, Map<Id, NOC__c> oldMap) {
        if (syncing || newList == null) return;

        Map<Id, String> bookingToStatus = new Map<Id, String>();
        for (NOC__c noc : newList) {
            if (noc.Booking__c == null) continue;
            NOC__c old = oldMap != null ? oldMap.get(noc.Id) : null;
            Boolean changed = (old == null) ? String.isNotBlank(noc.Approval_Status__c)
                                            : (noc.Approval_Status__c != old.Approval_Status__c);
            if (changed) {
                bookingToStatus.put(noc.Booking__c, noc.Approval_Status__c);
            }
        }
        if (bookingToStatus.isEmpty()) return;

        List<Booking__c> toUpdate = new List<Booking__c>();
        for (Id bookingId : bookingToStatus.keySet()) {
            toUpdate.add(new Booking__c(Id = bookingId, NOC_Approval_Status__c = bookingToStatus.get(bookingId)));
        }

        syncing = true;
        try {
            update toUpdate;
        } finally {
            syncing = false;
        }
    }
}