/**
 * @description Test class for PostSalesConstants
 */
@isTest
private class PostSalesConstantsTest {

    @isTest
    static void demandStatusConstants_definedAndGroupedCorrectly() {
        System.assertEquals('Open', PostSalesConstants.DEMAND_STATUS_OPEN);
        System.assertEquals('Partial', PostSalesConstants.DEMAND_STATUS_PARTIAL);
        System.assert(PostSalesConstants.DEMAND_OPEN_STATUSES.contains(PostSalesConstants.DEMAND_STATUS_OPEN));
        System.assertEquals(7, PostSalesConstants.DEMAND_ALL_OPEN_STATUSES.size());
    }

    @isTest
    static void scheduleClosedStatuses_includesPaidCompletedWaived() {
        System.assert(PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(PostSalesConstants.SCHEDULE_STATUS_PAID));
        System.assert(PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(PostSalesConstants.SCHEDULE_STATUS_COMPLETED));
        System.assert(PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(PostSalesConstants.SCHEDULE_STATUS_WAIVED));
    }

    @isTest
    static void approvalStatusMap_collapsesPendingApprovalToPending() {
        System.assertEquals(
            PostSalesConstants.APPROVAL_STATUS_PENDING,
            PostSalesConstants.APPROVAL_STATUS_MAP.get(PostSalesConstants.APPROVAL_STATUS_PENDING_APPROVAL)
        );
        System.assertEquals(
            PostSalesConstants.APPROVAL_STATUS_REJECTED,
            PostSalesConstants.APPROVAL_STATUS_MAP.get(PostSalesConstants.APPROVAL_STATUS_CANCELLED)
        );
    }

    @isTest
    static void formatCurrency_handlesNullAndDecimals() {
        System.assertEquals(PostSalesConstants.CURRENCY_SYMBOL + '0.00', PostSalesConstants.formatCurrency(null));
        String s = PostSalesConstants.formatCurrency(1234.5);
        System.assert(s.startsWith(PostSalesConstants.CURRENCY_SYMBOL));
        System.assert(s.contains('.'));
    }

    @isTest
    static void formatCurrencyNoDecimals_handlesNullAndRounds() {
        System.assertEquals(PostSalesConstants.CURRENCY_SYMBOL + ' 0', PostSalesConstants.formatCurrencyNoDecimals(null));
        String s = PostSalesConstants.formatCurrencyNoDecimals(1234.6);
        System.assert(s.startsWith(PostSalesConstants.CURRENCY_SYMBOL));
        System.assert(!s.contains('.'));
    }

    @isTest
    static void mapApprovalStatus_handlesNullKnownAndUnknown() {
        System.assertEquals(PostSalesConstants.APPROVAL_STATUS_DRAFT, PostSalesConstants.mapApprovalStatus(null));
        System.assertEquals(
            PostSalesConstants.APPROVAL_STATUS_APPROVED,
            PostSalesConstants.mapApprovalStatus(PostSalesConstants.APPROVAL_STATUS_APPROVED)
        );
        System.assertEquals('Custom', PostSalesConstants.mapApprovalStatus('Custom'));
    }

    @isTest
    static void getStatusColor_returnsConfiguredOrDefault() {
        System.assertEquals('green', PostSalesConstants.getStatusColor(PostSalesConstants.SCHEDULE_STATUS_PAID));
        System.assertEquals(PostSalesConstants.STATUS_COLOR_DEFAULT, PostSalesConstants.getStatusColor('Unknown'));
    }

    @isTest
    static void getStatusIcon_returnsConfiguredOrDefault() {
        System.assertEquals('utility:check', PostSalesConstants.getStatusIcon(PostSalesConstants.SCHEDULE_STATUS_PAID));
        System.assertEquals(PostSalesConstants.STATUS_ICON_DEFAULT, PostSalesConstants.getStatusIcon('Unknown'));
    }

    @isTest
    static void isWhatIdSupported_acceptsCustomObjectsAndKnownStandard() {
        System.assertEquals(true, PostSalesConstants.isWhatIdSupported('Account'));
        System.assertEquals(true, PostSalesConstants.isWhatIdSupported('Anything__c'));
        System.assertEquals(false, PostSalesConstants.isWhatIdSupported('Lead'));
        System.assertEquals(false, PostSalesConstants.isWhatIdSupported(null));
    }

    @isTest
    static void getPicklistValues_unknownKeyReturnsEmpty() {
        List<PostSalesConstants.PicklistOption> opts = PostSalesConstants.getPicklistValues('not_a_key');
        System.assertEquals(0, opts.size());
    }

    @isTest
    static void getPicklistValuesByObjectField_invalidObjectReturnsEmpty() {
        List<PostSalesConstants.PicklistOption> opts =
            PostSalesConstants.getPicklistValuesByObjectField('No_Such_Object__c', 'Field__c');
        System.assertEquals(0, opts.size());
    }

    @isTest
    static void getPicklistValuesByObjectField_invalidFieldReturnsEmpty() {
        List<PostSalesConstants.PicklistOption> opts =
            PostSalesConstants.getPicklistValuesByObjectField('Account', 'No_Such_Field__c');
        System.assertEquals(0, opts.size());
    }

    @isTest
    static void picklistOption_constructorAssigns() {
        PostSalesConstants.PicklistOption o = new PostSalesConstants.PicklistOption('L', 'V');
        System.assertEquals('L', o.label);
        System.assertEquals('V', o.value);
    }
}