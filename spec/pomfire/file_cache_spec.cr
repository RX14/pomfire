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
