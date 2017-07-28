require "secure_random"
require "../spec_helper"

describe Pomfire::FileCache do
  it "downloads and caches files" do
    with_tempdir do |tempdir|
      with_file("test.txt", "hello world") do |bucket, file|
        cache = Pomfire::FileCache.new(B2.test_client, bucket.name, tempdir)

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
        cache = Pomfire::FileCache.new(B2.test_client, bucket.name, tempdir)

        result = cache.get_file("test") { raise "Called IO block!" }
        result.should eq(Pomfire::FileCache::FileStatus::Missing)
      end
    end
  end
end
