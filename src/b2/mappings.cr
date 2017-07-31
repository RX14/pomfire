require "json"

module B2
  struct ErrorResponse
    JSON.mapping({
      status:  Int32,
      code:    String,
      message: String,
    })
  end

  struct AuthoriseAccountResponse
    JSON.mapping({
      account_id:                 {type: String, key: "accountId"},
      authorisation_token:        {type: String, key: "authorizationToken"},
      api_url:                    {type: String, key: "apiUrl"},
      download_url:               {type: String, key: "downloadUrl"},
      recommended_part_size:      {type: Int32, key: "recommendedPartSize"},
      absolute_minimum_part_size: {type: Int32, key: "absoluteMinimumPartSize"},
    })
  end

  struct LifecycleRule
    JSON.mapping({
      file_name_prefix:              {type: String, key: "fileNamePrefix"},
      days_from_uploading_to_hiding: {type: Int32, key: "daysFromUploadingToHiding"},
      days_from_hiding_to_deleting:  {type: Int32, key: "daysFromHidingToDeleting"},
    })

    def initialize(@file_name_prefix, @days_from_uploading_to_hiding, @days_from_hiding_to_deleting)
    end
  end

  struct Bucket
    JSON.mapping({
      account_id:      {type: String, key: "accountId"},
      id:              {type: String, key: "bucketId"},
      name:            {type: String, key: "bucketName"},
      type:            {type: BucketType, key: "bucketType"},
      bucket_info:     {type: Hash(String, String), key: "bucketInfo"},
      lifecycle_rules: {type: Array(LifecycleRule), key: "lifecycleRules"},
      revision:        Int32,
    })
  end

  struct UploadURLResponse
    JSON.mapping({
      bucket_id:           {type: String, key: "bucketId"},
      upload_url:          {type: String, key: "uploadUrl"},
      authorisation_token: {type: String, key: "authorizationToken"},
    })
  end

  struct File
    JSON.mapping({
      account_id:       {type: String, key: "accountId"},
      bucket_id:        {type: String, key: "bucketId"},
      id:               {type: String, key: "fileId"},
      name:             {type: String, key: "fileName"},
      size:             {type: Int64, key: "contentLength"},
      sha1:             {type: String, key: "contentSha1"},
      content_type:     {type: String, key: "contentType"},
      file_info:        {type: Hash(String, String), key: "fileInfo"},
      action:           String,
      upload_timestamp: {type: Time, key: "uploadTimestamp", converter: TimestampConverter},
    })
  end

  struct FileDownloadMetadata
    getter id : String
    getter name : String
    getter sha1 : String
    getter file_info : Hash(String, String)

    def initialize(@id, @name, @sha1, @file_info)
    end

    def self.from_headers(headers)
      id = headers["X-Bz-File-Id"]
      name = headers["X-Bz-File-Name"]
      sha1 = headers["X-Bz-Content-Sha1"]

      file_info = Hash(String, String).new
      headers.each do |key, values|
        next unless values.size == 1
        value = values[0]

        if key.starts_with? "X-Bz-Info-"
          key = key["X-Bz-Info-".size..-1]
          file_info[key] = value
        end
      end

      self.new(id, name, sha1, file_info)
    end
  end

  struct DeleteFileVersionResponse
    JSON.mapping({
      file_name: {type: String, key: "fileName"},
      file_id:   {type: String, key: "fileId"},
    })
  end

  module TimestampConverter
    def self.to_json(value, builder)
      builder.scalar(value.epoch_ms)
    end

    def self.from_json(parser)
      Time.epoch_ms(parser.read_int)
    end
  end
end
