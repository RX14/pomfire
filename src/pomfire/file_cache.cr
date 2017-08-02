class Pomfire::FileCache
  @b2 : B2::Client
  @b2_bucket : String
  @file_dir : String
  @missing_cache = Hash(String, Bool).new
  @mutex = Mutex.new

  def initialize(@b2 = B2::Client.new, @b2_bucket = ENV["POMF_B2_BUCKET"], @file_dir = ENV["POMF_CACHE_DIR"])
    spawn do
      loop do
        size = @mutex.@queue.try(&.size)
        if size && size != 0
          puts "#{size} fibers waiting on b2!"
        end
        sleep 1.second
      end
    end
  end

  enum FileStatus
    Missing
    Cached
    Downloaded
  end

  def get_file(name : String) : FileStatus
    name = normalise_name(name)
    return FileStatus::Missing if missing? name

    local_file_path = file_path(name)
    if File.exists? local_file_path
      File.open(local_file_path, "r") do |file|
        yield file, FileStatus::Cached
        return FileStatus::Cached
      end
    end

    begin
      @mutex.synchronize do
        @b2.download_file_by_name(@b2_bucket, name) do |io, metadata|
          File.open(local_file_path, "w") do |file|
            io = OpenSSL::DigestIO.new(io, "sha1")
            IO.copy(io, file)
            raise "Invalid download, try again!" unless io.hexdigest == metadata.sha1
          end
        end
      end

      File.open(local_file_path, "r") do |file|
        yield file, FileStatus::Downloaded
        return FileStatus::Downloaded
      end
    rescue ex : B2::APIError
      if ex.error.code == "not_found"
        set_missing(name)
        return FileStatus::Missing
      else
        raise ex
      end
    end

    raise "BUG: unreachable"
  end

  def put_file(name : String, io : IO) : Nil
    name = normalise_name(name)
    clear_missing(name)
  end

  private def file_path(name)
    File.join(@file_dir, name)
  end

  private def normalise_name(name)
    reader = Char::Reader.new(name)
    last_was_slash? = false
    name = String.build do |str|
      reader.each do |char|
        if {'\\', '/'}.includes? char
          str << '/' unless last_was_slash?
          last_was_slash? = true
        else
          str << char
          last_was_slash? = false
        end
      end
    end

    name.split('/') do |segment|
      raise "Invalid Path" if segment == ".."
    end

    name
  end

  private def missing?(name : String)
    @missing_cache[name]? == true
  end

  private def set_missing(name : String)
    @missing_cache[name] = true
  end

  private def clear_missing(name : String)
    @missing_cache.delete(name)
  end
end
