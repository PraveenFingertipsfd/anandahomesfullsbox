public class ContactFormatter {
    
    public static string getformated(string mobileoremail){   
        if(  mobileoremail == null){
            return ''; 
        }
        return mobileoremail;
    }
    public static List<string> geAllPhoneNumbers(string phones){   
        if(phones == null ){
            return new list<string>();
        }
        List<string> allphones = phones.split(',');   
        return allphones;
    }

}