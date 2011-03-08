require 'open-uri' 
require 'forwardable'
require 'RedCloth'
require 'yaml'
require 'haml'

class TextileParts
  def self.parse(tp, app)
    @app = app
    
    return {:title => '404 not found'} unless tp
    
    vars, *parts = tp.split(/^\+{4}([\w\d\-_]+)\+{4}$/)
    vars = YAML.load(vars) || {}
    
    parts = Hash[*parts]
    parts.each{|k,v| parts[k] = textilize(v)}
    
    vars.update(parts)
  end
  def self.image_url_for(img_name)
    @app.image_url_for img_name
  end
  def self.textilize(string)
    string.gsub!(%r{!([\w\d\-\._]+)!}){ |a| "!#{image_url_for $1}!" }
    
    RedCloth.new(string).to_html
  end
end

class CachedHttpFile
  def initialize(url, expires_in=3600)
    @url, @expires_in = url, expires_in
  end
  
  def fetch
    puts "fetching #{@url}"
    @body = open(@url).read
    store
    return 200, @body
  rescue OpenURI::HTTPError => error
    puts "OpenURI::HTTPError: #{error.message}"
    return error.message.to_i, nil
  end
  
  def cached?
    self.class.files[@url] && self.class.files[@url][:expires_at] > Time.now
  end
  def cached
    return 200, self.class.files[@url][:content]
  end
  
  def store
    puts "storing body of #{@url}"
    self.class.files[@url] = {:content => @body, :expires_at => Time.now + @expires_in}
  end
  
  def get
    (cached? && cached) || fetch
  end
  
  class << self
    def files
      @files ||= {}
    end
    def get(url, expires_in=3600)
      (new url, expires_in).get
    end
    def bust
      puts 'busting cache'
      @files = {}
    end
  end
end

class TinySite
  class View
    extend Forwardable
    def_delegators :@app, :request_path, :query_string, :global, :page, :file_url_for, :image_url_for
    
    def initialize(app) ; @app = app ; end
  end
end

class TinySite
  attr_reader :file_path, :file_path_postfix, :file_extension, :image_path, :request_path, :query_string
  
  def initialize(opts)
    @file_path         = opts[:file_path]
    @file_path_postfix = opts[:file_path_postfix] || ''
    @file_extension    = opts[:file_extension]    || 'textile'
    @image_path        = opts[:image_path]        || File.join(@file_path, 'images')
    @cache_buster      = opts[:cache_buster]      || 'bust'
  end
  
  def global
          _, global_file = CachedHttpFile.get page_content_url_for('__global')
    TextileParts.parse global_file, self
  end
  
  def page
    @status, page_file   = CachedHttpFile.get page_content_url_for(@request_path)
          _, page_file   = CachedHttpFile.get page_content_url_for(@status.to_s)        if @status != 200
    TextileParts.parse page_file, self
  end
  
  def status
    @status or page && @status
  end
  
  def image_url_for(img_name)
    file_url_for img_name, @image_path
  end
  def file_url_for(filename, path=file_path)
    File.join path, "#{filename}#{file_path_postfix}"
  end
  def page_content_url_for(filename)
    file_url_for "#{filename.gsub(%r{^/$},'/index')}.#{file_extension}"
  end
  
  def layout
    page[:layout] || global[:layout] || 'layout'
  end
  def body
    Haml::Engine.new(File.open("#{layout}.haml").read, :format => :html5).render view
  end
  
  def caching_header
    return { 'Cache-Control' => 'public, max-age=3600' } unless @query_string == @cache_buster
    
    CachedHttpFile.bust and return { 'Cache-Control' => 'no-cache' }
  end
  
  def headers
    caching_header.merge({'Content-Type' => 'text/html'})
  end
  
  def view
    @view ||= View.new self
  end
  
  def call(env)
    @request_path, @query_string = env['PATH_INFO'], env['QUERY_STRING']
    
    return [301, {'Location' => @request_path}, ['']] if @request_path.gsub!(/(.)\/$/,'\\1')
    
    [status, headers, [body]]
  rescue => e
    puts "#{e.class}: #{e.message} #{e.backtrace}"
    [500, {}, ['Sorry, but something went wrong']]
  end
end