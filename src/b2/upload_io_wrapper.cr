# :nodoc:
class B2::UploadIOWrapper
  include IO

  def initialize(@io : IO, @size : Int64)
    raise ArgumentError.new "Negative read_size" if @size < 0
    @digest = OpenSSL::Digest.new("SHA1")
  end

  def self.new(io : IO, size : Int)
    new(io, size.to_i64)
  end

  DIGEST_LENGTH = 40

  def read(slice : Bytes) : Int32
    if @size > 0
      # Read from body
      count = {slice.size.to_i64, @size}.min
      bytes_read = @io.read(slice[0, count])

      @digest.update(slice[0, bytes_read])
      @size -= bytes_read

      bytes_read
    else
      # Read from hexdigest

      # Return EOF if fully read digest
      return 0 if @size == -DIGEST_LENGTH

      digest = @digest.hexdigest.to_slice
      # Negative @size represents bytes read into the digest
      digest += -@size

      count = {slice.size, digest.size}.min
      slice.copy_from(digest[0, count])

      @size -= count

      count
    end
  end

  def write(slice : Bytes)
    raise IO::Error.new "Can't write to UploadIOWrapper"
  end

  def close
    raise IO::Error.new "Can't close UploadIOWrapper"
  end
end
