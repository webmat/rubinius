require File.dirname(__FILE__) + '/../../spec_helper'

describe "CType#islower" do
  it "returns true if self is between a..z" do
    a = []
    "MenTaLguY".each_byte { |b| a << b.islower }
    a.should == [false, true, true, false, true, false, true, true, false]
  end
end
