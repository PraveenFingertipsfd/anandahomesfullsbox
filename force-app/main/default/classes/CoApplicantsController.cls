public class CoApplicantsController {
    public Id BookingId { get; set; }
    public List<Co_Applicant__c> coApplicants { get; set; }
    
    public CoApplicantsController(ApexPages.StandardController stdController) {
        
        BookingId = (Id)stdController.getId();
        coApplicants = [SELECT Salutation__c, Name,Relalation_Details__c,W_o_S_o_C_o_c__c FROM Co_Applicant__c WHERE Booking__c = :BookingId];
        
    }

}