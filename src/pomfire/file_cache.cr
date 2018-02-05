class Pomfire::FileCache
  @b2 : B2::Client
  @b2_bucket : String
  @file_dir : String
  @missing_cache = Hash(String, Bool).new
  @mutex = Mutex.new
  @max_size : UInt64

  def initialize(@b2 = B2::Client.new,
                 @b2_bucket = ENV["POMF_B2_BUCKET"],
                 @file_dir = ENV["POMF_CACHE_DIR"],
                 @max_size = human_parse(ENV["POMF_CACHE_MAX_SIZE"]))
    spawn do
      loop do
        size = @mutex.@queue.try(&.size)
        if size && size != 0
          puts "#{size} fibers waiting on b2!"
        end
        sleep 1.second
      end
    end

    spawn do
      loop do
        ensure_cache_size
        sleep 5.minutes
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

  private def ensure_cache_size
    puts "Running cleanup..."

    delete_count = 0
    time = Time.measure do
      total_size = 0_u64
      children = Dir.new(@file_dir).each_child.compact_map do |entry|
        filename = File.join(@file_dir, entry)
        stat = File.stat(filename)
        next nil unless stat.file?

        total_size += stat.size
        {name: filename, size: stat.size}
      end
      children = children.to_a

      next unless total_size > @max_size

      target_size = @max_size * 95 / 100
      while total_size > target_size
        random_index = rand(0..children.size)
        random_child = children.delete_at(random_index)

        begin
          File.delete(random_child[:name])
          total_size -= random_child[:size]
          delete_count += 1
        rescue ex
          STDERR.print "FAILED TO DELETE FILE: "
          ex.inspect_with_backtrace(STDERR)
        end
      end
    end

    puts "Cleanup deleted #{delete_count} files in #{time.total_milliseconds}ms"
  end

  private def human_parse(str)
    case str[-1].upcase
    when 'K'
      factor = 1024
    when 'M'
      factor = 1024 * 1024
    when 'G'
      factor = 1024 * 1024 * 1024
    else
      factor = 1
    end

    if factor != 1
      str = str.rchop
    end

    str.to_u64 * factor
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
