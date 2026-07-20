/**
 * Tests for SiteLoginController_old, the legacy site login page controller.
 */
@IsTest global with sharing class SiteLoginController_oldTest {
    @IsTest global static void testSiteLoginController() {
        SiteLoginController_old controller = new SiteLoginController_old();
        controller.username = 'test@salesforce.com';
        controller.password = '123456';

        // Site.login() returns null when invoked outside a live Site request.
        System.assertEquals(null, controller.login(),
            'Legacy login() should return null outside a Site context');
    }
}