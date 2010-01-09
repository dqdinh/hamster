require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

require 'hamster/stack'

describe Hamster::Stack do

  [:to_a, :entries].each do |method|

    describe "##{method}" do

      [
        [[], []],
        [["A"], ["A"]],
        [["A", "B", "C"], ["C", "B", "A"]],
      ].each do |values, expected|

        describe "on #{values.inspect}" do

          before do
            @stack = Hamster.stack(*values)
            @result = @stack.send(method)
          end

          it "returns #{expected.inspect}" do
            @result.should == expected
          end

        end

      end

    end

  end

end
