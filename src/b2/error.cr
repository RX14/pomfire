module B2
  class APIError < Exception
    getter error : ErrorResponse

    def initialize(@error)
      super(@error.message.capitalize)
    end
  end
end
