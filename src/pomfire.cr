require "uri"
require "./b2"
require "./pomfire/*"

module Pomfire
  def self.handle_request(ctx, file_cache)
    file_name = ctx.request.path.lstrip '/'

    if file_name == ""
      # Root
      ctx.response.puts "aww.moe is in readonly mode, uploads coming soon!"
      return
    end

    res = file_cache.get_file(file_name) do |io, res|
      case res
      when .cached?
        ctx.response.headers["X-Pomf-Cache-Status"] = "Cached"
      when .downloaded?
        ctx.response.headers["X-Pomf-Cache-Status"] = "Downloaded"
      end

      if io.is_a? File
        ctx.response.content_type = mime_type = `file -b --mime-type #{io.path}`.strip
      end

      puts "Serving: #{file_name} #{mime_type} #{res}"

      IO.copy(io, ctx.response)
    end

    if res.missing?
      ctx.response.status_code = 404
      ctx.response.puts "Not Found"
    end
  rescue ex
    ctx.response.status_code = 500
    ctx.response.puts "#{ex.message} (#{ex.class})"
    ex.inspect_with_backtrace(STDERR)
  end

  def self.run(args = ARGV)
    # Uses settings from ENV by default
    file_cache = Pomfire::FileCache.new

    middleware = [HTTP::LogHandler.new]
    host = ENV["POMF_BIND_HOST"]? || "127.0.0.1"
    port = (ENV["POMF_PORT"]? || 80).to_i
    server = HTTP::Server.new(host, port, middleware) { |ctx| handle_request(ctx, file_cache) }

    puts "Listening on #{URI.new(scheme: "http", host: host, port: port)}"
    server.listen
  end
end
