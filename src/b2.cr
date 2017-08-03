require "http"
require "./b2/*"

# class HTTP::Client
#   def exec(request : HTTP::Request, &block)
#     puts
#     puts "==> #{request.method} #{request.resource} #{request.version}"
#     p request.headers

#     start_time = Time.now
#     previous_def(request) do |response|
#       puts "<== #{response.status_code} in #{(Time.now - start_time).total_milliseconds}ms"
#       p response.headers

#       wrapped_io = IO::Memory.new(response.body_io.gets_to_end)
#       p wrapped_io.to_s
#       new_response = HTTP::Client::Response.new(response.status_code, response.body?, response.headers, response.status_message, response.version, wrapped_io)
#       puts
#       yield new_response
#     end
#   end
# end

class B2::Client
  getter! authorisation : AuthoriseAccountResponse

  def initialize(@account_id = ENV["B2_ACCOUNT_ID"], @application_key = ENV["B2_APPLICATION_KEY"])
    authorise_account
  end

  def authorise_account
    uri = URI.parse("https://api.backblazeb2.com/b2api/v1/b2_authorize_account")
    uri.user = @account_id
    uri.password = @application_key

    puts "Authorising account!"
    @authorisation = call("GET", uri, type: AuthoriseAccountResponse, auth: false)
  end

  def call?(method, uri, type : SuccessType.class, headers = HTTP::Headers.new, body : String? = nil, auth = true) forall SuccessType
    delay = 1.second
    error = nil
    loop do
      headers["Authorization"] = authorisation.authorisation_token if auth
      HTTP::Client.exec(method, uri, headers: headers, body: body) do |response|
        if response.status_code == 200
          return SuccessType.from_json(response.body_io)
        else
          error = ErrorResponse.from_json(response.body_io)

          if error.status == 429 && (retry_after = response.headers["Retry-After"]?)
            # Too many requests
            sleep retry_after.to_i.seconds

            # Delay for half a second, so the next request has a delay of 1
            # second, effectively resetting the loop.
            delay = 0.5.seconds
          elsif auth && error.status == 401 && error.code == "expired_auth_token"
            authorise_account
          elsif response.status_code == 408 || 500 <= response.status_code < 600
            # Service error, retry
          else
            return error
          end
        end

        nil
      end

      sleep delay
      delay *= 2

      break if delay > 64.seconds
    end

    error.not_nil!
  end

  def call(method, uri, type : SuccessType.class, headers = HTTP::Headers.new, body : String? = nil, auth = true) forall SuccessType
    response = call?(method, uri, type, headers, body, auth)
    raise APIError.new(response) if response.is_a? ErrorResponse
    response
  end

  def create_bucket(name, type = BucketType::AllPrivate,
                    bucket_info = nil, lifecycle_rules : Array(LifecycleRule)? = nil)
    body = JSON.build do |json|
      json.object do
        json.field "accountId", authorisation.account_id
        json.field "bucketName", name
        json.field "bucketType", type.serialised_string
        json.field "bucketInfo" { bucket_info.to_json(json) } if bucket_info
        json.field "lifecycleRules" { lifecycle_rules.to_json(json) } if lifecycle_rules
      end
    end

    call("POST", api_url("b2_create_bucket"), Bucket, body: body)
  end

  def delete_bucket(bucket_id : String)
    call("POST", api_url("b2_delete_bucket"), Bucket, body: {
      accountId: authorisation.account_id,
      bucketId:  bucket_id,
    }.to_json)
  end

  def delete_bucket(bucket : Bucket)
    delete_bucket(bucket.id)
  end

  def download_file_by_name(bucket : String, name : String) : FileDownloadMetadata
    delay = 1.second
    error = nil
    loop do
      headers = HTTP::Headers{"Authorization" => authorisation.authorisation_token}
      HTTP::Client.get(download_url(bucket, name), headers) do |response|
        if response.status_code == 200
          metadata = FileDownloadMetadata.from_headers(response.headers)
          yield response.body_io, metadata
          return metadata
        else
          error = ErrorResponse.from_json(response.body_io)

          if error.status == 429 && (retry_after = response.headers["Retry-After"]?)
            # Too many requests
            sleep retry_after.to_i.seconds

            # Delay for half a second, so the next request has a delay of 1
            # second, effectively resetting the loop.
            delay = 0.5.seconds
          elsif error.status == 401 && error.code == "expired_auth_token"
            authorise_account
          elsif response.status_code == 408 || 500 <= response.status_code < 600
            # Service error, retry
          else
            raise APIError.new(error)
          end
        end

        nil
      end

      sleep delay
      delay *= 2

      break if delay > 64.seconds
    end

    raise APIError.new(error.not_nil!)
  end

  def download_file_by_name(bucket : Bucket, name : String)
    download_file_by_name(bucket.name, name) { |io| yield io }
  end

  def get_upload_url(bucket_id : String)
    call("POST", api_url("b2_get_upload_url"), UploadURLResponse, body: {bucketId: bucket_id}.to_json)
  end

  def get_upload_url(bucket : Bucket)
    get_upload_url(bucket.id)
  end

  def upload_file(bucket, file_name, size = nil, sha1_hash = nil, content_type = "b2/x-auto", by_parts = nil) : File
    raise ArgumentError.new("Must provide size unless forced by_parts") if size.nil? && !by_parts
    upload_file_single(bucket, file_name, size, sha1_hash, content_type) { yield }

    # if by_parts.nil?
    #   # Figure out whether we want to use parts or not
    #   if size > authorisation.recommended_part_size * 1.5
    #     upload_file_parts(bucket, file_name, size, sha1_hash, content_type) { yield }
    #   else
    #     upload_file_single(bucket, file_name, size, sha1_hash, content_type) { yield }
    #   end
    # elsif by_parts
    #   upload_file_parts(bucket, file_name, size, sha1_hash, content_type) { yield }
    # else
    #   upload_file_single(bucket, file_name, size, sha1_hash, content_type) { yield }
    # end
  end

  def upload_file(bucket, file_name, data : String | Bytes, sha1_hash = nil, content_type = "b2/x-auto")
    data = data.to_slice if data.is_a? String
    sha1_hash = OpenSSL::SHA1.hash(data.to_unsafe, LibC::SizeT.new(data.size)).to_slice.hexstring

    upload_file(bucket, file_name, data.size, sha1_hash, content_type) do
      IO::Memory.new(data, writeable: false)
    end
  end

  private def upload_file_single(bucket, file_name, size, sha1_hash = nil, content_type = "b2/x-auto")
    headers = HTTP::Headers{
      "X-Bz-File-Name" => URI.escape(file_name),
      "Content-Type"   => content_type,
    }

    if sha1_hash
      headers["X-Bz-Content-Sha1"] = sha1_hash
      headers["Content-Length"] = size.to_s
    else
      headers["X-Bz-Content-Sha1"] = "hex_digits_at_end"
      headers["Content-Length"] = (size + 40).to_s # 40 hex digits extra for sha1
    end

    delay = 1.second
    error = nil
    loop do
      io = yield
      io = UploadIOWrapper.new(io, size) unless sha1_hash

      upload_data = get_upload_url(bucket)
      headers["Authorization"] = upload_data.authorisation_token

      begin
        file_or_error, retry? = perform_upload_request(upload_data, headers, io)
        if file_or_error.is_a? File
          # Succeeded, return
          return file_or_error
        else
          error = file_or_error

          # Failed, raise unless we want to retry
          raise file_or_error unless retry?

          # Ugly hack to communicate a delay reset
          delay = retry? if retry?.is_a? Time::Span
        end
      end

      sleep delay
      delay *= 2

      break if delay > 64.seconds
    end

    raise error.not_nil!
  end

  private def perform_upload_request(upload_data, headers, body : IO)
    uri = URI.parse(upload_data.upload_url)
    client = HTTP::Client.new(uri)
    client.dns_timeout = 10.seconds
    client.connect_timeout = 10.seconds
    client.read_timeout = 10.seconds

    client.post(uri.full_path, headers, body) do |response|
      if response.status_code == 200
        return File.from_json(response.body_io), false
      else
        error = ErrorResponse.from_json(response.body_io)
        ex = APIError.new(error)

        if error.status == 429 && (retry_after = response.headers["Retry-After"]?)
          # Too many requests
          sleep retry_after.to_i.seconds

          # Delay for half a second, so the next request has a delay of 1
          # second, effectively resetting the loop.
          return ex, 0.5.seconds
        elsif error.status == 401 && error.code == "expired_auth_token"
          return ex, true
        elsif response.status_code == 408 || 500 <= response.status_code < 600
          return ex, true
        else
          return ex, false
        end
      end

      nil
    end
  rescue timeout : IO::Timeout
    return timeout, true
  rescue errno : Errno
    return errno, true
  end

  # private def upload_file_parts(bucket, file_name, size = nil, sha1_hash = nil, content_type = "b2/x-auto", &block)
  # end

  def delete_file_version(file_name : String, file_id : String)
    call("POST", api_url("b2_delete_file_version"), DeleteFileVersionResponse, body: {
      fileName: file_name,
      fileId:   file_id,
    }.to_json)
  end

  def delete_file_version(file : File)
    delete_file_version(file.name, file.id)
  end

  private def get_size(slice_or_io : Bytes | IO)
    case slice_or_io
    when Bytes
      slice_or_io.size
    when File, IO::Memory
      # We can tell the size and current position
      slice_or_io.size - slice_or_io.pos
    else
      # We need to be told the size
      raise ArgumentError.new("Cannot detect size from this IO, please provide it manually")
    end
  end

  private def api_url(endpoint)
    api_url = URI.parse(authorisation.api_url)
    api_url.path = "/b2api/v1/#{endpoint}"
    api_url
  end

  private def download_url(bucket, name)
    download_url = URI.parse(authorisation.download_url)
    download_url.path = "/file/#{bucket}/#{name}"
    download_url
  end
end
