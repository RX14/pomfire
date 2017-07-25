require "../spec_helper"

describe B2::UploadIOWrapper do
  it "reads" do
    io = IO::Memory.new "abc"
    wrapper = B2::UploadIOWrapper.new(io, 3)

    wrapper.gets_to_end.should eq("abca9993e364706816aba3e25717850c26c9cd0d89d")
  end

  it "reads single bytes" do
    io = IO::Memory.new "abc"
    wrapper = B2::UploadIOWrapper.new(io, 3)

    str = ""
    while byte = wrapper.read_byte
      str += byte.chr.to_s
    end

    str.should eq("abca9993e364706816aba3e25717850c26c9cd0d89d")
  end

  it "reads limiting length" do
    io = IO::Memory.new "abcde"
    wrapper = B2::UploadIOWrapper.new(io, 3)

    wrapper.gets_to_end.should eq("abca9993e364706816aba3e25717850c26c9cd0d89d")
  end

  it "reads single bytes limiting length" do
    io = IO::Memory.new "abcde"
    wrapper = B2::UploadIOWrapper.new(io, 3)

    str = ""
    while byte = wrapper.read_byte
      str += byte.chr.to_s
    end

    str.should eq("abca9993e364706816aba3e25717850c26c9cd0d89d")
  end
end
