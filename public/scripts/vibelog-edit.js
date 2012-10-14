function previewToggle()
{
	var enabled = $("#preview-checkbox").is(':checked');
	if( enabled ){
		var message = $("#message");
		var preview = $("#message-preview");
		preview.height(message.height());
		message.hide();
		preview.show();

		$.post(window.rootDir+"markup", {message: message.val()}, function(data){ preview.html(data); prettyPrint(); });
	} else {
		$("#message").show();
		$("#message-preview").hide();
	}
}
