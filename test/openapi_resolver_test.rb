require "test_helper"
require "open-uri"
require 'yaml'

class OpenapiResolverTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::OpenapiResolver::VERSION
  end
end

describe OpenapiResolver do
  let(:instance) { OpenapiResolver.new }

  before do
    instance.register('test/fixtures/root.yaml')
  end

  Request = Data.define(:method, :path, :query_parameters, :body)
  Response = Data.define(:status, :body)

  describe '#each_schema' do
    it do
      instance.each_schema(
        request: {
          method: 'GET',
          path: '/v1/pets/123',
        },
        response: {
          status: 200,
          body: {
            id: 'response',
          }
        }
      ) do |schema, data|
        puts schema:, data:
      end
    end
  end
end
