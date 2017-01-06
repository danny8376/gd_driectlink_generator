require "http/server"
require "http/client"

module Server
    def self.handle_request(context)
        context.response.content_type = "text/plain"
        context.response.print "Hello world!"
    end
    
    def self.start_server(port = 8080, bind = "0.0.0.0")
        server = HTTP::Server.new(bind, port, [
            HTTP::ErrorHandler.new,
        ]) { |context| handle_request context }
    
        puts "Listening on http://0.0.0.0:8080"
        server.listen
    end
end

Server.start_server
