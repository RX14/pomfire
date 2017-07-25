enum B2::BucketType
  AllPublic
  AllPrivate

  def serialised_string
    case self
    when AllPrivate
      "allPrivate"
    when AllPublic
      "allPublic"
    else
      raise "Invalid enum value!"
    end
  end
end
