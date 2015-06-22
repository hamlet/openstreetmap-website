require 'cgimap'

module CgimapExt
  def cgimap_handle_response(request)
    config = ActiveRecord::Base.connection_config
    rl = Cgimap::RateLimiter.new({})
    rt = Cgimap::Routes.new
    backend_config = { 'backend' => 'apidb', 'charset' => 'utf8', 'cachesize' => '1000' }
    {'dbname' => :database,
      'charset' => :encoding,
      'username' => :username,
      'password' => :password,
      'host' => :host }.each do |new_k, old_k|
      backend_config[new_k] = config[old_k] if config.has_key? old_k
    end
    f = Cgimap::create_backend(backend_config)
    self.status, response.headers, self.response_body = Cgimap::process_request(request, rl, GENERATOR, rt, f)
    self.content_type = response.headers['Content-Type'] if response.headers.has_key?('Content-Type')
  end
end
