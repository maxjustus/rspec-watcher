require 'rspec/core'
require 'rspec/expectations'

describe "test" do
  it "blends" do
    expect(1).to eq(1)
  end

  describe 'RspecWatcher::Rg' do
    it "finds matching specs" do
      expect(1).to eq(1)
    end
  end
end

