/**
 * Tests for MyProfilePageController_Old, the legacy portal-user profile page controller.
 */
@IsTest public with sharing class MyProfilePageController_OldTest {
    @IsTest static void testProfileLifecycle() {
        // The running test user is never a GUEST, so the constructor loads successfully.
        MyProfilePageController_Old controller = new MyProfilePageController_Old();

        System.assertEquals(UserInfo.getUserId(), controller.getUser().Id,
            'Controller should load the current user');
        System.assertEquals(false, controller.getIsEdit(), 'isEdit should default to false');

        controller.edit();
        System.assertEquals(true, controller.getIsEdit(), 'edit() should enable edit mode');

        controller.cancel();
        System.assertEquals(false, controller.getIsEdit(), 'cancel() should disable edit mode');

        // changePassword() is a no-op in the legacy controller and returns null.
        System.assertEquals(null, controller.changePassword(),
            'Legacy changePassword() should return null');

        // Exercise the save() path by updating a harmless field on the current user.
        String randFax = Math.rint(Math.random() * 1000) + '5551234';
        controller.getUser().Fax = randFax;
        controller.save();
        System.assertEquals(false, controller.getIsEdit(), 'save() should exit edit mode');

        User refreshed = [SELECT Id, Fax FROM User WHERE Id = :UserInfo.getUserId()];
        System.assertEquals(randFax, refreshed.Fax, 'save() should persist the updated field');
    }
}