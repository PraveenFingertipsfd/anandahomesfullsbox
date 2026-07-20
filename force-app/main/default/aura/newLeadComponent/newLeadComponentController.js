({
    doInit : function(component, event, helper) {
        var pageRef = component.get("v.pageReference");
        //alert('pageRef');
        if (pageRef && pageRef.state) {
            var rtId = pageRef.state.c__recordTypeId || pageRef.state.recordTypeId;
            //alert(rtId);
            if (rtId) {
                component.set("v.recordTypeId", rtId);
            }
        }
        //alert('hiii doInit')
        helper.getPickListValue(component,event, helper);
        var userId = $A.get("$SObjectType.CurrentUser.Id");
        component.set('v.userId',userId);
        //alert(userId);
        
        var action = component.get("c.getCountryAndCode");
        //alert(action);
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                var countryMap = response.getReturnValue();
                component.set("v.sectionLabels", countryMap);
            }
            
        });
        $A.enqueueAction(action);
    },
    
    onCountryChange : function(component, event, helper) {
        //alert('hiiii');
        //var eventFields = event.getParam("fields");
        //var source = component.get("v.selectedCountry");
        
        var selectedCountryLabel = component.get("v.selectedCountry");
        var countryMap = component.get("v.sectionLabels");
        if (countryMap.hasOwnProperty(selectedCountryLabel)) {
            var selectedCountryCode = countryMap[selectedCountryLabel];
            component.set("v.selectedCountryCode", selectedCountryCode);
        } else {
            // Handle the case where the selected country label is not found
            console.error("Selected country label not found in the map");
        }
        
    },
    handleError: function (cmp, event, helper) {
        cmp.set("v.isSubmitting", false);
        cmp.set('v.spinner', false);

        // Get the error message
        var errorMessage = event.getParam("message");
        if(errorMessage=='The requested resource does not exist'){
            helper.toastMsg('error','Duplicate','Lead already exist in the system');
            history.back();
            return;
        }

        // Show any other server validation/DML error as a proper toast (no inline banner)
        helper.toastMsg('error', 'Error', helper.extractFormError(event));
    },
    handleSubmit : function(component, event, helper) {
        component.set("v.isSubmitting", true);
        component.set('v.spinner', true);
        event.preventDefault(); // Stop the form submission to handle it manually
        
        // Get the field values
        let phoneField = component.find("PhoneNumber");
        let secondaryPhoneField = component.find("secondaryPhoneNumber");
        
        // Get actual values
        let phoneValue = phoneField.get("v.value");
        let secondaryPhoneValue = secondaryPhoneField.get("v.value");

        // Validate phone numbers client-side (mirrors Lead__c Mobile_Number_Validation rule)
        var TEN_DIGITS = /^[0-9]{10}$/;
        var badPhone = phoneValue && !TEN_DIGITS.test(String(phoneValue));
        var badSecondary = secondaryPhoneValue && !TEN_DIGITS.test(String(secondaryPhoneValue));
        if (badPhone || badSecondary) {
            component.set("v.isSubmitting", false);
            component.set('v.spinner', false);
            helper.toastMsg('error', 'Invalid Phone Number',
                'Phone Number and Secondary Phone Number must contain exactly 10 digits and only numbers.');
            return;
        }

        // Get the event fields and add additional values
        var eventFields = event.getParam("fields");
        //eventFields["Lead_source__c"] = component.get('v.leadSource');
        let countryCode = component.get('v.selectedCountryCode');
        if (countryCode) {
            eventFields["Country_Code__c"] = countryCode;
        }
        
        // Optional: You can log the fields to verify
        console.log('Event Fields:', eventFields);
        
        // If you're submitting the form manually
        // Ensure 'myform' is the aura:id of your form component
        component.find('myform').submit(eventFields);
    },

    handleSuccess : function(component, event, helper) {
        component.set("v.isSubmitting", false);
        var record = event.getParam("response");
        console.log('handleSuccess '+ JSON.stringify(record));
        var apiName = record.apiName;
        var myRecordId = record.id; // ID of updated or created record
        component.set('v.spinner', false);
        
        helper.toastMsg('Success', 'Success', 'Lead created successfully');
        
        // Navigate to the record page
        var navEvt = $A.get("e.force:navigateToSObject");
        navEvt.setParams({
            "recordId": myRecordId,
            "slideDevName": "detail"
        });
        navEvt.fire();
    },
    
    /*handleError : function(component, event, helper) {
        component.set("v.isSubmitting", false);
        component.set('v.spinner', false);
        
        // Get error details
        var errorMessage = "An error occurred while processing the request. ";
        var errors = event.getParam("error");
        
        // Check if the error contains a message
        if (errors && errors.message) {
            errorMessage += errors.message;
        } else if (errors && errors.body && errors.body.message) {
            errorMessage += errors.body.message;
        }
        
        // Show error message in a toast
        helper.toastMsg('Error', 'Error', errorMessage);
    },*/
    
    
    openModel: function(component, event, helper) {
        // Set isModalOpen attribute to true
        component.set("v.isModalOpen", true);
    },
    
    closeModel: function(component, event, helper) {
        // Set isModalOpen attribute to false  
        //  component.set("v.isModalOpen", false);
        // history.back();   
        var homeEvt = $A.get("e.force:navigateToObjectHome");
        homeEvt.setParams({
            "scope": "Lead__c"
        });
        homeEvt.fire();
        var dismissActionPanel = $A.get("e.force:closeQuickAction");
        dismissActionPanel.fire();
    },
    searchText : function(component, event, helper) {
        var accounts= component.get('v.accounts');
        var searchText= component.get('v.searchText');
        
        var matchaccounts=[];
        if(searchText !=''){
            
            for(var i=0;i<accounts.length; i++){ 
                if(accounts[i].toLowerCase().indexOf(searchText.toLowerCase())  != -1  ){
                    
                    if(matchaccounts.length <50){
                        matchaccounts.push( accounts[i] );
                    }else{
                        break;
                    }
                    
                } 
            } 
            if(matchaccounts.length >0){
                component.set('v.matchaccounts',matchaccounts);
            }
        }else{
            component.set('v.matchaccounts',[]);
            component.set('v.allocatedProject','');
        }
    },
    update: function(component, event, helper) {
        
        component.set('v.allocatedProject', event.currentTarget.dataset.id);
        var edi = component.get('v.allocatedProject');
        //alert(JSON.stringify(edi))
        var accounts= component.get('v.matchaccounts');
        for(var i=0;i<accounts.length; i++){ 
            if(accounts[i] ===  edi ){
                component.set('v.searchText', accounts[i]);
                component.set('v.allocatedProject', accounts[i]);
                
                break;
            } 
        } 
        
        component.set('v.matchaccounts',[]);
        
    },
    handleUnitChange: function(component, event, helper) {
        var selectedUnitId = component.find("unitLookupField").get("v.value");
        if(selectedUnitId) {
            helper.retrieveUnitData(component, selectedUnitId);
        }
    },
    handleCountryChange: function(component, event, helper) {
        var selectedUnitId = component.find("CountryLookupField").get("v.value");
        var countryMap = component.get("v.sectionLabels");
        console.log(JSON.stringify(countryMap));
        var selectedCountryCode = countryMap[selectedUnitId];
        component.set("v.selectedCountryCode", selectedCountryCode);
        
    },
    onselectProjectValue: function(component, event, helper) {
        var selectedUnitId = component.get("v.projectName");
        alert(selectedUnitId);
        
    },
    isChannelPartner: function(component, event, helper) {
        var eventFields = event.getParam("fields");
        var source = component.get("v.leadSource");
        if(source == "CP"){
            component.set('v.isChannelPartner',true);
        }
        else{
            component.set('v.isChannelPartner',false);
        }
        
    },
    countrymap : function(component, event, helper) {
        var action = component.get("c.getCountryAndCode");
        action.setCallback(this, function(response) {
            var state = response.getState();
            if (state === "SUCCESS") {
                component.set("v.countryMap", response.getReturnValue());
            }
        });
        $A.enqueueAction(action);
    },
    
    onCountryChange : function(component, event, helper) {
        var selectedCountry = component.find("countrySelect").get("v.value");
        var countryMap = component.get("v.countryMap");
        var selectedCountryCode = countryMap[selectedCountry];
        // Set the selected country code to the corresponding attribute
        component.set("v.selectedCountryCode", selectedCountryCode);
    },
    handlePhoneChange : function(component, event, helper) {
        var phoneNumber = component.find("PhoneNumber").get("v.value");
        
        var projname = component.find("projectname").get("v.value");
        var phoneNumberLength = phoneNumber.length;
        if (phoneNumber.length === 10) {
            var action = component.get("c.checkPhoneNumberExistence");
            action.setParams({
                phoneNumber : phoneNumber,
                projectName : projname,
            });
            action.setCallback(this, function(response) {
                var state = response.getState();
                if (state === "SUCCESS") {
                    var existsInSystem = response.getReturnValue();
                    if (existsInSystem!='not found') {
                        helper.toastMsg('error','Duplicate',existsInSystem);
                        
                    } else {
                        
                    }
                } else {
                    console.error("Error calling Apex method: " + state);
                }
            });
            $A.enqueueAction(action);
        }
        
    },
    
    handlesecondPhoneChange : function(component, event, helper) {
        var phoneNumber = component.find("seconfPhoneNumber").get("v.value");
        
        var projname = component.find("projectname").get("v.value");
        var phoneNumberLength = phoneNumber.length;
        if (phoneNumber.length === 10) {
            var action = component.get("c.checkPhoneNumberExistence");
            action.setParams({
                phoneNumber : phoneNumber,
                projectName : projname,
            });
            action.setCallback(this, function(response) {
                var state = response.getState();
                if (state === "SUCCESS") {
                    var existsInSystem = response.getReturnValue();
                    if (existsInSystem!='not found') {
                        helper.toastMsg('error','Duplicate',existsInSystem);
                        
                    } else {
                        
                    }
                } else {
                    console.error("Error calling Apex method: " + state);
                }
            });
            $A.enqueueAction(action);
        }
        
    },
    handleEmailChange: function(component, event, helper) {
        var email = component.find("email").get("v.value");
        var emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        var isValidEmail = emailRegex.test(email);
        var projname = component.find("projectname").get("v.value");
        
        if (isValidEmail) {
            //alert('Valid')
            
            var action = component.get("c.checkEmailExistence");
            action.setParams({
                email : email,
                projectName : projname,
            });
            action.setCallback(this, function(response) {
                var state = response.getState();
                if (state === "SUCCESS") {
                    var existsInSystem = response.getReturnValue();
                    if (existsInSystem!='not found') {
                        helper.toastMsg('error','Duplicate',existsInSystem);
                        
                    } else {
                        
                    }
                } else {
                    console.error("Error calling Apex method: " + state);
                }
            });
            $A.enqueueAction(action);
        } else {
            // Invalid email format
            console.log("Email is not in correct format");
        }
    }
})