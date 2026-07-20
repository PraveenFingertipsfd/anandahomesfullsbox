public class Cost_SheetController {
    
    public String FloorNumber { get; set; }
    public Double otherCharges { get; set; }
    public Double FloorRiseCharges { get; set; }
    public Double PremiumCharges { get; set; }
     public Double PricePerSqFt { get; set; }
    
    public Cost_SheetController(ApexPages.StandardController stdController) {
        Id bookingId = (Id)stdController.getId();
        Booking__c booking = [SELECT Date_of_Booking__c, Price_per_sqft__c,FloorNo__c,Floor_Rise_Charges_Rate__c,Premium_Charge__c,Other_Charges__c, Super_Built_up_area_NE__c,
                              Booking_Amount1__c, Maintenance_Charge__c 
                              FROM Booking__c 
                              WHERE Id = :bookingId LIMIT 1];
        
        // Handling Floor number conversion
        if (booking.FloorNo__c != null) {
            if(booking.FloorNo__c.isNumeric()){
                FloorNumber = convertToWords(Integer.valueOf(booking.FloorNo__c));
            } else {
                if(booking.FloorNo__c == 'G'){
                    FloorNumber = ' Ground Floor ';
                }else{
                    FloorNumber = booking.FloorNo__c + ' th Floor';
                }
                
            }
        }
        
        // Calculate the other charges, floor rise charges, and premium charges
        if (booking.Super_Built_up_area_NE__c != null) {
            Double superBuiltUpArea = booking.Super_Built_up_area_NE__c;
            
            // Multiplying the respective fields with Super_Built_up_area_NE__c
            if (booking.Other_Charges__c != null) {
                otherCharges = booking.Other_Charges__c * superBuiltUpArea;
            }
            if (booking.Floor_Rise_Charges_Rate__c != null) {
                FloorRiseCharges = booking.Floor_Rise_Charges_Rate__c * superBuiltUpArea;
            }
            if (booking.Premium_Charge__c != null) {
                PremiumCharges = booking.Premium_Charge__c * superBuiltUpArea;
            }
            if (booking.Price_per_sqft__c != null) {
                PricePerSqFt = booking.Price_per_sqft__c * superBuiltUpArea;
            }
        }
    }
    
    
    private String convertToWords(Integer fNumber) {
        if (fNumber == null) {
            return '';
        }
        
        list<String> units = new List<String>{ '', 'First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth', 'Ninth' };
            list<String> teens = new List<String>{ 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen' };
                list<String> tens = new List<String>{ '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety' };
                    list<String> hundred = new List<String> { '', 'Hundred' };
                        
                        String numberStr = String.valueOf(fNumber);
        Integer length = numberStr.length();
        
        String result = '';
        if(length == 2){
            Integer secondPart = Integer.valueOf(numberStr.substring(0, 2));
            if (secondPart >= 10 && secondPart < 20) {
                result += teens[secondPart - 10];
                result += 'th';
            }else if (secondPart >= 20){
                Integer secondFirst = Integer.valueOf(numberStr.substring(0, 1));
                Integer secondLast = Integer.valueOf(numberStr.substring(1, 2));
                result += tens[secondFirst];
                if(secondLast > 0){
                    result += ' '+units[secondLast];
                }
            }
        }else{
            Integer firstPart = Integer.valueOf(numberStr.substring(0, 1));
            if (firstPart > 0) {
                result += units[firstPart];
            } 
        }
         result += ' Floor';
        return result.trim().replaceAll(' +', ' ');
    }
}