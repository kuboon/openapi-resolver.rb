class OpenapiResolver
  class PathItem
    attr_reader :doc_pointer
    def initialize(doc_pointer)
      @doc_pointer = doc_pointer
      @memo = {}
    end

    def inspect
      "#<PathItem uri=#{uri} fragment=#{fragment}>"
    end

    def parameters_and_operation_for_method(method_)
      method = method_.downcase
      raise Error.new("unknown method '#{method}' for #{doc_pointer.fragment}") unless doc_pointer[method]
      @memo[method] ||= begin
        operation = doc_pointer.dig_new(method)

        doc_pointer.deep_resolve(doc_pointer["parameters"]) if doc_pointer["parameters"]
        doc_pointer.deep_resolve(operation["parameters"]) if operation["parameters"]

        parameters = doc_pointer["parameters"].to_a + operation["parameters"].to_a
        {
          parameters: generate_unified_parameters(parameters),
          operation: Operation.new(operation)
        }
      rescue Error => e
        raise e.add_message({doc_pointer:, method:})
      end
    end

    private

    def generate_unified_parameters(parameters)
      parameters.group_by { _1["in"].to_sym }.transform_values do |params|
        required = params.select { _1["required"] }.map { _1["name"] }
        properties = params.each_with_object({}) do |param, hash|
          hash[param["name"]] = param["schema"]
        end
        {
          "type" => "object",
          "properties" => properties,
          "required" => required
        }
      end
    rescue => e
      raise Error.wrap(e).add_message({parameters:})
    end
  end
end
