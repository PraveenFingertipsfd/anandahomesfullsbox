({
    Toast: function (title, type, msg){
        var toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({"title": title,
                              "type":type,
                              "message": msg});
        toastEvent.fire();
    }
})