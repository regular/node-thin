debug = require('debug')('build-proxy')
crypto = require 'crypto'

ManInTheMiddle = require("./lib/thin")
proxy = new ManInTheMiddle({})

cache = {}

proxy.use (req, res, next) ->
    url = proxy.getRequestURL req
    debug "Proxying: #{url}"

    shasum = crypto.createHash 'sha1'
    shasum.update url
    hash = shasum.digest 'hex'

    cacheEntry = cache[hash]

    if cacheEntry?
        debug 'cache hit'
        totalLength = 0
        for buffer in cacheEntry
            res.write buffer
            totalLength += buffer.length
        res.end()
        debug "send #{totalLength} bytes from cache"
    else
        debug "cache miss"
        # monkey-patching the response object
        # to intercept the response data sent to our proxy client
        origWrite = res.write
        origEnd = res.end
        entry = cache[hash] = []
        totalLength = 0
        res.write = (data, encoding) ->
            entry.push data
            totalLength += data.length
            origWrite.call res, data, encoding

        res.end = (data, encoding) ->
            if data?
                entry.push data
                totalLength += data.length
            origEnd.call res, data, encoding
            debug "wrote #{totalLength} bytes into cache"

        return next()

proxy.listen 8081, "localhost", (err) ->
    if err? then process.exit 1

