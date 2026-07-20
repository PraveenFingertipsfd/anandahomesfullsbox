@isTest
public class NumberTOWordConvertion_test {

    @isTest
    public static void convertsLargeNumber() {
        NumberTOWordConvertion nc = new NumberTOWordConvertion();
        String result = nc.getNumberTOWordConvertion(234456778);
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.length() > 0, 'Result should be non-empty');
    }

    @isTest
    public static void convertsZeroAndSmallValues() {
        NumberTOWordConvertion nc = new NumberTOWordConvertion();
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(0), 'Zero handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(1), 'One handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(99), 'Two-digit handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(100), 'Three-digit handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(1000), 'Four-digit handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(10000), 'Five-digit handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(100000), 'Six-digit handled');
        System.assertNotEquals(null, nc.getNumberTOWordConvertion(1000000), 'Seven-digit handled');
    }

    @isTest
    public static void convertsDecimalAmount() {
        NumberTOWordConvertion nc = new NumberTOWordConvertion();
        String result = nc.getNumberTOWordConvertion(1234.56);
        System.assertNotEquals(null, result, 'Decimal amount handled');
    }
}