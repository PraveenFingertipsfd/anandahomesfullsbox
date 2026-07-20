@isTest
public class RoundRobinUsersViewTest {

    @isTest
    Public static void testRoundRobinMethods() {
        Round_Robin__c testRoundRobin = new Round_Robin__c();
        insert testRoundRobin;
        
        List<Round_Robin_Member__c> testMembers = new List<Round_Robin_Member__c>();
        for(Integer i = 0; i < 2; i++) {
            testMembers.add(new Round_Robin_Member__c(
                Round_Robin__c = testRoundRobin.Id,
                Active__c = true,
               User_Type__c='Pre Sales'
            ));
        }
        insert testMembers;
        
        List<Round_Robin_Member__c> result1 = RoundRobinUsersView.fetchRoundRobinMembers(testRoundRobin.Id);
        
        for(Round_Robin_Member__c member : result1) {
            System.assertEquals(true, member.Active__c, 'Round Robin Member should be active');
        }
        
        Round_Robin_Member__c testMember = testMembers[0];
        List<Round_Robin_Member__c> updatedMembers;
        
        updatedMembers = RoundRobinUsersView.toggleMemberStatus(testMember.Id, testRoundRobin.Id);
        Round_Robin_Member__c updatedMember = updatedMembers[0];

        // Verify the toggle actually flipped Active__c from true to false
        Round_Robin_Member__c verifyToggle = [SELECT Active__c FROM Round_Robin_Member__c WHERE Id = :testMember.Id];
        System.assertEquals(false, verifyToggle.Active__c, 'toggleMemberStatus should flip Active__c from true to false');

        updatedMembers = RoundRobinUsersView.toggleMemberStatus(testMember.Id, testRoundRobin.Id);
        updatedMember = updatedMembers[0];

        // Verify the second toggle flipped it back to true
        Round_Robin_Member__c verifyToggle2 = [SELECT Active__c FROM Round_Robin_Member__c WHERE Id = :testMember.Id];
        System.assertEquals(true, verifyToggle2.Active__c, 'toggleMemberStatus should flip Active__c from false back to true');
    }

    /** Covers fetchRoundRobinMembers with no members under the round robin → empty list. */
    @isTest
    static void testFetchRoundRobinMembers_Empty() {
        Round_Robin__c emptyRR = new Round_Robin__c();
        insert emptyRR;

        Test.startTest();
        List<Round_Robin_Member__c> result = RoundRobinUsersView.fetchRoundRobinMembers(emptyRR.Id);
        Test.stopTest();

        System.assert(result.isEmpty(), 'Should return empty list when no members exist');
    }
}