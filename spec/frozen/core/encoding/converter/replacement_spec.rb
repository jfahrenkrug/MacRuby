require File.expand_path('../../../../spec_helper', __FILE__)

with_feature :encoding do
  describe "Encoding::Converter#replacement" do
    it "returns '?' in US-ASCII when the destination encoding is not UTF-8" do
      ec = Encoding::Converter.new("utf-8", "us-ascii")
      ec.replacement.should == "?"
      ec.replacement.encoding.should == Encoding::US_ASCII

      ec = Encoding::Converter.new("utf-8", "sjis")
      ec.replacement.should == "?"
      ec.replacement.encoding.should == Encoding::US_ASCII
    end

    it "returns \u{fffd} when the destination encoding is UTF-8" do
      ec = Encoding::Converter.new("us-ascii", "utf-8")
      ec.replacement.should == "\u{fffd}".force_encoding('utf-8')
      ec.replacement.encoding.should == Encoding::UTF_8
    end
  end

  describe "Encoding::Converter#replacement=" do
    it "accepts a String argument" do
      ec = Encoding::Converter.new("utf-8", "us-ascii")
      lambda { ec.replacement = "!" }.should_not raise_error(ArgumentError)
    end

    it "accepts a String argument of arbitrary length" do
      ec = Encoding::Converter.new("utf-8", "us-ascii")
      lambda { ec.replacement = "?!?" * 9999 }.should_not raise_error(ArgumentError)
      ec.replacement.should == "?!?" * 9999
    end

    it "raises an TypeError if assigned a non-String argument" do
      ec = Encoding::Converter.new("utf-8", "us-ascii")
      lambda { ec.replacement = nil }.should raise_error(TypeError)
    end

    it "sets #replacement" do
      ec = Encoding::Converter.new("us-ascii", "utf-8")
      ec.replacement.should == "\u{fffd}".force_encoding('utf-8')
      ec.replacement = '?'.encode('utf-8')
      ec.replacement.should == '?'.force_encoding('utf-8') 
    end

    it "raises an UndefinedConversionError is the argument cannot be converted into the destination encoding" do
      ec = Encoding::Converter.new("sjis", "ascii")
      utf8_q = "\u{986}".force_encoding('utf-8')
      ec.primitive_convert(utf8_q,"").should == :undefined_conversion
      lambda { ec.replacement = utf8_q }.should \
        raise_error(Encoding::UndefinedConversionError)
    end

    it "does not change the replacement character if the argument cannot be converted into the destination encoding" do
      ec = Encoding::Converter.new("sjis", "ascii")
      utf8_q = "\u{986}".force_encoding('utf-8')
      ec.primitive_convert(utf8_q,"").should == :undefined_conversion
      lambda { ec.replacement = utf8_q }.should \
        raise_error(Encoding::UndefinedConversionError)
      ec.replacement.should == "?".force_encoding('us-ascii')
    end
  end
end
