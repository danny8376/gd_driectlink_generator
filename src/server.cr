require "http/server"
require "http/client"
require "yaml"

module Server
  struct Config
    struct Bind
      YAML.mapping(
        host:   String,
        port:   Int32,
      )
    end
    struct APIKey
      YAML.mapping(
        main:       String,
        publicdl:   String,
      )
    end
    struct Cache
      YAML.mapping(
        expire:     UInt32,
        size:       UInt32,
      )
    end
    YAML.mapping(
      bind:   Bind,
      apikey: APIKey,
      cache:  Cache,
    )
  end

  # read example as default config value 030
  @@conf = Config.from_yaml(File.read("./config.yml.example"))
  def self.load_config(yaml = File.read("./config.yml"))
    @@conf = Config.from_yaml yaml
  end

  struct CacheNode
    property filesize, update
    def initialize(@filesize : Int64, @update : Time)
    end
  end

  @@cache = {} of String => CacheNode
  def self.init_cache
    @@cache.clear
  end

  def self.insert_cache(fid, filesize)
    if @@cache.size >= @@conf.cache.size
      old = @@cache.min_by { |_, v| v.update }
      @@cache.delete old[0]
    end
    @@cache[fid] = CacheNode.new filesize, Time.now
  end

  def self.check_cache(fid, data_proc, valid_proc)
    now = Time.now
    cache = @@cache[fid]?
      expire = @@conf.cache.expire
    # if cache still valid, just return it
    return cache.filesize if cache && (now - cache.update).total_seconds < expire
    # if no cache or expired, run block
    filesize = data_proc.call
    insert_cache fid, filesize if valid_proc.call filesize
    filesize
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
    check_cache(fid, -> {
      link = GD_APIDL_PATH % [fid, @@conf.apikey.main]
      res = gapi_cli.head link
      return -res.status_code.to_i64 unless res.status_code == 200
      return res.headers["Content-Length"].to_i64
    }, ->(filesize : Int64) {
      filesize > 0 || filesize == -404 # valid size or not found is cachable data
    })
  end

  def self.get_apidirectlink(fid)
    return GD_APIDL % [fid, @@conf.apikey.publicdl]
  end

  def self.auto_directlink(fid, forward = false)
    filesize = gd_filesize fid
    if filesize < 0 # error
      return "ERR#{-filesize}"
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
      if link.starts_with? "ERR"
        case link
        when "ERR404"
          context.response.status_code = 404
          context.response.print "FID: #{fid} not exist or not shared"
        when "ERR403"
          context.response.status_code = 503
          context.response.print "Google Drive API Quota exceeded, try again later QAQ"
        else
          context.response.status_code = 500
          context.response.print "Something weird happend OAO"
        end
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
    init_cache

    host = @@conf.bind.host if host.empty?
    port = @@conf.bind.port if port < 0

    server = HTTP::Server.new(host, port, [
      HTTP::ErrorHandler.new ENV["ENV"] == "debug",
    ]) { |context| handle_request context }

    puts "Listening on http://#{host}:#{port}"
    server.listen
  end
end


ENV["ENV"] ||= "production"

Server.start_server
