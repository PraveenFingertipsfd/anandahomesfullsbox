@IsTest
private class ForgotPasswordController_OldTest {

    @IsTest
    static void forgotPassword_returnsNull_whenSiteRejects() {
        Test.startTest();
        ForgotPasswordController_Old ctrl = new ForgotPasswordController_Old();
        ctrl.username = 'test@fingertipplus.com';
        PageReference result = ctrl.forgotPassword();
        Test.stopTest();

        // Site.forgotPassword() returns false in test context,
        // so we exercise the constructor, setter, Site call,
        // setRedirect, the if-condition, and the `return null` path.
        System.assertEquals(null, result,
            'Expected null because Site.forgotPassword() returns false in tests');
    }
}