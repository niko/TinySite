require 'rspec'
$LOAD_PATH << File.join(File.dirname(File.expand_path __FILE__), '../lib')

require 'tiny_site'

describe TextileParts do
  before do
    @t = <<-EOT
---
:a: bla
:e: ble
++++navigation++++
* "one":eins
* "two":zwei
++++body++++
h1. header
EOT
  end
  describe ".parse" do
    it 'gets the vars' do
      TextileParts.parse(@t).first.should == {:a => 'bla', :e => 'ble'}
    end
    it 'gets the parts and textilizes them' do
      TextileParts.parse(@t).last['navigation'].should ==
        %Q{<ul>\n\t<li><a href="eins">one</a></li>\n\t<li><a href="zwei">two</a></li>\n</ul>}
      TextileParts.parse(@t).last['body'].should ==
        %Q{<h1>header</h1>}
    end
  end
  describe ".textilize" do
    describe "images relative path" do
      it "adds the images path" do
        s = "bla bla !an_image.jpg! blable"
        TextileParts.textilize(s,'images').should == %Q{<p>bla bla <img src="images/an_image.jpg" alt="" /> blable</p>}
      end
    end
    describe "images absolute path" do
      it "leaves them alone" do
        s = "bla bla !/an_image.jpg! blable"
        TextileParts.textilize(s,'images').should == %Q{<p>bla bla <img src="/an_image.jpg" alt="" /> blable</p>}
      end
    end
    describe "images absolute path, domain and protocol" do
      it "leaves them alone" do
        s = "bla bla !http://foo.bar/an_image.jpg! blable"
        TextileParts.textilize(s,'images').should == %Q{<p>bla bla <img src="http://foo.bar/an_image.jpg" alt="" /> blable</p>}
      end
    end
  end
end

describe CachedHttpFile do
  describe '#fetch' do
    it 'gets the url' do
      uri = URI.parse 'http://foo/bar'
      f = CachedHttpFile.new uri
      OpenURI.should_receive(:open_uri).with(uri).and_return(StringIO.new)
      f.fetch
    end
    it 'returns the content of the file and the status 200' do
      f = CachedHttpFile.new 'http://foo/bar'
      OpenURI.stub! :open_uri => StringIO.new('foo')
      f.fetch.should == [200, 'foo']
    end
    it 'it catches http errors and returns the status' do
      f = CachedHttpFile.new 'http://foo/bar'
      OpenURI.should_receive(:open_uri).and_raise(OpenURI::HTTPError.new '485 Ugly client', '')
      f.fetch.should == [485, nil]
    end
    it "stores the body" do
      f = CachedHttpFile.new 'http://foo/bar'
      OpenURI.stub! :open_uri => StringIO.new('foo')
      now = Time.now
      Time.stub! :now => now
      CachedHttpFile.files['http://foo/bar'][:content].should == 'foo'
      CachedHttpFile.files['http://foo/bar'][:expires_at].should be_a(Time)
    end
  end
  describe "the caching" do
    it "expires" do
      f = CachedHttpFile.new 'http://foo/bar', 0.1
      OpenURI.stub! :open_uri => StringIO.new('foo')
      f.fetch
      f.cached?.should be_true
      sleep 0.1
      f.cached?.should be_false
    end
  end
end

