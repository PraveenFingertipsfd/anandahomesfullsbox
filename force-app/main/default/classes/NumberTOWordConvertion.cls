public class NumberTOWordConvertion {
 private static final String[] ONES = new String[]{ '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 
                                                      'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 
                                                      'Eighteen', 'Nineteen' };
    
    private static final String[] TENS = new String[]{ '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety' };
    
    private static final String[] UNITS = new String[]{ 'Crore', 'Lakh', 'Thousand', 'Hundred', '' };

    private static final Integer[] UNIT_VALUES = new Integer[]{ 10000000, 100000, 1000, 100, 1 };

    public String getNumberTOWordConvertion(Decimal amount) {
        // Handle rupees and paise separately
        Long rupeesPart = amount.setScale(0).longValue();
        Long paisePart = ((amount - amount.setScale(0)) * 100).setScale(0).longValue();
        
        String rupeesInWords = convertNumToWords(rupeesPart);
        String paiseInWords = convertNumToWords(paisePart);
        
        if (rupeesPart == 0 && paisePart == 0) {
            return 'Zero Only';
        }

        String result = '';

        if (rupeesPart > 0) {
            result += rupeesInWords;
        }
        
        if (paisePart > 0) {
            result += (rupeesPart > 0 ? ' and ' : '') + paiseInWords + ' Paise';
        }
		result += ' Only';
        return result.trim();
    }

    private static String convertNumToWords(Long num) {
        if (num == 0) {
            return '';
        }

        String words = '';

        for (Integer i = 0; i < UNITS.size(); i++) {
            Integer unitValue = UNIT_VALUES[i];
            Long currentValue = Math.floor(num / unitValue).longValue();
            if (currentValue > 0) {
                words += getWordForThreeDigitNum(currentValue) + ' ' + UNITS[i] + ' ';
                num = Math.mod(num, unitValue);  // Replacing '%' with Math.mod()
            }
        }

        return words.trim();
    }

    private static String getWordForThreeDigitNum(Long num) {
        String result = '';

        if (num >= 100) {
            result += ONES[Math.floor(num / 100).intValue()] + ' Hundred ';
            num = Math.mod(num, 100);  // Replacing '%' with Math.mod()
        }

        if (num > 0) {
            if (num < 20) {
                result += ONES[num.intValue()] + ' ';
            } else {
                result += TENS[Math.floor(num / 10).intValue()] + ' ' + ONES[Math.mod(num, 10).intValue()] + ' ';
            }
        }

        return result.trim();
    }
}