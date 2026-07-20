({
    
    doInit: function(component, event, helper) {
    // Fetch Lead details first
    //helper.fetchLeadDetails(component, event, helper);
     var recordId = component.get("v.recordId");
    // ---- Fetch all picklist values at once ----
    var picklistAction = component.get("c.getAllPicklistValues");

    //  Pass all required objects and fields (including your previously commented ones)
    picklistAction.setParams({
        "objectFieldMap": {
            "Lead__c": ["Allocated_Project__c"],
            "Plot__c": [
                "BHK_Type__c",
                "Floor__c",
                "Property_Type__c",
                "Unit_Facing_Direction__c",
                "Building__c",
                "Block__c"
            ]
        },
        'recordId': recordId
    });

    picklistAction.setCallback(this, function(response) {
        if (response.getState() === "SUCCESS") {
            var data = response.getReturnValue().fieldPicklists;
            console.log('All Picklists:', JSON.stringify(data));
            var LeadList = response.getReturnValue().leadRecord;
              console.log('LeadList',LeadList);
            var paymentTypePicklist = response.getReturnValue().paymentTypePicklist;
                console.log('paymentTypePicklist',paymentTypePicklist);
             var plotList = response.getReturnValue().plotList;
             console.log('plotList',plotList);
            
            if(LeadList){
                component.set('v.allocatedProjectValue1', LeadList.Allocated_Project__c);
                console.log('Allocated Project Value:', LeadList.Allocated_Project__c);
                console.log('Allocated Project Value (from attribute):', component.get('v.allocatedProjectValue1'));

                //component.set('v.preSaleUser',LeadList.Owner.Name);
                 //component.set('v.preSaleUser',LeadList.Old_Owner_Name__r.Name);
                component.set('v.relatoinshipManager',LeadList.Relationship_Manager__c);
            }
             if (paymentTypePicklist) {
                component.set("v.paymentTypePicklist",paymentTypePicklist);
            }
            
             if (plotList) {
                component.set("v.plots",plotList);
            }


            // Set each picklist in component attributes
            component.set("v.projectlist", data['Allocated_Project__c']);
            component.set("v.BHKList", data['BHK_Type__c']);
            component.set("v.floorList", data['Floor__c']);
            component.set("v.propertytype", data['Property_Type__c']);
            //component.set("v.UFList", data['Unit_Facing_Direction__c']);
            //component.set("v.BuildingList", data['Building__c']);
            //component.set("v.BlockList", data['Block__c']);
        } else {
            console.error('Error fetching picklists:', response.getError());
        }
    });

    $A.enqueueAction(picklistAction);

    // ---- Fetch projects with completed site visits for this lead ----
    var visitedAction = component.get("c.getVisitedProjects");
    visitedAction.setParams({ "recordId": recordId });
    visitedAction.setCallback(this, function(response) {
        if (response.getState() === "SUCCESS") {
            var visited = response.getReturnValue() || [];
            component.set("v.visitedProjects", visited);
            var allocated = component.get("v.allocatedProjectValue1");
            if (allocated && visited.indexOf(allocated) === -1) {
                // Allocated project has no completed site visit — clear preselection and prefetched plots
                component.set("v.allocatedProjectValue1", "");
                component.set("v.plots", []);
            }
        } else {
            console.error("Error fetching visited projects:", response.getError());
        }
    });
    $A.enqueueAction(visitedAction);

    // ---- Fetch discount config (Quote_Discount_Config__mdt) ----
    var discountAction = component.get("c.getDiscountConfig");
    discountAction.setCallback(this, function(response) {
        if (response.getState() === "SUCCESS") {
            var rows = response.getReturnValue() || [];
            component.set("v.discountConfig", rows);
            var options = rows.map(function(r){
                return { label: r.label, value: r.quoteField };
            });
            component.set("v.discountOptions", options);
        } else {
            console.error("Error fetching discount config:", response.getError());
        }
    });
    $A.enqueueAction(discountAction);

    // ---- Set Columns ----
    component.set('v.mycolumns3', [
        {label: 'Sl No.', fieldName: 'S_No__c', type: 'text', initialWidth: 10},
        {label: 'Name', fieldName: 'Name', type: 'text'},
        {label: 'Payment Percent', fieldName: 'Payment_percent__c', type: 'Percent', initialWidth: 15},
        {
            label: 'Completed Date',
            fieldName: 'Completed_Date__c',
            type: 'date',
            typeAttributes: {
                day: 'numeric',
                month: 'short',
                year: 'numeric'
            },
            initialWidth: 115
        }
    ]);
},

            searchText1 : function(component, event, helper) {
            var plot= component.get('v.plots');
            
            var searchText1= component.get('v.searchText1');
            console.log(searchText1.length)
            //var open = component.find("open");
            if(searchText1.length < 1){
            console.log(searchText1)
            //$A.util.toggleClass(open, 'slds-is-open');
            }
            var matchplots=[];
                      if(searchText1 !=''){
            for(var i=0;i<plot.length; i++){ 
                // console.log(plot[i].Name)
                if(plot[i].Name.toLowerCase().indexOf(searchText1.toLowerCase())  != -1  ){
                    
                    if(matchplots.length <50){
                        matchplots.push( plot[i] );
                    }
                    else{
                        break;
                    }
                } 
            } 
            // alert(matchplots)
            if(matchplots.length >0){
                component.set('v.matchplots',matchplots);
                // component.set('v.showqute',true);
            }
        }
        else{
            component.set('v.matchplots',[]);
            component.set('v.showqute',false);
        }
    },
    
    searchText2 : function(component, event, helper) {
        var pymntp= component.get('v.paymentplan');
        
        var searchText= component.get('v.searchText2');
        console.log(searchText.length)
        
        if(searchText.length < 1){
            console.log(searchText)
            //$A.util.toggleClass(open, 'slds-is-open');
        }
        var matchpaymentplan=[];
        if(searchText !=''){
            for(var i=0;i<pymntp.length; i++){ 
                if(pymntp[i].Name.toLowerCase().indexOf(searchText.toLowerCase())  != -1  ){
                    
                    if(matchpaymentplan.length <50){
                        matchpaymentplan.push( pymntp[i] );
                    }
                    else{
                        break;
                    }
                } 
            } 
            // alert(matchpaymentplan)
            if(matchpaymentplan.length >0){
                component.set('v.matchpaymentplan',matchpaymentplan);
                // component.set('v.showqute',true);
            }
        }
        else{
            component.set('v.matchpaymentplan',[]);
            component.set('v.showqute',true);
            
            var selectedValue = component.find("projectSelect").get("v.value");
            // alert(selectedValue);
            
            // getting Payment Plan
            
            var action4=component.get("c.getPyamentPlan");  
            
            action4.setParams({'project':selectedValue});
            action4.setCallback(this,function(response){
                
                if(response.getState()=="SUCCESS"){ 
                    var pymnpln = response.getReturnValue();
                    
                    component.set("v.paymentplan",pymnpln);
                }
            });
            $A.enqueueAction(action4);
            
            
        }
    },
    
    update1: function(component, event, helper) {
    //alert('hii');
    console.log('in Update');
    // component.set('v.prjId', event.currentTarget.dataset.id);
    //  alert('Update 1'); 
    var edi =  event.currentTarget.dataset.id;
    console.log('in Update 1');
    var plt= component.get('v.matchplots');
    console.log('in Update 2');
    var selPlot= component.get('v.plot');
    console.log('in Update 3');
    var oppPlot = component.get('v.oppPlot');
    // alert('oppPlot',JSON.stringify(component.get('v.oppPlot')));
     console.log('oppPlot',JSON.stringify(component.get('v.oppPlot')));
    var opp = component.get("v.OppRecord");
    console.log('in Update 4');
    var today = $A.localizationService.formatDate(new Date(), "YYYY-MM-DD");
    console.log('in Update 5');
    for(var i=0;i<plt.length; i++){  
        console.log('edi >> '+edi + 'PltId >> '+plt[i].Id);
        
        if(plt[i].Id ===  edi ){
            console.log('innn');
            //alert('Update 2 ');
            component.set('v.searchText1', plt[i].Name);
            selPlot = plt[i];
            component.set('v.showqute',true);
            oppPlot.CLead__c=component.get('v.recordId');
            oppPlot.Unit__c = plt[i].Id;
            oppPlot.Project__c = plt[i].Project__r ? plt[i].Project__r.Project__c : null;
            oppPlot.Quote_Date__c =today;
            oppPlot.Project1__c = plt[i].Project__c;
            oppPlot.Plot_Number__c = plt[i].Plot_Number__c;
            oppPlot.Facing__c = plt[i].Unit_Facing_Direction__c;
            oppPlot.BHK_Type__c = plt[i].BHK_Type__c;
            oppPlot.Unit_Type__c = plt[i].Plot_Type__c;
            oppPlot.Tower__c = plt[i].Block1__c;
            
            oppPlot.UDS_Area__c = plt[i].UDS__c;
            oppPlot.Super_Built_UpArea__c = plt[i].Super_built_up_area__c;
            oppPlot.Carpet_Area__c = plt[i].Carpet_Area__c;
            oppPlot.Balcony_Area__c = plt[i].Balcony_Area__c;
            oppPlot.Premium_Status__c = plt[i].Premium_Status__c;
            oppPlot.Common_Area_Allotted_to_Association__c = plt[i].Common_Area_Allotted_to_Association__c;
            oppPlot.Category__c  = plt[i].Category__c;
            oppPlot.Flat_Number__c = plt[i].Plot_Number__c;

            oppPlot.Price_Per_Sq_Ft__c = plt[i].Price_Per_Sq_Ft__c;
            oppPlot.Solar_Charges__c = plt[i].Solar_Charges__c;
            oppPlot.Other_Charges__c = plt[i].Other_Charges__c;
            oppPlot.Floor_Rise__c = plt[i].Floor_Rise__c;
            oppPlot.Premium_Charge__c = plt[i].Premium_Charge__c;
            oppPlot.Covered_Park_Parking__c = plt[i].Covered_Park_Parking__c;
            oppPlot.Extra_Covered_Car_Parking_Charges__c = 0;
            oppPlot.GST1__c = plt[i].GST1__c;
            oppPlot.Floor__c = plt[i].Floor__c;

            // New cost sheet fields
            oppPlot.Saleable_Area_Sft__c = plt[i].Saleable_Area_Sft__c;
            oppPlot.East_Facing_Charges__c = plt[i].East_Facing_Charges__c;
            oppPlot.Corner_Charges__c = plt[i].Corner_Charges__c;
            oppPlot.Hi_Rise_Charges__c = plt[i].Hi_Rise_Charges__c;
            oppPlot.Central_Court_Yard_Premium__c = plt[i].Central_Court_Yard_Premium__c;
            oppPlot.Meadow_Premium__c = plt[i].Meadow_Premium__c;
            oppPlot.Roadside_Premium__c = plt[i].Roadside_Premium__c;
            oppPlot.Court_Yard_Premium__c = plt[i].Court_Yard_Premium__c;
            oppPlot.Outer_Premium__c = plt[i].Outer_Premium__c;
            oppPlot.Amenities_Car_Parking__c = plt[i].Amenities_Car_Parking__c;
            oppPlot.Infrastructure_Charges__c = plt[i].Infrastructure_Charges__c;

            // Reset all discount fields and snapshot original charge rates
            var discountConfig = component.get('v.discountConfig') || [];
            var originals = {};
            for (var d = 0; d < discountConfig.length; d++) {
                var cfg = discountConfig[d];
                var origVal = parseFloat(oppPlot[cfg.unitField]) || 0;
                originals[cfg.unitField] = origVal;
                // Net on Quote starts at the original Plot rate; discount starts at 0.
                oppPlot[cfg.quoteField] = origVal;
                if (cfg.discountField) {
                    oppPlot[cfg.discountField] = 0;
                }
            }
            component.set('v.originalCharges', originals);
            component.set('v.selectedDiscounts', []);
            component.set('v.visibleDiscountRows', []);
            oppPlot.Apply_Discount__c = false;
            oppPlot.Additional_Car_Parking_Required__c = false;
            oppPlot.Payment_Type__c = 'Standard';
            oppPlot.New_Lead__c = component.get('v.recordId');
            oppPlot.Pre_Sale_User_Name__c = component.get('v.preSaleUser');
            oppPlot.Relationship_Manager__c = component.get('v.relatoinshipManager');

            component.set('v.blockName', plt[i].Block__c);
            component.set('v.towerName', plt[i].Block1__r ? plt[i].Block1__r.Name : '');

            // Cost sheet calculation
            var saleableArea = parseFloat(oppPlot.Saleable_Area_Sft__c) || 0;
            var pricePerSqFt = parseFloat(oppPlot.Price_Per_Sq_Ft__c) || 0;
            var gstPercentage = parseFloat(oppPlot.GST1__c) || 0;

            var basicPrice = saleableArea * pricePerSqFt;
            var eastFacing = (parseFloat(oppPlot.East_Facing_Charges__c) || 0) * saleableArea;
            var corner = (parseFloat(oppPlot.Corner_Charges__c) || 0) * saleableArea;
            var hiRise = (parseFloat(oppPlot.Hi_Rise_Charges__c) || 0) * saleableArea;
            var centralCourtYard = (parseFloat(oppPlot.Central_Court_Yard_Premium__c) || 0) * saleableArea;
            var meadow = (parseFloat(oppPlot.Meadow_Premium__c) || 0) * saleableArea;
            var roadside = (parseFloat(oppPlot.Roadside_Premium__c) || 0) * saleableArea;
            var courtYard = (parseFloat(oppPlot.Court_Yard_Premium__c) || 0) * saleableArea;
            var outer = (parseFloat(oppPlot.Outer_Premium__c) || 0) * saleableArea;
            var amenities = parseFloat(oppPlot.Amenities_Car_Parking__c) || 0;
            var infrastructure = parseFloat(oppPlot.Infrastructure_Charges__c) || 0;

            var flatCost = basicPrice + eastFacing + corner + hiRise + centralCourtYard
                         + meadow + roadside + courtYard + outer + amenities + infrastructure;
            var gstAmount = flatCost * (gstPercentage / 100);
            var grandTotal = flatCost + gstAmount;

            component.set('v.basicPriceCalc', basicPrice);
            component.set('v.eastFacingCalc', eastFacing);
            component.set('v.cornerCalc', corner);
            component.set('v.hiRiseCalc', hiRise);
            component.set('v.centralCourtYardCalc', centralCourtYard);
            component.set('v.meadowCalc', meadow);
            component.set('v.roadsideCalc', roadside);
            component.set('v.courtYardCalc', courtYard);
            component.set('v.outerCalc', outer);
            component.set('v.amenitiesCalc', amenities);
            component.set('v.infrastructureCalc', infrastructure);
            component.set('v.flatCost', flatCost);
            component.set('v.gstAmount', gstAmount);
            component.set('v.GrandTotalGST', grandTotal.toFixed(0));
            
            component.set('v.today', today);
            
            // FIX: Add null check for Project__r
            console.log('plt[i]: ', plt[i]);
            console.log('Project__r: ', plt[i].Project__r ? plt[i].Project__r.Name : '');
            component.set('v.projectName', plt[i].Project__r ? plt[i].Project__r.Name : '');
            
            component.set('v.flatNumber', plt[i].Name);
            component.set('v.RecTypeId',plt[i].Name);
            
            break;
        } 
    } 
    component.set('v.plot', selPlot);
    component.set('v.oppPlot',oppPlot);
    
    component.set('v.matchplots',[]);
    
},
    update2 : function(component, event, helper) {
        
        var edi =  event.currentTarget.dataset.id;
        var plt= component.get('v.matchpaymentplan');
        var selPlot= component.get('v.paymentplan');
        var oppPlot = component.get('v.oppPlot');
        //  alert(component.get('v.oppPlot')+'--'+edi);
        var opp = component.get("v.OppRecord");
        
        for(var i=0;i<plt.length; i++){  
            
            if(plt[i].Id ===  edi ){
                component.set('v.searchText2', plt[i].Name);
                selPlot = plt[i];
                //  alert(JSON.stringify(plt[i])+'---'+edi)
                oppPlot.Payment_Plan__c = plt[i].Id;
                break;
            }
        }
        component.set('v.paymentplan', selPlot);
        component.set('v.oppPlot',oppPlot);
        //alert(JSON.stringify(component.get('v.oppPlot')))
        component.set('v.matchpaymentplan',[]);
    },
    doSave: function(component,event,helper) {
        if (component.get('v.isSubmitting')) {
            return;
        }
        component.set('v.isSubmitting', true);
        component.set('v.showSave', false);
        if (helper.validateSave(component, event)) {
            helper.save(component, event, helper);
        } else {
            component.set('v.isSubmitting', false);
        }
    },
    closeModel: function(component, event, helper) {
        // Set isModalOpen attribute to false  
        //  component.set("v.isModalOpen", false);
        // history.back();
        $A.get("e.force:closeQuickAction").fire();   
    },
    handleCheckboxChange : function(component, event, helper) {
        var checkboxValue = component.find("checkbox").get("v.checked");
        component. set("v.isCheckboxChecked",checkboxValue);
        //  alert(checkboxValue);
        
    },
    handleSpecialLaunchChange : function(component, event, helper) {
        var checkboxValue = component.find("checkbox1").get("v.checked");
        component.set("v.isSpecialLaunch", checkboxValue);

        if (!checkboxValue) {
            // Toggled OFF — restore every Quote charge to its original Plot rate and clear discounts
            var oppPlot = component.get('v.oppPlot');
            var originals = component.get('v.originalCharges') || {};
            var config = component.get('v.discountConfig') || [];
            for (var i = 0; i < config.length; i++) {
                var row = config[i];
                oppPlot[row.quoteField] = parseFloat(originals[row.unitField]) || 0;
                if (row.discountField) {
                    oppPlot[row.discountField] = 0;
                }
            }
            component.set('v.oppPlot', oppPlot);
            component.set('v.selectedDiscounts', []);
            component.set('v.visibleDiscountRows', []);
        }

        $A.enqueueAction(component.get('c.handleChangeValues'));
    },

    handleDiscountSelectionChange : function(component, event, helper) {
        var newSel = event.getParam('value') || [];
        // Use visibleDiscountRows (last rendered state) as the previous selection,
        // since v.selectedDiscounts may already reflect the new value via two-way binding.
        var prevRows = component.get('v.visibleDiscountRows') || [];
        var oppPlot = component.get('v.oppPlot');
        var originals = component.get('v.originalCharges') || {};
        var config = component.get('v.discountConfig') || [];

        // Index config by quoteField for quick lookup
        var byQuoteField = {};
        for (var i = 0; i < config.length; i++) {
            byQuoteField[config[i].quoteField] = config[i];
        }

        // Restore originals for de-selected rows
        for (var j = 0; j < prevRows.length; j++) {
            var qf = prevRows[j].quoteField;
            if (newSel.indexOf(qf) === -1) {
                var cfg = byQuoteField[qf];
                if (cfg) {
                    oppPlot[cfg.quoteField] = parseFloat(originals[cfg.unitField]) || 0;
                    if (cfg.discountField) {
                        oppPlot[cfg.discountField] = 0;
                    }
                }
            }
        }

        // Rebuild visible rows preserving each row's current discount value
        var visible = [];
        for (var k = 0; k < newSel.length; k++) {
            var sel = newSel[k];
            var cfg2 = byQuoteField[sel];
            if (cfg2) {
                visible.push({
                    label: cfg2.label,
                    unitField: cfg2.unitField,
                    quoteField: cfg2.quoteField,
                    discountField: cfg2.discountField,
                    currentDiscount: cfg2.discountField ? (parseFloat(oppPlot[cfg2.discountField]) || 0) : 0
                });
            }
        }

        component.set('v.oppPlot', oppPlot);
        component.set('v.selectedDiscounts', newSel);
        component.set('v.visibleDiscountRows', visible);
        $A.enqueueAction(component.get('c.handleChangeValues'));
    },

    handleDiscountValueChange : function(component, event, helper) {
        var src = event.getSource();
        var quoteField = src.get('v.name');
        var typed = parseFloat(src.get('v.value')) || 0;

        var config = component.get('v.discountConfig') || [];
        var unitField = null;
        var discountField = null;
        var label = quoteField;
        for (var i = 0; i < config.length; i++) {
            if (config[i].quoteField === quoteField) {
                unitField     = config[i].unitField;
                discountField = config[i].discountField;
                label         = config[i].label;
                break;
            }
        }
        if (!unitField || !discountField) {
            return;
        }

        var originals = component.get('v.originalCharges') || {};
        var original  = parseFloat(originals[unitField]) || 0;

        if (typed > original) {
            src.setCustomValidity('Discount cannot exceed the original rate of ₹' + original);
            src.reportValidity();
            return;
        }
        src.setCustomValidity('');
        src.reportValidity();

        var oppPlot = component.get('v.oppPlot');
        oppPlot[discountField] = typed;
        oppPlot[quoteField]    = original - typed;
        component.set('v.oppPlot', oppPlot);

        // Keep visibleDiscountRows in sync so the bound value stays correct on re-render
        var visible = component.get('v.visibleDiscountRows') || [];
        for (var v = 0; v < visible.length; v++) {
            if (visible[v].quoteField === quoteField) {
                visible[v].currentDiscount = typed;
                break;
            }
        }
        component.set('v.visibleDiscountRows', visible);

        $A.enqueueAction(component.get('c.handleChangeValues'));
    },
    navigateToPaymentSchedule: function (component, event, helper) {
         // alert("navigateToPaymentSchedule");
        var payType = component.get("v.oppPlot.Payment_Type__c");
        if (helper.validate(component, event)) {
            if(payType != 'None'){
                if(payType == 'Custom'){
                    var existingSchedules = component.get("v.CustompaymentSchedules") || [];
                    if(existingSchedules.length === 0){
                        helper.addProductRecord(component,event,helper);
                    }
                }
                helper.getmasterpaymentschedule(component,event,helper);
            }
            else{
                helper.showToast('Error','Mandate Error','Please Select The Payment Type');
            }
        }
    },
    navigateToCreateQuote: function (component, event, helper) {
        component.set("v.showNextCmp", false);
        
    },
    
    handleProjectChange: function(component, event, helper){
        var selectedValue = component.find("projectSelect").get("v.value");
        console.log('selectedValue '+selectedValue);
        component.set('v.allocatedProjectValue1', selectedValue);

        // Reset any in-progress unit selection
        component.set('v.searchText1', '');
        component.set('v.matchplots', []);
        component.set('v.showqute', false);
        component.set('v.plots', []);

        if (!selectedValue) {
            return;
        }

        var plotsAction = component.get("c.getPlots");
        plotsAction.setParams({ "project": selectedValue });
        plotsAction.setCallback(this, function(response) {
            if (response.getState() === "SUCCESS") {
                component.set("v.plots", response.getReturnValue() || []);
            } else {
                console.error("Error fetching plots:", response.getError());
            }
        });
        $A.enqueueAction(plotsAction);
    },
    
    handleChangeValues: function(component, event, helper) {
        var oppPlot = component.get('v.oppPlot');

        var saleableArea  = parseFloat(oppPlot.Saleable_Area_Sft__c) || 0;
        var gstPercentage = parseFloat(oppPlot.GST1__c) || 0;

        // oppPlot[unitField] is the net rate (already discounted) — just multiply by area.
        var basicPrice       = (parseFloat(oppPlot.Price_Per_Sq_Ft__c)              || 0) * saleableArea;
        var eastFacing       = (parseFloat(oppPlot.East_Facing_Charges__c)          || 0) * saleableArea;
        var corner           = (parseFloat(oppPlot.Corner_Charges__c)               || 0) * saleableArea;
        var hiRise           = (parseFloat(oppPlot.Hi_Rise_Charges__c)              || 0) * saleableArea;
        var centralCourtYard = (parseFloat(oppPlot.Central_Court_Yard_Premium__c)   || 0) * saleableArea;
        var meadow           = (parseFloat(oppPlot.Meadow_Premium__c)               || 0) * saleableArea;
        var roadside         = (parseFloat(oppPlot.Roadside_Premium__c)             || 0) * saleableArea;
        var courtYard        = (parseFloat(oppPlot.Court_Yard_Premium__c)           || 0) * saleableArea;
        var outer            = (parseFloat(oppPlot.Outer_Premium__c)                || 0) * saleableArea;
        var amenities        =  parseFloat(oppPlot.Amenities_Car_Parking__c)        || 0;
        var infrastructure   =  parseFloat(oppPlot.Infrastructure_Charges__c)       || 0;

        var flatCost = basicPrice + eastFacing + corner + hiRise + centralCourtYard
                     + meadow + roadside + courtYard + outer + amenities + infrastructure;
        var gstAmount = flatCost * (gstPercentage / 100);
        var grandTotal = flatCost + gstAmount;

        component.set('v.basicPriceCalc', basicPrice);
        component.set('v.eastFacingCalc', eastFacing);
        component.set('v.cornerCalc', corner);
        component.set('v.hiRiseCalc', hiRise);
        component.set('v.centralCourtYardCalc', centralCourtYard);
        component.set('v.meadowCalc', meadow);
        component.set('v.roadsideCalc', roadside);
        component.set('v.courtYardCalc', courtYard);
        component.set('v.outerCalc', outer);
        component.set('v.amenitiesCalc', amenities);
        component.set('v.infrastructureCalc', infrastructure);
        component.set('v.flatCost', flatCost);
        component.set('v.gstAmount', gstAmount);
        component.set('v.GrandTotalGST', grandTotal.toFixed(0));
    },
    addRow: function(component, event, helper) {
        //alert('hello ocean');
        helper.addProductRecord(component, event,helper);
    },
     removeRow: function(component, event, helper) {
        //alert('hello remove');
        //var quoteList = component.get("v.QuoteItemList");
       var selectedItem = event.currentTarget;
       var index = selectedItem.dataset.record;
        console.log(index);
        var oitems= component.get('v.CustompaymentSchedules');
        console.log(oitems);
        console.log(oitems[index].Id);
        if(oitems[index].Id !='undefined' && oitems[index].Id !='' && oitems[index].Id !=undefined){
            console.log('in');
            
            if( oitems[index].Payment_percent__c !='' && oitems[index].Payment_percent__c !=undefined){
                var grandtotal = (component.get('v.GrandTotal')-oitems[index].Amount__c);
                var recivedamount = (component.get('v.RecivedAmountTotal')-oitems[index].Received_Amount__c);
                var perct = (component.get('v.totalPercent')-oitems[index].Payment_percent__c);
                component.set('v.GrandTotal',grandtotal.toFixed(0));
                component.set('v.RecivedAmountTotal',recivedamount.toFixed(2));
                component.set('v.totalPercent',perct);
            }
            oitems.splice(index, 1);
            for (var i = 0; i < oitems.length; i++) {
                oitems[i].S_No__c = i+1;
            }        
            component.set("v.CustompaymentSchedules", oitems);
            
            if(oitems.length < 1){
                helper.addProductRecord(component, event,helper);
            }
            
        }else{
            console.log(oitems[index].Payment_percent__c);
            if( oitems[index].Payment_percent__c !='' && oitems[index].Payment_percent__c !=undefined){
                var grandtotal = (component.get('v.GrandTotal')-oitems[index].Amount__c);
                var recivedamount = (component.get('v.RecivedAmountTotal')-oitems[index].Received_Amount__c);
                console.log(grandtotal);
                var perct = (component.get('v.totalPercent')-oitems[index].Payment_percent__c);
                console.log(perct);
                console.log('grandTotal1================>' + grandtotal);
                component.set('v.GrandTotalGST',grandtotal.toFixed(0));
                component.set('v.RecivedAmountTotal',recivedamount.toFixed(2));
                component.set('v.totalPercent',perct);
                console.log('d');
            }
            oitems.splice(index, 1);
            for (var i = 0; i < oitems.length; i++) {
                oitems[i].S_No__c = i+1;
            }  
            console.log('s');
            component.set("v.CustompaymentSchedules", oitems);
            
            if(oitems.length < 1){
                helper.addProductRecord(component, event);
            } 
            
        }
    },
    handlePrevious: function(component, event, helper) {
        component.set('v.showNextCmp',false);
    }
    
})