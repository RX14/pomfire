require "../spec_helper"

class Pomfire::FileCache
  def call_ensure_cache_size
    ensure_cache_size
  end
end

describe Pomfire::FileCache do
  it "downloads and caches files" do
    with_tempdir do |tempdir|
      with_file("test.txt", "hello world") do |bucket, file|
        cache = Pomfire::FileCache.new(
          b2: B2.test_client,
          b2_bucket: bucket.name,
          file_dir: tempdir,
          max_size: UInt64::MAX
        )

        str = nil
        result = cache.get_file("test.txt") { |io| str = io.gets_to_end }

        str.should eq("hello world")
        result.should eq(Pomfire::FileCache::FileStatus::Downloaded)

        str = nil
        result = cache.get_file("test.txt") { |io| str = io.gets_to_end }

        str.should eq("hello world")
        result.should eq(Pomfire::FileCache::FileStatus::Cached)
      end
    end
  end

  it "returns missing on missing files" do
    with_tempdir do |tempdir|
      with_file("test.txt", "hello world") do |bucket, file|
        cache = Pomfire::FileCache.new(
          b2: B2.test_client,
          b2_bucket: bucket.name,
          file_dir: tempdir,
          max_size: UInt64::MAX
        )

        result = cache.get_file("test") { raise "Called IO block!" }
        result.should eq(Pomfire::FileCache::FileStatus::Missing)
      end
    end
  end

  it "limits cache size" do
    with_tempdir do |tempdir|
      with_file("test.txt", "hello world") do |bucket, file|
        cache = Pomfire::FileCache.new(
          b2: B2.test_client,
          b2_bucket: bucket.name,
          file_dir: tempdir,
          max_size: 0_u64
        )

        Fiber.yield

        result = cache.get_file("test.txt") { |io| io.skip_to_end }
        result.should eq(Pomfire::FileCache::FileStatus::Downloaded)

        result = cache.get_file("test.txt") { |io| io.skip_to_end }
        result.should eq(Pomfire::FileCache::FileStatus::Cached)

        cache.call_ensure_cache_size

        result = cache.get_file("test.txt") { |io| io.skip_to_end }
        result.should eq(Pomfire::FileCache::FileStatus::Downloaded)

        result = cache.get_file("test.txt") { |io| io.skip_to_end }
        result.should eq(Pomfire::FileCache::FileStatus::Cached)
      end
    end
  end
end

private def assert_max_size(string, parsed_number, file = __FILE__, line = __LINE__, end_line = __END_LINE__)
  it "parses human-readable max_size", file, line, end_line do
    with_tempdir do |tempdir|
      file_cache = Pomfire::FileCache.new(B2.test_client, "", tempdir, string)
      file_cache.@max_size.should eq(parsed_number)
    end
  end
end

private def assert_invalid_size(string, file = __FILE__, line = __LINE__, end_line = __END_LINE__)
  it "parses human-readable max_size", file, line, end_line do
    with_tempdir do |tempdir|
      expect_raises(Exception) do
        Pomfire::FileCache.new(B2.test_client, "", tempdir, string)
      end
    end
  end
end

describe Pomfire::FileCache do
  assert_max_size "0", 0
  assert_max_size "1", 1
  assert_max_size "1k", 1024
  assert_max_size "1K", 1024
  assert_max_size "512m", 512 * 1024**2
  assert_max_size " 1M", 1024**2
  assert_max_size "1g", 1024**3
  assert_max_size "1.5G", 1536 * 1024**2

  assert_invalid_size "foo"
  assert_invalid_size ""
  assert_invalid_size "1kk"
  assert_invalid_size "1k "
end
