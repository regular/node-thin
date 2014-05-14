http = require 'http'
net = require 'net'
https = require 'https'
fs = require 'fs'
os = require 'os'
request = require 'request'
URL = require 'url'
debug = require('debug')('thin')
async = require 'async'
through = require 'through'
zlib = require 'zlib'

class ManInTheMiddle

  constructor: (@opts = {}) ->
    # socket path for system mitm https server
    @socket = os.tmpdir() + "/node-thin." + process.pid + ".sock"
    @interceptors = []
    @pending = 0
    @q = async.queue @process, 5

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
    ###
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
    ###

    @q.push {req, res}

  process: ({req, res}, cb) =>
    @direct req, res, cb

  _httpsHandler: (request, socketRequest, bodyhead) =>
    {url, httpVersion} = request
    
    # set up TCP connection
    proxySocket = new net.Socket()
    debug 'connecting to internal https server ...'
    proxySocket.connect @socket, ->
      debug "> writing head of length #{bodyhead.length}"
      proxySocket.write bodyhead
      
      # tell the caller the connection was successfully established
      socketRequest.write('HTTP/1.1 200 Connection Established\r\n' +
                    'Proxy-agent: Node-Proxy\r\n' +
                    '\r\n');

      proxySocket.pipe socketRequest
      socketRequest.pipe proxySocket
  
  use: (fn) ->
    @interceptors.push fn
    return @

  removeInterceptors: ->
    @interceptors = []

  getRequestURL: (req) ->
    path = URL.parse(req.url).path
    schema = (if Boolean(req.client.pair) then "https" else "http")
    return schema + "://" + req.headers.host + path

  direct: (req, res, cb) =>
    dest = @getRequestURL req
    params =
      hostname: req.headers.host
      port: URL.parse(req.url).port
      path: URL.parse(req.url).path
      method: req.method
      rejectUnauthorized: false
      headers: {}
  
    # Set original headers except proxy system's headers
    for key, value of req.headers
      if key isnt "proxy-connection"
        params.headers[key] = value

    console.log params.method + " " + dest
    console.log params.headers

    debug "requesting #{req.method} #{dest}"
    @pending++
    debug "pending: #{@pending}"

    r = null

    callback = (response) =>
      @pending--
   
      console.log response.headers
      debug "pending: #{@pending}"
      debug "responding #{req.method} #{response.statusCode} #{dest}"
   
      response.pipe through (data) ->
        console.log "server: #{data.length}"

      response.pipe res

      return cb null

    r = https.request params, callback
    r.on 'error', (err) ->
      console.log "ERROR requesting: #{dest} #{err}"
      return cb err
     
    req.pipe r
    
    clientStream = through (data) ->
      console.log "CLIENT: #{data}"

    if req.headers['content-encoding'] is 'gzip'
      req.pipe(zlib.createGunzip()).pipe clientStream
    else
      req.pipe clientStream

module.exports = ManInTheMiddle
