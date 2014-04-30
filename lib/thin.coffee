http = require 'http'
net = require 'net'
https = require 'https'
fs = require 'fs'
os = require 'os'
request = require 'request'
URL = require 'url'
debug = require('debug')('thin')

class ManInTheMiddle

  constructor: (@opts = {}) ->
    # socket path for system mitm https server
    @socket = os.tmpdir() + "/node-thin." + process.pid + ".sock"
    @interceptors = []

  listen: (port, host, cb) =>
    # make sure there's no previously created socket
    fs.unlinkSync @socket  if fs.existsSync(@socket)
    options =
      key: fs.readFileSync(__dirname + "/../cert/dummy.key", "utf8")
      cert: fs.readFileSync(__dirname + "/../cert/dummy.crt", "utf8")

    # fake https server, MITM if you want
    @httpsServer = https.createServer(options, @_handler).listen(@socket)
    
    # start HTTP server with custom request handler callback function
    @httpServer = http.createServer(@_handler).listen port, host, (err) ->
      debug "Cannot start proxy", err  if err
      cb err
    
    # add handler for HTTPS (which issues a CONNECT to the proxy)
    @httpServer.addListener "connect", @_httpsHandler

  close: (cb) ->
    @httpServer.close (err) =>
      return cb(err)  if err
      @httpsServer.close cb

  _handler: (req, res) =>
    debug 'handler'
    interceptors = @interceptors.concat([@direct])
    layer = 0
    (runner = ->
      interceptor = interceptors[layer++]
      interceptor req, res, (err) ->
        return res.end("Proxy error: " + err.toString())  if err
        runner()
        undefined
    )()
    undefined

  _httpsHandler: (request, socketRequest, bodyhead) =>
    {url, httpVersion} = request
    
    # set up TCP connection
    proxySocket = new net.Socket()
    proxySocket.connect @socket, ->
      debug "> writing head of length #{bodyhead.length}"
      proxySocket.write bodyhead
      
      # tell the caller the connection was successfully established
      socketRequest.write "HTTP/" + httpVersion + " 200 Connection established\r\n\r\n"

    proxySocket.on "data", (chunk) ->
      debug "< data length = %d", chunk.length
      socketRequest.write chunk

    proxySocket.on "end", ->
      debug "< end"
      socketRequest.end()

    socketRequest.on "data", (chunk) ->
      debug "> data length = %d", chunk.length
      proxySocket.write chunk

    socketRequest.on "end", ->
      debug "> end"
      proxySocket.end()

    proxySocket.on "error", (err) ->
      socketRequest.write "HTTP/" + httpVersion + " 500 Connection error\r\n\r\n"
      debug "< ERR: %s", err
      socketRequest.end()

    socketRequest.on "error", (err) ->
      debug "> ERR: %s", err
      proxySocket.end()

  
  use: (fn) ->
    @interceptors.push fn
    return @

  removeInterceptors: ->
    @interceptors.length = 0
    return

  getRequestURL: (req) ->
    path = URL.parse(req.url).path
    schema = (if Boolean(req.client.pair) then "https" else "http")
    return schema + "://" + req.headers.host + path

  direct: (req, res) =>
    dest = @getRequestURL(req)
    params =
      url: dest
      strictSSL: false
      method: req.method
      proxy: @opts.proxy
      headers: {}

    
    # Set original headers except proxy system's headers
    exclude = ["proxy-connection"]
    for hname of req.headers
      continue
    buffer = ""
    req.on "data", (chunk) ->
      buffer += chunk
      return

    req.on "end", ->
      params.body = buffer
      r = request(params, (err, response) ->
        
        # don't save responses with codes other than 20
        console.error err  if err or response.statusCode isnt 200
        return
      )
      r.pipe res
    
module.exports = ManInTheMiddle
