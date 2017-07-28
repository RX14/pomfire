class Pomfire::FileCache
  @b2 : B2::Client
  @b2_bucket : String
  @file_dir : String
  @missing_cache = Hash(String, Bool).new
  @mutex = Mutex.new

  def initialize(@b2 = B2::Client.new, @b2_bucket = ENV["POMF_B2_BUCKET"], @file_dir = ENV["POMF_CACHE_DIR"])
  end

  enum FileStatus
    Missing
    Cached
    Downloaded
  end

  def get_file(name : String) : FileStatus
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
        @b2.download_file_by_name(@b2_bucket, name) do |io|
          File.open(local_file_path, "w") do |file|
            IO.copy(io, file)
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
    clear_missing(name)
  end

  private def file_path(name)
    File.join(@file_dir, name)
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
