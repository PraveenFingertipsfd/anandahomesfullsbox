/**
 * Tests for ChangePasswordController_Old, the legacy change-password page controller.
 */
@IsTest public with sharing class ChangePasswordController_OldTest {
    @IsTest static void testChangePasswordController() {
        // Instantiate the legacy controller and populate the page properties.
        ChangePasswordController_Old controller = new ChangePasswordController_Old();
        controller.oldPassword = '123456';
        controller.verifyNewPassword = 'qwerty1';

        // changePassword() is a no-op in the legacy controller and always returns null.
        System.assertEquals(null, controller.changePassword(),
            'Legacy changePassword() should return null');
    }
}