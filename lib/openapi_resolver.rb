class OpenapiResolver
  autoload :VERSION, "openapi_resolver/version"

  class Error < StandardError
    def add_breadcrumb(breadcrumb)
      @breadcrumb ||= []
      @breadcrumb << breadcrumb
    end
    def message
      msg = super
      msg += "\n" + @breadcrumb.join("\n") if @breadcrumb
      msg
    end
  end

  RootDoc = Data.define(:schema_path, :path_matchers)
  SchemeSet = Data.define(:path, :query, :request_body, :response)

  def initialize
    @yaml_cache = {}
    @root_docs = {}
  end
  def register(schema_path_)
    schema_path = Pathname.pwd.join(schema_path_)
    root = load_yaml(schema_path)
    path_prefix = URI.parse(root.dig('servers', 0, 'url')).path
    path_matchers = root['paths'].sort_by{_1}.map do |path, obj|
      path_regex = path.gsub(%r"\{[^}]+\}"){
        "(?<#{$&.delete('{}')}>[^/]+)"
      }
      regex = Regexp.new("\\A#{path_regex}\\Z")
      [regex, PathItem.new(path, obj)]
    end.freeze
    @root_docs[path_prefix] = RootDoc.new(schema_path:, path_matchers:)
  end
  def inspect
    "#<#{self.class.name} @root_docs=#{@root_docs}>"
  end
  def each_schema(request:, response:, &block)
    request => method:, path:
    path_prefix, root_doc = @root_docs.find do |path_prefix, _|
      path.start_with?(path_prefix)
    end
    partial_path = path.sub(path_prefix, '')
    matched = root_doc.path_matchers.find do |regex, obj|
      match = regex.match(partial_path)
      if match
        break [obj, match.named_captures]
      end
    end
    raise Error.new("unknown path #{partial_path}") unless matched
    path_item, path_parameters = matched

    parameters = path_item.parameters_for_method(method)

    path_item.each_schema(method: method.downcase, )

    operation = path_item[method.downcase]
    [PathItem.new(path, resolved), path_parameters]
  rescue
    raise
  end

  class PathItem
    def initialize(path, path_item)
      @path = path
      @path_item = ref?(path_item) ? resolve_ref(path_item) : path_item
    end
    def inspect
      "#<#{self.class.name} @path=#{@path}>"
    end
    def parameters_for_method(method)
      operation = @path_item[method.downcase]
      raise Error.new("unknown method '#{method}' for #{@path}") unless operation
      parameters = @path_item['parameters'].to_a + operation['parameters'].to_a
      parameters.group_by { _1['in'].to_sym }
    end
    def validate_method(method)
      @method = method.downcase
      raise Error.new("unknown method '#{@method}' for #{@path}") unless @operation
    end
    def each_parameter_schemas(path:, query:)
      parameters.each do |parameter|
        case parameter['in']
        when 'query'
          data = query[parameter['name'].gsub('[]', '')]
        when 'path'
          data = path[parameter['name']]
        else
          raise Error.new "unkown parameter.in. parameters: #{parameters}"
        end
        if data.nil?
          raise Error.new("missing required query parameter '#{parameter['name']}'") if parameter['required']
          next
        end
        data = Integer(data) if parameter.dig('schema', 'type') == 'integer'
        yield parameter['schema'], data
      end
    end
    def request_body_schema(content_type: , has_body:)
      req_body = @operation['requestBody']
      return if !has_body && !req_body
      unless has_body
        raise Error.new("request body required") if req_body['required']
      end
      raise Error.new("missing requestBody schema") unless req_body
      raise Error.new("missing content-type") if !content_type
      # return if content_type == 'application/x-www-form-urlencoded' # rspec
      raise Error.new("unknown content-type #{content_type}") unless req_body.dig('content', content_type)
      schema = req_body.dig('content', content_type, 'schema')
      raise Error.new("missing schema for #{content_type}") unless schema
      schema
    end
    def response_schema(status:, content_type:)
      resp = @operation['responses'][status.to_s]
      raise Error.new("unknown response code #{status}") unless resp
      return if status == 204
      content = resp['content'] or raise Error.new("missing content. resp: #{resp}")
      raise Error.new("missing content-type") unless content_type
      unless content[content_type]
        Rails.logger.warn "unknown content-type #{content_type} for #{status} at #{@method} #{@path}"
        return
      end
      schema = content[content_type]['schema']
      raise Error.new("missing schema") unless schema
      schema
    end
  end

  private

  def load_yaml(path)
    @yaml_cache[path] ||= YAML.load_file(path)
  end
  def path_match(path)
    @path_matcher ||= begin
      @root_doc['paths'].sort_by{_1}.map do |path, obj|
        path_regex = path.gsub(%r"\{[^}]+\}"){
          "(?<#{$&.delete('{}')}>[^/]+)"
        }
        regex = Regexp.new("\\A#{path_regex}\\Z")
        [regex, obj]
      end
    end
    @path_matcher.find do |regex, obj|
      match = regex.match(path)
      if match
        break [obj, match.named_captures]
      end
    end
  end

  REF = "$ref"
  def ref?(obj)
    return false unless obj.is_a?(Hash) && obj.key?(REF)
    return true if obj.size == 1
    raise Error.new("Invalid $ref")
  end
  def resolve_refs(schema_path, obj)
    raise Error.new("nil obj") if obj.nil?
    case obj
    when Hash
      obj.each do |k,v|
        if k.starts_with?('example')
          obj[k] = '[example]'
        elsif ref?(v)
          resolve_ref(schema_path, obj, k)
        elsif v.is_a?(Hash) || v.is_a?(Array)
          resolve_refs(schema_path, v) unless v.frozen?
        end
      end
    when Array
      obj.each_with_index do |x, i|
        if ref?(x)
          resolve_ref(schema_path, obj, i)
        end
      end
    end
    obj
  rescue Error => e
    e.add_breadcrumb({obj:})
    raise
  end
  def resolve_ref(schema_path, obj, k)
    ref = obj[k].values[0]
    path, pointer = ref.split('#')
    if path.present?
      schema_path = schema_path.dirname.join(path)
    end
    doc = load_yaml(schema_path)
    digged = doc.dig(*pointer.split('/').drop(1))
    obj[k] = digged
    unless digged.frozen?
      digged.freeze
      resolve_refs(schema_path, digged)
    end
  rescue Error => e
    e.add_breadcrumb({ref:, keys: doc.keys})
    raise
  end
end
