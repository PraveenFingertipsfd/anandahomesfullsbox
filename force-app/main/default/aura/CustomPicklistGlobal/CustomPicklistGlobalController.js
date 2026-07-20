({
	doInit : function(component, event, helper) {
        console.log('objAPIName'+component.get('v.objAPIName'));
        console.log('fieldAPIname'+component.get('v.fieldAPIname'));
        
		var action = component.get('c.findPicklistOptions');
        action.setParams({
            'objAPIName':component.get('v.objAPIName'),
            'fieldAPIname':component.get('v.fieldAPIname')
        });
        action.setCallback(this,function(response){
            if(response.getState() === 'SUCCESS') {
                var options = response.getReturnValue();
                console.log('options'+JSON.stringify(options));
                component.set("v.options",options);
            }else {
                // If server throws any error
                var errors = response.getError();
                console.log('options'+JSON.stringify(errors));
                if (errors && errors[0] && errors[0].message) {
                    component.set('v.message', errors[0].message);
                    console.log(errors[0].message);
                }
            }
        });
         $A.enqueueAction(action);
	}
})