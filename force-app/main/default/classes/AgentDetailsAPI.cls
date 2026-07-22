@RestResource(urlMapping='/AgentDetails')
global without sharing class AgentDetailsAPI {

    global class AgentWrapper {
        public String agentName;
        public String mobileNumber;

        public AgentWrapper(String agentName, String mobileNumber) {
            this.agentName = agentName;
            this.mobileNumber = mobileNumber;
        }
    }

    global class AgentDetailsResponse {
        public String status;
        public String message;
        public List<AgentWrapper> agents;

        public AgentDetailsResponse(String status, String message, List<AgentWrapper> agents) {
            this.status = status;
            this.message = message;
            this.agents = agents;
        }
    }

    @HttpGet
    global static AgentDetailsResponse getAgentDetails() {
        try {
            List<AgentWrapper> agents = new List<AgentWrapper>();
            for (Agent_Details__mdt agent : [
                SELECT Agent_Name__c, Mobile_Number__c
                FROM Agent_Details__mdt
                ORDER BY Agent_Name__c
            ]) {
                agents.add(new AgentWrapper(agent.Agent_Name__c, agent.Mobile_Number__c));
            }

            RestContext.response.statusCode = 200;
            return new AgentDetailsResponse('SUCCESS', 'Agent details retrieved successfully.', agents);

        } catch (Exception e) {
            RestContext.response.statusCode = 500;
            return new AgentDetailsResponse('FAIL', 'An unexpected error occurred: ' + e.getMessage(), null);
        }
    }
}
