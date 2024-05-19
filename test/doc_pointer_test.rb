require "test_helper"
require "yaml"
require "uri"

describe OpenapiResolver::DocPointer do
  let(:doc_pointer) { OpenapiResolver::DocPointer.new(uri:) }
  let(:uri) { URI::File.build(path: Pathname.pwd.join("./test/fixtures/root.yaml").to_s) }

  describe "#deep_resolve" do
    it do
      doc_pointer.deep_resolve
      expect(doc_pointer.dig("paths", "/pets").class).must_equal(OpenapiResolver::DocPointer)
      expect(doc_pointer.dig("paths", "/pets", "get")).must_not_be_nil
    end
  end
end
