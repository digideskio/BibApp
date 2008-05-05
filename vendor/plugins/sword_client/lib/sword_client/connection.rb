# Client Connection to a SWORD Server
#  
# This is the core class which communicates with the SWORD Server
# and sends GET or POST requests via HTTP

require 'net/http'

class SwordClient::Connection
  
  # Base URL of SWORD Server, and the persistent connection to it
  attr_reader :url, :connection
  
  # Timeout for our connection
  attr_reader :timeout

  #User Name & Password to Authenticate with
  attr_writer :username, :password
  
  # If depositing on behalf of someone else, this is his/her username
  attr_accessor :on_behalf_of
  
  # Proxy Settings to use for all requests (if necessary)
  # This is a hash including {:server, :port, :username, :password}
  attr_accessor :proxy_settings
  
  
  # Create a connection to a SWORD Server instance using the base url
  #
  #   conn = Sword::Connection.new("http://example.com:8080/sword-app")
  #
  # Note: The Base URL of the SWORD Server is *not* the same as the
  #   Service Document.  Both the Service Document and Deposit script
  #   are assumed to be available at a sub-path of that base url
  #   (see the options below)
  #
  # Options available:
  #    :username => User name to connect as
  #    :password => Password for user
  #    :on_behalf_of => Connect on behalf of another user
  #    :timeout => specify connection timeout (in seconds)
  #    :proxy_settings => Proxy Server Settings
  #                      Hash which may include (only :server is required):
  #                      {:server   => name of proxy server, 
  #                       :port     => port on proxy server,
  #                       :username => login name for proxy server, 
  #                       :password => password for proxy server}
  #
  def initialize(url="http://localhost:8080/sword-app", opts={})
    @url = URI.parse(url)
    unless @url.kind_of? URI::HTTP
      raise "invalid http url: #{url}"
    end
  
    #Only load Username/Password/On_Behalf_Of, if specified
    @username = opts[:username] if opts[:username]
    @password = opts[:password] if opts[:password]
    @on_behalf_of = opts[:on_behalf_of] if opts[:on_behalf_of]
    
    # Setup proxy if using
    @proxy_settings = opts[:proxy_settings] if opts[:proxy_settings]
    if @proxy_settings
      # Not actually opening the connection yet, just setting up the persistent connection.
      @connection = Net::HTTP.new(@url.host, @url.port, @proxy_settings[:server], @proxy_settings[:port], @proxy_settings[:username], @proxy_settings[:password])
    else
      # Not actually opening the connection yet, just setting up the persistent connection.
      @connection = Net::HTTP.new(@url.host, @url.port)
    end

    #set to SSL if HTTPS connection  (@TODO: NOT WORKING RIGHT NOW)
    #@connection.use_ssl = @url.scheme == "https:" 
    #@connection.verify_mode = OpenSSL::SSL::VERIFY_NONE #turn off SSL verify mode
    
    #setup connection timeout, if specified
    @connection.read_timeout = opts[:timeout] if opts[:timeout]
  end
  
  # Retrieve the SWORD Service Document for this connection.
  #   Path of service document should be relative to the base URL
  #   of the connection (and begin with a slash).  
  #   Service document path defaults to "/servicedocument"
  #
  # This will return the service document (as an XML string) if found,
  # otherwise it throws a response error.
  def service_document(path="/servicedocument")
    
    response = fetch(@url.path + path)
    
    #service document should just be in body of request
    response.body
  end

  # Posts a file to the SWORD connection for deposit.
  #   Path of deposit should be relative to the base URL
  #   of the connection (and begin with a slash).  
  #   Deposit path defaults to "http://localhost:8080/sword-app".  
  #   However, chances are you need to deposit to a specific 
  #   collection similar to:
  #   "http://localhost:8080/sword-app/deposit/123456789/1"
  #
  # This filepath should be a *local* filepath to file.  
  # MIME type is assumed to be "application/zip", unless specified otherwise
  def post_file(file_path, deposit_url="http://localhost:8080/sword-app", mime_type="application/zip")
    
    #@TODO: ZIPPING FILES
    # http://info.michael-simons.eu/2008/01/21/using-rubyzip-to-create-zip-files-on-the-fly/

    # Make sure file exists
    fail "Could not find file at " + file_path if(!File.exists?(file_path))
   
    # Add content type to HTTP Request Headers
    headers = {'Content-Type' =>  mime_type}
    
    if mime_type.match('^text\/.*') #check if begins with "text/"
      file = File.open(file_path) # open as normal (text-based format)
    else
      file = File.open(file_path, 'rb') # force opening in Binary file mode
    end
      
    # POST our file to deposit_url
    response = request("post", deposit_url, headers, file)
    
    #determine response
    case response
    when Net::HTTPSuccess then response.body
    else
      response.error!
    end
    
  end
  
  
  
  ###################
  # PRIVATE METHODS
  ###################
  private
  
  # Fetch (via GET) a path using our current connection, 
  # and follow redirections down to 10 levels deep (by default)
  def fetch(path, limit = 10)
    
    fail 'HTTP redirection is too deep...cannot retrieve requested path: ' + path if limit == 0

    #make our GET request
    response = request("get", path)

    #determine response
    case response
    when Net::HTTPSuccess     then response
    when Net::HTTPRedirection then fetch(response['location'], limit - 1)
    else
      response.error!
    end
  end
  
  # This method actually makes a request to the SWORD server  
  # The "verb" can be either "get" or "post" (the two HTTP verbs supported by SWORD)
  # The "body" may be text to send, or a File (via File.open)
  #
  # This method returns a response
  #
  # Note: This method is based on similar method in Amazon S3 ruby code 
  # (http://amazon.rubyforge.org/doc/)
  def request(verb, path, headers = {}, body = nil, attempts = 0, &block)
        
        #If body was already read once, may need to rewind it
        body.rewind if body.respond_to?(:rewind) unless attempts.zero?      
        
        #Build our "request" procedure
        requester = Proc.new do 
          
          #init request type
          request = request_method(verb).new(path, headers)
          
          #Check all our necessary request headers are set
          add_user_agent!(request)
          add_sword_headers!(request)
          authenticate!(request)
       
          if body
            #If body responds to 'read', it is a file which should be streamed
            if body.respond_to?(:read)                                                                
              request.body_stream    = body
              add_file_info!(request, body)
            else  
              #Otherwise, we can just add the body to request as-is
              request.body = body                                                                     
            end                                                                                       
          end
          
          @connection.request(request, &block)
        end
        
        #actually start our request
        @connection.start(&requester)
      rescue Errno::EPIPE, Timeout::Error, Errno::EPIPE, Errno::EINVAL
        #try 3 times before failing altogether
        attempts == 3 ? raise : (attempts += 1; retry)
  end
  
  # If specified, add authentication information into Request
  def authenticate!(request)
    if @username and @password  
      request.basic_auth @username, @password
    end
  end
  
  # If unspecified, set User-Agent to Ruby SWORD Client
  def add_user_agent!(request)
    request['User-Agent'] ||= "Ruby SWORD Client"
  end
  
  # Set our SWORD headers, if they haven't been set already
  def add_sword_headers!(request)
    request['X-On-Behalf-Of'] ||= @on_behalf_of.to_s  if @on_behalf_of
    request['X-Verbose'] ||= "true"
  end
  
  # If unspecified, add file information to request
  def add_file_info!(request, body)
    #add content length
    request.content_length = body.respond_to?(:lstat) ? body.lstat.size : body.size         
    
    #Add filename to Content-Disposition
    request['Content-Disposition'] ||= body.respond_to?(:path) ? "filename=\"" + File.basename(body.path).to_s + "\"" : ""
    
    #If content type header not set, assume binary/octet-stream, since this is a file
    request['Content-Type'] ||= 'binary/octet-stream'
  end
  
  # Get constant representing the request verb
  def request_method(verb)
    Net::HTTP.const_get(verb.to_s.capitalize)
  end
  
end