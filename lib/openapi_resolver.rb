require "forwardable"
require "pathname"

module URI
  class File < Generic
    def open(*args, &)
      ::File.open(path, &)
    end
  end
end

class OpenapiResolver
  autoload :VERSION, "openapi_resolver/version"

  # subset of https://api.rubyonrails.org/classes/ActionDispatch/Request.html
  Request = Data.define(:method, :path, :query_parameters, :body, :headers) do
    def initialize(method:, path:, query_parameters: {}, body: nil, headers: {"Content-Type" => "application/json"})
      super
    end
  end

  # subset of https://api.rubyonrails.org/classes/ActionDispatch/Response.html
  Response = Data.define(:status, :body) do
    def headers
      {"Content-Type" => "application/json"}
    end
  end

  class Error < StandardError
    def self.wrap(e)
      e.is_a?(self) ? e : new("#{e.class.name} #{e.message}").tap { _1.set_backtrace(e.backtrace) }
    end

    def add_message(message)
      @messages ||= []
      @messages << message
      self
    end

    def message
      msg = super
      msg += "\n" + @messages.join("\n") if @messages
      msg
    end
  end

  attr_reader :loader
  def initialize(loader: Loader.new)
    @loader = loader
    @root_docs = []
  end

  def register(uri)
    unless uri.is_a?(URI)
      # uri = Pathname.pwd.join(uri).to_s
      uri = URI::File.build(path: Pathname.pwd.join(uri).to_s)
    end
    @root_docs << RootDoc.new(uri:, loader:)
  end

  def inspect
    "#<#{self.class.name} @root_docs=#{@root_docs}>"
  end

  def each_schema(request:, response:, &)
    request = Request.new(**request) if request.is_a?(Hash)
    root_doc = @root_docs.find { _1.match?(request) }
    raise Error.new("unknown path #{request.path}") unless root_doc
    root_doc.each_schema(request:, response:, &)
  end

  class Loader
    def initialize
      @cache = {}
    end

    def call(uri)
      # raise 'type error' unless uri.is_a?(URI)
      @cache[uri] ||= YAML.load(uri.open(&:read))
    end
  end

  REF = "$ref"
  DocPointer = Data.define(:uri, :segments, :loader) do
    extend Forwardable

    def initialize(uri:, segments: [], loader: Loader.new)
      @memo = {}
      super
    end

    def inspect
      "#<#{self.class.name} @uri=#{uri} @fragment=#{fragment}>"
    end

    def doc
      @memo[:doc] ||= loader.call(uri)
    end

    def fragment
      @memo[:fragment] ||= "#/" + segments.map { |it| it.to_s.gsub("~", "~0").gsub("/", "~1") }.join("/")
    end

    def as_json
      @memo[:json] ||= doc.dig(*segments) or raise Error.new("not found #{fragment} in #{uri}")
    end
    delegate :[] => :as_json

    def dig(*child_segments)
      self.class.new(uri:, segments: segments + child_segments, loader:)
    end

    def ref?(obj)
      return false unless obj.is_a?(Hash) && obj.key?(REF)
      raise Error.new("Invalid $ref") unless obj.size == 1
      true
    end

    def resolve_ref(ref_obj)
      raise Error, "type error" unless ref?(ref_obj)
      path, fragment = ref_obj[REF].split("#")
      uri = self.uri.merge(path)
      segments = fragment.split("/").drop(1).map { URI.decode_www_form_component(_1).gsub("~1", "/").gsub("~0", "~") }
      DocPointer.new(uri:, segments:, loader:)
    end

    def deep_resolve(obj = as_json)
      raise Error, "type error" unless obj.is_a?(Hash) || obj.is_a?(Array)
      iter = obj.is_a?(Array) ? obj.each_with_index.map { [_2, _1] } : obj
      iter.each do |k, v|
        if k.is_a?(String) && k.start_with?("example")
          obj[k] = "[example]"
        elsif ref?(v)
          obj[k] = resolve_ref(v)
          obj[k].deep_resolve
        elsif v.is_a?(Hash) || v.is_a?(Array)
          deep_resolve(v)
        end
      rescue Error => e
        raise e.add_message({k:, v:})
      end
    rescue Error => e
      raise e.add_message({obj:})
    end
  end

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
      unless path_item.is_a?(PathItem)
        doc_pointer =
          if ref?(path_item)
            resolve_ref(path_item)
          else
            DocPointer.new(uri:, segments: ["paths", path], loader:)
          end
        doc["paths"][path] = path_item = PathItem.new(root_doc: self, path:, doc_pointer:)
      end

      begin
        path_item.parameters_and_operation_for_method(request.method) => {parameters:, operation:}

        if parameters in path: path_param
          yield path_param, "#", path_parameters.to_h, "path parameters for #{path} in #{uri}"
        end

        if parameters in query:
          yield query, "#", request.query_parameters, "query parameters for #{path} in #{uri}"
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

  class PathItem
    attr_reader :doc_pointer
    def initialize(root_doc:, path:, doc_pointer:)
      @root_doc = root_doc
      @path = path
      @doc_pointer = doc_pointer
      @cache = {}
    end

    def inspect
      "#<#{self.class.name} @path=#{@path}>"
    end

    def parameters_and_operation_for_method(method_)
      method = method_.downcase
      @cache[method] ||= begin
        operation = doc_pointer[method]
        raise Error.new("unknown method '#{method}' for #{@path}") unless operation

        doc_pointer.deep_resolve(doc_pointer["parameters"]) if doc_pointer["parameters"]
        doc_pointer.deep_resolve(operation["parameters"]) if operation["parameters"]

        parameters = doc_pointer["parameters"].to_a + operation["parameters"].to_a
        {
          parameters: generate_unified_parameters(parameters),
          operation: Operation.new(doc_pointer:, method:, operation:)
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

  Operation = Data.define(:doc_pointer, :method, :operation) do
    def each_schema(request:, response:, &block)
      content_type = request.headers["Content-Type"]
      req_schema = request_body_schema(content_type:, has_body: request.body&.present?)
      if req_schema
        yield doc_pointer.doc.merge("$id" => doc_pointer.uri.to_s), req_schema, request.body
      end

      content_type = response.headers["Content-Type"]
      res_schema = response_schema(status: response.status, content_type:)
      if res_schema
        yield doc_pointer.doc.merge("$id" => doc_pointer.uri.to_s), res_schema, response.body
      end
    rescue => e
      raise Error.wrap(e).add_message({method:, content_type:})
    end

    private

    def request_body_schema(content_type:, has_body:)
      req_body = operation["requestBody"]
      return if !has_body && !req_body
      unless has_body
        raise Error.new("request body required") if req_body["required"]
      end
      raise Error.new("missing requestBody schema") unless req_body
      raise Error.new("missing content-type") if !content_type
      # return if content_type == 'application/x-www-form-urlencoded' # rspec
      raise Error.new("unknown content-type #{content_type}") unless req_body.dig("content", content_type)
      schema = req_body.dig("content", content_type, "schema")
      raise Error.new("missing schema for #{content_type}") unless schema
      doc_pointer.dig(method, "requestBody", "content", content_type, "schema").fragment
    end

    def response_schema(status:, content_type:)
      resp = operation["responses"][status.to_s]
      raise Error.new("unknown response code #{status}") unless resp
      return if status == 204
      content = resp["content"] or raise Error.new("missing content. resp: #{resp}")
      raise Error.new("missing content-type") unless content_type
      unless content[content_type]
        Rails.logger.warn "unknown content-type #{content_type} for #{status} at #{@method} #{@path}"
        return
      end
      schema = content[content_type]["schema"]
      raise Error.new("missing schema") unless schema
      doc_pointer.dig(method, "responses", status, "content", content_type, "schema").fragment
    end
  end
end
