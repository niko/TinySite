require 'open-uri' 
require 'RedCloth'
require 'yaml'
require 'haml'

class TextileParts
  def self.parse(tp, image_path='')
    vars, *parts = tp.split(/^\+{4}|\+{4}$/)
    
    vars = YAML.load(vars) || {}
    parts = Hash[*parts]
    
    parts.each{|k,v| parts[k] = textilize(v,image_path)}
    
    return vars, parts
  end
  def self.textilize(string, image_path)
    string.gsub!(%r{!([\w\d\-\._]+)!}){ |a| "!#{image_path}/#{$1}!" }
    
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
  def initialize(opts)
    @file_path    = opts[:file_path]
    @image_path   = opts[:image_path] || File.join(@file_path, 'images')
    @cache_buster = opts[:cache_buster] || 'bust'
  end
  
  def remote_file_url_for(filename)
    File.join @file_path, "#{filename}.textile"
  end
  
  def render
    global_file_fetch_tread = Thread.new{
            _, @global_file = CachedHttpFile.get remote_file_url_for('__global') } # get __global in background
      @status, page_file    = CachedHttpFile.get remote_file_url_for(@path)
            _, page_file    = CachedHttpFile.get remote_file_url_for(@status) if @status != 200
    global_file_fetch_tread.join
    
    global_vars, global_parts = TextileParts.parse @global_file, @image_path
    page_vars,   page_parts   = TextileParts.parse page_file,    @image_path
    
    render_layout :global_vars  => global_vars, :global_parts => global_parts,
                  :page_vars    => page_vars,   :page_parts   => page_parts
  end
  
  def render_layout(params)
    layout = params[:page_vars][:layout] || params[:global_vars][:layout] || 'layout'
    
    puts "rendering layout '#{layout}'"
    haml = Haml::Engine.new File.open("#{layout}.haml").read, :format => :html5
    haml.render Object.new, params
  end
  
  def caching_header
    return { 'Cache-Control' => 'public, max-age=3600' } unless @query_string == @cache_buster
    
    CachedHttpFile.bust and return { 'Cache-Control' => 'no-cache' }
  end
  
  def call(env)
    @path, @query_string = env['PATH_INFO'], env['QUERY_STRING']
    @path = '/index' if @path == '/'
    
    return [301, {'Location' => @path}, ''] if @path.gsub!(/\/$/,'')
    
    body = render # render the body first to set @status
    [@status, caching_header, body]
  rescue => e
    puts "#{e.class}: #{e.message} #{e.backtrace}"
    [500, {}, 'Sorry, but something went wrong']
  end
end