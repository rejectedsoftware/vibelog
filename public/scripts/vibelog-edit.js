function previewUpdate()
{
	var enabled = $('#preview-checkbox').is(':checked');
	if( enabled )
	{
		var message = $('#message');
		var preview = $('#message-preview');
		var filters = $('#filters-field').val();

		if (filters != "")
		{
			$.get('/filter', {message: message.val(), filters: filters}, function(data){ preview.html(data) });
		}
		else
		{
			preview.html(message.val());
		}

		preview.height(message.height());
		message.hide();
		preview.show();
	}
	else
	{
		$('#message').show();
		$('#message-preview').hide();
	}
}
