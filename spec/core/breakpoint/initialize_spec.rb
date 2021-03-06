require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/fixtures/classes'

describe "GlobalBreakpoint#initalize" do

  before :all do
    @cm = BreakpointSpecs::Debuggee.instance_method(:simple_method).compiled_method
    @cm.iseq = BreakpointSpecs::Debuggee.orig_bytecodes.dup
  end

  it "converts a missing instruction pointer argument to 0" do
    bp = GlobalBreakpoint.new(@cm) {}
    bp.ip.should == 0
  end

  it "throws an ArgumentError if the IP is out of range" do
    lambda { GlobalBreakpoint.new(@cm, -1) {} }.should raise_error(ArgumentError)
    lambda { GlobalBreakpoint.new(@cm, 1000) {} }.should raise_error(ArgumentError)
    lambda { GlobalBreakpoint.new(@cm, 10) {} }.should_not raise_error(ArgumentError)
  end

  it "throws an ArgumentError if the IP is not the address of an instruction" do
    lambda { GlobalBreakpoint.new(@cm, 14) {} }.should raise_error(ArgumentError)
  end

  it "does not modify the compiled method instruction sequence" do
    pre = @cm.iseq.decode
    bp = GlobalBreakpoint.new(@cm) {}
    bp.installed?.should == false
    @cm.iseq.decode.should == pre
  end
end