describe TinySite do
  describe "#render" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
      CachedHttpFile.stub! :get
      TextileParts.stub! :parse
      @app.stub! :render_layout
      @app.stub! :remote_file_url_for
    end
    it 'gets the __global file' do
      @app.should_receive(:remote_file_url_for).with('__global').and_return('__global')
      CachedHttpFile.should_receive(:get).with('__global')
      @app.render
    end
    it 'gets the actual page file' do
      @app.instance_variable_set '@path', 'some/path'
      @app.should_receive(:remote_file_url_for).with('some/path').and_return('some/path')
      CachedHttpFile.should_receive(:get).with('some/path')
      @app.render
    end
    describe "when the actual page file doesn't exist" do
      it 'gets the 404 file' do
        @app.instance_variable_set '@path', 'some/path'
        @app.should_receive(:remote_file_url_for).with('some/path').and_return('some/path')
        CachedHttpFile.should_receive(:get).with('some/path').and_return([404, 'foobar'])
        
        @app.should_receive(:remote_file_url_for).with(404).and_return('404')
        CachedHttpFile.should_receive(:get).with('404')
        @app.render
      end
    end
    describe 'after getting the files' do
      before(:each) do
        @app.instance_variable_set '@path', 'some/path'
        @app.should_receive(:remote_file_url_for).with('some/path').and_return('some/path')
        @app.should_receive(:remote_file_url_for).with('__global').and_return('__global')
        CachedHttpFile.should_receive(:get).with('some/path').and_return([200, 'some page related stuff'])
        CachedHttpFile.should_receive(:get).with('__global').and_return([200, 'some global stuff'])
      end
      it 'parses the global file' do
        TextileParts.should_receive(:parse).with('some global stuff', 'http://foo/bar/images')
        @app.render
      end
      it 'parses the actual page file' do
        TextileParts.should_receive(:parse).with('some page related stuff', 'http://foo/bar/images')
        @app.render
      end
      describe "after parsing" do
        before(:each) do
          TextileParts.should_receive(:parse).with('some global stuff', 'http://foo/bar/images').and_return([:g_vars, :g_parts])
          TextileParts.should_receive(:parse).with('some page related stuff', 'http://foo/bar/images').and_return([:p_vars, :p_parts])
        end
        it 'renders the layout' do
          @app.should_receive(:render_layout).with({:global_vars=>:g_vars, :global_parts=>:g_parts, :page_vars=>:p_vars, :page_parts=>:p_parts})
          @app.render
        end
      end
    end
  end
  describe "#render_layout" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
      @params = {
        :global_vars=>{},
        :global_parts=>{},
        :page_vars=>{},
        :page_parts=>{}
      }
      File.stub! :open => StringIO.new('foo')
    end
    describe "determining the layout file" do
      it "uses the page var :layout if given" do
        File.should_receive(:open).with('some_layout.haml').and_return(StringIO.new('foo'))
        @app.render_layout @params.update(:page_vars => {:layout => 'some_layout'})
      end
      it "uses the global var :layout if given no page var :layout is given" do
        File.should_receive(:open).with('some_global_layout.haml').and_return(StringIO.new('foo'))
        @app.render_layout @params.update(:global_vars => {:layout => 'some_global_layout'})
      end
      it "uses the default if no layout given explicitly" do
        File.should_receive(:open).with('layout.haml').and_return(StringIO.new('foo'))
        @app.render_layout @params
      end
    end
    it "uses haml to render" do
      File.stub! :open => StringIO.new('foo')
      haml_engine = Haml::Engine.new 'foo'
      haml_engine.should_receive(:render)
      Haml::Engine.should_receive(:new).with('foo', :format => :html5).and_return(haml_engine)
      @app.render_layout @params
    end
  end
  describe "#caching_header" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar', :cache_buster => 'bust'
    end
    describe "when the cachebuster is given" do
      before(:each) do
        @app.instance_variable_set '@query_string', 'bust'
      end
      it "doesn't cache" do
        CachedHttpFile.should_receive(:bust).and_return(true)
        @app.caching_header.should == { 'Cache-Control' => 'no-cache' }
      end
    end
    describe "when the cachebuster is not given" do
      before(:each) do
        @app.instance_variable_set '@query_string', 'whatever'
      end
      it "doesn't cache" do
        @app.caching_header.should == { 'Cache-Control' => 'public, max-age=3600' }
      end
    end
  end
  describe "#call" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
      @app.stub :render => 'foo'
      @app.stub :caching_header => {'cache' => 'no cache'}
      @app.instance_variable_set '@status', 123
    end
    it "adds 'index' to the root path" do
      @app.call('PATH_INFO' => '/')
      @app.instance_variable_get('@path').should == '/index'
    end
    it "sanitizes paths ending in '/' by a redirect" do
      @app.call('PATH_INFO' => '/foo/bar/').should == [301, {'Location' => '/foo/bar'}, '']
    end
    it "returns the set status and the rendered body" do
      @app.call('PATH_INFO' => '/foo').should == [123, {'cache' => 'no cache'}, 'foo']
    end
    it "catches errors nicely" do
      error = StandardError.new 'an_error'
      error.stub!(:backtrace => ['one'])
      @app.should_receive(:render).and_raise(error)
      @app.call('PATH_INFO' => '/foo').should == [500, {}, 'Sorry, but something went wrong']
    end
  end
end
