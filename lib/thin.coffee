http = require 'http'
net = require 'net'
https = require 'https'
fs = require 'fs'
os = require 'os'
request = require 'request'
URL = require 'url'
debug = require('debug')('thin')
async = require 'async'

class ManInTheMiddle

  constructor: (@opts = {}) ->
    # socket path for system mitm https server
    @socket = os.tmpdir() + "/node-thin." + process.pid + ".sock"
    @interceptors = []
    @pending = 0
    @q = async.queue @process, 1

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
      socketRequest.write "HTTP/" + httpVersion + " 200 Connection established\r\n\r\n"

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
      url: dest
      strictSSL: false
      followRedirect: true
      followAllRedirects: true
      method: req.method
      timeout: 4000
      #proxy: @opts.proxy
      headers: {}
  
    # Set original headers except proxy system's headers
    for key, value of req.headers
      if key isnt "proxy-connection"
        params.headers[key] = value

    #console.log params

    debug "requesting #{dest}"
    @pending++
    debug "pending: #{@pending}"
    r = request params, (err, response) =>
      @pending--
      
      if err?
        console.log "error requesting #{dest}: #{err}"
        res.end()
      
      else
        debug "responding #{response.statusCode} #{dest}"
    
      debug "pending: #{@pending}"
      res.end()
      
      return cb err
      
    req.pipe r
    r.pipe res
    
module.exports = ManInTheMiddle
