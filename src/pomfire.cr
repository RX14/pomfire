require "uri"
require "./b2"
require "./pomfire/*"

module Pomfire
  def self.eat_client_errors
    yield
  rescue error : IO::Error
    raise error unless {Errno::EPIPE, Errno::ECONNRESET}.includes? error.os_error
  end

  def self.elapsed_text(elapsed)
    minutes = elapsed.total_minutes
    return "#{minutes.round(2)}m" if minutes >= 1

    seconds = elapsed.total_seconds
    return "#{seconds.round(2)}s" if seconds >= 1

    millis = elapsed.total_milliseconds
    return "#{millis.round(2)}ms" if millis >= 1

    "#{(millis * 1000).round(2)}µs"
  end

  def self.handle_request(ctx, file_cache)
    file_name = URI.decode(ctx.request.path).lstrip '/'

    if file_name == ""
      # Root
      eat_client_errors do
        ctx.response.puts "aww.moe is in readonly mode, uploads coming soon!"
        ctx.response.flush
      end
      return
    end

    time_start = Time.monotonic
    res = file_cache.get_file(file_name) do |io, res|
      case res
      when .cached?
        ctx.response.headers["X-Pomf-Cache-Status"] = "Cached"
      when .downloaded?
        ctx.response.headers["X-Pomf-Cache-Status"] = "Downloaded"
      end

      if io.is_a? File
        ctx.response.content_length = io.size
        ctx.response.content_type = mime_type = `file -b --mime-type #{io.path}`.strip
      end

      puts "Serving: #{file_name} #{mime_type} #{res} first byte in #{elapsed_text(Time.monotonic - time_start)}"

      eat_client_errors do
        IO.copy(io, ctx.response)
      end
    end

    if res.missing?
      ctx.response.status_code = 404
      eat_client_errors do
        ctx.response.puts "Not Found"
      end
    end

    eat_client_errors do
      ctx.response.flush
    end
  rescue ex
    ctx.response.status_code = 500
    eat_client_errors do
      ctx.response.puts "#{ex.message} (#{ex.class})"
      ctx.response.flush
    end
    ex.inspect_with_backtrace(STDERR)
  end

  def self.run(args = ARGV)
    # Uses settings from ENV by default
    file_cache = Pomfire::FileCache.new

    server = HTTP::Server.new([HTTP::LogHandler.new]) { |ctx| handle_request(ctx, file_cache) }

    host = ENV["POMF_BIND_HOST"]? || "127.0.0.1"
    port = (ENV["POMF_PORT"]? || 80).to_i
    address = server.bind_tcp(host, port)

    puts "Listening on http://#{address}"
    server.listen
  end
end
