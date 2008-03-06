require File.dirname(__FILE__) + '/../../spec_helper'

describe "LookupTable#[]=" do
  before :each do
    @lt = LookupTable.new
  end

  it "adds an entry for the given key, value" do
    @lt[:a] = 1
    @lt[:b] = "2"
    
    @lt[:a].should == 1
    @lt[:b].should == "2"
  end

  it "converts a String key argument to a Symbol" do
    @lt["c"] = 3
    @lt["c"].should == 3
  end

  it "raises a TypeError if passed other than a Symbol or String" do
    key = mock("lookuptable key")
    lambda { @lt[key] = 1 }.should raise_error(TypeError)
  end
end