require "./spec_helper"

private module SpecMethods
  extend Spec::Methods
end

private def it(*args, **kwargs, &block)
  if ENV["B2_ACCOUNT_ID"]? && ENV["B2_APPLICATION_KEY"]?
    SpecMethods.it(*args, **kwargs, &block)
  else
    SpecMethods.pending(*args, **kwargs, &block)
  end
end

private def validate_uri(uri)
  uri = URI.parse(uri) unless uri.is_a? URI
  uri.scheme.should eq("https")
  uri.host.should_not eq(nil)
  uri.path.should_not eq(nil)
end

module B2
  class_property(test_client) { B2::Client.new }
end

private def with_bucket
  bucket = B2.test_client.create_bucket("crystal-b2-test")
  yield bucket
ensure
  begin
    B2.test_client.delete_bucket(bucket) if bucket
  rescue ex
    STDERR.puts "Exception while deleting file:"
    ex.inspect_with_backtrace(STDERR)
  end
end

describe B2::Client do
  it "initializes a new client" do
    client = B2::Client.new
    client.authorisation.account_id.should eq(ENV["B2_ACCOUNT_ID"])
    validate_uri(client.authorisation.api_url)
    validate_uri(client.authorisation.download_url)
    client.authorisation.recommended_part_size.should be > 0
    client.authorisation.absolute_minimum_part_size.should be > 0
  end

  it "creates and deletes a new bucket" do
    lifecycle_rules = [
      B2::LifecycleRule.new(
        file_name_prefix: "lifecycle_rule/",
        days_from_uploading_to_hiding: 2,
        days_from_hiding_to_deleting: 10
      ),
    ]

    begin
      bucket = B2.test_client.create_bucket("crystal-b2-test", type: B2::BucketType::AllPublic,
        bucket_info: {"foo": "bar"}, lifecycle_rules: lifecycle_rules)

      bucket.name.should eq("crystal-b2-test")
      bucket.type.should eq(B2::BucketType::AllPublic)
      bucket.bucket_info["foo"]?.should eq("bar")
      bucket.lifecycle_rules.should eq(lifecycle_rules)
      bucket.revision.should eq(1)
    ensure
      B2.test_client.delete_bucket(bucket) if bucket
    end
  end

  it "uploads and downloads files" do
    with_bucket do |bucket|
      begin
        file = B2.test_client.upload_file(bucket, "test.txt", "hello world")
      rescue ex
        p ex
        raise ex
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
end
