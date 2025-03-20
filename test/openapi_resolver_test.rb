require "test_helper"
require "json_schemer"
require "rack"

class OpenapiResolverTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::OpenapiResolver::VERSION
  end

  class ValidationError < StandardError; end

  describe OpenapiResolver do
    let(:instance) { OpenapiResolver.new }

    before do
      instance.register("test/fixtures/root.yaml")
    end

    describe "#each_schema" do
      subject do
        errors = []
        instance.each_schema(request:, response:) do |schema, fragment, data, context|
          schemer = JSONSchemer.schema(schema, ref_resolver: instance.loader).ref(fragment)
          results = schemer.validate(data).to_a
          next if results.empty?
          if context.start_with?("query parameters")
            patches = []
            results.each do |result|
              type, error_data, data_pointer = %w[type data data_pointer].map { result[_1] }
              if type == "integer" && error_data.is_a?(String)
                patches << {"op" => "replace", "path" => data_pointer, "value" => error_data.to_i}
              end
            end
            unless patches.empty?
              data = Hana::Patch.new(patches).apply(data)
              results = schemer.validate(data).to_a
            end
          end
          errors.concat([context, results]) unless results.empty?
        end
        errors
      end

      let(:request) do
        method, path_ = self.class.desc.split(" ")
        uri = URI.parse("http://example.com#{path_}")
        path = uri.path
        get = uri.query ? Rack::Utils.parse_query(uri.query) : nil
        {method:, path:, get:}
      end

      describe "GET /v1/pets" do
        let(:response) { {status: 200, parsed_body: [{id: 123, name: "hoge"}]} }
        it("no param") { assert_empty subject }
      end
      describe "GET /v1/pets/123" do
        let(:response) { {status: 200, parsed_body: {id: 123, name: "hoge"}} }
        it { assert_empty subject }
      end

      describe "GET /v1/pets?limit=10" do
        let(:response) { {status: 200, parsed_body: [{id: 123, name: "hoge"}]} }
        it { assert_empty subject }
      end

      describe "GET /v1/pets/456" do
        let(:response) { {status: 200, parsed_body: {id: 456, name: "fuga"}} }
        it { assert_empty subject }
      end

      describe "POST /v1/pets" do
        let(:request) {
          method(:request).super_method.call.merge(post: {id: 789, name: "piyo"})
        }
        let(:response) { {status: 201, parsed_body: nil} }
        it { assert_empty subject }
      end

      describe "GET /v1/pets with invalid query parameters" do
        let(:request) { {method: "GET", path: "/v1/pets", get: {"limit" => "invalid"}} }
        let(:response) { {status: 200, parsed_body: [{id: 123, name: "hoge"}]} }
        it("has no error") { assert_empty subject }
      end

      describe "GET /v1/pets/{petId} with missing path parameters" do
        let(:request) { {method: "GET", path: "/v1/pets"} }
        let(:response) { {status: 200, parsed_body: [{id: 456, name: "fuga"}]} }
        it("has no error") { assert_empty subject }
      end

      describe "GET /unknown/path" do
        let(:request) { {method: "GET", path: "/unknown/path"} }
        let(:response) { {status: 200, parsed_body: [{id: 123, name: "hoge"}]} }
        it "raises validation error" do
          assert_raises(OpenapiResolver::Error) { subject }
        end
      end
    end
  end
end
