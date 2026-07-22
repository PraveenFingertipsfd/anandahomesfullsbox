@IsTest
private class AgentDetailsAPITest {

    @IsTest
    static void testGetAgentDetails() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/AgentDetails';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AgentDetailsAPI.AgentDetailsResponse response = AgentDetailsAPI.getAgentDetails();
        Test.stopTest();

        System.assertEquals('SUCCESS', response.status, 'Response status should be SUCCESS');
        System.assertEquals(200, RestContext.response.statusCode, 'Status code should be 200');
        System.assertNotEquals(null, response.agents, 'Agents list should not be null');

        // Custom metadata records are visible in tests; verify the deployed agents are returned
        Integer agentCount = [SELECT COUNT() FROM Agent_Details__mdt];
        System.assertEquals(agentCount, response.agents.size(), 'All agent records should be returned');
    }
}
