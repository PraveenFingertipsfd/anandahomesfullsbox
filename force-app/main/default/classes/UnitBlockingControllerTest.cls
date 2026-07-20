@isTest
private class UnitBlockingControllerTest {

    static String projectName;
    static Id leadId;
    static Id plotId;

    @TestSetup
    static void seed() {
        Project__c project = new Project__c(
            Name = 'The Ozone Heights',
            Project__c = 'The Ozone Heights',
            Project_Type__c = 'Residential',
            Max_Unit_Block_Days__c = 7
        );
        insert project;

        Block__c block = new Block__c(Name = 'A', Project__c = project.Id);
        insert block;

        Plot__c plot = new Plot__c(
            Name = '101',
            Status__c = 'Available',
            Project__c = project.Id,
            Block__c = 'A4',
            Plot_Type__c = 'Residential',
            Block1__c = block.Id,
            BHK_Type__c = '3 BHK + 2T',
            Apartment_No__c = 'A-101',
            Unit_Number__c = 'U-101',
            Plot_Number__c = 'P-101',
            Tower__c = 'A',
            Floor_Number__c = 1
        );
        insert plot;

        Lead__c lead = new Lead__c(
            Name__c = 'UBC Lead',
            Phone__c = '9100000000'
        );
        insert lead;
    }

    static void loadIds() {
        Project__c pj = [SELECT Name FROM Project__c LIMIT 1];
        projectName = pj.Name;
        leadId = [SELECT Id FROM Lead__c LIMIT 1].Id;
        plotId = [SELECT Id FROM Plot__c LIMIT 1].Id;
    }

    @isTest
    static void getProjectOptionsReturnsPicklist() {
        Test.startTest();
        List<UnitBlockingController.PicklistOption> opts = UnitBlockingController.getProjectOptions();
        Test.stopTest();
        System.assertNotEquals(null, opts, 'Returned list not null');
    }

    @isTest
    static void searchUnitsBlankTerm() {
        loadIds();
        Test.startTest();
        List<UnitBlockingController.UnitWrapper> wrappers =
            UnitBlockingController.searchUnits(projectName, '');
        Test.stopTest();
        System.assertNotEquals(null, wrappers, 'Wrappers list not null');
        System.assertEquals(1, wrappers.size(), 'One available plot for the project');
        UnitBlockingController.UnitWrapper w = wrappers[0];
        System.assertEquals(plotId, w.unitId, 'Wrapper unitId matches');
        System.assertEquals('A-101', w.apartmentNo, 'Apartment number mapped');
        System.assertEquals('1.00', w.floorNumber, 'Floor number serialized to string');
    }

    @isTest
    static void searchUnitsWithMatchingTerm() {
        loadIds();
        Test.startTest();
        List<UnitBlockingController.UnitWrapper> wrappers =
            UnitBlockingController.searchUnits(projectName, 'A-101');
        Test.stopTest();
        System.assertEquals(1, wrappers.size(), 'Matched plot returned');
    }

    @isTest
    static void searchUnitsBlankProjectReturnsEmpty() {
        Test.startTest();
        List<UnitBlockingController.UnitWrapper> wrappers =
            UnitBlockingController.searchUnits('', 'anything');
        Test.stopTest();
        System.assertEquals(0, wrappers.size(), 'Blank project short-circuits');
    }

    @isTest
    static void saveUnitBlockHappyPath() {
        loadIds();
        Test.startTest();
        Id blockId = UnitBlockingController.saveUnitBlock(
            leadId, plotId, projectName, 'Customer interested', 3
        );
        Test.stopTest();

        System.assertNotEquals(null, blockId, 'Block row id returned');
        Unit_Block_History__c row = [
            SELECT CLead__c, Unit__c, Project__c, Block_Reason__c,
                   Block_Duration__c, Status__c, Blocked_Time__c,
                   Blocked_Expiry_Date__c, Executive__c
            FROM Unit_Block_History__c WHERE Id = :blockId
        ];
        System.assertEquals(leadId, row.CLead__c, 'Lead linked');
        System.assertEquals(plotId, row.Unit__c, 'Unit linked');
        System.assertEquals(projectName, row.Project__c, 'Project recorded');
        System.assertEquals('Blocked', row.Status__c, 'Status set to Blocked');
        System.assertEquals(UserInfo.getUserId(), row.Executive__c, 'Executive is running user');
        System.assertNotEquals(null, row.Blocked_Expiry_Date__c, 'Expiry computed');

        Plot__c plot = [SELECT Status__c FROM Plot__c WHERE Id = :plotId];
        System.assertEquals('Blocked', plot.Status__c, 'Plot flipped to Blocked');
    }

    @isTest
    static void saveUnitBlockNullLeadThrows() {
        loadIds();
        Boolean threw = false;
        try {
            UnitBlockingController.saveUnitBlock(null, plotId, projectName, 'reason', 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Null lead must throw');
    }

    @isTest
    static void saveUnitBlockNullUnitThrows() {
        loadIds();
        Boolean threw = false;
        try {
            UnitBlockingController.saveUnitBlock(leadId, null, projectName, 'reason', 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Null unit must throw');
    }

    @isTest
    static void saveUnitBlockBlankProjectThrows() {
        loadIds();
        Boolean threw = false;
        try {
            UnitBlockingController.saveUnitBlock(leadId, plotId, '', 'reason', 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Blank project must throw');
    }

    @isTest
    static void saveUnitBlockBlankReasonThrows() {
        loadIds();
        Boolean threw = false;
        try {
            UnitBlockingController.saveUnitBlock(leadId, plotId, projectName, '', 1);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Blank reason must throw');
    }

    @isTest
    static void saveUnitBlockZeroDurationThrows() {
        loadIds();
        Boolean threw = false;
        try {
            UnitBlockingController.saveUnitBlock(leadId, plotId, projectName, 'reason', 0);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Zero duration must throw');
    }

    @isTest
    static void saveUnitBlockExceedsProjectLimitThrows() {
        loadIds();
        Boolean threw = false;
        try {
            UnitBlockingController.saveUnitBlock(leadId, plotId, projectName, 'reason', 99);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Exceeding project max must throw');
    }
}