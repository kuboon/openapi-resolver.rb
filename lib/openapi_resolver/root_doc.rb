require "uri"
require "yaml"
require_relative "doc_pointer"

class OpenapiResolver
  class RootDoc < DocPointer
    def server_urls
      @memo[:server_urls] ||= doc["servers"].map { URI.parse(_1["url"]) }
    end

    def match?(request)
      !!partial_path(request)
    end

    def each_schema(request:, response:, &)
      return enum_for(__method__, request:, response:) unless block_given?
      request = Request.new(**request) if request.is_a?(Hash)
      response = Response.new(**response) if response.is_a?(Hash)
      partial_path = self.partial_path(request)
      raise Error.new("unknown path #{request.path}") unless partial_path
      matched = path_matchers.find do |regex, path|
        match = regex.match(partial_path)
        break [match.named_captures, path] if match
      end
      raise Error.new("unknown path #{partial_path}") unless matched

      path_parameters, path = matched
      path_item = doc["paths"][path]
      if ref?(path_item)
        doc["paths"][path] = resolve_ref(path_item)
        path_item = PathItem.new(doc["paths"][path])
      elsif path_item.is_a?(DocPointer)
        path_item = PathItem.new(path_item)
      else
        path_item = PathItem.new(dig_new("paths", path))
      end
      begin
        path_item.parameters_and_operation_for_method(request.method) => {parameters:, operation:}

        if parameters in path: path_param
          yield path_param, "#", path_parameters.to_h, "path parameters for #{path} in #{uri}"
        end

        if parameters in query:
          yield query, "#", request.GET, "query parameters for #{path} in #{uri}"
        end

        if parameters in header:
          raise "not implemented yet #{header}"
        end

        if parameters in cookie:
          raise "not implemented yet #{cookie}"
        end

        operation.each_schema(request:, response:, &)
      rescue => e
        doc_pointer = path_item.doc_pointer
        raise Error.wrap(e).add_message({uri: doc_pointer.uri.to_s, fragment: doc_pointer.fragment})
      end
    end

    private

    def partial_path(request)
      server_urls.each do |server_url|
        if request.path.start_with?(server_url.path)
          return request.path.sub(server_url.path, "")
        end
      end
      nil
    end

    def path_matchers
      @memo[:path_matchers] ||= doc["paths"].keys.sort.map do |path|
        path_regex = path.gsub(%r"\{[^}]+\}") {
          "(?<#{$&.delete("{}")}>[^/]+)"
        }
        regex = Regexp.new("\\A#{path_regex}\\Z")
        [regex, path]
      end.freeze
    end
  end
end
