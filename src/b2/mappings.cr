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

  alias JSONScalar = String | Int::Primitive | Float::Primitive | Bool | Nil

  struct Bucket
    JSON.mapping({
      account_id:      {type: String, key: "accountId"},
      id:              {type: String, key: "bucketId"},
      name:            {type: String, key: "bucketName"},
      type:            {type: BucketType, key: "bucketType"},
      bucket_info:     {type: Hash(String, JSONScalar), key: "bucketInfo"},
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
      file_info:        {type: Hash(String, JSONScalar), key: "fileInfo"},
      action:           String,
      upload_timestamp: {type: Time, key: "uploadTimestamp", converter: TimestampConverter},
    })
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
