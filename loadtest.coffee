request = require 'request'


request.get "http://google.com", (err, res) ->
	if err?
		console.log err
	else
		console.log res.statusCode

