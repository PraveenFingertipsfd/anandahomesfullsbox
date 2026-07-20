({
    addAppliacantRecord: function(component, event, helper) {
        var appList = component.get("v.applicantList");
        appList.push({
            'sObjectType': 'Co_Applicant__c',
            'Salutation__c':'',
            'Name':'',
            'Relalation_Details__c':'',
            'W_o_S_o_C_o_c__c':'',
            'Contact_Number__c':'',
            'Country__c': '',
            'Date_of_Birth__c': '',
            'Email__c': '',
            'PAN_Number__c': '',
            'Booking__c':''        
        });
        component.set("v.applicantList", appList);
    },
    getBookingPicklists:function(component,event,helper){
        var modeofpayment = component.get("c.getModeofPayment");
        modeofpayment.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                var paymentTypePicklist = response.getReturnValue();
                component.set("v.paymentTypePicklist", paymentTypePicklist);
            }
        });
        $A.enqueueAction(modeofpayment);
        
        var fundingType = component.get("c.getFundingType");
        fundingType.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                var paymentTypePicklist = response.getReturnValue();
                component.set("v.fundingTypePicklist", paymentTypePicklist);
            }
        });
        $A.enqueueAction(fundingType);
    },
    fetchQuoteDetails: function(component, event, helper) {
        //alert('hello');
        //alert(component.get("v.recordId"));
    var action = component.get("c.fetchQuoteDetail"); // Get Apex action
    
    // Set the parameters for the Apex call
    action.setParams({
        QuoteId: component.get("v.recordId") // Get the QuoteId from the component
    });
    
    // Set the callback for the action
    action.setCallback(this, function(response) {
        //alert(response.getState());
        if (response.getState() === "SUCCESS") {
            var quoteDetails = response.getReturnValue(); // Store the return value in a variable
            component.set("v.Quote",quoteDetails);
            //alert('quoteDetails '+quoteDetails);
            // Now you can use the 'quoteDetails' to do something, like setting the component attributes
            console.log(quoteDetails);
        } else {
            // Handle errors if response state is not SUCCESS
            console.error("Error fetching quote details: " + response.getError());
        }
    });
    
    // Enqueue the action for execution
    $A.enqueueAction(action);
}
})