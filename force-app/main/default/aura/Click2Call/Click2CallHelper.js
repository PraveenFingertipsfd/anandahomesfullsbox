({
    showError : function(response) {
        var errors = response.getError();
        var msg = "Unknown error, contact your system admin";
        if (errors && errors[0] && errors[0].message) {
            msg = errors[0].message;
        }
        this.showToast("Error", "error", msg);
    },

    showToast : function(title, type, message) {
        var toast = $A.get("e.force:showToast");
        toast.setParams({ title: title, type: type, message: message });
        toast.fire();
    }
})