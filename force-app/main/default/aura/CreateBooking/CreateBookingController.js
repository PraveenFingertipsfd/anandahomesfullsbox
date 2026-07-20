({
    doInit : function(component, event, helper) {
        //alert('hi');
        helper.fetchQuoteDetails(component, event, helper);
        helper.addAppliacantRecord(component, event, helper);
        helper.getBookingPicklists(component,event,helper);
        var action=component.get("c.convertUnit");
        action.setParams({'recId':  component.get('v.recordId')})
        // Updated 2026-04-10: Map Quote fields instead of Plot fields
        action.setCallback(this,function(response){
            var state = response.getState();
            if(state == "SUCCESS"){
                var qt = response.getReturnValue();
                if(qt != null){
                    var bk = component.get('v.plot') || {};
                    var today = $A.localizationService.formatDate(new Date(), "YYYY-MM-DD");

                    // Unit display fields from Quote
                    component.set('v.towerName', qt.Tower__c);
                    component.set('v.floorName', qt.Unit__r ? qt.Unit__r.Floor__c : '');
                    component.set('v.unitName', qt.Unit__r ? qt.Unit__r.Name : '');

                    // Booking fields from Quote
                    bk.Plot__c = qt.Unit__c;
                    bk.Project1__c = qt.Unit__r ? qt.Unit__r.Project__c : null;
                    bk.Block__c = qt.Unit__r ? qt.Unit__r.Block1__c : null;
                    bk.Block1__c = qt.Unit__r ? qt.Unit__r.Block__c : null;

                    // Charge fields from Quote
                    bk.Saleable_Area_Sft__c = qt.Saleable_Area_Sft__c;
                    bk.Price_per_sqft__c = qt.Price_Per_Sq_Ft__c;
                    bk.East_Facing_Charges__c = qt.East_Facing_Charges__c;
                    bk.Corner_Charges__c = qt.Corner_Charges__c;
                    bk.Floor_Rise_Charges_Rate__c = qt.Hi_Rise_Charges__c;
                    bk.Central_Court_Yard_Premium__c = qt.Central_Court_Yard_Premium__c;
                    bk.Meadow_Premium__c = qt.Meadow_Premium__c;
                    bk.Roadside_Premium__c = qt.Roadside_Premium__c;
                    bk.Court_Yard_Premium__c = qt.Court_Yard_Premium__c;
                    bk.Outer_Premium__c = qt.Outer_Premium__c;
                    bk.Amenities_Car_Parking__c = qt.Amenities_Car_Parking__c;
                    bk.Infrastructure_Charges__c = qt.Infrastructure_Charges__c;

                    bk.GST__c = qt.Unit__r ? qt.Unit__r.GST1__c : null;
                    bk.Booking_Amount1__c = (qt.Unit__r && qt.Unit__r.Project__r) ? qt.Unit__r.Project__r.Booking_Advance_Amount__c : null;
                    bk.Agreement_Percentage__c = 10;
                    bk.Date_of_Booking__c = today;

                    component.set('v.plot', bk);
                }
            }
        });
        $A.enqueueAction(action); 
    },
    closeModel: function(component, event, helper) {
        
        $A.get('e.force:closeQuickAction').fire();
        $A.get('e.force:refreshView').fire();
        
        
    },
    saveBooking : function(component, event, helper) {
        console.log('Test1');
        let isAllValid = component.find('field').reduce(function(isValidSoFar, inputCmp){
            inputCmp.showHelpMessageIfInvalid();
            return isValidSoFar && inputCmp.checkValidity();
        }, true);
        console.log('Test2');
        
        if(isAllValid) {
            var book = component.get("v.plot");
            var action = component.get("c.createBook");
            action.setParams({
                'bk': book,
                'recId': component.get('v.recordId'),
                'applicantList': component.get('v.applicantList')
            });
            console.log('Test3');
            
            action.setCallback(this, function(response) {
                var state = response.getState();
                 console.log('state'+state);
                if(state === 'SUCCESS') {
                    console.log('Test4');
                    var db = response.getReturnValue();
                    component.set('v.recordId', db);
                    
                    var navEvt = $A.get("e.force:navigateToSObject");
                    navEvt.setParams({
                        "recordId": db,
                        "slideDevName": "detail"
                    });
                    navEvt.fire();
                    
                    component.set('v.showNext', true);
                    
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        "type": 'Success',
                        "title": 'Success!',
                        "message": 'Booking and Co-Applicants processed successfully.',
                        "duration": 5000
                    });
                    toastEvent.fire();
                } 
                else if(state === 'ERROR') {
                    const errors = response.getError();
                    if (errors && errors[0] && errors[0].message) {
                        const fullErrorMessage = errors[0].message;
                        
                        // Extract relevant error message from full error message
                        const regex = /(?:first error:\s)(.*)/;
                        const match = fullErrorMessage.match(regex);
                        const errorMessage = match ? match[1] : "An unexpected error occurred.";
                        
                        // Show toast with formatted error message
                        var toastEvent = $A.get("e.force:showToast");
                        toastEvent.setParams({
                            "type": 'Error',
                            "title": 'Error!',
                            "message": errorMessage,
                            "duration": 5000
                        });
                        toastEvent.fire();
                        
                        console.log('Error: ' + errorMessage);
                    }
                }
            });
            
            $A.enqueueAction(action);
        }
    },
    /* gotoReceipt : function (component, event, helper) {
         var action=component.get("c.getPhotosNumber");
          action.setParams({
                'storeId' :component.get('v.bookingRecordId')
            });
        action.setCallback(this,function(response){
            if(response.getState() == "SUCCESS"){
                var acc = response.getReturnValue();
                if(acc >= 2){
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        "type":'Success',
                        "title": 'Success!',
                        "message":'Booking Files Submitted Successfully',
                        "duration":5000
                    });
                    toastEvent.fire();
                    //var navEvt = $A.get("e.force:navigateToSObject");
                    //navEvt.setParams({
                       // "recordId": component.get('v.bookingRecordId'),
                        //"slideDevName": "detail"
                    //});
                    //navEvt.fire(); 
                    component.set('v.showNext',false);
                    component.set('v.goToreceipt',true);
                }
                else{
                    var toastEvent = $A.get("e.force:showToast");
                    toastEvent.setParams({
                        "type":'Error',
                        "title": 'Error!',
                        "message":'Please Upload Booking Form and Scanned Quotation',
                        "duration":5000
                    });
                    toastEvent.fire();
                }
               
            }
        });
        $A.enqueueAction(action);		
    }*/
    addRow: function(component, event, helper) { 
        helper.addAppliacantRecord(component, event, helper);
    },
    removeRow : function(component, event, helper) {
        var selectedItem = event.currentTarget;
        var index = selectedItem.dataset.record;
        var aitems= component.get('v.applicantList');
        aitems.splice(index, 1);
        component.set("v.applicantList", aitems);
        
    },
    handleSelectedProjectIdChange: function(component, event, helper){
        var newSelectedId = event.getParam("value");
        console.log('Value changed to: ' + newSelectedId);
        var plot = component.get('v.plot');
        plot.Associated_Project__c = newSelectedId;
        component.set('v.plot',plot);
    },
    handleSelectedUnitIdChange: function(component, event, helper){
        var newSelectedId = event.getParam("value");
        console.log('unit Value changed to: ' + newSelectedId);
        var plot = component.get('v.plot');
        plot.Associated_Unit__c = newSelectedId;
        component.set('v.plot',plot);
    },
    handleSelectExisting: function(component, event, helper) {
        var selectedValue = component.get("v.plot.Existing_customer__c");
        var plot = component.get("v.plot");
        if (selectedValue !== "Yes") {
            plot.Associated_Unit__c = null;
            plot.Associated_Project__c = null;
            component.set("v.plot", plot);
        }
    },
    
    // ---- PAN: ABCDE1234F (5 letters, 4 digits, 1 letter)
    normalizePAN : function(component, event, helper){
        var src = event.getSource();
        var v = (src.get("v.value") || "").replace(/[^a-zA-Z0-9]/g,"").toUpperCase().slice(0,10);
        src.set("v.value", v);
    },
    
    // ---- PAN: ABCDE1234F (5 letters, 4 digits, 1 letter)
    normalizePAN : function(component, event, helper){
        var src = event.getSource();
        var v = (src.get("v.value") || "").replace(/[^a-zA-Z0-9]/g,"").toUpperCase().slice(0,10);
        src.set("v.value", v);
    },
    
    // ---- Passport: A1234567 (1 letter + 7 digits)
    normalizePassport : function(component, event, helper){
        var src = event.getSource();
        var v = (src.get("v.value") || "").toUpperCase().replace(/\s+/g,"").slice(0,8);
        // keep only first letter + digits after it
        v = v.replace(/[^A-Z0-9]/g,"");
        src.set("v.value", v);
    },
    
    // ---- Aadhaar: 12 digits, no spaces
    keepAadhaarDigits : function(component, event, helper){
        var src = event.getSource();
        var v = (src.get("v.value") || "").replace(/\D/g,"").slice(0,12);
        src.set("v.value", v);
    },
    
    // ---- Mobile (India): 10 digits, starts 6–9
    keepDigits10 : function(component, event, helper){
        var src = event.getSource();
        var v = (src.get("v.value") || "").replace(/\D/g,"").slice(0,10);
        src.set("v.value", v);
    },
    
    // ---- Generic: show “Invalid format” / required messages
    validateField : function(component, event, helper){
        var src = event.getSource ? event.getSource() : null;
        if (src) src.showHelpMessageIfInvalid();
    },
    
    // (Optional) call this before save to block submit if any are invalid
    validateBeforeSave : function(component){
        // add the aura:ids you want to enforce at submit
        var ids = ["mobile","pan","aadhar","passport","mobile2","pan2","aadhar2","passport2"];
        var allValid = true;
        ids.forEach(function(id){
            var c = component.find(id);
            if(!c) return;
            // find() returns array if duplicate ids exist
            var arr = Array.isArray(c) ? c : [c];
            arr.forEach(function(ctrl){
                ctrl.showHelpMessageIfInvalid();
                var v = ctrl.get("v.validity");
                if (v && !v.valid) allValid = false;
            });
        });
        return allValid;
    }

})