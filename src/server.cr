require "http/server"
require "http/client"
require "yaml"

module Server
    @@conf = YAML::Any.new(nil)
    def self.load_config
        @@conf = YAML.parse(File.read("./config.yml"))
    end

    GAPI_URI = "https://www.googleapis.com"

    GD_APIDL_PATH = "/drive/v3/files/%s?alt=media&key=%s"

    GD_APIDL = GAPI_URI + GD_APIDL_PATH
    GD_UCDL = "https://drive.google.com/uc?export=download&id=%s"

    FORWARD_DL_PATH = "/adl/%s"

    def self.gapi_cli
        cli = HTTP::Client.new "www.googleapis.com", 443, true
        cli.compress = false
        cli
    end

    def self.gd_filesize(fid)
        link = GD_APIDL_PATH % [fid, @@conf["apikey"]["main"].as_s]
        res = gapi_cli.head link
        return -1 unless res.status_code == 200
        return res.headers["Content-Length"].to_i
    end

    def self.get_apidirectlink(fid)
        return GD_APIDL % [fid, @@conf["apikey"]["publicdl"].as_s]
    end

    def self.auto_directlink(fid, forward = false)
        filesize = gd_filesize fid
        if filesize < 0 # error
            return ""
        elsif filesize <= 26214400 # under scan size limit
            return GD_UCDL % [fid]
        else
            if forward # forward with /adl/
                return FORWARD_DL_PATH % [fid]
            else
                return get_apidirectlink fid
            end
        end
    end

    def self.handle_request(context)
        case context.request.path
        when /^\/adl\/(?<id>.*)$/ # API Direct Link
            fid = $~["id"]
            context.response.status_code = 302
            link = get_apidirectlink fid
            context.response.headers["Location"] = link
            context.response.print "Redirecting you to #{link}"
        when /^\/(?<act>link|dl)\/(?<id>.*)$/ # get link (text)
            fid = $~["id"]
            act_link = $~["act"] == "link"
            link = auto_directlink fid, act_link
            context.response.content_type = "text/plain"
            if link.empty?
                context.response.status_code = 404
                context.response.print "FID: #{fid} not exist or not shared"
            elsif act_link
                context.response.print link
            else
                context.response.status_code = 302
                context.response.headers["Location"] = link
                context.response.print "Redirecting you to #{link}"
            end
        else
            context.response.content_type = "text/plain"
            context.response.print "Hello world!"
        end
    end
    
    def self.start_server(host = "", port = -1)
        load_config

        host = @@conf["bind"]["host"].as_s if host.empty?
        port = @@conf["bind"]["port"].as_s.to_i if port < 0

        server = HTTP::Server.new(host, port, [
            HTTP::ErrorHandler.new ENV["ENV"] == "debug",
        ]) { |context| handle_request context }
    
        puts "Listening on http://#{host}:#{port}"
        server.listen
    end
end


ENV["ENV"] ||= "production"

Server.start_server
