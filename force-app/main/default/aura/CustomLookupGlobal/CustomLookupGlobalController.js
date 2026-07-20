({
    // To prepopulate the seleted value pill if value attribute is filled
    doInit: function (component, event, helper) {
        $A.util.removeClass(component.find('resultsDiv'), 'slds-is-open');
        console.log('value:' + component.get('v.value'));
        //helper.searchRecordsHelper(component, event, helper);
        if (!$A.util.isEmpty(component.get('v.value'))) {
            helper.searchRecordsHelper(component, event, helper, component.get('v.value'));
        } else {
            //$A.util.toggleClass(component.find('resultsDiv'), 'slds-is-open');
            //console.log('im here 1');
            helper.searchRecordsHelper(component, event, helper, '');
        }
    },
    changeValue: function (component, event, helper) {
        $A.util.removeClass(component.find('resultsDiv'), 'slds-is-open');
        helper.searchRecordsHelper(component, event, helper, component.get('v.value'));
    },
    // When a keyword is entered in search box
    searchRecords: function (component, event, helper) {
        var searchString = event.getSource().get("v.value");
        component.set('v.searchString', searchString);
        var splV = component.get('v.queryValue') || '';
        console.log('queryValue: ' + splV);
        helper.searchRecordsHelper(component, event, helper, '');
    },

    // When an item is selected
    selectItem: function (component, event, helper) {
        if (!$A.util.isEmpty(event.currentTarget.id)) {
            var recordsList = component.get('v.recordsList');
            var index = recordsList.findIndex(x => x.value === event.currentTarget.id)
            if (index != -1) {
                var selectedRecord = recordsList[index];
            }
            console.log('json' + JSON.stringify(selectedRecord));
            component.set('v.selectedRecord', selectedRecord);
            //component.set('v.value', selectedRecord.label);
            component.set('v.selectedId', selectedRecord.value);
            //component.set('v.searchString',selectedRecord.value);
            $A.util.removeClass(component.find('resultsDiv'), 'slds-is-open');
        }
    },

    showRecords: function (component, event, helper) {
        helper.searchRecordsHelper(component, event, helper, '');
        $A.util.toggleClass(component.find('resultsDiv'), 'slds-is-open');
    },

    // To remove the selected item.
    removeItem: function (component, event, helper) {
        helper.removeItem(component, event, helper);
    },

    // To close the dropdown if clicked outside the dropdown.
    blurEvent: function (component, event, helper) {
        // component.set('v.showRecords',false);
        $A.util.removeClass(component.find('resultsDiv'), 'slds-is-open');
    },
    changeParent: function (component, event, helper) {
        if ($A.util.isEmpty(component.get('v.queryValue'))) {
            helper.removeItem(component, event, helper);
        }
    }
})