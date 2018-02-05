require "spec"
require "file_utils"
require "../src/pomfire"

private module SpecMethods
  extend Spec::Methods
end

def it(description, file = __FILE__, line = __LINE__, end_line = __END_LINE__, &block)
  if ENV["B2_ACCOUNT_ID"]? && ENV["B2_APPLICATION_KEY"]?
    SpecMethods.it(description, file: file, line: line, end_line: end_line, &block)
  else
    SpecMethods.pending(description, file: file, line: line, end_line: end_line, &block)
  end
end

module B2
  class_property(test_client) { B2::Client.new }
end

def with_bucket
  bucket = B2.test_client.create_bucket("crystal-b2-test")
  yield bucket
ensure
  begin
    B2.test_client.delete_bucket(bucket) if bucket
  rescue ex
    STDERR.puts "Exception while deleting bucket:"
    ex.inspect_with_backtrace(STDERR)
  end
end

def with_file(name, contents)
  with_bucket do |bucket|
    begin
      file = B2.test_client.upload_file(bucket, name, contents)
      yield bucket, file
    ensure
      begin
        B2.test_client.delete_file_version(file) if file
      rescue ex
        STDERR.puts "Exception while deleting file:"
        ex.inspect_with_backtrace(STDERR)
      end
    end
  end
end

def with_tempdir
  tempdir = File.join("/tmp", Random::Secure.hex)
  Dir.mkdir(tempdir)
  yield tempdir
ensure
  begin
    FileUtils.rm_rf(tempdir) if tempdir
  rescue ex
    STDERR.puts "Exception while removing tempdir:"
    ex.inspect_with_backtrace(STDERR)
  end
end
