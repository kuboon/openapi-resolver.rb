require "json_schemer"

require "test_helper"
require "open-uri"
require "yaml"

class OpenapiResolverTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::OpenapiResolver::VERSION
  end
end

describe OpenapiResolver do
  let(:instance) { OpenapiResolver.new }

  before do
    instance.register("test/fixtures/root.yaml")
  end

  describe "#each_schema" do
    subject do
      instance.each_schema(request: request, response: response) do |schema, fragment, data, context|
        # p(schema:, fragment:, data:, context:)
        schemer = JSONSchemer.schema(schema, ref_resolver: instance.loader).ref(fragment)
        assert schemer.valid?(data)
      end
    end

    describe "GET /v1/pets" do
      let(:request) { {method: "GET", path: "/v1/pets"} }
      let(:response) { {status: 200, body: [{id: 123, name: "hoge"}]} }
      it { subject }
    end
    describe "GET /v1/pets/123" do
      let(:request) { {method: "GET", path: "/v1/pets/123"} }
      let(:response) { {status: 200, body: {id: 123, name: "hoge"}} }
      it { subject }
    end
  end
end
