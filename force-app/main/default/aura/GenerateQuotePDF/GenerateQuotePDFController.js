({
    doInit : function(component, event, helper) {
        var action=component.get("c.getQuoteData");
        var recordId = component.get('v.recordId');
        console.log('recordId '+recordId);
        action.setParams({'recordId':  recordId })
        action.setCallback(this,function(response){
            var state = response.getState();
            if(state == "SUCCESS" ){
                var result = response.getReturnValue();
                console.log('result '+JSON.stringify(result));
                var customerName = (result.CLead__r && result.CLead__r.Salutation__c ? result.CLead__r.Salutation__c + ' ' : '') + (result.CLead__r && result.CLead__r.Name__c ? result.CLead__r.Name__c : result.Lead_Name__c);
                var salesExecutiveName = result.Owner.Name;
                var salesExecutiveEmail = result.Owner.Email || '';
                var salesExecutivePhone = result.Owner.Phone || '';
                var encryptedId = result.Encrypted_Key__c;
                var customerEmail = (result.CLead__r && result.CLead__r.Email__c) ? result.CLead__r.Email__c : result.Lead_Email__c;
                var project = result.Project1__r ? result.Project1__r.Name : '';
                var unitName = result.Unit__r ? result.Unit__r.Name : '';
                var projectCompany = result.Project_Company__c;
                var ApplyDiscount = result.Apply_Discount__c;
                var MangerApprovalStatus = result.Manager_Approval_Status__c;
                var DiscountApprovalStatus = result.Discount_Approval_Status__c;
                
                if(result.Discount_Approval_Status__c != 'Pending' && result.Discount_Approval_Status__c != 'Rejected' && result.Manager_Approval_Status__c != 'Pending' && result.Manager_Approval_Status__c != 'Rejected'){
                    component.set("v.ApplyDiscount",false);
                }
                else {
                    component.set("v.ApplyDiscount",true);
                }
                component.set("v.ownerEmail", salesExecutiveEmail);
                component.set("v.ownerPhone", salesExecutivePhone);
                component.set("v.ownerName", salesExecutiveName);
                component.set("v.customerEmail", customerEmail);
                
                var defaultEmailContent = "<div style='color: black;'>Dear " + customerName + ",</div><br/>";
                defaultEmailContent += "<div style='color: black;'>Thank you for choosing <strong>Ananda Homes</strong>.</div><br/>";
                defaultEmailContent += "<div style='color: black;'>We are pleased to share the cost sheet for Unit: <strong>" + project + " " + unitName + "</strong> for your review. Please find the details attached for your reference.</div><br/>";
                defaultEmailContent += "<div style='color: black;'>If you have any questions or need further assistance, feel free to get in touch with your sales executive. We're here to help you every step of the way.</div><br/>";
                defaultEmailContent += "<div style='color: black;'>Warm regards,</div>";
                defaultEmailContent += "<div style='color: black;'><strong>" + salesExecutiveName + "</strong></div>";
                defaultEmailContent += "<div style='color: black;'>" + salesExecutiveEmail + "</div>";
                if (salesExecutivePhone) {
                    defaultEmailContent += "<div style='color: black;'>" + salesExecutivePhone + "</div>";
                }
                
                component.set("v.emailContent", defaultEmailContent);
                var project = result.Project1__r ? result.Project1__r.Name : '';
                var projectNorm = project.trim().toLowerCase();
                var vfpage;
                if (projectNorm === 'the legacey') {
                    vfpage = '/apex/COST_SHEET_TL?Id=' + recordId;
                }
                if (!vfpage) {
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        "type": "error",
                        "title": "Error!",
                        "message": "Cost Sheet is not configured for project: " + project
                    });
                    toastEvent.fire();
                    $A.get("e.force:closeQuickAction").fire();
                    return;
                }
                component.set('v.vfPage', vfpage);
                component.set('v.showPdf', true);
            }
        });
        $A.enqueueAction(action); 
    },
    sendEmail: function(component, event, helper) {
        console.log('start');
        var allFiles = component.get('v.files');
        var contentDocumentIds = component.get('v.filesIDS');
        var modifiedEmailContent = component.get("v.emailContent");
        var ownerName = component.get("v.ownerName");
        var ownerPhone = component.get("v.ownerPhone");
        var ownerEmail = component.get("v.ownerEmail");
        var customerEmail = component.get("v.customerEmail");
        var toAddresses = [];
        
        if (customerEmail) {
            toAddresses.push(customerEmail);
        }
        if (toAddresses.length === 0) {
            var toastEvent = $A.get("e.force:showToast");
            toastEvent.setParams({
                "title": "Error!",
                "message": "No email address available to send the email.",
                "type": "error"
            });
            toastEvent.fire();
            return;
        }
        var action = component.get("c.sendEmailtoCustomer");
        action.setParams({
            "recordId": component.get("v.recordId"),
            "emailContent": modifiedEmailContent,
            "contentIds": contentDocumentIds
        });
        
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                console.log('finish');
                var toastEvent = $A.get("e.force:showToast");
                toastEvent.setParams({
                    "title": "Success!",
                    "message": "Email Sent Successfully.",
                    "type": "success"
                });
                toastEvent.fire();
                
                var dismissActionPanel = $A.get("e.force:closeQuickAction");
                dismissActionPanel.fire();
            } else {
                console.log('finish');
                console.error("Error sending email");
            }
        });
        
        $A.enqueueAction(action);
    },
    close : function(component, event, helper) {
        $A.get("e.force:closeQuickAction").fire();
    },
})