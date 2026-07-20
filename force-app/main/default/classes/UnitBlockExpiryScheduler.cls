public with sharing class UnitBlockExpiryScheduler implements Schedulable {

    @TestVisible
    private static final String EXPIRED_REASON = 'Time expired for the unit block';

    public void execute(SchedulableContext sc) {
        revokeExpiredBlocks();
    }

    public static Integer revokeExpiredBlocks() {
        Date today = Date.today();
        Datetime startOfDay = Datetime.newInstance(today.year(), today.month(), today.day(), 0, 0, 0);
        Datetime endOfDay = startOfDay.addDays(1);

        List<Unit_Block_History__c> expired = [
            SELECT Id, Status__c, Revoke_Reason__c
            FROM Unit_Block_History__c
            WHERE Status__c = 'Blocked'
              AND Blocked_Expiry_Date__c != null
              AND Blocked_Expiry_Date__c >= :startOfDay
              AND Blocked_Expiry_Date__c < :endOfDay
            LIMIT 10000
        ];

        if (expired.isEmpty()) {
            return 0;
        }

        for (Unit_Block_History__c h : expired) {
            h.Status__c        = 'Revoked';
            h.Revoke_Reason__c = EXPIRED_REASON;
        }
        update expired;
        return expired.size();
    }
}