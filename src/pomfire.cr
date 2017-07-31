require "uri"
require "./b2"
require "./pomfire/*"

module Pomfire
  def self.eat_epipe
    yield
  rescue errno : Errno
    raise errno unless errno.errno == Errno::EPIPE
  end

  def self.handle_request(ctx, file_cache)
    file_name = ctx.request.path.lstrip '/'

    if file_name == ""
      # Root
      eat_epipe do
        ctx.response.puts "aww.moe is in readonly mode, uploads coming soon!"
        ctx.response.flush
      end
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

      eat_epipe do
        IO.copy(io, ctx.response)
      end
    end

    if res.missing?
      ctx.response.status_code = 404
      eat_epipe do
        ctx.response.puts "Not Found"
      end
    end

    eat_epipe do
      ctx.response.flush
    end
  rescue ex
    ctx.response.status_code = 500
    eat_epipe do
      ctx.response.puts "#{ex.message} (#{ex.class})"
      ctx.response.flush
    end
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
